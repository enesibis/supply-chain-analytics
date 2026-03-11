USE [SCM_3];
GO
SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    -------------------------------------------------------------------
    -- 1) Eklenecek partner-adres eşleşmeleri (burayı değiştirirsin)
    -------------------------------------------------------------------
    DECLARE @src TABLE
    (
        partnerName   varchar(200),
        addressType   varchar(30),
        isPrimary     bit,
        addressLine1  varchar(250),
        addressLine2  varchar(250),
        postalCode    varchar(15),
        districtID    int
    );

    INSERT INTO @src (partnerName, addressType, isPrimary, addressLine1, addressLine2, postalCode, districtID)
    VALUES
    ('ACME STEEL SUPPLY', 'HQ',       1, 'İkitelli OSB, Atatürk Blv No:10, Başakşehir/İstanbul', NULL, '34306', NULL),
    ('ACME STEEL SUPPLY', 'BILLING',  1, 'İkitelli OSB, Muhasebe Cd No:5, Başakşehir/İstanbul',  NULL, '34306', NULL),

    ('MEGA CUSTOMER LTD', 'HQ',       1, 'Organize Sanayi, 2. Cd No:20, Gebze/Kocaeli',          NULL, '41400', NULL),
    ('MEGA CUSTOMER LTD', 'SHIPPING', 1, 'Depo: Dilovası, Lojistik Sk No:7, Kocaeli',             NULL, '41455', NULL),

    ('FAST CARRIER',      'HQ',       1, 'Lojistik Merkez, 1. Sk No:3, Pendik/İstanbul',          NULL, '34912', NULL);

    -------------------------------------------------------------------
    -- 2) PartnerID kontrol + map
    -------------------------------------------------------------------
    ;WITH p AS
    (
        SELECT s.*, bp.partnerID
        FROM @src s
        JOIN dbo.BusinessPartner bp
          ON bp.partnerName = s.partnerName
    )
    SELECT * INTO #mapped FROM p;

    IF EXISTS (SELECT 1 FROM @src s WHERE NOT EXISTS (SELECT 1 FROM #mapped m WHERE m.partnerName = s.partnerName))
        THROW 50010, 'Bazı partnerName değerleri BusinessPartner tablosunda bulunamadı. Önce BusinessPartner insert et.', 1;

    -------------------------------------------------------------------
    -- 3) Address yoksa ekle (basit eşleşme: addressLine1 + postalCode)
    -------------------------------------------------------------------
    DECLARE @addr TABLE
    (
        addressLine1 varchar(250),
        postalCode   varchar(15),
        addressID    bigint
    );

    -- Var olanları topla
    INSERT INTO @addr (addressLine1, postalCode, addressID)
    SELECT DISTINCT a.addressLine1, a.postalCode, a.addressID
    FROM dbo.Address a
    JOIN (SELECT DISTINCT addressLine1, postalCode FROM #mapped) x
      ON x.addressLine1 = a.addressLine1
     AND ISNULL(x.postalCode,'') = ISNULL(a.postalCode,'');

    -- Eksik olanları ekle
    INSERT INTO dbo.Address (districtID, postalCode, addressLine1, addressLine2, createdAt)
    OUTPUT inserted.addressLine1, inserted.postalCode, inserted.addressID
    INTO @addr (addressLine1, postalCode, addressID)
    SELECT DISTINCT
        m.districtID,
        m.postalCode,
        m.addressLine1,
        m.addressLine2,
        SYSUTCDATETIME()
    FROM #mapped m
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM @addr a
        WHERE a.addressLine1 = m.addressLine1
          AND ISNULL(a.postalCode,'') = ISNULL(m.postalCode,'')
    );

    -------------------------------------------------------------------
    -- 4) BusinessPartnerAddress ekle (varsa ekleme)
    --    + aynı partner+addressType için yeni primary geldiyse eskileri 0 yap
    -------------------------------------------------------------------
    ;WITH x AS
    (
        SELECT
            m.partnerID,
            a.addressID,
            m.addressType,
            m.isPrimary
        FROM #mapped m
        JOIN @addr a
          ON a.addressLine1 = m.addressLine1
         AND ISNULL(a.postalCode,'') = ISNULL(m.postalCode,'')
    )
    -- Primary set edilecekse aynı partner + type eski primaryleri kapat
    UPDATE bpa
       SET bpa.isPrimary = 0
    FROM dbo.BusinessPartnerAddress bpa
    JOIN x
      ON x.partnerID = bpa.partnerID
     AND x.addressType = bpa.addressType
    WHERE x.isPrimary = 1
      AND bpa.isPrimary = 1;

    -- Insert (UQ korumalı)
    INSERT INTO dbo.BusinessPartnerAddress (partnerID, addressID, addressType, isPrimary)
    SELECT x.partnerID, x.addressID, x.addressType, x.isPrimary
    FROM x
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.BusinessPartnerAddress bpa
        WHERE bpa.partnerID = x.partnerID
          AND bpa.addressID = x.addressID
          AND bpa.addressType = x.addressType
    );

    COMMIT;

    -------------------------------------------------------------------
    -- 5) Kontrol
    -------------------------------------------------------------------
    SELECT
        bpa.partnerAddressID,
        bp.partnerName,
        bpa.addressType,
        bpa.isPrimary,
        a.addressLine1,
        a.postalCode,
        bpa.createdAt
    FROM dbo.BusinessPartnerAddress bpa
    JOIN dbo.BusinessPartner bp ON bp.partnerID = bpa.partnerID
    JOIN dbo.Address a ON a.addressID = bpa.addressID
    ORDER BY bp.partnerName, bpa.addressType, bpa.isPrimary DESC;

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