USE [SCM_3];
GO
SET NOCOUNT ON;

-------------------------
-- 1) UNIT ID'LERİ
-------------------------
DECLARE @unitEA smallint = (SELECT unitID FROM dbo.Unit WHERE unitCode='EA');
DECLARE @unitKG smallint = (SELECT unitID FROM dbo.Unit WHERE unitCode='KG');
DECLARE @unitM2 smallint = (SELECT unitID FROM dbo.Unit WHERE unitCode='M2');

IF @unitEA IS NULL OR @unitKG IS NULL OR @unitM2 IS NULL
BEGIN
    RAISERROR('Unit tablosunda EA/KG/M2 eksik. Önce dbo.Unit verilerini ekle.', 16, 1);
    RETURN;
END

-------------------------
-- 2) CATEGORY ID'LERİ (varsa bağlarız)
-------------------------
DECLARE @catRaw      bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Hammadde'  AND parentCategoryID IS NULL);
DECLARE @catSemi     bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Yarı Mamul' AND parentCategoryID IS NULL);
DECLARE @catFinished bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Mamul'     AND parentCategoryID IS NULL);
DECLARE @catPack     bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Ambalaj'   AND parentCategoryID IS NULL);

DECLARE @catMetal bigint = CASE WHEN @catRaw IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Metal' AND parentCategoryID=@catRaw) END;
DECLARE @catFast  bigint = CASE WHEN @catRaw IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Bağlantı Elemanları' AND parentCategoryID=@catRaw) END;

DECLARE @catCutSheet bigint = CASE WHEN @catSemi IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Kesilmiş Sac' AND parentCategoryID=@catSemi) END;

DECLARE @catCabinet bigint = CASE WHEN @catFinished IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Dolap' AND parentCategoryID=@catFinished) END;

DECLARE @catBox bigint = CASE WHEN @catPack IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Koli' AND parentCategoryID=@catPack) END;
DECLARE @catStretch bigint = CASE WHEN @catPack IS NULL THEN NULL ELSE (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Streç Film' AND parentCategoryID=@catPack) END;

-------------------------
-- 3) PRODUCT INSERT (SKU varsa atlar)
-------------------------
INSERT INTO dbo.Product
(
    SKU, productName, productType, categoryID, unitID,
    brand, model_, barcode, description_
)
SELECT
    v.SKU, v.productName, v.productType, v.categoryID, v.unitID,
    v.brand, v.model_, v.barcode, v.description_
FROM (VALUES
    -- RAW MATERIAL
    ('RAW-001',  'Çelik Levha 2mm',            'RAW_MATERIAL',  @catMetal,   @unitKG, 'Generic', NULL, NULL, N'Üretimde kullanılan çelik levha (2mm).'),
    ('RAW-002',  'Dolap Menteşesi',           'RAW_MATERIAL',  @catFast,    @unitEA, 'Generic', NULL, NULL, N'Mobilya/metal dolap menteşesi.'),
    ('RAW-003',  'Altıgen Civata M8',         'RAW_MATERIAL',  @catFast,    @unitEA, 'Generic', NULL, NULL, N'Bağlantı elemanı.'),

    -- SEMI FINISHED
    ('SEMI-001', 'Kesilmiş Sac Panel',        'SEMI_FINISHED', @catCutSheet,@unitEA, 'Generic', NULL, NULL, N'Sac levhadan kesim sonrası yarı mamul panel.'),

    -- FINISHED GOOD
    ('FG-001',   'Metal Dolap 2 Kapaklı',     'FINISHED_GOOD', @catCabinet, @unitEA, 'Generic', NULL, NULL, N'2 kapaklı mamul metal dolap.'),

    -- PACKAGING (istersen productType RAW_MATERIAL olarak tutuyoruz)
    ('PACK-001', 'Koli 60x40x40',             'RAW_MATERIAL',  @catBox,     @unitEA, 'Generic', NULL, NULL, N'Sevkiyat kolisi.'),
    ('PACK-002', 'Streç Film 50cm',           'RAW_MATERIAL',  @catStretch, @unitEA, 'Generic', NULL, NULL, N'Paletleme için streç film.')
) AS v(SKU, productName, productType, categoryID, unitID, brand, model_, barcode, description_)
WHERE NOT EXISTS (SELECT 1 FROM dbo.Product p WHERE p.SKU = v.SKU);

-------------------------
-- 4) KONTROL
-------------------------
SELECT
    p.productID, p.SKU, p.productName, p.productType,
    pc.categoryName, u.unitCode, p.isActive, p.createdAt
FROM dbo.Product p
LEFT JOIN dbo.ProductCategory pc ON pc.categoryID = p.categoryID
JOIN dbo.Unit u ON u.unitID = p.unitID
ORDER BY p.productID;
GO