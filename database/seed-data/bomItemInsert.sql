USE [SCM_3];
GO

SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRAN;

    -- 1) Üst ürün (BOM'un ait olduğu ürün) ID
    DECLARE @fgProductID BIGINT =
    (
        SELECT TOP (1) productID
        FROM dbo.Product
        WHERE SKU = 'FG-001'
    );

    IF @fgProductID IS NULL
        THROW 50001, 'FG-001 SKU bulunamadı. Önce Product tablosuna ekle.', 1;

    -- 2) Bu ürünün aktif BOM'u (istersen version'a göre de filtrelersin)
    DECLARE @bomID BIGINT =
    (
        SELECT TOP (1) bomID
        FROM dbo.BOM
        WHERE productID = @fgProductID
          AND isActive = 1
        ORDER BY bomID DESC
    );

    IF @bomID IS NULL
        THROW 50002, 'FG-001 için aktif BOM bulunamadı. Önce BOM tablosuna ekle.', 1;

    -- 3) Bileşen ürün ID'leri
    DECLARE @comp1 BIGINT =
    (
        SELECT TOP (1) productID
        FROM dbo.Product
        WHERE SKU = 'RAW-001'
    );

    DECLARE @comp2 BIGINT =
    (
        SELECT TOP (1) productID
        FROM dbo.Product
        WHERE SKU = 'RAW-002'
    );

    IF @comp1 IS NULL OR @comp2 IS NULL
        THROW 50003, 'Component SKU (RAW-001/RAW-002) bulunamadı. Önce Product tablosuna ekle.', 1;

    -- (Opsiyonel) Aynı BOM için daha önce satır eklendiyse çakışmayı önlemek için temizle:
    -- DELETE FROM dbo.BOMItem WHERE bomID = @bomID;

    -- 4) BOMItem ekle
    INSERT INTO dbo.BOMItem (bomID, lineNo_, componentProductID, quantityPer, scrapRate)
    VALUES
        (@bomID, 1, @comp1, 1.000000, 0.0000),
        (@bomID, 2, @comp2, 4.000000, 0.0200);

    COMMIT;

    -- 5) Kontrol
    SELECT *
    FROM dbo.BOMItem
    WHERE bomID = @bomID
    ORDER BY lineNo_;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK;

    -- Hata detayı
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_SEVERITY() AS ErrorSeverity,
        ERROR_STATE()    AS ErrorState,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH;
GO