USE [SCM_3];
GO
SET NOCOUNT ON;

-- ===========================================================
-- POWER BI GÖRSELLEŞTİRME VIEW'LARI
-- ===========================================================

-- 1. STOK DURUMU
CREATE OR ALTER VIEW dbo.vw_StokDurumu AS
SELECT
    w.warehouseCode                             AS DepoKodu,
    w.warehouseName                             AS DepoAdi,
    p.SKU,
    p.productName                               AS UrunAdi,
    p.productType                               AS UrunTipi,
    pc.categoryName                             AS Kategori,
    u.unitCode                                  AS Birim,
    ISNULL(ib.onHandQty, 0)                     AS EldeKi,
    ISNULL(ib.reservedQty, 0)                   AS Rezerveli,
    ISNULL(ib.onHandQty,0) - ISNULL(ib.reservedQty,0) AS Kullanilabilir,
    ib.updatedAt                                AS SonGuncelleme
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product   p ON p.productID   = ib.productID
LEFT JOIN dbo.ProductCategory pc ON pc.categoryID = p.categoryID
JOIN dbo.Unit u ON u.unitID = p.unitID;
GO

-- 2. STOK HAREKETLERİ (tarih + tip bazlı)
CREATE OR ALTER VIEW dbo.vw_StokHareketleri AS
SELECT
    sm.stockMovementID,
    CAST(sm.movementDate AS DATE)   AS Tarih,
    DATENAME(MONTH, sm.movementDate) AS Ay,
    YEAR(sm.movementDate)            AS Yil,
    sm.movementType                  AS HareketTipi,
    CASE sm.movementType
        WHEN 'PURCHASE_RECEIPT'       THEN 'Satın Alma Girişi'
        WHEN 'SALES_SHIPMENT'         THEN 'Satış Çıkışı'
        WHEN 'PRODUCTION_CONSUMPTION' THEN 'Üretim Tüketimi'
        WHEN 'PRODUCTION_OUTPUT'      THEN 'Üretim Çıktısı'
        ELSE sm.movementType
    END                              AS HareketTipiTR,
    w.warehouseCode                  AS DepoKodu,
    w.warehouseName                  AS DepoAdi,
    p.SKU,
    p.productName                    AS UrunAdi,
    p.productType                    AS UrunTipi,
    sm.qtyIn                         AS GirenMiktar,
    sm.qtyOut                        AS CikanMiktar,
    sm.qtyIn - sm.qtyOut             AS NetMiktar,
    sm.refType                       AS ReferansTip,
    sm.refID                         AS ReferansID
FROM dbo.StockMovement sm
JOIN dbo.Warehouse w ON w.warehouseID = sm.warehouseID
JOIN dbo.Product   p ON p.productID   = sm.productID;
GO

-- 3. SATIN ALMA SİPARİŞLERİ
CREATE OR ALTER VIEW dbo.vw_SatinAlmaSiparisleri AS
SELECT
    po.purchaseOrderID,
    po.orderNumber                  AS SiparisNo,
    CAST(po.orderDate AS DATE)      AS SiparisTarihi,
    CAST(po.expectedDeliveryDate AS DATE) AS BekTeslimTarihi,
    po.status                       AS Durum,
    CASE po.status
        WHEN 'DRAFT'              THEN 'Taslak'
        WHEN 'APPROVED'           THEN 'Onaylandı'
        WHEN 'PARTIALLY_RECEIVED' THEN 'Kısmi Teslim'
        WHEN 'RECEIVED'           THEN 'Teslim Alındı'
        WHEN 'CANCELLED'          THEN 'İptal'
        ELSE po.status
    END                             AS DurumTR,
    bp.partnerName                  AS Tedarikci,
    po.totalAmount                  AS ToplamTutar,
    -- kalem detayı
    poi.lineNo_                     AS KalemNo,
    p.SKU,
    p.productName                   AS UrunAdi,
    poi.quantity                    AS SiparisMiktari,
    poi.receivedQuantity            AS TeslimAlinanMiktar,
    poi.quantity - poi.receivedQuantity AS KalanMiktar,
    poi.unitPrice                   AS BirimFiyat,
    poi.totalPrice                  AS SatirToplami
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp ON bp.partnerID = po.supplierPartnerID
JOIN dbo.PurchaseOrderItem poi ON poi.purchaseOrderID = po.purchaseOrderID
JOIN dbo.Product p ON p.productID = poi.productID;
GO

-- 4. SATIŞ SİPARİŞLERİ
CREATE OR ALTER VIEW dbo.vw_SatisSiparisleri AS
SELECT
    so.salesOrderID,
    so.orderNumber                  AS SiparisNo,
    CAST(so.orderDate AS DATE)      AS SiparisTarihi,
    so.status                       AS Durum,
    CASE so.status
        WHEN 'DRAFT'             THEN 'Taslak'
        WHEN 'APPROVED'          THEN 'Onaylandı'
        WHEN 'RESERVED'          THEN 'Rezerveli'
        WHEN 'PARTIALLY_SHIPPED' THEN 'Kısmi Sevk'
        WHEN 'SHIPPED'           THEN 'Sevk Edildi'
        WHEN 'CANCELLED'         THEN 'İptal'
        ELSE so.status
    END                             AS DurumTR,
    bp.partnerName                  AS Musteri,
    so.totalAmount                  AS ToplamTutar,
    -- kalem detayı
    soi.lineNo_                     AS KalemNo,
    p.SKU,
    p.productName                   AS UrunAdi,
    soi.quantity                    AS SiparisMiktari,
    soi.shippedQuantity             AS SevkEdilenMiktar,
    soi.quantity - ISNULL(soi.shippedQuantity,0) AS KalanMiktar,
    soi.unitPrice                   AS BirimFiyat,
    soi.totalPrice                  AS SatirToplami,
    wRes.warehouseCode              AS RezerveDep
FROM dbo.SalesOrder so
JOIN dbo.BusinessPartner bp ON bp.partnerID = so.customerPartnerID
JOIN dbo.SalesOrderItem soi ON soi.salesOrderID = so.salesOrderID
JOIN dbo.Product p ON p.productID = soi.productID
LEFT JOIN dbo.Warehouse wRes ON wRes.warehouseID = so.reservedWarehouseID;
GO

-- 5. ÜRETİM EMİRLERİ
CREATE OR ALTER VIEW dbo.vw_UretimEmirleri AS
SELECT
    pr.productionOrderID,
    pr.orderNumber                  AS EmiNo,
    CAST(pr.startDate AS DATE)      AS BaslangicTarihi,
    CAST(pr.endDate   AS DATE)      AS BitisTarihi,
    pr.status                       AS Durum,
    CASE pr.status
        WHEN 'DRAFT'       THEN 'Taslak'
        WHEN 'RELEASED'    THEN 'Serbest Bırakıldı'
        WHEN 'IN_PROGRESS' THEN 'Devam Ediyor'
        WHEN 'COMPLETED'   THEN 'Tamamlandı'
        WHEN 'CANCELLED'   THEN 'İptal'
        ELSE pr.status
    END                             AS DurumTR,
    p.SKU,
    p.productName                   AS UrunAdi,
    pr.plannedQuantity              AS PlanlananMiktar,
    pr.producedQuantity             AS ÜretilenMiktar,
    pr.plannedQuantity - pr.producedQuantity AS KalanMiktar,
    CASE WHEN pr.plannedQuantity > 0
         THEN CAST(pr.producedQuantity * 100.0 / pr.plannedQuantity AS DECIMAL(5,1))
         ELSE 0
    END                             AS TamamlanmaPct,
    wSrc.warehouseCode              AS KaynakDepo,
    wTgt.warehouseCode              AS HedefDepo,
    b.version                       AS BomVersiyon
FROM dbo.ProductionOrder pr
JOIN dbo.Product   p    ON p.productID    = pr.productID
JOIN dbo.BOM       b    ON b.bomID        = pr.bomID
JOIN dbo.Warehouse wSrc ON wSrc.warehouseID = pr.sourceWarehouseID
JOIN dbo.Warehouse wTgt ON wTgt.warehouseID = pr.targetWarehouseID;
GO

-- 6. SEVKİYATLAR
CREATE OR ALTER VIEW dbo.vw_Sevkiyatlar AS
SELECT
    sh.shipmentID,
    sh.shipmentNumber               AS SevkiyatNo,
    CAST(sh.shipmentDate AS DATE)   AS SevkTarihi,
    sh.status                       AS Durum,
    CASE sh.status
        WHEN 'DRAFT'     THEN 'Taslak'
        WHEN 'POSTED'    THEN 'Gönderildi'
        WHEN 'CANCELLED' THEN 'İptal'
        ELSE sh.status
    END                             AS DurumTR,
    soNum.orderNumber               AS SiparisNo,
    musteri.partnerName             AS Musteri,
    tasiyici.partnerName            AS Tasiyici,
    w.warehouseCode                 AS CikisDepo,
    p.SKU,
    p.productName                   AS UrunAdi,
    si.quantity                     AS SevkMiktari
FROM dbo.Shipment sh
JOIN dbo.SalesOrder so      ON so.salesOrderID   = sh.salesOrderID
JOIN dbo.BusinessPartner musteri  ON musteri.partnerID  = sh.customerPartnerID
LEFT JOIN dbo.BusinessPartner tasiyici ON tasiyici.partnerID = sh.carrierPartnerID
JOIN dbo.Warehouse w        ON w.warehouseID     = sh.warehouseID
JOIN dbo.ShipmentItem si    ON si.shipmentID     = sh.shipmentID
JOIN dbo.Product p          ON p.productID       = si.productID
JOIN (SELECT salesOrderID, orderNumber FROM dbo.SalesOrder) soNum
  ON soNum.salesOrderID = sh.salesOrderID;
GO

-- 7. KPI ÖZET (tek satır — kart görselleri için)
CREATE OR ALTER VIEW dbo.vw_KPI AS
SELECT
    (SELECT COUNT(*) FROM dbo.PurchaseOrder WHERE status NOT IN ('CANCELLED'))    AS ToplamPO,
    (SELECT COUNT(*) FROM dbo.PurchaseOrder WHERE status='APPROVED')              AS BekleyenPO,
    (SELECT ISNULL(SUM(totalAmount),0) FROM dbo.PurchaseOrder WHERE status='RECEIVED') AS ToplamSatinAlmaTL,

    (SELECT COUNT(*) FROM dbo.SalesOrder WHERE status NOT IN ('CANCELLED'))       AS ToplamSO,
    (SELECT COUNT(*) FROM dbo.SalesOrder WHERE status NOT IN ('SHIPPED','CANCELLED')) AS AktifSO,
    (SELECT ISNULL(SUM(totalAmount),0) FROM dbo.SalesOrder WHERE status='SHIPPED') AS ToplamSatisTL,

    (SELECT COUNT(*) FROM dbo.ProductionOrder WHERE status NOT IN ('CANCELLED'))  AS ToplamUretimEmri,
    (SELECT COUNT(*) FROM dbo.ProductionOrder WHERE status='IN_PROGRESS')         AS DevamEdenUretim,
    (SELECT COUNT(*) FROM dbo.ProductionOrder WHERE status='COMPLETED')           AS TamamlananUretim,

    (SELECT COUNT(DISTINCT productID) FROM dbo.InventoryBalance WHERE onHandQty>0) AS StokluUrunSayisi,
    (SELECT ISNULL(SUM(onHandQty),0) FROM dbo.InventoryBalance)                   AS ToplamStokAdet,

    (SELECT COUNT(*) FROM dbo.BusinessPartner WHERE isActive=1)                   AS AktifPartnerSayisi,
    (SELECT COUNT(*) FROM dbo.Product WHERE isActive=1)                           AS AktifUrunSayisi;
GO

-- Kontrol
PRINT 'View''lar oluşturuldu:';
SELECT name AS ViewAdi FROM sys.views
WHERE name LIKE 'vw_%'
ORDER BY name;
GO
