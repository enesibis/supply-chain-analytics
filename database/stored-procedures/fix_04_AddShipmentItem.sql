USE [SCM_3];
GO
-- FIX 04: AddShipmentItem
-- Sorun: Stok kontrolü sadece onHandQty'a bakıyordu, reservedQty'ı yok sayıyordu.
-- Rezerve edilmiş stok başka siparişe de kesilebiliyordu.
ALTER PROCEDURE dbo.AddShipmentItem
    @shipmentID       BIGINT,
    @salesOrderItemID BIGINT,
    @quantity         DECIMAL(18,3),
    @shipmentItemID   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF @quantity IS NULL OR @quantity <= 0
        BEGIN
            RAISERROR('quantity 0 veya negatif olamaz.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        DECLARE @shipStatus VARCHAR(20), @soID BIGINT, @warehouseID INT;
        DECLARE @soItemSOID BIGINT, @productID BIGINT, @soQty DECIMAL(18,3), @shippedQty DECIMAL(18,3);

        SELECT
            @shipStatus  = s.status,
            @soID        = s.salesOrderID,
            @warehouseID = s.warehouseID
        FROM dbo.Shipment s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.shipmentID = @shipmentID;

        IF @soID IS NULL
        BEGIN
            RAISERROR('Shipment bulunamadı.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @shipStatus <> 'DRAFT'
        BEGIN
            RAISERROR('Sadece DRAFT Shipment''a satır eklenebilir.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.SalesOrder so WITH (UPDLOCK, HOLDLOCK)
            WHERE so.salesOrderID = @soID
              AND so.status IN ('APPROVED','PARTIALLY_SHIPPED','RESERVED')
        )
        BEGIN
            RAISERROR('Bu SalesOrder için Shipment kalemi eklenemez (SalesOrder status uyumsuz).', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        SELECT
            @soItemSOID = soi.salesOrderID,
            @productID  = soi.productID,
            @soQty      = ISNULL(soi.quantity, 0),
            @shippedQty = ISNULL(soi.shippedQuantity, 0)
        FROM dbo.SalesOrderItem soi WITH (UPDLOCK, HOLDLOCK)
        WHERE soi.salesOrderItemID = @salesOrderItemID;

        IF @soItemSOID IS NULL
        BEGIN
            RAISERROR('SalesOrderItem bulunamadı.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @soItemSOID <> @soID
        BEGIN
            RAISERROR('Bu SalesOrderItem, Shipment''ın bağlı olduğu SalesOrder''a ait değil.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @soQty <= 0
        BEGIN
            RAISERROR('SalesOrderItem.quantity geçersiz.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        DECLARE @alreadyInThisShipment DECIMAL(18,3) = 0;

        SELECT @alreadyInThisShipment = ISNULL(SUM(si.quantity), 0)
        FROM dbo.ShipmentItem si WITH (UPDLOCK, HOLDLOCK)
        WHERE si.shipmentID = @shipmentID
          AND si.salesOrderItemID = @salesOrderItemID;

        IF (ISNULL(@shippedQty,0) + @alreadyInThisShipment + @quantity) > @soQty
        BEGIN
            RAISERROR('Sevk miktarı, SalesOrderItem kalan miktarını aşıyor.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- FIX: Stok kontrolü — kullanılabilir stok = onHandQty - reservedQty
        DECLARE @onHand   DECIMAL(18,3) = 0;
        DECLARE @reserved DECIMAL(18,3) = 0;

        SELECT
            @onHand   = ISNULL(ib.onHandQty, 0),
            @reserved = ISNULL(ib.reservedQty, 0)
        FROM dbo.InventoryBalance ib WITH (UPDLOCK, HOLDLOCK)
        WHERE ib.warehouseID = @warehouseID
          AND ib.productID   = @productID;

        IF (@onHand - @reserved) < @quantity
        BEGIN
            RAISERROR('Depoda yeterli kullanılabilir stok yok (onHand - reserved yetersiz).', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        DECLARE @lineNo_ INT;

        SELECT @lineNo_ = ISNULL(MAX(lineNo_), 0) + 1
        FROM dbo.ShipmentItem WITH (UPDLOCK, HOLDLOCK)
        WHERE shipmentID = @shipmentID;

        INSERT INTO dbo.ShipmentItem
        (
            shipmentID, salesOrderItemID, lineNo_, productID, quantity
        )
        VALUES
        (
            @shipmentID, @salesOrderItemID, @lineNo_, @productID, @quantity
        );

        SET @shipmentItemID = SCOPE_IDENTITY();

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
