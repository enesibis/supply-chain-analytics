-- ============================================================
-- SCM_3 - ANALİTİK VIEW & SNAPSHOT SİSTEMİ
-- SQL Server Express 2019 (Agent yok → Python Task Scheduler)
--
-- MİMARİ:
--   Katman 1 - Core Views      : Ham veriden türetilen temel view'lar
--   Katman 2 - Snapshot Tables : Pre-computed özet tablolar (hızlı BI)
--   Katman 3 - TVF             : Parametrik sorgular (tarih/şube/kategori)
--   Katman 4 - sp_RefreshAll   : Tek komutla tüm snapshot güncelleme
-- ============================================================

-- ============================================================
-- KATMAN 1: CORE VIEW'LAR (güncel, direkt sorgu)
-- Power BI direkt bu view'lardan okur.
-- ============================================================

-- ── 1.1 SATIŞ SİPARİŞLERİ (detay) ───────────────────────────
CREATE OR ALTER VIEW dbo.vw_SatisSiparisleri AS
SELECT
    so.salesOrderID,
    so.orderNumber                          AS SiparisNo,
    LEFT(so.orderNumber, CHARINDEX('-',so.orderNumber,4)-1)
                                            AS BelgeTipi,       -- SO
    SUBSTRING(so.orderNumber,4,3)           AS SubeKisaKod,     -- IST
    CAST(so.orderDate AS DATE)              AS SiparisTarihi,
    YEAR(so.orderDate)                      AS Yil,
    MONTH(so.orderDate)                     AS Ay,
    DATENAME(MONTH, so.orderDate)           AS AyAdi,
    DATEPART(QUARTER, so.orderDate)         AS Ceyrek,
    so.status                               AS Durum,
    CASE so.status
        WHEN 'DRAFT'             THEN N'Taslak'
        WHEN 'APPROVED'          THEN N'Onaylandı'
        WHEN 'PARTIALLY_SHIPPED' THEN N'Kısmi Sevk'
        WHEN 'SHIPPED'           THEN N'Sevk Edildi'
        WHEN 'CANCELLED'         THEN N'İptal'
        ELSE so.status
    END                                     AS DurumTR,
    bp.partnerName                          AS Musteri,
    so.totalAmount                          AS ToplamTutar,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    s.sehir                                 AS SubeSehir,
    soi.lineNo_                             AS KalemNo,
    p.SKU,
    p.productName                           AS Urun,
    p.productType                           AS UrunTipi,
    pc.categoryName                         AS Kategori,
    soi.quantity                            AS Miktar,
    soi.unitPrice                           AS BirimFiyat,
    soi.shippedQuantity                     AS GonderildiMiktar,
    soi.totalPrice                          AS KalemTutar,
    CASE WHEN soi.quantity > 0
         THEN ROUND(100.0 * soi.shippedQuantity / soi.quantity, 1)
         ELSE 0 END                         AS GonderimOrani
FROM dbo.SalesOrder so
JOIN dbo.BusinessPartner bp ON so.customerPartnerID = bp.partnerID
JOIN dbo.Sube s              ON so.subeID = s.subeID
JOIN dbo.SalesOrderItem soi  ON so.salesOrderID = soi.salesOrderID
JOIN dbo.Product p           ON soi.productID = p.productID
JOIN dbo.ProductCategory pc  ON p.categoryID = pc.categoryID;
GO

-- ── 1.2 SATIN ALMA SİPARİŞLERİ (detay) ──────────────────────
CREATE OR ALTER VIEW dbo.vw_SatinAlmaSiparisleri AS
SELECT
    po.purchaseOrderID,
    po.orderNumber                          AS SiparisNo,
    SUBSTRING(po.orderNumber,4,3)           AS SubeKisaKod,
    CAST(po.orderDate AS DATE)              AS SiparisTarihi,
    CAST(po.expectedDeliveryDate AS DATE)   AS BeklenenTeslim,
    YEAR(po.orderDate)                      AS Yil,
    MONTH(po.orderDate)                     AS Ay,
    DATEPART(QUARTER, po.orderDate)         AS Ceyrek,
    DATEDIFF(DAY, po.orderDate,
        ISNULL(gr.receiptDate, po.expectedDeliveryDate))
                                            AS TeslimSuresi,
    po.status                               AS Durum,
    CASE po.status
        WHEN 'DRAFT'               THEN N'Taslak'
        WHEN 'APPROVED'            THEN N'Onaylandı'
        WHEN 'PARTIALLY_RECEIVED'  THEN N'Kısmi Alındı'
        WHEN 'RECEIVED'            THEN N'Alındı'
        WHEN 'CANCELLED'           THEN N'İptal'
        ELSE po.status
    END                                     AS DurumTR,
    bp.partnerName                          AS Tedarikci,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    s.sehir                                 AS SubeSehir,
    po.totalAmount                          AS ToplamTutar,
    poi.lineNo_                             AS KalemNo,
    p.productName                           AS Urun,
    pc.categoryName                         AS Kategori,
    poi.quantity                            AS SiparisMiktar,
    poi.unitPrice                           AS BirimFiyat,
    poi.receivedQuantity                    AS AlinanMiktar,
    poi.totalPrice                          AS KalemTutar,
    CASE WHEN poi.quantity > 0
         THEN ROUND(100.0 * poi.receivedQuantity / poi.quantity, 1)
         ELSE 0 END                         AS TeslimOrani
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp  ON po.supplierPartnerID = bp.partnerID
JOIN dbo.Sube s              ON po.subeID = s.subeID
JOIN dbo.PurchaseOrderItem poi ON po.purchaseOrderID = poi.purchaseOrderID
JOIN dbo.Product p           ON poi.productID = p.productID
JOIN dbo.ProductCategory pc  ON p.categoryID = pc.categoryID
LEFT JOIN dbo.GoodsReceipt gr ON gr.purchaseOrderID = po.purchaseOrderID
    AND gr.status = 'POSTED';
GO

-- ── 1.3 ÜRETİM EMİRLERİ ──────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_UretimEmirleri AS
SELECT
    prod.productionOrderID,
    prod.orderNumber                        AS EmirNo,
    SUBSTRING(prod.orderNumber,5,3)         AS SubeKisaKod,
    CAST(prod.startDate AS DATE)            AS BaslangicTarihi,
    CAST(prod.endDate AS DATE)              AS BitisTarihi,
    DATEDIFF(DAY, prod.startDate, prod.endDate)
                                            AS UretimSuresiGun,
    YEAR(prod.startDate)                    AS Yil,
    MONTH(prod.startDate)                   AS Ay,
    DATEPART(QUARTER, prod.startDate)       AS Ceyrek,
    prod.status                             AS Durum,
    CASE prod.status
        WHEN 'DRAFT'       THEN N'Taslak'
        WHEN 'RELEASED'    THEN N'Yayınlandı'
        WHEN 'IN_PROGRESS' THEN N'Üretimde'
        WHEN 'COMPLETED'   THEN N'Tamamlandı'
        WHEN 'CANCELLED'   THEN N'İptal'
        ELSE prod.status
    END                                     AS DurumTR,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    p.productName                           AS Urun,
    pc.categoryName                         AS Kategori,
    prod.plannedQuantity                    AS PlanlananMiktar,
    prod.producedQuantity                   AS UretilenMiktar,
    CASE WHEN prod.plannedQuantity > 0
         THEN ROUND(100.0 * prod.producedQuantity / prod.plannedQuantity, 1)
         ELSE 0 END                         AS GerceklesmeOrani
FROM dbo.ProductionOrder prod
JOIN dbo.Sube s    ON prod.subeID = s.subeID
JOIN dbo.Product p ON prod.productID = p.productID
JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
WHERE prod.startDate IS NOT NULL;
GO

-- ── 1.4 SEVKİYATLAR (teslimat süresi analizi) ────────────────
CREATE OR ALTER VIEW dbo.vw_Sevkiyatlar AS
SELECT
    sh.shipmentID,
    sh.shipmentNumber                       AS SevkiyatNo,
    CAST(sh.shipmentDate AS DATE)           AS SevkiyatTarihi,
    YEAR(sh.shipmentDate)                   AS Yil,
    MONTH(sh.shipmentDate)                  AS Ay,
    sh.status                               AS Durum,
    so.orderNumber                          AS SiparisNo,
    DATEDIFF(DAY, so.orderDate, sh.shipmentDate)
                                            AS SiparisdenSevkeGun,
    bp_musteri.partnerName                  AS Musteri,
    bp_tasiyici.partnerName                 AS Tasiyici,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    p.productName                           AS Urun,
    shi.quantity                            AS SevkMiktar
FROM dbo.Shipment sh
JOIN dbo.SalesOrder so       ON sh.salesOrderID = so.salesOrderID
JOIN dbo.Sube s              ON so.subeID = s.subeID
JOIN dbo.BusinessPartner bp_musteri  ON sh.customerPartnerID = bp_musteri.partnerID
LEFT JOIN dbo.BusinessPartner bp_tasiyici ON sh.carrierPartnerID = bp_tasiyici.partnerID
JOIN dbo.ShipmentItem shi    ON sh.shipmentID = shi.shipmentID
JOIN dbo.Product p           ON shi.productID = p.productID;
GO

-- ── 1.5 STOK DURUMU ──────────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_StokDurumu AS
SELECT
    ib.warehouseID,
    w.warehouseName                         AS Depo,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    p.productID,
    p.productName                           AS Urun,
    p.SKU,
    pc.categoryName                         AS Kategori,
    p.productType                           AS UrunTipi,
    ib.onHandQty                            AS MevcutStok,
    ib.reservedQty                          AS RezerveStok,
    ib.onHandQty - ib.reservedQty          AS KullanilabilirStok,
    p.minStockLevel                         AS MinStokSeviyesi,
    CASE
        WHEN ib.onHandQty <= 0                      THEN N'Stok Yok'
        WHEN ib.onHandQty <= p.minStockLevel        THEN N'Kritik'
        WHEN ib.onHandQty <= p.minStockLevel * 1.5  THEN N'Düşük'
        ELSE N'Normal'
    END                                     AS StokDurumu,
    ib.updatedAt                            AS SonGuncelleme
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w    ON ib.warehouseID = w.warehouseID
JOIN dbo.Sube s         ON w.subeID = s.subeID
JOIN dbo.Product p      ON ib.productID = p.productID
JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID;
GO

-- ── 1.6 STOK HAREKETLERİ ─────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_StokHareketleri AS
SELECT
    sm.stockMovementID,
    CAST(sm.movementDate AS DATE)           AS HareketTarihi,
    YEAR(sm.movementDate)                   AS Yil,
    MONTH(sm.movementDate)                  AS Ay,
    DATEPART(QUARTER, sm.movementDate)      AS Ceyrek,
    sm.movementType                         AS HareketTipi,
    CASE sm.movementType
        WHEN 'PURCHASE_RECEIPT'        THEN N'Satın Alma Girişi'
        WHEN 'SALES_SHIPMENT'          THEN N'Satış Çıkışı'
        WHEN 'PRODUCTION_OUTPUT'       THEN N'Üretim Çıktısı'
        WHEN 'PRODUCTION_CONSUMPTION'  THEN N'Üretim Tüketimi'
        WHEN 'TRANSFER_IN'             THEN N'Transfer Girişi'
        WHEN 'TRANSFER_OUT'            THEN N'Transfer Çıkışı'
        WHEN 'ADJUSTMENT_IN'           THEN N'Düzeltme Artış'
        WHEN 'ADJUSTMENT_OUT'          THEN N'Düzeltme Azalış'
        ELSE sm.movementType
    END                                     AS HareketTipiTR,
    w.warehouseName                         AS Depo,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    p.productName                           AS Urun,
    pc.categoryName                         AS Kategori,
    sm.qtyIn                                AS GirisMiktar,
    sm.qtyOut                               AS CikisMiktar,
    sm.qtyIn - sm.qtyOut                    AS NetHareket,
    sm.refType                              AS ReferansTipi,
    sm.refID                                AS ReferansID
FROM dbo.StockMovement sm
JOIN dbo.Warehouse w    ON sm.warehouseID = w.warehouseID
JOIN dbo.Sube s         ON w.subeID = s.subeID
JOIN dbo.Product p      ON sm.productID = p.productID
JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID;
GO

-- ── 1.7 KPI KARTI (tek satır, Power BI KPI kartları) ─────────
CREATE OR ALTER VIEW dbo.vw_KPI AS
SELECT
    -- Satış
    (SELECT COUNT(*) FROM SalesOrder WHERE status NOT IN ('CANCELLED'))         AS ToplamSO,
    (SELECT COUNT(*) FROM SalesOrder WHERE status = 'SHIPPED')                  AS TamamlananSO,
    (SELECT ISNULL(SUM(totalAmount),0) FROM SalesOrder WHERE status='SHIPPED')  AS ToplamSatisTL,
    (SELECT COUNT(*) FROM SalesOrder WHERE status IN ('DRAFT','APPROVED'))      AS AktifSO,
    -- Satın Alma
    (SELECT COUNT(*) FROM PurchaseOrder WHERE status NOT IN ('CANCELLED'))      AS ToplamPO,
    (SELECT COUNT(*) FROM PurchaseOrder WHERE status = 'RECEIVED')              AS TamamlananPO,
    (SELECT ISNULL(SUM(totalAmount),0) FROM PurchaseOrder WHERE status='RECEIVED') AS ToplamSatinAlmaTL,
    -- Üretim
    (SELECT COUNT(*) FROM ProductionOrder WHERE status NOT IN ('CANCELLED'))    AS ToplamUretimEmri,
    (SELECT COUNT(*) FROM ProductionOrder WHERE status = 'COMPLETED')           AS TamamlananUretim,
    (SELECT ISNULL(SUM(producedQuantity),0) FROM ProductionOrder WHERE status='COMPLETED') AS ToplamUretimMiktar,
    -- Stok
    (SELECT COUNT(*) FROM InventoryBalance WHERE onHandQty <= 0)                AS StokYokSayisi,
    (SELECT COUNT(*) FROM vw_StokDurumu WHERE StokDurumu = N'Kritik')          AS KritikStokSayisi,
    -- Performans
    (SELECT ROUND(AVG(CAST(DATEDIFF(DAY,po.orderDate,gr_min.minRec) AS FLOAT)),1)
     FROM PurchaseOrder po
     JOIN (SELECT purchaseOrderID, MIN(receiptDate) AS minRec
           FROM GoodsReceipt GROUP BY purchaseOrderID) gr_min
       ON gr_min.purchaseOrderID = po.purchaseOrderID
     WHERE po.status='RECEIVED')                                                AS OrtTeslimSuresi,
    (SELECT ROUND(AVG(CAST(DATEDIFF(DAY,so.orderDate,sh.shipmentDate) AS FLOAT)),1)
     FROM Shipment sh JOIN SalesOrder so ON sh.salesOrderID=so.salesOrderID)    AS OrtSevkSuresi;
GO

-- ── 1.8 TEDARİKÇİ PERFORMANSI ────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_TedarikciPerformansi AS
SELECT
    bp.partnerID                            AS TedarikciID,
    bp.partnerName                          AS Tedarikci,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    YEAR(po.orderDate)                      AS Yil,
    COUNT(DISTINCT po.purchaseOrderID)      AS ToplamSiparis,
    SUM(po.totalAmount)                     AS ToplamTutar,
    SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)   AS TamamlananSiparis,
    SUM(CASE WHEN po.status='CANCELLED' THEN 1 ELSE 0 END)  AS IptalSiparis,
    ROUND(100.0 * SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*),0), 1)          AS TamamlamOrani,
    ROUND(AVG(CAST(DATEDIFF(DAY, po.orderDate, gr_min.minRec) AS FLOAT)), 1) AS OrtTeslimGun
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp ON po.supplierPartnerID = bp.partnerID
JOIN dbo.Sube s             ON po.subeID = s.subeID
LEFT JOIN (
    SELECT purchaseOrderID, MIN(receiptDate) AS minRec
    FROM dbo.GoodsReceipt GROUP BY purchaseOrderID
) gr_min ON gr_min.purchaseOrderID = po.purchaseOrderID
GROUP BY bp.partnerID, bp.partnerName, s.subeAdi, s.subeKodu, YEAR(po.orderDate);
GO

-- ── 1.9 MÜŞTERİ ANALİZİ (RFM) ───────────────────────────────
CREATE OR ALTER VIEW dbo.vw_MusteriAnalizi AS
SELECT
    bp.partnerID                            AS MusteriID,
    bp.partnerName                          AS Musteri,
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    COUNT(DISTINCT so.salesOrderID)         AS ToplamSiparis,
    SUM(so.totalAmount)                     AS ToplamCiro,
    AVG(so.totalAmount)                     AS OrtSiparisTutari,
    COUNT(DISTINCT soi.productID)           AS FarkliUrunSayisi,
    MIN(CAST(so.orderDate AS DATE))         AS IlkSiparisTarihi,
    MAX(CAST(so.orderDate AS DATE))         AS SonSiparisTarihi,
    DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) AS SonSiparidenGun, -- Recency
    COUNT(DISTINCT so.salesOrderID)         AS SiparisFrekansi,     -- Frequency
    SUM(so.totalAmount)                     AS MonetaryDeger,       -- Monetary
    -- RFM Segment
    CASE
        WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 90
             AND COUNT(DISTINCT so.salesOrderID) >= 5   THEN N'VIP'
        WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 180 THEN N'Aktif'
        WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 365 THEN N'Pasif'
        ELSE N'Kayıp Risk'
    END                                     AS MusteriSegment
FROM dbo.BusinessPartner bp
JOIN dbo.SalesOrder so ON so.customerPartnerID = bp.partnerID
JOIN dbo.SalesOrderItem soi ON soi.salesOrderID = so.salesOrderID
LEFT JOIN dbo.Sube s ON bp.subeID = s.subeID
WHERE so.status != 'CANCELLED'
GROUP BY bp.partnerID, bp.partnerName, s.subeID, s.subeAdi, s.subeKodu;
GO

-- ── 1.10 ŞUBE ÖZETİ ──────────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_SubeOzeti AS
SELECT
    s.subeID,
    s.subeAdi                               AS Sube,
    s.subeKodu,
    s.sehir,
    -- Satış
    COUNT(DISTINCT so.salesOrderID)         AS ToplamSiparis,
    ISNULL(SUM(so.totalAmount),0)           AS ToplamSatis,
    ISNULL(SUM(CASE WHEN so.status='SHIPPED' THEN so.totalAmount END),0) AS TamamlananSatis,
    -- Satın Alma
    COUNT(DISTINCT po.purchaseOrderID)      AS ToplamSatinAlma,
    ISNULL(SUM(po.totalAmount),0)           AS ToplamSatinAlmaTutar,
    -- Üretim
    COUNT(DISTINCT prod.productionOrderID)  AS ToplamUretimEmri,
    -- Karlılık (Satış - Satın Alma)
    ISNULL(SUM(so.totalAmount),0) -
    ISNULL(SUM(po.totalAmount),0)           AS TahminiKar
FROM dbo.Sube s
LEFT JOIN dbo.SalesOrder so     ON so.subeID = s.subeID AND so.status != 'CANCELLED'
LEFT JOIN dbo.PurchaseOrder po  ON po.subeID = s.subeID AND po.status != 'CANCELLED'
LEFT JOIN dbo.ProductionOrder prod ON prod.subeID = s.subeID AND prod.status != 'CANCELLED'
GROUP BY s.subeID, s.subeAdi, s.subeKodu, s.sehir;
GO

-- ── 1.11 ÜRÜN SATIŞ ANALİZİ ──────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_UrunSatisAnalizi AS
SELECT
    p.productID,
    p.productName                           AS Urun,
    p.SKU,
    pc.categoryName                         AS Kategori,
    p.productType                           AS UrunTipi,
    YEAR(so.orderDate)                      AS Yil,
    MONTH(so.orderDate)                     AS Ay,
    s.subeKodu,
    s.subeAdi                               AS Sube,
    COUNT(DISTINCT so.salesOrderID)         AS SiparisSayisi,
    SUM(soi.quantity)                       AS ToplamSatisMiktar,
    SUM(soi.totalPrice)                     AS ToplamSatisTutar,
    AVG(soi.unitPrice)                      AS OrtBirimFiyat,
    SUM(soi.shippedQuantity)                AS GonderilenMiktar,
    ROUND(100.0 * SUM(soi.shippedQuantity)
          / NULLIF(SUM(soi.quantity),0), 1) AS GonderimYuzdesi
FROM dbo.Product p
JOIN dbo.ProductCategory pc  ON p.categoryID = pc.categoryID
JOIN dbo.SalesOrderItem soi  ON soi.productID = p.productID
JOIN dbo.SalesOrder so       ON soi.salesOrderID = so.salesOrderID
JOIN dbo.Sube s              ON so.subeID = s.subeID
WHERE so.status != 'CANCELLED'
GROUP BY p.productID, p.productName, p.SKU, pc.categoryName,
         p.productType, YEAR(so.orderDate), MONTH(so.orderDate),
         s.subeKodu, s.subeAdi;
GO

-- ── 1.12 AYLIK NAKİT AKIŞI ───────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_AylikNakitAkisi AS
SELECT
    YEAR(tarih)  AS Yil,
    MONTH(tarih) AS Ay,
    DATENAME(MONTH, tarih) AS AyAdi,
    SUM(SatisGelir)     AS ToplamSatisGelir,
    SUM(SatinAlmaGider) AS ToplamSatinAlmaGider,
    SUM(SatisGelir) - SUM(SatinAlmaGider) AS NetNakitAkisi
FROM (
    SELECT CAST(so.orderDate AS DATE) AS tarih,
           so.totalAmount AS SatisGelir, 0 AS SatinAlmaGider
    FROM dbo.SalesOrder so
    WHERE so.status = 'SHIPPED'
    UNION ALL
    SELECT CAST(po.orderDate AS DATE),
           0, po.totalAmount
    FROM dbo.PurchaseOrder po
    WHERE po.status = 'RECEIVED'
) src
GROUP BY YEAR(tarih), MONTH(tarih), DATENAME(MONTH, tarih);
GO

-- ── 1.13 KRİTİK STOK ─────────────────────────────────────────
CREATE OR ALTER VIEW dbo.vw_KritikStok AS
SELECT TOP 100
    sd.subeKodu,
    sd.Sube,
    sd.Depo,
    sd.Urun,
    sd.Kategori,
    sd.MevcutStok,
    sd.MinStokSeviyesi,
    sd.StokDurumu,
    sd.KullanilabilirStok,
    sd.SonGuncelleme
FROM dbo.vw_StokDurumu sd
WHERE sd.StokDurumu IN (N'Kritik', N'Stok Yok')
ORDER BY sd.MevcutStok ASC;
GO

PRINT 'Katman 1: 13 core view olusturuldu/guncellendi.';
GO

-- ============================================================
-- KATMAN 2: SNAPSHOT TABLOLAR (pre-computed, hızlı BI)
-- Power BI büyük veri setlerinde bu tabloları kullanır.
-- sp_RefreshAllSnapshots ile güncellenir.
-- ============================================================

-- ── 2.1 Aylık Satış Özeti ────────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='snap_AylikSatis')
CREATE TABLE dbo.snap_AylikSatis (
    snapID        INT IDENTITY(1,1) PRIMARY KEY,
    Yil           INT,
    Ay            INT,
    AyAdi         NVARCHAR(20),
    Ceyrek        INT,
    subeID        INT,
    subeKodu      NVARCHAR(20),
    Sube          NVARCHAR(100),
    ToplamSiparis INT,
    TamamlananSiparis INT,
    IptalSiparis  INT,
    ToplamTutar   DECIMAL(18,2),
    ToplamMiktar  DECIMAL(18,2),
    OrtSiparisTutari DECIMAL(18,2),
    FarkliMusteriSayisi INT,
    FarkliUrunSayisi INT,
    snap_tarih    DATETIME DEFAULT GETDATE()
);
GO

-- ── 2.2 Aylık Satın Alma Özeti ───────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='snap_AylikSatinAlma')
CREATE TABLE dbo.snap_AylikSatinAlma (
    snapID        INT IDENTITY(1,1) PRIMARY KEY,
    Yil           INT, Ay INT, AyAdi NVARCHAR(20), Ceyrek INT,
    subeID        INT, subeKodu NVARCHAR(20), Sube NVARCHAR(100),
    ToplamSiparis INT, TamamlananSiparis INT, IptalSiparis INT,
    ToplamTutar   DECIMAL(18,2),
    OrtTeslimGun  DECIMAL(10,2),
    FarkliTedarikciSayisi INT,
    snap_tarih    DATETIME DEFAULT GETDATE()
);
GO

-- ── 2.3 Aylık Üretim Özeti ───────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='snap_AylikUretim')
CREATE TABLE dbo.snap_AylikUretim (
    snapID        INT IDENTITY(1,1) PRIMARY KEY,
    Yil           INT, Ay INT, AyAdi NVARCHAR(20), Ceyrek INT,
    subeID        INT, subeKodu NVARCHAR(20), Sube NVARCHAR(100),
    ToplamEmir    INT, TamamlananEmir INT, IptalEmir INT,
    PlanlananMiktar DECIMAL(18,2), UretilenMiktar DECIMAL(18,2),
    OrtGerceklesmeOrani DECIMAL(10,2),
    snap_tarih    DATETIME DEFAULT GETDATE()
);
GO

-- ── 2.4 Ürün Performans Özeti ────────────────────────────────
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE name='snap_UrunPerformans')
CREATE TABLE dbo.snap_UrunPerformans (
    snapID        INT IDENTITY(1,1) PRIMARY KEY,
    Yil           INT, Ay INT,
    productID     INT, Urun NVARCHAR(200), Kategori NVARCHAR(100),
    subeKodu      NVARCHAR(20),
    ToplamSatisMiktar DECIMAL(18,2),
    ToplamSatisTutar  DECIMAL(18,2),
    SiparisSayisi INT,
    snap_tarih    DATETIME DEFAULT GETDATE()
);
GO

PRINT 'Katman 2: 4 snapshot tablo olusturuldu.';
GO

-- ============================================================
-- KATMAN 3: PARAMETRİK TVF (Table-Valued Functions)
-- Power BI parametre ile çağırır: tarihe, şubeye, kategoriye göre.
-- ============================================================

-- ── 3.1 Tarih Aralığı Satış Raporu ──────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_SatisRaporu (
    @baslangic DATE,
    @bitis     DATE,
    @subeKodu  NVARCHAR(20) = NULL,   -- NULL = tüm şubeler
    @kategori  NVARCHAR(100) = NULL   -- NULL = tüm kategoriler
)
RETURNS TABLE AS RETURN (
    SELECT
        so.orderNumber      AS SiparisNo,
        CAST(so.orderDate AS DATE) AS SiparisTarihi,
        s.subeKodu, s.subeAdi AS Sube,
        bp.partnerName      AS Musteri,
        p.productName       AS Urun,
        pc.categoryName     AS Kategori,
        soi.quantity        AS Miktar,
        soi.unitPrice       AS BirimFiyat,
        soi.totalPrice      AS Tutar,
        so.status           AS Durum
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s             ON so.subeID = s.subeID
    JOIN dbo.BusinessPartner bp ON so.customerPartnerID = bp.partnerID
    JOIN dbo.SalesOrderItem soi ON so.salesOrderID = soi.salesOrderID
    JOIN dbo.Product p          ON soi.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE CAST(so.orderDate AS DATE) BETWEEN @baslangic AND @bitis
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND (@kategori IS NULL OR pc.categoryName = @kategori)
      AND so.status != 'CANCELLED'
);
GO

-- ── 3.2 Dönem Karşılaştırma ──────────────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_DonemKarsilastirma (
    @yil1 INT, @yil2 INT,
    @subeKodu NVARCHAR(20) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        MONTH(so.orderDate)             AS Ay,
        DATENAME(MONTH,so.orderDate)    AS AyAdi,
        s.subeKodu,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END) AS Donem1Tutar,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) AS Donem2Tutar,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil1 THEN 1 END) AS Donem1Siparis,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil2 THEN 1 END) AS Donem2Siparis,
        ROUND(100.0 *
            (SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) -
             SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END)) /
            NULLIF(SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END),0)
        , 1)                            AS BuyumeOrani
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s ON so.subeID = s.subeID
    WHERE YEAR(so.orderDate) IN (@yil1, @yil2)
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND so.status != 'CANCELLED'
    GROUP BY MONTH(so.orderDate), DATENAME(MONTH,so.orderDate), s.subeKodu
);
GO

-- ── 3.3 Tedarikçi Teslim Analizi ─────────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_TedarikciTeslimAnalizi (
    @yil INT,
    @subeKodu NVARCHAR(20) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        bp.partnerName              AS Tedarikci,
        s.subeKodu,
        COUNT(po.purchaseOrderID)   AS ToplamSiparis,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.orderDate,          gr_min.minRec) AS FLOAT)),1) AS OrtTeslimGun,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.expectedDeliveryDate, gr_min.minRec) AS FLOAT)),1) AS OrtGecikmeGun,
        SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END) AS ZamanindaTeslim,
        ROUND(100.0 * SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*),0), 1) AS ZamanindaTeslimOrani
    FROM dbo.PurchaseOrder po
    JOIN dbo.BusinessPartner bp ON po.supplierPartnerID=bp.partnerID
    JOIN dbo.Sube s             ON po.subeID=s.subeID
    LEFT JOIN (
        SELECT purchaseOrderID, MIN(receiptDate) AS minRec
        FROM dbo.GoodsReceipt GROUP BY purchaseOrderID
    ) gr_min ON gr_min.purchaseOrderID = po.purchaseOrderID
    WHERE YEAR(po.orderDate) = @yil
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND po.status != 'CANCELLED'
    GROUP BY bp.partnerName, s.subeKodu
);
GO

PRINT 'Katman 3: 3 parametrik TVF olusturuldu.';
GO

-- ============================================================
-- KATMAN 4: SNAPSHOT REFRESH STORED PROCEDURE
-- Python scripti bu SP'yi her gece çağırır.
-- Power BI Import Mode'da snap_ tablolarına bağlanır.
-- ============================================================

CREATE OR ALTER PROCEDURE dbo.sp_RefreshAllSnapshots
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @baslar DATETIME = GETDATE();
    PRINT 'Snapshot guncelleme basliyor: ' + CONVERT(NVARCHAR,@baslar,120);

    -- ── Snap 1: Aylık Satış ──────────────────────────────────
    TRUNCATE TABLE dbo.snap_AylikSatis;
    INSERT INTO dbo.snap_AylikSatis
        (Yil,Ay,AyAdi,Ceyrek,subeID,subeKodu,Sube,
         ToplamSiparis,TamamlananSiparis,IptalSiparis,
         ToplamTutar,ToplamMiktar,OrtSiparisTutari,
         FarkliMusteriSayisi,FarkliUrunSayisi)
    SELECT
        YEAR(so.orderDate), MONTH(so.orderDate),
        DATENAME(MONTH,so.orderDate),
        DATEPART(QUARTER,so.orderDate),
        s.subeID, s.subeKodu, s.subeAdi,
        COUNT(DISTINCT so.salesOrderID),
        SUM(CASE WHEN so.status='SHIPPED' THEN 1 ELSE 0 END),
        SUM(CASE WHEN so.status='CANCELLED' THEN 1 ELSE 0 END),
        ISNULL(SUM(CASE WHEN so.status!='CANCELLED' THEN so.totalAmount END),0),
        ISNULL(SUM(CASE WHEN so.status!='CANCELLED' THEN soi.quantity END),0),
        ISNULL(AVG(CASE WHEN so.status!='CANCELLED' THEN so.totalAmount END),0),
        COUNT(DISTINCT CASE WHEN so.status!='CANCELLED' THEN so.customerPartnerID END),
        COUNT(DISTINCT CASE WHEN so.status!='CANCELLED' THEN soi.productID END)
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s ON so.subeID=s.subeID
    LEFT JOIN dbo.SalesOrderItem soi ON so.salesOrderID=soi.salesOrderID
    GROUP BY YEAR(so.orderDate),MONTH(so.orderDate),
             DATENAME(MONTH,so.orderDate),DATEPART(QUARTER,so.orderDate),
             s.subeID,s.subeKodu,s.subeAdi;
    PRINT '  snap_AylikSatis: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' satir';

    -- ── Snap 2: Aylık Satın Alma ─────────────────────────────
    TRUNCATE TABLE dbo.snap_AylikSatinAlma;
    INSERT INTO dbo.snap_AylikSatinAlma
        (Yil,Ay,AyAdi,Ceyrek,subeID,subeKodu,Sube,
         ToplamSiparis,TamamlananSiparis,IptalSiparis,
         ToplamTutar,OrtTeslimGun,FarkliTedarikciSayisi)
    SELECT
        YEAR(po.orderDate),MONTH(po.orderDate),
        DATENAME(MONTH,po.orderDate),DATEPART(QUARTER,po.orderDate),
        s.subeID,s.subeKodu,s.subeAdi,
        COUNT(DISTINCT po.purchaseOrderID),
        SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END),
        SUM(CASE WHEN po.status='CANCELLED' THEN 1 ELSE 0 END),
        ISNULL(SUM(CASE WHEN po.status!='CANCELLED' THEN po.totalAmount END),0),
        ROUND(AVG(CAST(DATEDIFF(DAY, po.orderDate, gr_min.minRec) AS FLOAT)),1),
        COUNT(DISTINCT CASE WHEN po.status!='CANCELLED' THEN po.supplierPartnerID END)
    FROM dbo.PurchaseOrder po
    JOIN dbo.Sube s ON po.subeID=s.subeID
    LEFT JOIN (
        SELECT purchaseOrderID, MIN(receiptDate) AS minRec
        FROM dbo.GoodsReceipt GROUP BY purchaseOrderID
    ) gr_min ON gr_min.purchaseOrderID = po.purchaseOrderID
    GROUP BY YEAR(po.orderDate),MONTH(po.orderDate),
             DATENAME(MONTH,po.orderDate),DATEPART(QUARTER,po.orderDate),
             s.subeID,s.subeKodu,s.subeAdi;
    PRINT '  snap_AylikSatinAlma: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' satir';

    -- ── Snap 3: Aylık Üretim ─────────────────────────────────
    TRUNCATE TABLE dbo.snap_AylikUretim;
    INSERT INTO dbo.snap_AylikUretim
        (Yil,Ay,AyAdi,Ceyrek,subeID,subeKodu,Sube,
         ToplamEmir,TamamlananEmir,IptalEmir,
         PlanlananMiktar,UretilenMiktar,OrtGerceklesmeOrani)
    SELECT
        YEAR(startDate),MONTH(startDate),
        DATENAME(MONTH,startDate),DATEPART(QUARTER,startDate),
        s.subeID,s.subeKodu,s.subeAdi,
        COUNT(*),
        SUM(CASE WHEN status='COMPLETED' THEN 1 ELSE 0 END),
        SUM(CASE WHEN status='CANCELLED' THEN 1 ELSE 0 END),
        SUM(plannedQuantity),SUM(producedQuantity),
        ROUND(AVG(CASE WHEN plannedQuantity>0
              THEN 100.0*producedQuantity/plannedQuantity END),1)
    FROM dbo.ProductionOrder prod
    JOIN dbo.Sube s ON prod.subeID=s.subeID
    WHERE startDate IS NOT NULL
    GROUP BY YEAR(startDate),MONTH(startDate),
             DATENAME(MONTH,startDate),DATEPART(QUARTER,startDate),
             s.subeID,s.subeKodu,s.subeAdi;
    PRINT '  snap_AylikUretim: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' satir';

    -- ── Snap 4: Ürün Performans ──────────────────────────────
    TRUNCATE TABLE dbo.snap_UrunPerformans;
    INSERT INTO dbo.snap_UrunPerformans
        (Yil,Ay,productID,Urun,Kategori,subeKodu,
         ToplamSatisMiktar,ToplamSatisTutar,SiparisSayisi)
    SELECT
        YEAR(so.orderDate),MONTH(so.orderDate),
        p.productID,p.productName,pc.categoryName,s.subeKodu,
        SUM(soi.quantity),SUM(soi.totalPrice),
        COUNT(DISTINCT so.salesOrderID)
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s             ON so.subeID=s.subeID
    JOIN dbo.SalesOrderItem soi ON so.salesOrderID=soi.salesOrderID
    JOIN dbo.Product p          ON soi.productID=p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID=pc.categoryID
    WHERE so.status != 'CANCELLED'
    GROUP BY YEAR(so.orderDate),MONTH(so.orderDate),
             p.productID,p.productName,pc.categoryName,s.subeKodu;
    PRINT '  snap_UrunPerformans: ' + CAST(@@ROWCOUNT AS NVARCHAR) + ' satir';

    PRINT 'Snapshot guncelleme tamamlandi. Sure: ' +
          CAST(DATEDIFF(SECOND,@baslar,GETDATE()) AS NVARCHAR) + ' sn';
END;
GO

-- İlk çalıştırma
EXEC dbo.sp_RefreshAllSnapshots;
GO

PRINT 'Katman 4: sp_RefreshAllSnapshots olusturuldu ve calistirildi.';
GO

-- ── DOĞRULAMA ─────────────────────────────────────────────────
SELECT 'snap_AylikSatis'     t, COUNT(*) n FROM snap_AylikSatis    UNION ALL
SELECT 'snap_AylikSatinAlma' t, COUNT(*) n FROM snap_AylikSatinAlma UNION ALL
SELECT 'snap_AylikUretim'    t, COUNT(*) n FROM snap_AylikUretim   UNION ALL
SELECT 'snap_UrunPerformans' t, COUNT(*) n FROM snap_UrunPerformans;
GO
