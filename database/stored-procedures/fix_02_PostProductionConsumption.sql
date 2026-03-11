USE [SCM_3];
GO
-- FIX 02: PostProductionConsumption
-- Sorun: @quantity ve @consumptionDate validasyonları BEGIN TRY/TRAN dışındaydı.
-- Hata olursa rollback edilecek aktif transaction yoktu.
ALTER PROCEDURE dbo.PostProductionConsumption
    @productionOrderID       BIGINT,
    @componentProductID      BIGINT,
    @quantity                DECIMAL(18,3),
    @consumptionDate         DATETIME2(7) = NULL,
    @productionConsumptionID BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Validasyonlar transaction içinde
        IF @quantity IS NULL OR @quantity <= 0
            THROW 50000, 'quantity 0 veya negatif olamaz.', 1;

        IF @consumptionDate IS NULL
            SET @consumptionDate = SYSUTCDATETIME();

        DECLARE @warehouseID INT;
        DECLARE @status      VARCHAR(30);

        SELECT
            @status      = po.status,
            @warehouseID = po.sourceWarehouseID
        FROM dbo.ProductionOrder po WITH (UPDLOCK, HOLDLOCK)
        WHERE po.productionOrderID = @productionOrderID;

        IF @status IS NULL
            THROW 50000, 'ProductionOrder bulunamadı.', 1;

        IF @status <> 'IN_PROGRESS'
            THROW 50000, 'ProductionOrder IN_PROGRESS olmali.', 1;

        IF NOT EXISTS (SELECT 1 FROM dbo.Product WHERE productID = @componentProductID AND isActive = 1)
            THROW 50000, 'Component product bulunamadı veya pasif.', 1;

        DECLARE @onHand DECIMAL(18,3) = 0;

        SELECT @onHand = ISNULL(ib.onHandQty, 0)
        FROM dbo.InventoryBalance ib WITH (UPDLOCK, HOLDLOCK)
        WHERE ib.warehouseID = @warehouseID
          AND ib.productID   = @componentProductID;

        IF @onHand < @quantity
            THROW 50000, 'Yetersiz stok.', 1;

        INSERT INTO dbo.ProductionConsumption
        (
            productionOrderID, warehouseID, productID,
            quantity, consumptionDate, createdAt
        )
        VALUES
        (
            @productionOrderID, @warehouseID, @componentProductID,
            @quantity, @consumptionDate, SYSUTCDATETIME()
        );

        SET @productionConsumptionID = SCOPE_IDENTITY();

        INSERT INTO dbo.StockMovement
        (
            movementType, warehouseID, productID,
            qtyIn, qtyOut, movementDate,
            refType, refID, createdAt
        )
        VALUES
        (
            'PRODUCTION_CONSUMPTION', @warehouseID, @componentProductID,
            0, @quantity, @consumptionDate,
            'ProductionConsumption', @productionConsumptionID, SYSUTCDATETIME()
        );

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO
