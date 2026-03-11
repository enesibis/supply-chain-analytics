SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;

-- Üretim test verilerini temizle (bağımlılık sırasına göre)
DELETE FROM dbo.StockMovement
WHERE refType = 'ProductionConsumption'
  AND refID IN (SELECT productionConsumptionID FROM dbo.ProductionConsumption
                WHERE productionOrderID IN (SELECT productionOrderID FROM dbo.ProductionOrder
                                            WHERE orderNumber LIKE 'PROD-TEST-%'));

DELETE FROM dbo.StockMovement
WHERE refType = 'ProductionOutput'
  AND refID IN (SELECT productionOutputID FROM dbo.ProductionOutput
                WHERE productionOrderID IN (SELECT productionOrderID FROM dbo.ProductionOrder
                                            WHERE orderNumber LIKE 'PROD-TEST-%'));

DELETE FROM dbo.ProductionConsumption
WHERE productionOrderID IN (SELECT productionOrderID FROM dbo.ProductionOrder WHERE orderNumber LIKE 'PROD-TEST-%');

DELETE FROM dbo.ProductionOutput
WHERE productionOrderID IN (SELECT productionOrderID FROM dbo.ProductionOrder WHERE orderNumber LIKE 'PROD-TEST-%');

DELETE FROM dbo.ProductionOrder WHERE orderNumber LIKE 'PROD-TEST-%';

-- Satış test verilerini temizle
DELETE FROM dbo.StockMovement
WHERE refType = 'Shipment'
  AND refID IN (SELECT shipmentID FROM dbo.Shipment
                WHERE salesOrderID IN (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber LIKE 'SO-TEST-%'));

DELETE FROM dbo.ShipmentItem
WHERE shipmentID IN (SELECT shipmentID FROM dbo.Shipment
                     WHERE salesOrderID IN (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber LIKE 'SO-TEST-%'));

DELETE FROM dbo.Shipment
WHERE salesOrderID IN (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber LIKE 'SO-TEST-%');

DELETE FROM dbo.SalesOrderItem
WHERE salesOrderID IN (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber LIKE 'SO-TEST-%');

DELETE FROM dbo.SalesOrder WHERE orderNumber LIKE 'SO-TEST-%';

-- Satın alma test verilerini temizle
DELETE FROM dbo.StockMovement
WHERE refType = 'GoodsReceipt'
  AND refID IN (SELECT goodsReceiptID FROM dbo.GoodsReceipt
                WHERE purchaseOrderID IN (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber LIKE 'PO-TEST-%'));

DELETE FROM dbo.GoodsReceiptItem
WHERE goodsReceiptID IN (SELECT goodsReceiptID FROM dbo.GoodsReceipt
                         WHERE purchaseOrderID IN (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber LIKE 'PO-TEST-%'));

DELETE FROM dbo.GoodsReceipt
WHERE purchaseOrderID IN (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber LIKE 'PO-TEST-%');

DELETE FROM dbo.PurchaseOrderItem
WHERE purchaseOrderID IN (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber LIKE 'PO-TEST-%');

DELETE FROM dbo.PurchaseOrder WHERE orderNumber LIKE 'PO-TEST-%';

-- Stokları başlangıç değerine sıfırla
UPDATE dbo.InventoryBalance SET onHandQty = 4,    reservedQty = 0 WHERE warehouseID = 1 AND productID = 6;
UPDATE dbo.InventoryBalance SET onHandQty = 57.5, reservedQty = 0 WHERE warehouseID = 2 AND productID = 4;
UPDATE dbo.InventoryBalance SET onHandQty = 80,   reservedQty = 0 WHERE warehouseID = 2 AND productID = 5;

PRINT 'Tüm test verileri temizlendi.';

SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product p ON p.productID = ib.productID
ORDER BY w.warehouseCode, p.SKU;
GO
