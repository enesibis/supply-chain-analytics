USE [SCM_3];
GO
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    ;WITH src AS
    (
        SELECT * FROM (VALUES
            ('ACME STEEL SUPPLY', 'SUPPLIER'),
            ('MEGA CUSTOMER LTD', 'CUSTOMER'),
            ('FAST CARRIER',      'CARRIER')
        ) v(partnerName, roleType)
    ),
    mapped AS
    (
        SELECT
            bp.partnerID,
            s.roleType,
            s.partnerName
        FROM src s
        JOIN dbo.BusinessPartner bp
            ON bp.partnerName = s.partnerName
    )
    INSERT INTO dbo.BusinessPartnerRole (partnerID, roleType)
    SELECT m.partnerID, m.roleType
    FROM mapped m
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.BusinessPartnerRole r
        WHERE r.partnerID = m.partnerID
          AND r.roleType = m.roleType
    );

    COMMIT;

    -- kontrol çıktısı
    SELECT
        r.partnerRoleID, r.partnerID, bp.partnerName, r.roleType, r.isActive, r.createdAt
    FROM dbo.BusinessPartnerRole r
    JOIN dbo.BusinessPartner bp ON bp.partnerID = r.partnerID
    ORDER BY r.partnerRoleID;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH;
GO