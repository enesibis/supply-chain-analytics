USE [SCM_3];
GO
-- FIX 01: RecalcSalesOrderTotal
-- Sorun: Transaction yok, TRY/CATCH yok, lock yok, updatedAt güncellenmiyordu.
ALTER PROCEDURE dbo.RecalcSalesOrderTotal
    @salesOrderID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        UPDATE so
            SET so.totalAmount = calc.totalAmount,
                so.updatedAt   = SYSUTCDATETIME()
        FROM dbo.SalesOrder so WITH (UPDLOCK, HOLDLOCK)
        CROSS APPLY
        (
            SELECT
                CAST(
                    ISNULL(
                        SUM(CAST(ISNULL(soi.quantity,0) * ISNULL(soi.unitPrice,0) AS DECIMAL(18,4))),
                        0
                    )
                AS DECIMAL(18,4)) AS totalAmount
            FROM dbo.SalesOrderItem soi
            WHERE soi.salesOrderID = so.salesOrderID
        ) AS calc
        WHERE so.salesOrderID = @salesOrderID;

        COMMIT TRAN;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRAN;
        DECLARE @msg NVARCHAR(4000) = ERROR_MESSAGE();
        RAISERROR(@msg, 16, 1);
    END CATCH
END;
GO
