USE [SCM_3];
GO
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    ;WITH src AS
    (
        SELECT * FROM (VALUES
            ('ACME STEEL SUPPLY', '12345678901', 'supplier@acme.com', '+90 500 000 00 01'),
            ('MEGA CUSTOMER LTD', '9876543210',  'customer@mega.com', '+90 500 000 00 02'),
            ('FAST CARRIER',      NULL,          'carrier@fast.com',  '+90 500 000 00 03')
        ) v(partnerName, taxNumber, email, phone)
    )
    INSERT INTO dbo.BusinessPartner (partnerName, taxNumber, email, phone)
    SELECT s.partnerName, s.taxNumber, s.email, s.phone
    FROM src s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.BusinessPartner bp
        WHERE bp.partnerName = s.partnerName
    );

    COMMIT;

    SELECT * FROM dbo.BusinessPartner ORDER BY partnerID;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() ErrorNumber, ERROR_MESSAGE() ErrorMessage;
END CATCH;
GO