SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'TEST 04 — GENEL DURUM SELECTLERİ';
PRINT '============================================================';

PRINT '--- Tüm PurchaseOrder''lar ---';
SELECT po.purchaseOrderID, po.orderNumber, bp.partnerName AS supplier,
       po.status, po.totalAmount, po.orderDate
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp ON bp.partnerID = po.supplierPartnerID
ORDER BY po.purchaseOrderID;

PRINT '--- Tüm SalesOrder''lar ---';
SELECT so.salesOrderID, so.orderNumber, bp.partnerName AS customer,
       so.status, so.totalAmount, so.reservedWarehouseID
FROM dbo.SalesOrder so
JOIN dbo.BusinessPartner bp ON bp.partnerID = so.customerPartnerID
ORDER BY so.salesOrderID;

PRINT '--- Tüm ProductionOrder''lar ---';
SELECT productionOrderID, orderNumber, status,
       plannedQuantity, producedQuantity, startDate, endDate
FROM dbo.ProductionOrder
ORDER BY productionOrderID;

PRINT '--- Güncel InventoryBalance (tüm depolar) ---';
SELECT w.warehouseCode, p.SKU, p.productName,
       ib.onHandQty, ib.reservedQty,
       (ib.onHandQty - ib.reservedQty) AS availableQty,
       ib.updatedAt
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product p ON p.productID = ib.productID
ORDER BY w.warehouseCode, p.SKU;

PRINT '--- StockMovement özeti (tüm hareketler) ---';
SELECT sm.movementType, p.SKU, w.warehouseCode,
       sm.qtyIn, sm.qtyOut,
       (sm.qtyIn - sm.qtyOut) AS netQty,
       sm.refType, sm.movementDate
FROM dbo.StockMovement sm
JOIN dbo.Product p ON p.productID = sm.productID
JOIN dbo.Warehouse w ON w.warehouseID = sm.warehouseID
ORDER BY sm.stockMovementID;

PRINT '--- Stok Özeti: Ürün bazında toplam giriş/çıkış ---';
SELECT p.SKU, p.productName, w.warehouseCode,
       SUM(sm.qtyIn)  AS toplamGiris,
       SUM(sm.qtyOut) AS toplamCikis,
       SUM(sm.qtyIn - sm.qtyOut) AS netStok
FROM dbo.StockMovement sm
JOIN dbo.Product p ON p.productID = sm.productID
JOIN dbo.Warehouse w ON w.warehouseID = sm.warehouseID
GROUP BY p.SKU, p.productName, w.warehouseCode
ORDER BY w.warehouseCode, p.SKU;

PRINT '--- Tüm Shipment''lar ---';
SELECT s.shipmentID, s.shipmentNumber, so.orderNumber AS salesOrder,
       bp.partnerName AS customer, s.status, s.shipmentDate
FROM dbo.Shipment s
JOIN dbo.SalesOrder so ON so.salesOrderID = s.salesOrderID
JOIN dbo.BusinessPartner bp ON bp.partnerID = s.customerPartnerID
ORDER BY s.shipmentID;

PRINT '--- Tüm GoodsReceipt''lar ---';
SELECT gr.goodsReceiptID, gr.receiptNumber, po.orderNumber AS purchaseOrder,
       w.warehouseCode, gr.status, gr.receiptDate
FROM dbo.GoodsReceipt gr
JOIN dbo.PurchaseOrder po ON po.purchaseOrderID = gr.purchaseOrderID
JOIN dbo.Warehouse w ON w.warehouseID = gr.warehouseID
ORDER BY gr.goodsReceiptID;

PRINT '============================================================';
PRINT 'TEST 04 TAMAMLANDI';
PRINT '============================================================';
GO
