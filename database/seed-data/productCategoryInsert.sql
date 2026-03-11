USE [SCM_3];
GO
SET NOCOUNT ON;

-------------------------
-- 1) ÜST KATEGORİLER
-------------------------
IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE categoryName='Hammadde'    AND parentCategoryID IS NULL)
    INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID) VALUES ('Hammadde', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE categoryName='Yarı Mamul'   AND parentCategoryID IS NULL)
    INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID) VALUES ('Yarı Mamul', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE categoryName='Mamul'       AND parentCategoryID IS NULL)
    INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID) VALUES ('Mamul', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE categoryName='Ambalaj'     AND parentCategoryID IS NULL)
    INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID) VALUES ('Ambalaj', NULL);

IF NOT EXISTS (SELECT 1 FROM dbo.ProductCategory WHERE categoryName='Sarf Malzeme' AND parentCategoryID IS NULL)
    INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID) VALUES ('Sarf Malzeme', NULL);

-- ID’leri al
DECLARE @catRaw      bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Hammadde'     AND parentCategoryID IS NULL);
DECLARE @catSemi     bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Yarı Mamul'    AND parentCategoryID IS NULL);
DECLARE @catFinished bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Mamul'        AND parentCategoryID IS NULL);
DECLARE @catPack     bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Ambalaj'      AND parentCategoryID IS NULL);
DECLARE @catConsum   bigint = (SELECT categoryID FROM dbo.ProductCategory WHERE categoryName='Sarf Malzeme' AND parentCategoryID IS NULL);

-------------------------
-- 2) ALT KATEGORİLER
-------------------------
-- Hammadde altı
INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID)
SELECT v.name, @catRaw
FROM (VALUES
  ('Metal'), ('Plastik'), ('Bağlantı Elemanları'), ('Kimyasal'), ('Boya')
) v(name)
WHERE @catRaw IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductCategory
      WHERE categoryName = v.name AND parentCategoryID = @catRaw
  );

-- Yarı Mamul altı
INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID)
SELECT v.name, @catSemi
FROM (VALUES
  ('Kesilmiş Sac'), ('Bükümlü Parça'), ('Kaynaklı Parça'), ('İşlenmiş Parça')
) v(name)
WHERE @catSemi IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductCategory
      WHERE categoryName = v.name AND parentCategoryID = @catSemi
  );

-- Mamul altı
INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID)
SELECT v.name, @catFinished
FROM (VALUES
  ('Dolap'), ('Kapak'), ('Raf Sistemi'), ('Aksesuar')
) v(name)
WHERE @catFinished IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductCategory
      WHERE categoryName = v.name AND parentCategoryID = @catFinished
  );

-- Ambalaj altı
INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID)
SELECT v.name, @catPack
FROM (VALUES
  ('Koli'), ('Streç Film'), ('Palet Malzemesi'), ('Köşebent')
) v(name)
WHERE @catPack IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductCategory
      WHERE categoryName = v.name AND parentCategoryID = @catPack
  );

-- Sarf Malzeme altı
INSERT INTO dbo.ProductCategory (categoryName, parentCategoryID)
SELECT v.name, @catConsum
FROM (VALUES
  ('Eldiven'), ('Zımpara'), ('Kesici Uç'), ('Paketleme Bandı')
) v(name)
WHERE @catConsum IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM dbo.ProductCategory
      WHERE categoryName = v.name AND parentCategoryID = @catConsum
  );

-------------------------
-- 3) KONTROL (AĞAÇ GÖRÜNÜMÜ)
-------------------------
SELECT
  c.categoryID,
  c.categoryName,
  c.parentCategoryID,
  p.categoryName AS parentCategoryName,
  c.isActive,
  c.createdAt
FROM dbo.ProductCategory c
LEFT JOIN dbo.ProductCategory p ON p.categoryID = c.parentCategoryID
ORDER BY ISNULL(p.categoryName, c.categoryName), c.parentCategoryID, c.categoryName;
GO