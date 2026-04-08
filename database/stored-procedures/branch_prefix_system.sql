-- ============================================================
-- SCM_3 - SUBE BAZLI BELGE NUMARASI SISTEMI
-- Format: {DocType}-{SubeKodu}-{Yil}-{Sira:05d}
-- Ornek:  SO-IST-2024-00001
-- ============================================================

-- ── 1. SEQUENCE TABLOSU ──────────────────────────────────────
-- Her docType + sube + yil icin son sira numarasini tutar
-- Yeni insert oldugunda atomik olarak arttirilir

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name = 'DocNumberSequence')
BEGIN
    CREATE TABLE DocNumberSequence (
        seqID     INT IDENTITY(1,1) PRIMARY KEY,
        docType   NVARCHAR(10)  NOT NULL,  -- SO, PO, PRO, GR, SH
        subeID    INT           NOT NULL REFERENCES Sube(subeID),
        yil       INT           NOT NULL,
        sonSira   INT           NOT NULL DEFAULT 0,
        CONSTRAINT UQ_DocSeq UNIQUE (docType, subeID, yil)
    );
    PRINT 'DocNumberSequence tablosu olusturuldu.';
END
GO

-- ── 2. NUMARA URETME FONKSIYONU ───────────────────────────────
-- Verilen docType + subeID + yil icin sonraki sira numarasini
-- atomik sekilde alir ve formatli numara doner

CREATE OR ALTER FUNCTION dbo.fn_NextDocNumber (
    @docType NVARCHAR(10),
    @subeID  INT,
    @yil     INT
)
RETURNS NVARCHAR(30)
AS
BEGIN
    -- Bu fonksiyon trigger icinden MERGE ile cagrilacak,
    -- asil atomik artirma trigger'da yapilir.
    -- Burada sadece format olusturma:
    DECLARE @subeKodu  NVARCHAR(20);
    DECLARE @sonSira   INT;

    SELECT @subeKodu = subeKodu FROM Sube WHERE subeID = @subeID;

    SELECT @sonSira = ISNULL(sonSira, 0)
    FROM DocNumberSequence
    WHERE docType = @docType AND subeID = @subeID AND yil = @yil;

    RETURN CONCAT(@docType, '-', @subeKodu, '-', @yil, '-', FORMAT(@sonSira, '00000'));
END
GO

-- ── 3. MEVCUT KAYITLARI GUNCELLE ─────────────────────────────
-- Tum tablolardaki eski numaralari yeni formata cevir.
-- Her sube+yil icin 1'den baslayan sira atanir.

PRINT 'Mevcut kayitlar guncelleniyor...';

-- 3a. SalesOrder
WITH Siralama AS (
    SELECT salesOrderID, subeID,
           YEAR(orderDate) AS yil,
           ROW_NUMBER() OVER (PARTITION BY subeID, YEAR(orderDate)
                              ORDER BY orderDate, salesOrderID) AS sira
    FROM SalesOrder
)
UPDATE so
SET so.orderNumber = CONCAT('SO-', s.subeKodu, '-', sr.yil, '-', FORMAT(sr.sira, '00000'))
FROM SalesOrder so
JOIN Siralama sr ON so.salesOrderID = sr.salesOrderID
JOIN Sube s ON so.subeID = s.subeID;

PRINT '  SalesOrder: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' kayit guncellendi.';

-- 3b. PurchaseOrder
WITH Siralama AS (
    SELECT purchaseOrderID, subeID,
           YEAR(orderDate) AS yil,
           ROW_NUMBER() OVER (PARTITION BY subeID, YEAR(orderDate)
                              ORDER BY orderDate, purchaseOrderID) AS sira
    FROM PurchaseOrder
)
UPDATE po
SET po.orderNumber = CONCAT('PO-', s.subeKodu, '-', sr.yil, '-', FORMAT(sr.sira, '00000'))
FROM PurchaseOrder po
JOIN Siralama sr ON po.purchaseOrderID = sr.purchaseOrderID
JOIN Sube s ON po.subeID = s.subeID;

PRINT '  PurchaseOrder: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' kayit guncellendi.';

-- 3c. ProductionOrder
WITH Siralama AS (
    SELECT productionOrderID, subeID,
           YEAR(ISNULL(startDate, GETDATE())) AS yil,
           ROW_NUMBER() OVER (PARTITION BY subeID, YEAR(ISNULL(startDate, GETDATE()))
                              ORDER BY ISNULL(startDate, GETDATE()), productionOrderID) AS sira
    FROM ProductionOrder
)
UPDATE prod
SET prod.orderNumber = CONCAT('PRO-', s.subeKodu, '-', sr.yil, '-', FORMAT(sr.sira, '00000'))
FROM ProductionOrder prod
JOIN Siralama sr ON prod.productionOrderID = sr.productionOrderID
JOIN Sube s ON prod.subeID = s.subeID;

PRINT '  ProductionOrder: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' kayit guncellendi.';

-- 3d. GoodsReceipt (subeID yok, PurchaseOrder uzerinden alinir)
WITH Siralama AS (
    SELECT gr.goodsReceiptID, po.subeID,
           YEAR(gr.receiptDate) AS yil,
           ROW_NUMBER() OVER (PARTITION BY po.subeID, YEAR(gr.receiptDate)
                              ORDER BY gr.receiptDate, gr.goodsReceiptID) AS sira
    FROM GoodsReceipt gr
    JOIN PurchaseOrder po ON gr.purchaseOrderID = po.purchaseOrderID
)
UPDATE gr
SET gr.receiptNumber = CONCAT('GR-', s.subeKodu, '-', sr.yil, '-', FORMAT(sr.sira, '00000'))
FROM GoodsReceipt gr
JOIN Siralama sr ON gr.goodsReceiptID = sr.goodsReceiptID
JOIN Sube s ON sr.subeID = s.subeID;

PRINT '  GoodsReceipt: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' kayit guncellendi.';

-- 3e. Shipment (subeID yok, SalesOrder uzerinden alinir)
WITH Siralama AS (
    SELECT sh.shipmentID, so.subeID,
           YEAR(sh.shipmentDate) AS yil,
           ROW_NUMBER() OVER (PARTITION BY so.subeID, YEAR(sh.shipmentDate)
                              ORDER BY sh.shipmentDate, sh.shipmentID) AS sira
    FROM Shipment sh
    JOIN SalesOrder so ON sh.salesOrderID = so.salesOrderID
)
UPDATE sh
SET sh.shipmentNumber = CONCAT('SH-', s.subeKodu, '-', sr.yil, '-', FORMAT(sr.sira, '00000'))
FROM Shipment sh
JOIN Siralama sr ON sh.shipmentID = sr.shipmentID
JOIN Sube s ON sr.subeID = s.subeID;

PRINT '  Shipment: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' kayit guncellendi.';

-- ── 4. SEQUENCE TABLOSUNU DOLDUR ─────────────────────────────
-- Mevcut en buyuk sira numarasini kaydet (yeni insertlar buradan devam eder)

INSERT INTO DocNumberSequence (docType, subeID, yil, sonSira)
SELECT 'SO', subeID, YEAR(orderDate),
       COUNT(*) -- her sube+yil icin kac kayit var = son sira
FROM SalesOrder
GROUP BY subeID, YEAR(orderDate);

INSERT INTO DocNumberSequence (docType, subeID, yil, sonSira)
SELECT 'PO', subeID, YEAR(orderDate), COUNT(*)
FROM PurchaseOrder
GROUP BY subeID, YEAR(orderDate);

INSERT INTO DocNumberSequence (docType, subeID, yil, sonSira)
SELECT 'PRO', subeID, YEAR(ISNULL(startDate, GETDATE())), COUNT(*)
FROM ProductionOrder
GROUP BY subeID, YEAR(ISNULL(startDate, GETDATE()));

PRINT 'DocNumberSequence dolduruldu.';
GO

-- ── 5. TRİGGERLAR ────────────────────────────────────────────
-- Yeni kayit eklendiginde otomatik numara atar
-- MERGE ile atomik sekilde sira arttirilir

-- 5a. SalesOrder Trigger
CREATE OR ALTER TRIGGER TR_SalesOrder_AutoNumber
ON SalesOrder AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @salesOrderID INT, @subeID INT, @yil INT, @sira INT;
    DECLARE @subeKodu NVARCHAR(20), @yeniNo NVARCHAR(30);

    SELECT @salesOrderID = salesOrderID,
           @subeID       = subeID,
           @yil          = YEAR(orderDate)
    FROM inserted;

    -- Atomik sira artir
    MERGE DocNumberSequence AS target
    USING (SELECT 'SO' AS docType, @subeID AS subeID, @yil AS yil) AS src
    ON target.docType = src.docType AND target.subeID = src.subeID AND target.yil = src.yil
    WHEN MATCHED THEN
        UPDATE SET sonSira = sonSira + 1
    WHEN NOT MATCHED THEN
        INSERT (docType, subeID, yil, sonSira) VALUES ('SO', @subeID, @yil, 1);

    SELECT @sira     = sonSira FROM DocNumberSequence
    WHERE docType = 'SO' AND subeID = @subeID AND yil = @yil;

    SELECT @subeKodu = subeKodu FROM Sube WHERE subeID = @subeID;

    SET @yeniNo = CONCAT('SO-', @subeKodu, '-', @yil, '-', FORMAT(@sira, '00000'));

    UPDATE SalesOrder SET orderNumber = @yeniNo WHERE salesOrderID = @salesOrderID;
END
GO

-- 5b. PurchaseOrder Trigger
CREATE OR ALTER TRIGGER TR_PurchaseOrder_AutoNumber
ON PurchaseOrder AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @purchaseOrderID INT, @subeID INT, @yil INT, @sira INT;
    DECLARE @subeKodu NVARCHAR(20), @yeniNo NVARCHAR(30);

    SELECT @purchaseOrderID = purchaseOrderID,
           @subeID          = subeID,
           @yil             = YEAR(orderDate)
    FROM inserted;

    MERGE DocNumberSequence AS target
    USING (SELECT 'PO' AS docType, @subeID AS subeID, @yil AS yil) AS src
    ON target.docType = src.docType AND target.subeID = src.subeID AND target.yil = src.yil
    WHEN MATCHED THEN UPDATE SET sonSira = sonSira + 1
    WHEN NOT MATCHED THEN INSERT (docType, subeID, yil, sonSira) VALUES ('PO', @subeID, @yil, 1);

    SELECT @sira     = sonSira FROM DocNumberSequence
    WHERE docType = 'PO' AND subeID = @subeID AND yil = @yil;

    SELECT @subeKodu = subeKodu FROM Sube WHERE subeID = @subeID;

    SET @yeniNo = CONCAT('PO-', @subeKodu, '-', @yil, '-', FORMAT(@sira, '00000'));

    UPDATE PurchaseOrder SET orderNumber = @yeniNo WHERE purchaseOrderID = @purchaseOrderID;
END
GO

-- 5c. ProductionOrder Trigger
CREATE OR ALTER TRIGGER TR_ProductionOrder_AutoNumber
ON ProductionOrder AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @productionOrderID INT, @subeID INT, @yil INT, @sira INT;
    DECLARE @subeKodu NVARCHAR(20), @yeniNo NVARCHAR(30);

    SELECT @productionOrderID = productionOrderID,
           @subeID            = subeID,
           @yil               = YEAR(ISNULL(startDate, GETDATE()))
    FROM inserted;

    MERGE DocNumberSequence AS target
    USING (SELECT 'PRO' AS docType, @subeID AS subeID, @yil AS yil) AS src
    ON target.docType = src.docType AND target.subeID = src.subeID AND target.yil = src.yil
    WHEN MATCHED THEN UPDATE SET sonSira = sonSira + 1
    WHEN NOT MATCHED THEN INSERT (docType, subeID, yil, sonSira) VALUES ('PRO', @subeID, @yil, 1);

    SELECT @sira     = sonSira FROM DocNumberSequence
    WHERE docType = 'PRO' AND subeID = @subeID AND yil = @yil;

    SELECT @subeKodu = subeKodu FROM Sube WHERE subeID = @subeID;

    SET @yeniNo = CONCAT('PRO-', @subeKodu, '-', @yil, '-', FORMAT(@sira, '00000'));

    UPDATE ProductionOrder SET orderNumber = @yeniNo WHERE productionOrderID = @productionOrderID;
END
GO

-- ── 6. DOGRULAMA SORGUSU ─────────────────────────────────────
SELECT 'SalesOrder' AS Tablo, orderNumber, subeID FROM SalesOrder
WHERE orderNumber LIKE 'SO-%'
ORDER BY orderNumber
OFFSET 0 ROWS FETCH NEXT 5 ROWS ONLY;

SELECT docType, s.subeKodu, yil, sonSira AS SonSira
FROM DocNumberSequence seq
JOIN Sube s ON seq.subeID = s.subeID
ORDER BY docType, s.subeKodu, yil;
GO
