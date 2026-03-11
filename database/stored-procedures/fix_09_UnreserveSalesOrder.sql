USE [SCM_3];
GO
-- FIX 09: UnreserveSalesOrder — Eksik prosedür
-- ReserveSalesOrder var ama rezervasyonu geri alan prosedür yoktu.
-- reservedQty serbest bırakılmadan yeni rezervasyon yapılamıyordu.
CREATE OR ALTER PROCEDURE dbo.UnreserveSalesOrder
    @salesOrderID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @soStatus           VARCHAR(20);
        DECLARE @reservedWarehouseID INT;

        SELECT
            @soStatus            = so.status,
            @reservedWarehouseID = so.reservedWarehouseID
        FROM dbo.SalesOrder so WITH (UPDLOCK, HOLDLOCK)
        WHERE so.salesOrderID = @salesOrderID;

        IF @soStatus IS NULL
        BEGIN
            RAISERROR('SalesOrder bulunamadı.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @reservedWarehouseID IS NULL
        BEGIN
            RAISERROR('SalesOrder zaten rezerve değil.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @soStatus NOT IN ('APPROVED')
        BEGIN
            RAISERROR('Sadece APPROVED SalesOrder rezervasyonu çözülebilir.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- Rezerve edilen miktarları hesapla (kalan = quantity - shippedQuantity)
        DECLARE @release TABLE
        (
            productID  BIGINT PRIMARY KEY,
            releaseQty DECIMAL(18,3) NOT NULL
        );

        INSERT INTO @release(productID, releaseQty)
        SELECT
            soi.productID,
            SUM(soi.quantity - ISNULL(soi.shippedQuantity, 0)) AS releaseQty
        FROM dbo.SalesOrderItem soi WITH (UPDLOCK, HOLDLOCK)
        WHERE soi.salesOrderID = @salesOrderID
        GROUP BY soi.productID
        HAVING SUM(soi.quantity - ISNULL(soi.shippedQuantity, 0)) > 0;

        -- reservedQty'ı azalt (negatife düşürme)
        UPDATE ib
            SET ib.reservedQty = CASE
                                     WHEN ISNULL(ib.reservedQty,0) - r.releaseQty < 0
                                     THEN 0
                                     ELSE ISNULL(ib.reservedQty,0) - r.releaseQty
                                 END,
                ib.updatedAt = SYSUTCDATETIME()
        FROM dbo.InventoryBalance ib
        JOIN @release r
          ON r.productID = ib.productID
        WHERE ib.warehouseID = @reservedWarehouseID;

        -- SalesOrder rezervasyon bilgisini temizle
        UPDATE dbo.SalesOrder
            SET reservedWarehouseID = NULL,
                reservedAt          = NULL,
                updatedAt           = SYSUTCDATETIME()
        WHERE salesOrderID = @salesOrderID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
        RETURN;
    END CATCH
END;
GO
