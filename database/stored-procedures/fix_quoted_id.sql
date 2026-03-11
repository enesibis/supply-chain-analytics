SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO

-- AddShipmentItem
EXEC sp_executesql N'
ALTER PROCEDURE dbo.AddShipmentItem
    @shipmentID       BIGINT,
    @salesOrderItemID BIGINT,
    @quantity         DECIMAL(18,3),
    @shipmentItemID   BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    BEGIN TRY
        BEGIN TRAN;
        IF @quantity IS NULL OR @quantity <= 0 BEGIN RAISERROR(''quantity 0 veya negatif olamaz.'',16,1); ROLLBACK TRAN; RETURN; END;
        DECLARE @shipStatus VARCHAR(20),@soID BIGINT,@warehouseID INT,@soItemSOID BIGINT,@productID BIGINT,@soQty DECIMAL(18,3),@shippedQty DECIMAL(18,3);
        SELECT @shipStatus=s.status,@soID=s.salesOrderID,@warehouseID=s.warehouseID FROM dbo.Shipment s WITH(UPDLOCK,HOLDLOCK) WHERE s.shipmentID=@shipmentID;
        IF @soID IS NULL BEGIN RAISERROR(''Shipment bulunamadi.'',16,1); ROLLBACK TRAN; RETURN; END;
        IF @shipStatus<>''DRAFT'' BEGIN RAISERROR(''Sadece DRAFT Shipment a satir eklenebilir.'',16,1); ROLLBACK TRAN; RETURN; END;
        IF NOT EXISTS(SELECT 1 FROM dbo.SalesOrder so WITH(UPDLOCK,HOLDLOCK) WHERE so.salesOrderID=@soID AND so.status IN(''APPROVED'',''PARTIALLY_SHIPPED'',''RESERVED'')) BEGIN RAISERROR(''SalesOrder status uyumsuz.'',16,1); ROLLBACK TRAN; RETURN; END;
        SELECT @soItemSOID=soi.salesOrderID,@productID=soi.productID,@soQty=ISNULL(soi.quantity,0),@shippedQty=ISNULL(soi.shippedQuantity,0) FROM dbo.SalesOrderItem soi WITH(UPDLOCK,HOLDLOCK) WHERE soi.salesOrderItemID=@salesOrderItemID;
        IF @soItemSOID IS NULL BEGIN RAISERROR(''SalesOrderItem bulunamadi.'',16,1); ROLLBACK TRAN; RETURN; END;
        IF @soItemSOID<>@soID BEGIN RAISERROR(''SalesOrderItem bu SalesOrder a ait degil.'',16,1); ROLLBACK TRAN; RETURN; END;
        IF @soQty<=0 BEGIN RAISERROR(''SalesOrderItem.quantity gecersiz.'',16,1); ROLLBACK TRAN; RETURN; END;
        DECLARE @alreadyInThisShipment DECIMAL(18,3)=0;
        SELECT @alreadyInThisShipment=ISNULL(SUM(si.quantity),0) FROM dbo.ShipmentItem si WITH(UPDLOCK,HOLDLOCK) WHERE si.shipmentID=@shipmentID AND si.salesOrderItemID=@salesOrderItemID;
        IF(ISNULL(@shippedQty,0)+@alreadyInThisShipment+@quantity)>@soQty BEGIN RAISERROR(''Sevk miktari SalesOrderItem kalan miktarini asiyor.'',16,1); ROLLBACK TRAN; RETURN; END;
        DECLARE @onHand DECIMAL(18,3)=0,@reserved DECIMAL(18,3)=0;
        SELECT @onHand=ISNULL(ib.onHandQty,0),@reserved=ISNULL(ib.reservedQty,0) FROM dbo.InventoryBalance ib WITH(UPDLOCK,HOLDLOCK) WHERE ib.warehouseID=@warehouseID AND ib.productID=@productID;
        IF(@onHand-@reserved)<@quantity BEGIN RAISERROR(''Depoda yeterli kullanilabilir stok yok (onHand - reserved yetersiz).'',16,1); ROLLBACK TRAN; RETURN; END;
        DECLARE @lineNo_ INT;
        SELECT @lineNo_=ISNULL(MAX(lineNo_),0)+1 FROM dbo.ShipmentItem WITH(UPDLOCK,HOLDLOCK) WHERE shipmentID=@shipmentID;
        INSERT INTO dbo.ShipmentItem(shipmentID,salesOrderItemID,lineNo_,productID,quantity) VALUES(@shipmentID,@salesOrderItemID,@lineNo_,@productID,@quantity);
        SET @shipmentItemID=SCOPE_IDENTITY();
        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT>0 ROLLBACK TRAN;
        DECLARE @msg NVARCHAR(4000)=ERROR_MESSAGE(); RAISERROR(@msg,16,1); RETURN;
    END CATCH
END;';
GO
