USE [SCM_3];
GO
SET NOCOUNT ON;

-- Ürünleri SKU ile yakala
DECLARE @FG1   bigint = (SELECT productID FROM dbo.Product WHERE SKU = 'FG-001');     -- Metal Dolap 2 Kapaklı
DECLARE @SEMI1 bigint = (SELECT productID FROM dbo.Product WHERE SKU = 'SEMI-001');   -- Kesilmiş Sac Panel

IF @FG1 IS NULL
BEGIN
    RAISERROR('Product bulunamadı: FG-001. Önce Product tablosuna ekle.', 16, 1);
    RETURN;
END

-- (Opsiyonel) SEMI-001 yoksa sorun yapmayalım; sadece varsa BOM açalım
-- BOM ekle (FG-001 için)
INSERT INTO dbo.BOM (productID, version)
SELECT @FG1, '1.0'
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.BOM b
    WHERE b.productID = @FG1 AND b.version = '1.0'
);

-- BOM ekle (SEMI-001 için - varsa)
IF @SEMI1 IS NOT NULL
BEGIN
    INSERT INTO dbo.BOM (productID, version)
    SELECT @SEMI1, '1.0'
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.BOM b
        WHERE b.productID = @SEMI1 AND b.version = '1.0'
    );
END

-- Kontrol
SELECT
    b.bomID, b.version, b.isActive, b.createdAt,
    p.SKU, p.productName, p.productType
FROM dbo.BOM b
JOIN dbo.Product p ON p.productID = b.productID
ORDER BY b.bomID;
GO