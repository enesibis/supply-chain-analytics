USE [SCM_3];
GO
-- FIX 03: PostProductionOutput
-- Sorun 1: @quantity validasyonu BEGIN TRY/TRAN dışındaydı.
-- Sorun 2: Fazla üretim engeli yoktu (plannedQuantity aşılabiliyordu).
ALTER PROCEDURE dbo.PostProductionOutput
    @productionOrderID BIGINT,
    @quantity          DECIMAL(18,3),
    @outputDate        DATETIME2(7) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- Validasyonlar transaction içinde
        IF @quantity IS NULL OR @quantity <= 0
            THROW 50000, 'quantity 0 veya negatif olamaz.', 1;

        IF @outputDate IS NULL
            SET @outputDate = SYSUTCDATETIME();

        DECLARE @warehouseID  INT;
        DECLARE @productID    BIGINT;
        DECLARE @status       VARCHAR(20);
        DECLARE @plannedQty   DECIMAL(18,3);
        DECLARE @producedQty  DECIMAL(18,3);

        SELECT
            @warehouseID = po.targetWarehouseID,
            @productID   = po.productID,
            @status      = po.status,
            @plannedQty  = ISNULL(po.plannedQuantity, 0),
            @producedQty = ISNULL(po.producedQuantity, 0)
        FROM dbo.ProductionOrder po WITH (UPDLOCK, HOLDLOCK)
        WHERE po.productionOrderID = @productionOrderID;

        IF @status IS NULL
            THROW 50000, 'ProductionOrder bulunamadı.', 1;

        IF @status <> 'IN_PROGRESS'
            THROW 50000, 'ProductionOrder IN_PROGRESS olmali.', 1;

        -- FIX: Fazla üretim engeli
        IF (@producedQty + @quantity) > @plannedQty
            THROW 50000, 'Üretim miktarı plannedQuantity değerini aşıyor.', 1;

        DECLARE @productionOutputID BIGINT;

        INSERT INTO dbo.ProductionOutput
        (
            productionOrderID, warehouseID, productID,
            quantity, outputDate, createdAt
        )
        VALUES
        (
            @productionOrderID, @warehouseID, @productID,
            @quantity, @outputDate, SYSUTCDATETIME()
        );

        SET @productionOutputID = SCOPE_IDENTITY();

        INSERT INTO dbo.StockMovement
        (
            movementType, warehouseID, productID,
            qtyIn, qtyOut, movementDate,
            refType, refID, createdAt
        )
        VALUES
        (
            'PRODUCTION_OUTPUT', @warehouseID, @productID,
            @quantity, 0, @outputDate,
            'ProductionOutput', @productionOutputID, SYSUTCDATETIME()
        );

        UPDATE dbo.ProductionOrder
            SET producedQuantity = @producedQty + @quantity,
                updatedAt        = SYSUTCDATETIME()
        WHERE productionOrderID = @productionOrderID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        THROW;
    END CATCH
END;
GO
