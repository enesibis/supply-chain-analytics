SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;

PRINT '============================================================';
PRINT 'MASTER DATA GENİŞLEME — SCM_3  (idempotent)';
PRINT 'Kapsam:';
PRINT '  5 Yeni BusinessPartner';
PRINT '  8 Yeni Adres';
PRINT '  8 Yeni Ürün (RAW/SEMI/FG/PACK)';
PRINT '  3 Yeni BOM + BOMItem';
PRINT '============================================================';
GO

-- ===========================================================
-- 1. BUSINESS PARTNER
-- ===========================================================
BEGIN TRY
    BEGIN TRAN;

    ;WITH src AS (
        SELECT * FROM (VALUES
            ('DELTA ALÜMİNYUM A.Ş.',    '2233445566', 'satis@deltaalu.com.tr',   '+90 212 555 01 01'),
            ('POLİMER PLASTİK LTD.',    '3344556677', 'tedarik@polimer.com.tr',  '+90 232 555 02 02'),
            ('STAR MARKETİNG A.Ş.',     '4455667788', 'siparis@starmkt.com.tr',  '+90 312 555 03 03'),
            ('KOCAELİ ENDÜSTRİ LTD.',   '5566778899', 'info@kocaeliend.com.tr',  '+90 262 555 04 04'),
            ('ARAS KARGO A.Ş.',         '6677889900', 'ops@araskargo.com.tr',    '+90 216 555 05 05')
        ) v(partnerName, taxNumber, email, phone)
    )
    INSERT INTO dbo.BusinessPartner (partnerName, taxNumber, email, phone)
    SELECT s.partnerName, s.taxNumber, s.email, s.phone
    FROM src s
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BusinessPartner bp WHERE bp.partnerName = s.partnerName
    );

    COMMIT;
    PRINT 'OK 1 | BusinessPartner eklendi';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 2. BUSINESS PARTNER ROLE
-- ===========================================================
BEGIN TRY
    BEGIN TRAN;

    ;WITH src AS (
        SELECT * FROM (VALUES
            ('DELTA ALÜMİNYUM A.Ş.',  'SUPPLIER'),
            ('POLİMER PLASTİK LTD.',  'SUPPLIER'),
            ('STAR MARKETİNG A.Ş.',   'CUSTOMER'),
            ('KOCAELİ ENDÜSTRİ LTD.', 'CUSTOMER'),
            ('KOCAELİ ENDÜSTRİ LTD.', 'SUPPLIER'),   -- çift rol: hem alıcı hem tedarikçi
            ('ARAS KARGO A.Ş.',       'CARRIER')
        ) v(partnerName, roleType)
    )
    INSERT INTO dbo.BusinessPartnerRole (partnerID, roleType)
    SELECT bp.partnerID, s.roleType
    FROM src s
    JOIN dbo.BusinessPartner bp ON bp.partnerName = s.partnerName
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BusinessPartnerRole r
        WHERE r.partnerID = bp.partnerID AND r.roleType = s.roleType
    );

    COMMIT;
    PRINT 'OK 2 | BusinessPartnerRole eklendi';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 3. ADRES — yeni adresler (districtID ile)
-- ===========================================================
BEGIN TRY
    BEGIN TRAN;

    -- Kullanılacak districtID'ler (mevcut District tablosundan)
    DECLARE @dLevent    INT = (SELECT districtID FROM dbo.District WHERE districtName='Levent');
    DECLARE @dAlsancak  INT = (SELECT districtID FROM dbo.District WHERE districtName='Alsancak');
    DECLARE @dKizilay   INT = (SELECT districtID FROM dbo.District WHERE districtName='Kızılay');
    DECLARE @dErciyes   INT = (SELECT districtID FROM dbo.District WHERE districtName='Erciyes');
    DECLARE @dGoztepe   INT = (SELECT districtID FROM dbo.District WHERE districtName='Göztepe');
    DECLARE @dCaferaga  INT = (SELECT districtID FROM dbo.District WHERE districtName='Caferağa');
    DECLARE @dEtiler    INT = (SELECT districtID FROM dbo.District WHERE districtName='Etiler');
    DECLARE @dBahceliev INT = (SELECT districtID FROM dbo.District WHERE districtName='Bahçelievler');

    INSERT INTO dbo.Address (districtID, postalCode, addressLine1, addressLine2)
    SELECT v.districtID, v.postalCode, v.addressLine1, v.addressLine2
    FROM (VALUES
        -- DELTA ALÜMİNYUM — İstanbul, Beşiktaş, Levent
        (@dLevent,    '34330', 'Levent Mah. Nispetiye Cd. No:18',          'Kat 3'),
        (@dLevent,    '34330', 'Levent Mah. Büyükdere Cd. No:201',         'Depo Blok'),

        -- POLİMER PLASTİK — İzmir, Konak, Alsancak
        (@dAlsancak,  '35220', 'Alsancak Mah. 1380 Sk. No:22',             NULL),

        -- STAR MARKETİNG — Ankara, Çankaya, Kızılay
        (@dKizilay,   '06420', 'Kızılay Mah. Ziya Gökalp Cd. No:44',       'Ofis 7'),
        (@dBahceliev, '06490', 'Bahçelievler Mah. 7. Cd. No:9',            NULL),

        -- KOCAELİ ENDÜSTRİ — Kayseri, Melikgazi, Erciyes
        (@dErciyes,   '38040', 'Erciyes Mah. Organize San. Blv. No:55',    NULL),
        (@dErciyes,   '38040', 'Erciyes Mah. Sanayi Cd. No:12',            'Lojistik Kapı'),

        -- ARAS KARGO — İstanbul, Kadıköy, Göztepe
        (@dGoztepe,   '34730', 'Göztepe Mah. Bağdat Cd. No:310',           NULL)
    ) v(districtID, postalCode, addressLine1, addressLine2)
    WHERE v.districtID IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM dbo.Address a
        WHERE a.addressLine1 = v.addressLine1
          AND ISNULL(a.postalCode,'') = ISNULL(v.postalCode,'')
    );

    COMMIT;
    PRINT 'OK 3 | Adresler eklendi';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 4. BUSINESS PARTNER ADDRESS
-- ===========================================================
BEGIN TRY
    BEGIN TRAN;

    DECLARE @src TABLE (
        partnerName  VARCHAR(200),
        addressLine1 VARCHAR(250),
        postalCode   VARCHAR(15),
        addressType  VARCHAR(30),
        isPrimary    BIT
    );

    INSERT INTO @src VALUES
        ('DELTA ALÜMİNYUM A.Ş.',  'Levent Mah. Nispetiye Cd. No:18',       '34330', 'HQ',       1),
        ('DELTA ALÜMİNYUM A.Ş.',  'Levent Mah. Büyükdere Cd. No:201',      '34330', 'SHIPPING', 1),
        ('POLİMER PLASTİK LTD.',  'Alsancak Mah. 1380 Sk. No:22',          '35220', 'HQ',       1),
        ('STAR MARKETİNG A.Ş.',   'Kızılay Mah. Ziya Gökalp Cd. No:44',    '06420', 'HQ',       1),
        ('STAR MARKETİNG A.Ş.',   'Bahçelievler Mah. 7. Cd. No:9',         '06490', 'SHIPPING', 1),
        ('KOCAELİ ENDÜSTRİ LTD.', 'Erciyes Mah. Organize San. Blv. No:55', '38040', 'HQ',       1),
        ('KOCAELİ ENDÜSTRİ LTD.', 'Erciyes Mah. Sanayi Cd. No:12',         '38040', 'SHIPPING', 1),
        ('ARAS KARGO A.Ş.',       'Göztepe Mah. Bağdat Cd. No:310',        '34730', 'HQ',       1);

    -- Address ID'lerini eşleştir, partner ID'lerini al ve ekle
    INSERT INTO dbo.BusinessPartnerAddress (partnerID, addressID, addressType, isPrimary)
    SELECT bp.partnerID, a.addressID, s.addressType, s.isPrimary
    FROM @src s
    JOIN dbo.BusinessPartner bp ON bp.partnerName = s.partnerName
    JOIN dbo.Address a
      ON a.addressLine1 = s.addressLine1
     AND ISNULL(a.postalCode,'') = ISNULL(s.postalCode,'')
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BusinessPartnerAddress bpa
        WHERE bpa.partnerID   = bp.partnerID
          AND bpa.addressID   = a.addressID
          AND bpa.addressType = s.addressType
    );

    COMMIT;
    PRINT 'OK 4 | BusinessPartnerAddress eklendi';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 5. ÜRÜNLER
-- ===========================================================
BEGIN TRY
    -- Unit ID'leri
    DECLARE @uEA  SMALLINT = (SELECT unitID FROM dbo.Unit WHERE unitCode='EA');
    DECLARE @uKG  SMALLINT = (SELECT unitID FROM dbo.Unit WHERE unitCode='KG');
    DECLARE @uM   SMALLINT = (SELECT unitID FROM dbo.Unit WHERE unitCode='M');

    -- Kategori ID'leri
    DECLARE @catMetal   BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Metal');
    DECLARE @catBaglant BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Bağlantı Elemanları');
    DECLARE @catBoya    BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Boya');
    DECLARE @catPlastik BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Plastik');
    DECLARE @catBukum   BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Bükülmüş Parça');
    DECLARE @catDolap   BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Dolap');
    DECLARE @catRaf     BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Raf Sistemi');
    DECLARE @catKap     BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Kapak');
    DECLARE @catKoseben BIGINT = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Köşebent');

    INSERT INTO dbo.Product (SKU, productName, productType, categoryID, unitID, brand, model_, barcode, description_)
    SELECT v.SKU, v.productName, v.productType, v.categoryID, v.unitID, v.brand, v.model_, v.barcode, v.description_
    FROM (VALUES
        -- RAW MATERIAL
        ('RAW-004', N'Alüminyum Profil 40x40',     'RAW_MATERIAL',  @catMetal,   @uKG,  'Generic', NULL, NULL, N'Yapısal alüminyum profil, 40x40 mm kesit.'),
        ('RAW-005', N'Rondela M8 Çelik',           'RAW_MATERIAL',  @catBaglant, @uEA,  'Generic', NULL, NULL, N'Standart M8 çelik rondela.'),
        ('RAW-006', N'Epoksi Boya Gri 7035',       'RAW_MATERIAL',  @catBoya,    @uKG,  'Generic', NULL, NULL, N'Endüstriyel epoksi toz boya, RAL 7035 açık gri.'),
        ('RAW-007', N'PP Granül Doğal',             'RAW_MATERIAL',  @catPlastik, @uKG,  'Generic', NULL, NULL, N'Enjeksiyon kalıplamaya uygun polipropilen granül.'),
        ('RAW-008', N'Paslanmaz Boru Ø25',         'RAW_MATERIAL',  @catMetal,   @uM,   'Generic', NULL, NULL, N'304 kalite paslanmaz çelik boru, dış çap 25 mm.'),

        -- SEMI FINISHED
        ('SEMI-002', N'Boyalı Sac Panel',          'SEMI_FINISHED', @catBukum,   @uEA,  'Generic', NULL, NULL, N'Epoksi boyalı, preslenmiş sac panel, 1000x500 mm.'),

        -- FINISHED GOOD
        ('FG-002',  N'Metal Dolap 4 Kapaklı',      'FINISHED_GOOD', @catDolap,   @uEA,  'Generic', NULL, NULL, N'4 kapaklı boyalı metal dolap, 180x90x40 cm.'),
        ('FG-003',  N'Çelik Raf Sistemi 5 Katlı',  'FINISHED_GOOD', @catRaf,     @uEA,  'Generic', NULL, NULL, N'Endüstriyel 5 katlı çelik raf sistemi, 200x100x50 cm.'),
        ('FG-004',  N'Metal Kapak Seti 2li',        'FINISHED_GOOD', @catKap,     @uEA,  'Generic', NULL, NULL, N'Dolap için 2 adet menteşeli metal kapak seti.'),

        -- PACKAGING
        ('PACK-003', N'Köşebent Koruyucu 50cm',    'RAW_MATERIAL',  @catKoseben, @uEA,  'Generic', NULL, NULL, N'Paletleme için karton köşebent koruyucu, 50 cm.')
    ) v(SKU, productName, productType, categoryID, unitID, brand, model_, barcode, description_)
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Product p WHERE p.SKU = v.SKU);

    PRINT 'OK 5 | Ürünler eklendi';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 6. BOM — yeni ürünler için reçeteler
-- ===========================================================
BEGIN TRY
    DECLARE @pFG2   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='FG-002');
    DECLARE @pFG3   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='FG-003');
    DECLARE @pSEMI2 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='SEMI-002');

    IF @pFG2   IS NULL THROW 50200, 'FG-002 bulunamadı.',   1;
    IF @pFG3   IS NULL THROW 50201, 'FG-003 bulunamadı.',   1;
    IF @pSEMI2 IS NULL THROW 50202, 'SEMI-002 bulunamadı.', 1;

    -- FG-002 BOM
    INSERT INTO dbo.BOM (productID, version)
    SELECT @pFG2, '1.0'
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BOM WHERE productID=@pFG2 AND version='1.0');

    -- FG-003 BOM
    INSERT INTO dbo.BOM (productID, version)
    SELECT @pFG3, '1.0'
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BOM WHERE productID=@pFG3 AND version='1.0');

    -- SEMI-002 BOM
    INSERT INTO dbo.BOM (productID, version)
    SELECT @pSEMI2, '1.0'
    WHERE NOT EXISTS (SELECT 1 FROM dbo.BOM WHERE productID=@pSEMI2 AND version='1.0');

    PRINT 'OK 6 | BOM eklendi';
END TRY
BEGIN CATCH
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- 7. BOM ITEM — reçete bileşenleri
-- ===========================================================
BEGIN TRY
    BEGIN TRAN;

    -- Ürün ID'leri
    DECLARE @pRaw1   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-001');  -- Çelik Levha 2mm
    DECLARE @pRaw2   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-002');  -- Dolap Menteşesi
    DECLARE @pRaw4   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-004');  -- Alüminyum Profil 40x40
    DECLARE @pRaw5   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-005');  -- Rondela M8
    DECLARE @pRaw6   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-006');  -- Epoksi Boya
    DECLARE @pRaw8   BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-008');  -- Paslanmaz Boru

    -- BOM ID'leri
    DECLARE @bomFG2   BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=(SELECT productID FROM dbo.Product WHERE SKU='FG-002')   AND isActive=1 ORDER BY bomID DESC);
    DECLARE @bomFG3   BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=(SELECT productID FROM dbo.Product WHERE SKU='FG-003')   AND isActive=1 ORDER BY bomID DESC);
    DECLARE @bomSEMI2 BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=(SELECT productID FROM dbo.Product WHERE SKU='SEMI-002') AND isActive=1 ORDER BY bomID DESC);

    -- FG-002 BOMItem: Çelik Levha x2 KG + Menteşe x8 EA + Epoksi Boya x0.30 KG
    -- (eklenmemişse ekle — lineNo_ ile kontrol)
    INSERT INTO dbo.BOMItem (bomID, lineNo_, componentProductID, quantityPer, scrapRate)
    SELECT v.bomID, v.lineNo_, v.compID, v.qty, v.scrap
    FROM (VALUES
        (@bomFG2, 1, @pRaw1, 2.000000, 0.0200),   -- Çelik Levha 2mm: 2 KG/adet, %2 fire
        (@bomFG2, 2, @pRaw2, 8.000000, 0.0200),   -- Dolap Menteşesi: 8 EA/adet, %2 fire
        (@bomFG2, 3, @pRaw6, 0.300000, 0.0500)    -- Epoksi Boya Gri: 0.30 KG/adet, %5 fire
    ) v(bomID, lineNo_, compID, qty, scrap)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BOMItem bi
        WHERE bi.bomID=v.bomID AND bi.lineNo_=v.lineNo_
    );

    -- FG-003 BOMItem: Alüminyum Profil x5 KG + Rondela x20 EA + Paslanmaz Boru x3 M
    INSERT INTO dbo.BOMItem (bomID, lineNo_, componentProductID, quantityPer, scrapRate)
    SELECT v.bomID, v.lineNo_, v.compID, v.qty, v.scrap
    FROM (VALUES
        (@bomFG3, 1, @pRaw4, 5.000000, 0.0100),   -- Alüminyum Profil: 5 KG/adet, %1 fire
        (@bomFG3, 2, @pRaw5, 20.000000, 0.0100),  -- Rondela M8: 20 EA/adet, %1 fire
        (@bomFG3, 3, @pRaw8, 3.000000, 0.0000)    -- Paslanmaz Boru: 3 M/adet, %0 fire
    ) v(bomID, lineNo_, compID, qty, scrap)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BOMItem bi
        WHERE bi.bomID=v.bomID AND bi.lineNo_=v.lineNo_
    );

    -- SEMI-002 BOMItem: Çelik Levha x1 KG + Epoksi Boya x0.15 KG
    INSERT INTO dbo.BOMItem (bomID, lineNo_, componentProductID, quantityPer, scrapRate)
    SELECT v.bomID, v.lineNo_, v.compID, v.qty, v.scrap
    FROM (VALUES
        (@bomSEMI2, 1, @pRaw1, 1.000000, 0.0300),  -- Çelik Levha 2mm: 1 KG/adet, %3 fire
        (@bomSEMI2, 2, @pRaw6, 0.150000, 0.0500)   -- Epoksi Boya Gri: 0.15 KG/adet, %5 fire
    ) v(bomID, lineNo_, compID, qty, scrap)
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BOMItem bi
        WHERE bi.bomID=v.bomID AND bi.lineNo_=v.lineNo_
    );

    COMMIT;
    PRINT 'OK 7 | BOMItem eklendi';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO

-- ===========================================================
-- ÖZET
-- ===========================================================
PRINT '';
PRINT '============================================================';
PRINT 'MASTER DATA GENİŞLEME TAMAMLANDI';
PRINT '============================================================';

PRINT '';
PRINT '--- İŞ ORTAKLARI ---';
SELECT bp.partnerID, bp.partnerName, bp.taxNumber, bp.email,
       STRING_AGG(r.roleType, ' | ') AS roller
FROM dbo.BusinessPartner bp
LEFT JOIN dbo.BusinessPartnerRole r ON r.partnerID=bp.partnerID AND r.isActive=1
GROUP BY bp.partnerID, bp.partnerName, bp.taxNumber, bp.email
ORDER BY bp.partnerID;

PRINT '';
PRINT '--- ADRESLER (yeni) ---';
SELECT
    bp.partnerName,
    bpa.addressType,
    a.postalCode,
    a.addressLine1,
    d.districtName,
    t.townName,
    c.cityName
FROM dbo.BusinessPartnerAddress bpa
JOIN dbo.BusinessPartner bp ON bp.partnerID=bpa.partnerID
JOIN dbo.Address a ON a.addressID=bpa.addressID
LEFT JOIN dbo.District d ON d.districtID=a.districtID
LEFT JOIN dbo.Town t ON t.townID=d.townID
LEFT JOIN dbo.City c ON c.cityID=t.cityID
WHERE bp.partnerName IN (
    'DELTA ALÜMİNYUM A.Ş.','POLİMER PLASTİK LTD.','STAR MARKETİNG A.Ş.',
    'KOCAELİ ENDÜSTRİ LTD.','ARAS KARGO A.Ş.'
)
ORDER BY bp.partnerName, bpa.addressType;

PRINT '';
PRINT '--- ÜRÜNLER ---';
SELECT p.SKU, p.productName, p.productType, pc.categoryName, u.unitCode
FROM dbo.Product p
LEFT JOIN dbo.ProductCategory pc ON pc.categoryID=p.categoryID
JOIN dbo.Unit u ON u.unitID=p.unitID
ORDER BY p.productType, p.SKU;

PRINT '';
PRINT '--- BOM & BOMItem ---';
SELECT
    b.bomID,
    fp.SKU          AS urun,
    b.version,
    bi.lineNo_,
    cp.SKU          AS bilesen,
    bi.quantityPer,
    bi.scrapRate
FROM dbo.BOM b
JOIN dbo.Product fp ON fp.productID=b.productID
LEFT JOIN dbo.BOMItem bi ON bi.bomID=b.bomID
LEFT JOIN dbo.Product cp ON cp.productID=bi.componentProductID
ORDER BY b.bomID, bi.lineNo_;
GO
