USE [SCM_3];
GO
-- FIX 08: CancelProductionOrder — Eksik prosedür
-- Diğer entity'lerde (PO, SO, GR, Shipment) cancel var, ProductionOrder'da yoktu.
CREATE OR ALTER PROCEDURE dbo.CancelProductionOrder
    @productionOrderID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        DECLARE @status VARCHAR(20);

        SELECT @status = po.status
        FROM dbo.ProductionOrder po WITH (UPDLOCK, HOLDLOCK)
        WHERE po.productionOrderID = @productionOrderID;

        IF @status IS NULL
        BEGIN
            RAISERROR('ProductionOrder bulunamadı.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @status = 'CANCELLED'
        BEGIN
            RAISERROR('ProductionOrder zaten CANCELLED.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @status = 'COMPLETED'
        BEGIN
            RAISERROR('COMPLETED ProductionOrder iptal edilemez.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        -- IN_PROGRESS üretim emri: tüketim/çıktı kaydı varsa iptal yok
        IF @status = 'IN_PROGRESS'
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.ProductionConsumption WHERE productionOrderID = @productionOrderID)
            BEGIN
                RAISERROR('Tüketim kaydı olan IN_PROGRESS ProductionOrder iptal edilemez. Önce reverse işlemi gerekir.', 16, 1);
                ROLLBACK TRAN; RETURN;
            END;

            IF EXISTS (SELECT 1 FROM dbo.ProductionOutput WHERE productionOrderID = @productionOrderID)
            BEGIN
                RAISERROR('Çıktı kaydı olan IN_PROGRESS ProductionOrder iptal edilemez. Önce reverse işlemi gerekir.', 16, 1);
                ROLLBACK TRAN; RETURN;
            END;
        END;

        UPDATE dbo.ProductionOrder
            SET status    = 'CANCELLED',
                updatedAt = SYSUTCDATETIME()
        WHERE productionOrderID = @productionOrderID;

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
