USE [SCM_3];
GO
-- FIX 07: CreatePurchaseOrder — Eksik prosedür
-- PurchaseOrder tablosu vardı ama oluşturma prosedürü yoktu.
CREATE OR ALTER PROCEDURE dbo.CreatePurchaseOrder
    @orderNumber            VARCHAR(30),
    @supplierPartnerID      BIGINT,
    @orderDate              DATETIME2(7) = NULL,
    @expectedDeliveryDate   DATETIME2(7) = NULL,
    @purchaseOrderID        BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        IF @orderNumber IS NULL OR LTRIM(RTRIM(@orderNumber)) = ''
        BEGIN
            RAISERROR('orderNumber boş olamaz.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber = @orderNumber)
        BEGIN
            RAISERROR('orderNumber zaten kullanılmış.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM dbo.BusinessPartner WHERE partnerID = @supplierPartnerID AND isActive = 1)
        BEGIN
            RAISERROR('Supplier partner bulunamadı veya pasif.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.BusinessPartnerRole r
            WHERE r.partnerID = @supplierPartnerID
              AND r.roleType  = 'SUPPLIER'
              AND r.isActive  = 1
        )
        BEGIN
            RAISERROR('Seçilen iş ortağı SUPPLIER rolüne sahip değil.', 16, 1);
            ROLLBACK TRAN; RETURN;
        END;

        IF @orderDate IS NULL
            SET @orderDate = SYSUTCDATETIME();

        INSERT INTO dbo.PurchaseOrder
        (
            supplierPartnerID, orderNumber, orderDate,
            expectedDeliveryDate, status, totalAmount, createdAt
        )
        VALUES
        (
            @supplierPartnerID, @orderNumber, @orderDate,
            @expectedDeliveryDate, 'DRAFT', 0, SYSUTCDATETIME()
        );

        SET @purchaseOrderID = SCOPE_IDENTITY();

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
