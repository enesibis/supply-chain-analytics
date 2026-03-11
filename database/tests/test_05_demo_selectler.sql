USE [SCM_3];
GO

-- ============================================================
-- DEMO SELECT'LER — Staj Sunumu
-- Her sorgu bağımsız çalışır, tek tek çalıştırabilirsiniz.
-- ============================================================


-- -------------------------------------------------------
-- 1. İŞ ORTAKLARI — Kim tedarikçi, kim müşteri?
-- -------------------------------------------------------
SELECT
    bp.partnerName,
    bpr.roleType,
    bp.email,
    bp.isActive
FROM dbo.BusinessPartner bp
JOIN dbo.BusinessPartnerRole bpr ON bpr.partnerID = bp.partnerID
ORDER BY bpr.roleType, bp.partnerName;


-- -------------------------------------------------------
-- 2. ÜRÜNLER — Tip ve kategoriye göre
-- -------------------------------------------------------
SELECT
    p.SKU,
    p.productName,
    p.productType,
    pc.categoryName,
    u.unitCode
FROM dbo.Product p
JOIN dbo.ProductCategory pc ON pc.categoryID = p.categoryID
JOIN dbo.Unit u             ON u.unitID = p.unitID
ORDER BY p.productType, p.productName;


-- -------------------------------------------------------
-- 3. ÜRÜN REÇETESİ (BOM) — Hangi ürün neden yapılıyor?
-- -------------------------------------------------------
SELECT
    p_parent.productName   AS [Mamul],
    b.version              AS [BOM Versiyon],
    p_comp.productName     AS [Bileşen],
    bi.quantityPer         AS [Miktar],
    u.unitCode             AS [Birim],
    bi.scrapRate           AS [Fire %]
FROM dbo.BOM b
JOIN dbo.Product p_parent   ON p_parent.productID = b.productID
JOIN dbo.BOMItem bi         ON bi.bomID = b.bomID
JOIN dbo.Product p_comp     ON p_comp.productID = bi.componentProductID
JOIN dbo.Unit u             ON u.unitID = p_comp.unitID
ORDER BY p_parent.productName, bi.lineNo_;


-- -------------------------------------------------------
-- 4. STOK DURUMU — Depoda ne kadar var?
-- -------------------------------------------------------
SELECT
    w.warehouseCode,
    w.warehouseName,
    p.productName,
    p.productType,
    ib.onHandQty    AS [Eldeki],
    ib.reservedQty  AS [Rezerve],
    (ib.onHandQty - ib.reservedQty) AS [Kullanılabilir]
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product   p ON p.productID   = ib.productID
ORDER BY w.warehouseCode, p.productName;


-- -------------------------------------------------------
-- 5. SATIN ALMA SİPARİŞLERİ — Tedarikçiden ne alındı?
-- -------------------------------------------------------
SELECT
    po.orderNumber          AS [Sipariş No],
    bp.partnerName          AS [Tedarikçi],
    po.orderDate            AS [Sipariş Tarihi],
    po.expectedDeliveryDate AS [Beklenen Teslimat],
    po.status               AS [Durum],
    po.totalAmount          AS [Toplam Tutar]
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp ON bp.partnerID = po.supplierPartnerID
ORDER BY po.orderDate DESC;


-- -------------------------------------------------------
-- 6. SATIN ALMA KALEMLERİ — Hangi üründen kaç adet?
-- -------------------------------------------------------
SELECT
    po.orderNumber    AS [Sipariş No],
    p.productName     AS [Ürün],
    poi.quantity      AS [Sipariş Miktarı],
    poi.receivedQuantity AS [Teslim Alınan],
    poi.unitPrice     AS [Birim Fiyat],
    poi.totalPrice    AS [Toplam]
FROM dbo.PurchaseOrderItem poi
JOIN dbo.PurchaseOrder po ON po.purchaseOrderID = poi.purchaseOrderID
JOIN dbo.Product       p  ON p.productID = poi.productID
ORDER BY po.orderNumber, poi.lineNo_;


-- -------------------------------------------------------
-- 7. MAL KABUL — Hangi sipariş hangi depoya teslim alındı?
-- -------------------------------------------------------
SELECT
    gr.receiptNumber AS [Mal Kabul No],
    po.orderNumber   AS [Sipariş No],
    w.warehouseName  AS [Depo],
    gr.receiptDate   AS [Tarih],
    gr.status        AS [Durum]
FROM dbo.GoodsReceipt gr
JOIN dbo.PurchaseOrder po ON po.purchaseOrderID = gr.purchaseOrderID
JOIN dbo.Warehouse     w  ON w.warehouseID = gr.warehouseID
ORDER BY gr.receiptDate DESC;


-- -------------------------------------------------------
-- 8. SATIŞ SİPARİŞLERİ — Müşteriden ne talep edildi?
-- -------------------------------------------------------
SELECT
    so.orderNumber   AS [Sipariş No],
    bp.partnerName   AS [Müşteri],
    so.orderDate     AS [Tarih],
    so.status        AS [Durum],
    so.totalAmount   AS [Toplam Tutar],
    w.warehouseName  AS [Rezerve Depo]
FROM dbo.SalesOrder so
JOIN dbo.BusinessPartner bp ON bp.partnerID = so.customerPartnerID
LEFT JOIN dbo.Warehouse  w  ON w.warehouseID = so.reservedWarehouseID
ORDER BY so.orderDate DESC;


-- -------------------------------------------------------
-- 9. SATIŞ KALEMLERİ — Hangi üründen kaç adet satıldı?
-- -------------------------------------------------------
SELECT
    so.orderNumber      AS [Sipariş No],
    p.productName       AS [Ürün],
    soi.quantity        AS [Sipariş Miktarı],
    soi.shippedQuantity AS [Sevk Edilen],
    soi.unitPrice       AS [Birim Fiyat],
    soi.totalPrice      AS [Toplam]
FROM dbo.SalesOrderItem soi
JOIN dbo.SalesOrder so ON so.salesOrderID = soi.salesOrderID
JOIN dbo.Product    p  ON p.productID = soi.productID
ORDER BY so.orderNumber, soi.lineNo_;


-- -------------------------------------------------------
-- 10. SEVKİYATLAR — Müşteriye ne gönderildi?
-- -------------------------------------------------------
SELECT
    sh.shipmentNumber AS [Sevkiyat No],
    so.orderNumber    AS [Sipariş No],
    bp.partnerName    AS [Müşteri],
    w.warehouseName   AS [Depo],
    sh.shipmentDate   AS [Tarih],
    sh.status         AS [Durum]
FROM dbo.Shipment sh
JOIN dbo.SalesOrder      so ON so.salesOrderID = sh.salesOrderID
JOIN dbo.BusinessPartner bp ON bp.partnerID = sh.customerPartnerID
JOIN dbo.Warehouse        w ON w.warehouseID = sh.warehouseID
ORDER BY sh.shipmentDate DESC;


-- -------------------------------------------------------
-- 11. ÜRETİM EMİRLERİ — Ne üretildi / üretiliyor?
-- -------------------------------------------------------
SELECT
    prod.orderNumber      AS [Üretim Emri],
    p.productName         AS [Ürün],
    prod.plannedQuantity  AS [Planlanan],
    prod.producedQuantity AS [Üretilen],
    prod.status           AS [Durum],
    ws.warehouseName      AS [Ham. Deposu],
    wt.warehouseName      AS [Hedef Depo]
FROM dbo.ProductionOrder prod
JOIN dbo.Product   p  ON p.productID = prod.productID
JOIN dbo.Warehouse ws ON ws.warehouseID = prod.sourceWarehouseID
JOIN dbo.Warehouse wt ON wt.warehouseID = prod.targetWarehouseID
ORDER BY prod.createdAt DESC;


-- -------------------------------------------------------
-- 12. STOK HAREKETLERİ — Depo giriş/çıkış geçmişi
-- -------------------------------------------------------
SELECT TOP 50
    sm.movementDate  AS [Tarih],
    w.warehouseCode  AS [Depo],
    p.productName    AS [Ürün],
    sm.movementType  AS [Hareket Tipi],
    sm.qtyIn         AS [Giriş],
    sm.qtyOut        AS [Çıkış],
    sm.refType       AS [Kaynak],
    sm.note          AS [Not]
FROM dbo.StockMovement sm
JOIN dbo.Warehouse w ON w.warehouseID = sm.warehouseID
JOIN dbo.Product   p ON p.productID = sm.productID
ORDER BY sm.movementDate DESC, sm.stockMovementID DESC;


-- -------------------------------------------------------
-- 13. ÖZET — Depo bazında toplam stok
-- -------------------------------------------------------
SELECT
    w.warehouseCode,
    w.warehouseName,
    COUNT(ib.productID)       AS [Ürün Çeşidi],
    SUM(ib.onHandQty)         AS [Toplam Eldeki],
    SUM(ib.reservedQty)       AS [Toplam Rezerve],
    SUM(ib.onHandQty - ib.reservedQty) AS [Toplam Kullanılabilir]
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
GROUP BY w.warehouseCode, w.warehouseName
ORDER BY w.warehouseCode;
