SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;

PRINT '============================================================';
PRINT 'ÖRNEK VERİ — SCM_3  (idempotent)';
PRINT 'Kapsam:';
PRINT '  3 Satın Alma Siparişi  (2 RECEIVED, 1 APPROVED)';
PRINT '  2 Üretim Emri          (1 COMPLETED, 1 IN_PROGRESS)';
PRINT '  2 Satış Siparişi       (1 SHIPPED, 1 RESERVED)';
PRINT '============================================================';

BEGIN TRY

-- ===========================================================
-- 0. TEMEL ID LOOKUP
-- ===========================================================
DECLARE @supplierID BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName = 'ACME STEEL SUPPLY');
DECLARE @customerID BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName = 'MEGA CUSTOMER LTD');
DECLARE @carrierID  BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName = 'FAST CARRIER');

DECLARE @pRaw1 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU = 'RAW-001');  -- Çelik Levha 2mm
DECLARE @pRaw2 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU = 'RAW-002');  -- Dolap Menteşesi
DECLARE @pRaw3 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU = 'RAW-003');  -- Altıgen Civata M8
DECLARE @pFG1  BIGINT = (SELECT productID FROM dbo.Product WHERE SKU = 'FG-001');   -- Metal Dolap 2 Kapaklı

DECLARE @wRAW  INT = (SELECT warehouseID FROM dbo.Warehouse WHERE warehouseCode = 'RAW');
DECLARE @wMAIN INT = (SELECT warehouseID FROM dbo.Warehouse WHERE warehouseCode = 'MAIN');
DECLARE @wFG   INT = (SELECT warehouseID FROM dbo.Warehouse WHERE warehouseCode = 'FG');

DECLARE @bomFG1 BIGINT = (
    SELECT TOP 1 bomID FROM dbo.BOM
    WHERE productID = @pFG1 AND isActive = 1
    ORDER BY bomID DESC
);

-- Kontrol
IF @supplierID IS NULL OR @customerID IS NULL OR @carrierID IS NULL
    THROW 50100, 'BusinessPartner eksik — önce businesspartnerInsert.sql çalıştır.', 1;
IF @pRaw1 IS NULL OR @pRaw2 IS NULL OR @pRaw3 IS NULL OR @pFG1 IS NULL
    THROW 50101, 'Product eksik — önce productInsert.sql çalıştır.', 1;
IF @wRAW IS NULL OR @wMAIN IS NULL OR @wFG IS NULL
    THROW 50102, 'Warehouse eksik — önce warehouseInsert.sql çalıştır.', 1;
IF @bomFG1 IS NULL
    THROW 50103, 'FG-001 için aktif BOM yok — önce bomInsert.sql çalıştır.', 1;

PRINT 'OK 0 | ID lookup tamamlandı.';

-- ===========================================================
-- 1. SATIN ALMA — PO-2024-001
--    ACME STEEL SUPPLY → RAW deposu
--    RAW-001: 100 KG @ 45 TL | RAW-002: 200 EA @ 12 TL
--    Durum: RECEIVED (GR-2024-001 POSTED)
-- ===========================================================
DECLARE @po1ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-001')
BEGIN
    EXEC dbo.CreatePurchaseOrder
        @orderNumber          = 'PO-2024-001',
        @supplierPartnerID    = @supplierID,
        @orderDate            = '2024-02-01',
        @expectedDeliveryDate = '2024-02-15',
        @purchaseOrderID      = @po1ID OUTPUT;

    INSERT INTO dbo.PurchaseOrderItem
        (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
    VALUES
        (@po1ID, 1, @pRaw1, 100.000, 45.0000, 0),
        (@po1ID, 2, @pRaw2, 200.000, 12.0000, 0);

    UPDATE dbo.PurchaseOrder
       SET totalAmount = 100 * 45.00 + 200 * 12.00
     WHERE purchaseOrderID = @po1ID;

    EXEC dbo.ApprovePurchaseOrder @purchaseOrderID = @po1ID;

    DECLARE @gr1ID BIGINT;
    EXEC dbo.CreateGoodsReceipt
        @purchaseOrderID = @po1ID,
        @warehouseID     = @wRAW,
        @receiptNumber   = 'GR-2024-001',
        @receiptDate     = '2024-02-10',
        @goodsReceiptID  = @gr1ID OUTPUT;

    DECLARE @poi1a BIGINT, @poi1b BIGINT;
    SELECT @poi1a = MIN(purchaseOrderItemID),
           @poi1b = MAX(purchaseOrderItemID)
    FROM dbo.PurchaseOrderItem WHERE purchaseOrderID = @po1ID;

    DECLARE @grTmp BIGINT;
    EXEC dbo.AddGoodsReceiptItem @goodsReceiptID=@gr1ID, @purchaseOrderItemID=@poi1a, @quantity=100.000, @goodsReceiptItemID=@grTmp OUTPUT;
    EXEC dbo.AddGoodsReceiptItem @goodsReceiptID=@gr1ID, @purchaseOrderItemID=@poi1b, @quantity=200.000, @goodsReceiptItemID=@grTmp OUTPUT;

    EXEC dbo.PostGoodsReceipt @goodsReceiptID = @gr1ID;
    PRINT 'OK 1 | PO-2024-001 RECEIVED  → RAW: +100 KG RAW-001, +200 EA RAW-002';
END
ELSE
BEGIN
    SET @po1ID = (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-001');
    PRINT 'SKIP 1 | PO-2024-001 zaten mevcut';
END;

-- ===========================================================
-- 2. SATIN ALMA — PO-2024-002
--    ACME STEEL SUPPLY → RAW deposu
--    RAW-001: 200 KG @ 44 TL | RAW-002: 400 EA @ 11.50 TL
--    Durum: RECEIVED (GR-2024-002 POSTED)
-- ===========================================================
DECLARE @po2ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-002')
BEGIN
    EXEC dbo.CreatePurchaseOrder
        @orderNumber          = 'PO-2024-002',
        @supplierPartnerID    = @supplierID,
        @orderDate            = '2024-02-20',
        @expectedDeliveryDate = '2024-03-10',
        @purchaseOrderID      = @po2ID OUTPUT;

    INSERT INTO dbo.PurchaseOrderItem
        (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
    VALUES
        (@po2ID, 1, @pRaw1, 200.000, 44.0000, 0),
        (@po2ID, 2, @pRaw2, 400.000, 11.5000, 0);

    UPDATE dbo.PurchaseOrder
       SET totalAmount = 200 * 44.00 + 400 * 11.50
     WHERE purchaseOrderID = @po2ID;

    EXEC dbo.ApprovePurchaseOrder @purchaseOrderID = @po2ID;

    DECLARE @gr2ID BIGINT;
    EXEC dbo.CreateGoodsReceipt
        @purchaseOrderID = @po2ID,
        @warehouseID     = @wRAW,
        @receiptNumber   = 'GR-2024-002',
        @receiptDate     = '2024-03-05',
        @goodsReceiptID  = @gr2ID OUTPUT;

    DECLARE @poi2a BIGINT, @poi2b BIGINT;
    SELECT @poi2a = MIN(purchaseOrderItemID),
           @poi2b = MAX(purchaseOrderItemID)
    FROM dbo.PurchaseOrderItem WHERE purchaseOrderID = @po2ID;

    DECLARE @grTmp2 BIGINT;
    EXEC dbo.AddGoodsReceiptItem @goodsReceiptID=@gr2ID, @purchaseOrderItemID=@poi2a, @quantity=200.000, @goodsReceiptItemID=@grTmp2 OUTPUT;
    EXEC dbo.AddGoodsReceiptItem @goodsReceiptID=@gr2ID, @purchaseOrderItemID=@poi2b, @quantity=400.000, @goodsReceiptItemID=@grTmp2 OUTPUT;

    EXEC dbo.PostGoodsReceipt @goodsReceiptID = @gr2ID;
    PRINT 'OK 2 | PO-2024-002 RECEIVED  → RAW: +200 KG RAW-001, +400 EA RAW-002';
END
ELSE
BEGIN
    SET @po2ID = (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-002');
    PRINT 'SKIP 2 | PO-2024-002 zaten mevcut';
END;

-- ===========================================================
-- 3. SATIN ALMA — PO-2024-003
--    ACME STEEL SUPPLY
--    RAW-003: 1000 EA @ 3.50 TL (Altıgen Civata)
--    Durum: APPROVED — teslim bekleniyor
-- ===========================================================
DECLARE @po3ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-003')
BEGIN
    EXEC dbo.CreatePurchaseOrder
        @orderNumber          = 'PO-2024-003',
        @supplierPartnerID    = @supplierID,
        @orderDate            = '2024-04-01',
        @expectedDeliveryDate = '2024-04-20',
        @purchaseOrderID      = @po3ID OUTPUT;

    INSERT INTO dbo.PurchaseOrderItem
        (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
    VALUES
        (@po3ID, 1, @pRaw3, 1000.000, 3.5000, 0);

    UPDATE dbo.PurchaseOrder
       SET totalAmount = 1000 * 3.50
     WHERE purchaseOrderID = @po3ID;

    EXEC dbo.ApprovePurchaseOrder @purchaseOrderID = @po3ID;
    PRINT 'OK 3 | PO-2024-003 APPROVED  → teslim bekleniyor (1000 EA RAW-003)';
END
ELSE
BEGIN
    SET @po3ID = (SELECT purchaseOrderID FROM dbo.PurchaseOrder WHERE orderNumber = 'PO-2024-003');
    PRINT 'SKIP 3 | PO-2024-003 zaten mevcut';
END;

-- Stok durumu (üretim öncesi):
-- RAW: RAW-001 = 300 KG, RAW-002 = 600 EA

-- ===========================================================
-- 4. ÜRETİM — PRD-2024-001
--    FG-001 x10  |  RAW deposu → MAIN deposu
--    Durum: COMPLETED
--    Tüketim: RAW-001 x10 KG, RAW-002 x40 EA
--    Çıktı: FG-001 x10 EA  → MAIN
-- ===========================================================
DECLARE @prd1ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.ProductionOrder WHERE orderNumber = 'PRD-2024-001')
BEGIN
    EXEC dbo.CreateProductionOrder
        @orderNumber       = 'PRD-2024-001',
        @productID         = @pFG1,
        @bomID             = @bomFG1,
        @plannedQuantity   = 10.000,
        @sourceWarehouseID = @wRAW,
        @targetWarehouseID = @wMAIN,
        @productionOrderID = @prd1ID OUTPUT;

    EXEC dbo.ReleaseProductionOrder @productionOrderID = @prd1ID;
    EXEC dbo.StartProductionOrder   @productionOrderID = @prd1ID, @startDate = '2024-03-15';

    -- Hammadde tüketimi (BOM: 1 KG RAW-001 + 4 EA RAW-002 per unit → x10)
    DECLARE @pcTmp BIGINT;
    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @prd1ID,
        @componentProductID      = @pRaw1,
        @quantity                = 10.000,
        @consumptionDate         = '2024-03-15',
        @productionConsumptionID = @pcTmp OUTPUT;

    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @prd1ID,
        @componentProductID      = @pRaw2,
        @quantity                = 40.000,
        @consumptionDate         = '2024-03-15',
        @productionConsumptionID = @pcTmp OUTPUT;

    -- Çıktı (hepsi MAIN deposuna)
    EXEC dbo.PostProductionOutput
        @productionOrderID = @prd1ID,
        @quantity          = 10.000,
        @outputDate        = '2024-03-18';

    EXEC dbo.CompleteProductionOrder
        @productionOrderID = @prd1ID,
        @allowPartial      = 0,
        @endDate           = '2024-03-18';

    PRINT 'OK 4 | PRD-2024-001 COMPLETED → MAIN: +10 EA FG-001  |  RAW: -10 KG / -40 EA';
END
ELSE
BEGIN
    SET @prd1ID = (SELECT productionOrderID FROM dbo.ProductionOrder WHERE orderNumber = 'PRD-2024-001');
    PRINT 'SKIP 4 | PRD-2024-001 zaten mevcut';
END;

-- Stok durumu:
-- RAW: RAW-001 = 290 KG, RAW-002 = 560 EA
-- MAIN: FG-001 = 10 EA

-- ===========================================================
-- 5. ÜRETİM — PRD-2024-002
--    FG-001 x5 planlı  |  RAW deposu → FG deposu
--    Durum: IN_PROGRESS (3/5 üretildi, kalan 2 üretim devam ediyor)
--    Tüketim: RAW-001 x3 KG, RAW-002 x12 EA  (kısmi)
--    Çıktı: FG-001 x3 EA → FG deposu
-- ===========================================================
DECLARE @prd2ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.ProductionOrder WHERE orderNumber = 'PRD-2024-002')
BEGIN
    EXEC dbo.CreateProductionOrder
        @orderNumber       = 'PRD-2024-002',
        @productID         = @pFG1,
        @bomID             = @bomFG1,
        @plannedQuantity   = 5.000,
        @sourceWarehouseID = @wRAW,
        @targetWarehouseID = @wFG,
        @productionOrderID = @prd2ID OUTPUT;

    EXEC dbo.ReleaseProductionOrder @productionOrderID = @prd2ID;
    EXEC dbo.StartProductionOrder   @productionOrderID = @prd2ID, @startDate = '2024-03-20';

    -- Kısmi tüketim (3 birim için)
    DECLARE @pcTmp2 BIGINT;
    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @prd2ID,
        @componentProductID      = @pRaw1,
        @quantity                = 3.000,
        @consumptionDate         = '2024-03-20',
        @productionConsumptionID = @pcTmp2 OUTPUT;

    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @prd2ID,
        @componentProductID      = @pRaw2,
        @quantity                = 12.000,
        @consumptionDate         = '2024-03-20',
        @productionConsumptionID = @pcTmp2 OUTPUT;

    -- Kısmi çıktı (3/5)
    EXEC dbo.PostProductionOutput
        @productionOrderID = @prd2ID,
        @quantity          = 3.000,
        @outputDate        = '2024-03-21';

    -- NOT COMPLETE → kalır IN_PROGRESS
    PRINT 'OK 5 | PRD-2024-002 IN_PROGRESS (3/5 FG-001) → FG: +3 EA  |  RAW: -3 KG / -12 EA';
END
ELSE
BEGIN
    SET @prd2ID = (SELECT productionOrderID FROM dbo.ProductionOrder WHERE orderNumber = 'PRD-2024-002');
    PRINT 'SKIP 5 | PRD-2024-002 zaten mevcut';
END;

-- Stok durumu:
-- RAW: RAW-001 = 287 KG, RAW-002 = 548 EA
-- MAIN: FG-001 = 10 EA
-- FG:   FG-001 =  3 EA

-- ===========================================================
-- 6. SATIŞ — SO-2024-001
--    MEGA CUSTOMER LTD  |  FG-001 x6 @ 500 TL
--    Durum: SHIPPED (SHP-2024-001, FAST CARRIER)
--    Kaynak depo: MAIN
-- ===========================================================
DECLARE @so1ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE orderNumber = 'SO-2024-001')
BEGIN
    EXEC dbo.CreateSalesOrder
        @orderNumber       = 'SO-2024-001',
        @customerPartnerID = @customerID,
        @orderDate         = '2024-03-22',
        @salesOrderID      = @so1ID OUTPUT;

    DECLARE @soi1ID BIGINT;
    EXEC dbo.AddSalesOrderItem
        @salesOrderID     = @so1ID,
        @productID        = @pFG1,
        @quantity         = 6.000,
        @unitPrice        = 500.0000,
        @salesOrderItemID = @soi1ID OUTPUT;

    EXEC dbo.ApproveSalesOrder @salesOrderID = @so1ID;
    EXEC dbo.ReserveSalesOrder @salesOrderID = @so1ID, @warehouseID = @wMAIN;

    DECLARE @shp1ID BIGINT;
    EXEC dbo.CreateShipment
        @salesOrderID     = @so1ID,
        @warehouseID      = @wMAIN,
        @shipmentNumber   = 'SHP-2024-001',
        @shipmentDate     = '2024-03-25',
        @carrierPartnerID = @carrierID,
        @shipmentID       = @shp1ID OUTPUT;

    DECLARE @shiTmp1 BIGINT;
    EXEC dbo.AddShipmentItem
        @shipmentID       = @shp1ID,
        @salesOrderItemID = @soi1ID,
        @quantity         = 6.000,
        @shipmentItemID   = @shiTmp1 OUTPUT;

    EXEC dbo.PostShipment @shipmentID = @shp1ID;
    PRINT 'OK 6 | SO-2024-001 SHIPPED   → SHP-2024-001 (FAST CARRIER, 6x FG-001)  |  MAIN: -6 EA';
END
ELSE
BEGIN
    SET @so1ID = (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber = 'SO-2024-001');
    PRINT 'SKIP 6 | SO-2024-001 zaten mevcut';
END;

-- Stok durumu:
-- MAIN: FG-001 = 4 EA (onHand), 0 reserved

-- ===========================================================
-- 7. SATIŞ — SO-2024-002
--    MEGA CUSTOMER LTD  |  FG-001 x3 @ 520 TL
--    Durum: RESERVED — sevkiyat bekleniyor
--    Kaynak depo: FG (Mamul Deposu)
-- ===========================================================
DECLARE @so2ID BIGINT;

IF NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE orderNumber = 'SO-2024-002')
BEGIN
    EXEC dbo.CreateSalesOrder
        @orderNumber       = 'SO-2024-002',
        @customerPartnerID = @customerID,
        @orderDate         = '2024-03-28',
        @salesOrderID      = @so2ID OUTPUT;

    DECLARE @soi2ID BIGINT;
    EXEC dbo.AddSalesOrderItem
        @salesOrderID     = @so2ID,
        @productID        = @pFG1,
        @quantity         = 3.000,
        @unitPrice        = 520.0000,
        @salesOrderItemID = @soi2ID OUTPUT;

    EXEC dbo.ApproveSalesOrder @salesOrderID = @so2ID;
    EXEC dbo.ReserveSalesOrder @salesOrderID = @so2ID, @warehouseID = @wFG;
    PRINT 'OK 7 | SO-2024-002 RESERVED  → sevkiyat bekleniyor (3x FG-001)  |  FG: reserved +3 EA';
END
ELSE
BEGIN
    SET @so2ID = (SELECT salesOrderID FROM dbo.SalesOrder WHERE orderNumber = 'SO-2024-002');
    PRINT 'SKIP 7 | SO-2024-002 zaten mevcut';
END;

-- ===========================================================
-- ÖZET
-- ===========================================================
PRINT '';
PRINT '============================================================';
PRINT 'ÖRNEK VERİ YÜKLEMESİ TAMAMLANDI';
PRINT '============================================================';
PRINT '';

PRINT '--- SATIN ALMA SİPARİŞLERİ ---';
SELECT
    po.orderNumber,
    bp.partnerName       AS tedarikci,
    po.status,
    po.totalAmount       AS toplam_TL,
    po.orderDate,
    po.expectedDeliveryDate
FROM dbo.PurchaseOrder po
JOIN dbo.BusinessPartner bp ON bp.partnerID = po.supplierPartnerID
ORDER BY po.orderNumber;

PRINT '';
PRINT '--- ÜRETİM EMİRLERİ ---';
SELECT
    prd.orderNumber,
    p.SKU,
    prd.plannedQuantity,
    prd.producedQuantity,
    prd.status,
    ws.warehouseCode  AS kaynak_depo,
    wt.warehouseCode  AS hedef_depo,
    prd.startDate,
    prd.endDate
FROM dbo.ProductionOrder prd
JOIN dbo.Product   p  ON p.productID   = prd.productID
JOIN dbo.Warehouse ws ON ws.warehouseID = prd.sourceWarehouseID
JOIN dbo.Warehouse wt ON wt.warehouseID = prd.targetWarehouseID
ORDER BY prd.orderNumber;

PRINT '';
PRINT '--- SATIŞ SİPARİŞLERİ ---';
SELECT
    so.orderNumber,
    bp.partnerName   AS musteri,
    so.status,
    so.totalAmount   AS toplam_TL,
    wh.warehouseCode AS rezerve_depo,
    so.orderDate
FROM dbo.SalesOrder so
JOIN dbo.BusinessPartner bp ON bp.partnerID = so.customerPartnerID
LEFT JOIN dbo.Warehouse  wh ON wh.warehouseID = so.reservedWarehouseID
ORDER BY so.orderNumber;

PRINT '';
PRINT '--- STOK DURUMU ---';
SELECT
    w.warehouseCode,
    p.SKU,
    p.productName,
    ib.onHandQty,
    ib.reservedQty,
    ib.onHandQty - ib.reservedQty  AS kullanilabilir
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product   p ON p.productID   = ib.productID
ORDER BY w.warehouseCode, p.SKU;

PRINT '';
PRINT '--- STOK HAREKETLERİ ---';
SELECT
    sm.stockMovementID,
    w.warehouseCode,
    p.SKU,
    sm.movementType,
    sm.qtyIn,
    sm.qtyOut,
    sm.refType,
    sm.refID,
    CAST(sm.movementDate AS DATE)  AS tarih
FROM dbo.StockMovement sm
JOIN dbo.Warehouse w ON w.warehouseID = sm.warehouseID
JOIN dbo.Product   p ON p.productID   = sm.productID
ORDER BY sm.stockMovementID;

END TRY
BEGIN CATCH
    PRINT '';
    PRINT 'HATA OLUŞTU!';
    SELECT
        ERROR_NUMBER()   AS ErrorNumber,
        ERROR_LINE()     AS ErrorLine,
        ERROR_MESSAGE()  AS ErrorMessage;
END CATCH;
GO
