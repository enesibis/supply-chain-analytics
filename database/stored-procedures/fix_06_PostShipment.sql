USE [SCM_3];
GO
-- FIX 06: PostShipment
-- Sorun: Validasyon koşulunda soi.salesOrderID <> @salesOrderID ve soi.productID <> a.productID
-- kontrolleri FK garantisi altında hiç gerçekleşemez ama hatalı error mesajı üretebilirdi.
-- Sadece gerçek kontrol bırakıldı: sevk miktarı kalan miktarı aşıyor mu?
ALTER PROCEDURE dbo.PostShipment
    @shipmentID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @shipStatus VARCHAR(20), @salesOrderID BIGINT, @warehouseID INT;

        SELECT
            @shipStatus   = s.status,
            @salesOrderID = s.salesOrderID,
            @warehouseID  = s.warehouseID
        FROM dbo.Shipment s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.shipmentID = @shipmentID;

        IF @salesOrderID IS NULL
        BEGIN
            RAISERROR('Shipment bulunamadı.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @shipStatus <> 'DRAFT'
        BEGIN
            RAISERROR('Sadece DRAFT Shipment POST edilebilir.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.ShipmentItem WHERE shipmentID = @shipmentID)
        BEGIN
            RAISERROR('Shipment satırı yok. POST edilemez.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- FIX: Sadece miktar aşımını kontrol et (gereksiz salesOrderID/productID koşulları kaldırıldı)
        IF EXISTS
        (
            SELECT 1
            FROM
            (
                SELECT
                    si.salesOrderItemID,
                    SUM(si.quantity) AS shipQty
                FROM dbo.ShipmentItem si WITH (UPDLOCK, HOLDLOCK)
                WHERE si.shipmentID = @shipmentID
                GROUP BY si.salesOrderItemID
            ) a
            JOIN dbo.SalesOrderItem soi WITH (UPDLOCK, HOLDLOCK)
              ON soi.salesOrderItemID = a.salesOrderItemID
            WHERE (ISNULL(soi.shippedQuantity,0) + a.shipQty) > soi.quantity
        )
        BEGIN
            RAISERROR('Sevk miktarları SalesOrderItem kalanını aşıyor.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- Stok yeterlilik kontrolü (ürün bazında toplam sevk)
        IF EXISTS
        (
            SELECT 1
            FROM
            (
                SELECT
                    si.productID,
                    SUM(si.quantity) AS shipQty
                FROM dbo.ShipmentItem si WITH (UPDLOCK, HOLDLOCK)
                WHERE si.shipmentID = @shipmentID
                GROUP BY si.productID
            ) p
            LEFT JOIN dbo.InventoryBalance ib WITH (UPDLOCK, HOLDLOCK)
              ON ib.warehouseID = @warehouseID
             AND ib.productID   = p.productID
            WHERE ISNULL(ib.onHandQty, 0) < p.shipQty
        )
        BEGIN
            RAISERROR('Yetersiz stok: depoda sevk için yeterli miktar yok.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- StockMovement (qtyOut)
        INSERT INTO dbo.StockMovement
        (
            warehouseID, productID, movementType,
            qtyIn, qtyOut, movementDate,
            refType, refID, note
        )
        SELECT
            @warehouseID,
            si.productID,
            'SALES_SHIPMENT',
            0,
            si.quantity,
            SYSUTCDATETIME(),
            'Shipment',
            @shipmentID,
            NULL
        FROM dbo.ShipmentItem si
        WHERE si.shipmentID = @shipmentID;

        -- SalesOrderItem shippedQuantity güncelle
        UPDATE soi
            SET soi.shippedQuantity = ISNULL(soi.shippedQuantity,0) + a.shipQty
        FROM dbo.SalesOrderItem soi
        JOIN
        (
            SELECT si.salesOrderItemID, SUM(si.quantity) AS shipQty
            FROM dbo.ShipmentItem si
            WHERE si.shipmentID = @shipmentID
            GROUP BY si.salesOrderItemID
        ) a ON a.salesOrderItemID = soi.salesOrderItemID;

        -- Shipment status = POSTED
        UPDATE dbo.Shipment
            SET status = 'POSTED'
        WHERE shipmentID = @shipmentID;

        -- SalesOrder status güncelle
        DECLARE @isFullyShipped BIT = 0;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SalesOrderItem soi
            WHERE soi.salesOrderID = @salesOrderID
              AND ISNULL(soi.shippedQuantity,0) < soi.quantity
        )
            SET @isFullyShipped = 1;

        UPDATE dbo.SalesOrder
            SET status    = CASE WHEN @isFullyShipped = 1 THEN 'SHIPPED' ELSE 'PARTIALLY_SHIPPED' END,
                updatedAt = SYSUTCDATETIME()
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
