SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;

PRINT '=================================================';
PRINT '2024 YILI TOPLU VERİ — Ocak-Aralık (12 ay)';
PRINT 'Tahmini: ~34 PO, ~33 Üretim Emri, ~30 Satış';
PRINT '=================================================';

BEGIN TRY

-- ==================================================
-- 0. ID LOOKUP
-- ==================================================
DECLARE @supACME    BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='ACME STEEL SUPPLY');
DECLARE @supDELTA   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='DELTA ALÜMİNYUM A.Ş.');
DECLARE @supPOLIMER BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='POLİMER PLASTİK LTD.');
DECLARE @custMEGA   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='MEGA CUSTOMER LTD');
DECLARE @custSTAR   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='STAR MARKETİNG A.Ş.');
DECLARE @custKOCA   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='KOCAELİ ENDÜSTRİ LTD.');
DECLARE @carrFAST   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='FAST CARRIER');
DECLARE @carrARAS   BIGINT = (SELECT partnerID FROM dbo.BusinessPartner WHERE partnerName='ARAS KARGO A.Ş.');

DECLARE @pRaw1 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-001');
DECLARE @pRaw2 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-002');
DECLARE @pRaw4 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-004');
DECLARE @pRaw5 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-005');
DECLARE @pRaw6 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-006');
DECLARE @pRaw7 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-007');
DECLARE @pRaw8 BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='RAW-008');
DECLARE @pFG1  BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='FG-001');
DECLARE @pFG2  BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='FG-002');
DECLARE @pFG3  BIGINT = (SELECT productID FROM dbo.Product WHERE SKU='FG-003');

DECLARE @wRAW  INT = (SELECT warehouseID FROM dbo.Warehouse WHERE warehouseCode='RAW');
DECLARE @wMAIN INT = (SELECT warehouseID FROM dbo.Warehouse WHERE warehouseCode='MAIN');

DECLARE @bomFG1 BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=@pFG1 AND isActive=1 ORDER BY bomID DESC);
DECLARE @bomFG2 BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=@pFG2 AND isActive=1 ORDER BY bomID DESC);
DECLARE @bomFG3 BIGINT = (SELECT TOP 1 bomID FROM dbo.BOM WHERE productID=@pFG3 AND isActive=1 ORDER BY bomID DESC);

IF @supDELTA IS NULL OR @supPOLIMER IS NULL OR @custSTAR IS NULL OR @custKOCA IS NULL
    THROW 50300, 'Partner eksik — önce masterDataExpand.sql çalıştır.', 1;
IF @pFG2 IS NULL OR @pFG3 IS NULL OR @pRaw4 IS NULL
    THROW 50301, 'Ürün eksik — önce masterDataExpand.sql çalıştır.', 1;
IF @bomFG2 IS NULL OR @bomFG3 IS NULL
    THROW 50302, 'BOM eksik — önce masterDataExpand.sql çalıştır.', 1;

-- ==================================================
-- Çalışma değişkenleri (hepsi burada declare edilir)
-- ==================================================
DECLARE @m        INT;
DECLARE @mStr     VARCHAR(2);
DECLARE @poDate   DATE;
DECLARE @grDate   DATE;
DECLARE @prdDate  DATE;
DECLARE @shipDate DATE;
DECLARE @carrier  BIGINT;

-- ID değişkenleri
DECLARE @poID    BIGINT;
DECLARE @poi1    BIGINT;
DECLARE @poi2    BIGINT;
DECLARE @poi3    BIGINT;
DECLARE @grID    BIGINT;
DECLARE @prdID   BIGINT;
DECLARE @pcID    BIGINT;
DECLARE @outID   BIGINT;
DECLARE @soID    BIGINT;
DECLARE @soiID   BIGINT;
DECLARE @soiID2  BIGINT;
DECLARE @shipID  BIGINT;

-- Miktar değişkenleri
DECLARE @qR1     INT;   -- RAW-001
DECLARE @qR2     INT;   -- RAW-002
DECLARE @qR4     INT;   -- RAW-004
DECLARE @qR5     INT;   -- RAW-005
DECLARE @qR6     INT;   -- RAW-006
DECLARE @qR7     INT;   -- RAW-007
DECLARE @qR8     INT;   -- RAW-008

DECLARE @qFG1p   INT;   -- FG-001 üretim
DECLARE @qFG2p   INT;   -- FG-002 üretim
DECLARE @qFG3p   INT;   -- FG-003 üretim

DECLARE @cR1fg1  DECIMAL(10,3);   -- FG1 için RAW-001 tüketim
DECLARE @cR2fg1  DECIMAL(10,3);   -- FG1 için RAW-002 tüketim
DECLARE @cR1fg2  DECIMAL(10,3);   -- FG2 için RAW-001 tüketim
DECLARE @cR2fg2  DECIMAL(10,3);   -- FG2 için RAW-002 tüketim
DECLARE @cR6fg2  DECIMAL(10,3);   -- FG2 için RAW-006 tüketim
DECLARE @cR4fg3  DECIMAL(10,3);   -- FG3 için RAW-004 tüketim
DECLARE @cR5fg3  DECIMAL(10,3);   -- FG3 için RAW-005 tüketim
DECLARE @cR8fg3  DECIMAL(10,3);   -- FG3 için RAW-008 tüketim

-- Satış miktar ve fiyat
DECLARE @qFG1mega INT;
DECLARE @qFG2mega INT;
DECLARE @qFG1star INT;
DECLARE @qFG2star INT;
DECLARE @qFG2koca INT;
DECLARE @qFG3koca INT;

DECLARE @pFG1pr  DECIMAL(10,2);
DECLARE @pFG2pr  DECIMAL(10,2);
DECLARE @pFG3pr  DECIMAL(10,2);

DECLARE @soStatus VARCHAR(20);
DECLARE @totalAmt DECIMAL(18,4);

-- ==================================================
-- ANA DÖNGÜ: Ocak (1) — Aralık (12)
-- ==================================================
SET @m = 1;

WHILE @m <= 12
BEGIN
    SET @mStr     = RIGHT('0' + CAST(@m AS VARCHAR(2)), 2);
    SET @poDate   = DATEFROMPARTS(2024, @m, 3);
    SET @grDate   = DATEFROMPARTS(2024, @m, 12);
    SET @prdDate  = DATEFROMPARTS(2024, @m, 15);
    SET @shipDate = DATEFROMPARTS(2024, @m, 22);
    SET @carrier  = CASE WHEN @m % 2 = 0 THEN @carrARAS ELSE @carrFAST END;

    -- Mevsimsellik: Q4 (Ekim-Aralık) daha yüksek
    SET @qFG1p  = CASE WHEN @m >= 10 THEN 30 + (@m % 3)*5
                       WHEN @m >= 7  THEN 20 + (@m % 3)*5
                       ELSE               15 + (@m % 3)*5 END;
    SET @qFG2p  = CASE WHEN @m >= 10 THEN 14 + @m % 3
                       WHEN @m >= 7  THEN 10 + @m % 3
                       ELSE               8  + @m % 3 END;
    SET @qFG3p  = CASE WHEN @m >= 10 THEN 7 + @m % 2
                       ELSE               4 + @m % 2 END;

    -- Hammadde satın alma miktarları
    SET @qR1  = 250 + (@m % 4) * 50;      -- 250-400 KG RAW-001
    SET @qR2  = @qR1 * 3;                 -- RAW-002
    SET @qR4  = 80  + (@m % 3) * 20;      -- 80-120 KG RAW-004
    SET @qR5  = @qR4 * 3;                 -- RAW-005
    SET @qR8  = 40  + (@m % 2) * 20;      -- 40-60 M RAW-008
    SET @qR6  = 40  + (@m % 2) * 15;      -- 40-55 KG RAW-006
    SET @qR7  = 60  + (@m % 3) * 20;      -- 60-100 KG RAW-007

    -- Üretim tüketimleri (BOM oranlarına göre)
    SET @cR1fg1 = @qFG1p * 1.0;           -- FG-001: 1 KG RAW-001/adet
    SET @cR2fg1 = @qFG1p * 4.0;           -- FG-001: 4 EA RAW-002/adet
    SET @cR1fg2 = @qFG2p * 2.0;           -- FG-002: 2 KG RAW-001/adet
    SET @cR2fg2 = @qFG2p * 8.0;           -- FG-002: 8 EA RAW-002/adet
    SET @cR6fg2 = @qFG2p * 0.30;          -- FG-002: 0.30 KG RAW-006/adet
    SET @cR4fg3 = @qFG3p * 5.0;           -- FG-003: 5 KG RAW-004/adet
    SET @cR5fg3 = @qFG3p * 20.0;          -- FG-003: 20 EA RAW-005/adet
    SET @cR8fg3 = @qFG3p * 3.0;           -- FG-003: 3 M RAW-008/adet

    -- Satış miktarları (üretimden az → stok birikimi)
    SET @qFG1mega = @qFG1p - 5;
    SET @qFG2mega = 3;                     -- sabit 3 adet (stok birikmesi için)
    SET @qFG1star = 3 + @m % 3;           -- 3-5 adet
    SET @qFG2star = 2;                     -- sabit 2 adet
    SET @qFG2koca = 2;                     -- sabit 2 adet (toplam FG-002 satış ≤ üretim)
    SET @qFG3koca = 2 + @m % 2;           -- 2-3 adet

    -- Fiyat artışı: yıl boyunca hafif artış
    SET @pFG1pr = 500.00 + (@m - 1) * 3;  -- 500 → 533
    SET @pFG2pr = 850.00 + (@m - 1) * 5;  -- 850 → 905
    SET @pFG3pr = 1200.00 + (@m - 1) * 8; -- 1200 → 1288

    -- Ay 11-12: sipariş var ama sevkiyat yok (bekleyen)
    SET @soStatus = CASE WHEN @m <= 10 THEN 'SHIPPED'
                         WHEN @m = 11  THEN 'APPROVED'
                         ELSE               'DRAFT' END;

    -- ====================================================
    -- A. SATIN ALMA — ACME (RAW-001, RAW-002) — her ay
    -- ====================================================
    IF NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber='PO-2024-'+@mStr+'-ACME')
    BEGIN
        INSERT INTO dbo.PurchaseOrder
            (supplierPartnerID, orderNumber, orderDate, expectedDeliveryDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@supACME, 'PO-2024-'+@mStr+'-ACME', @poDate, @grDate, 'RECEIVED',
             @qR1*45.00 + @qR2*12.00, @poDate, @grDate);
        SET @poID = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 1, @pRaw1, @qR1, 45.00, @qR1);
        SET @poi1 = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 2, @pRaw2, @qR2, 12.00, @qR2);
        SET @poi2 = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceipt (purchaseOrderID, warehouseID, receiptNumber, receiptDate, status, createdAt)
        VALUES (@poID, @wRAW, 'GR-2024-'+@mStr+'-ACME', @grDate, 'POSTED', @grDate);
        SET @grID = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceiptItem (goodsReceiptID, purchaseOrderItemID, lineNo_, productID, quantity)
        VALUES (@grID, @poi1, 1, @pRaw1, @qR1),
               (@grID, @poi2, 2, @pRaw2, @qR2);

        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw1, 'PURCHASE_RECEIPT', @qR1, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate),
               (@wRAW, @pRaw2, 'PURCHASE_RECEIPT', @qR2, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate);
    END;

    -- ====================================================
    -- B. SATIN ALMA — DELTA (RAW-004, RAW-005, RAW-008) — ay 2+
    -- ====================================================
    IF @m >= 2 AND NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber='PO-2024-'+@mStr+'-DELTA')
    BEGIN
        INSERT INTO dbo.PurchaseOrder
            (supplierPartnerID, orderNumber, orderDate, expectedDeliveryDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@supDELTA, 'PO-2024-'+@mStr+'-DELTA', @poDate, @grDate, 'RECEIVED',
             @qR4*78.00 + @qR5*4.80 + @qR8*92.00, @poDate, @grDate);
        SET @poID = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 1, @pRaw4, @qR4, 78.00, @qR4);
        SET @poi1 = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 2, @pRaw5, @qR5, 4.80, @qR5);
        SET @poi2 = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 3, @pRaw8, @qR8, 92.00, @qR8);
        SET @poi3 = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceipt (purchaseOrderID, warehouseID, receiptNumber, receiptDate, status, createdAt)
        VALUES (@poID, @wRAW, 'GR-2024-'+@mStr+'-DELTA', @grDate, 'POSTED', @grDate);
        SET @grID = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceiptItem (goodsReceiptID, purchaseOrderItemID, lineNo_, productID, quantity)
        VALUES (@grID, @poi1, 1, @pRaw4, @qR4),
               (@grID, @poi2, 2, @pRaw5, @qR5),
               (@grID, @poi3, 3, @pRaw8, @qR8);

        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw4, 'PURCHASE_RECEIPT', @qR4, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate),
               (@wRAW, @pRaw5, 'PURCHASE_RECEIPT', @qR5, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate),
               (@wRAW, @pRaw8, 'PURCHASE_RECEIPT', @qR8, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate);
    END;

    -- ====================================================
    -- C. SATIN ALMA — POLİMER (RAW-006, RAW-007) — ay 2+
    -- ====================================================
    IF @m >= 2 AND NOT EXISTS (SELECT 1 FROM dbo.PurchaseOrder WHERE orderNumber='PO-2024-'+@mStr+'-POLIMER')
    BEGIN
        INSERT INTO dbo.PurchaseOrder
            (supplierPartnerID, orderNumber, orderDate, expectedDeliveryDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@supPOLIMER, 'PO-2024-'+@mStr+'-POLIMER', @poDate, @grDate, 'RECEIVED',
             @qR6*118.00 + @qR7*8.50, @poDate, @grDate);
        SET @poID = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 1, @pRaw6, @qR6, 118.00, @qR6);
        SET @poi1 = SCOPE_IDENTITY();

        INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
        VALUES (@poID, 2, @pRaw7, @qR7, 8.50, @qR7);
        SET @poi2 = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceipt (purchaseOrderID, warehouseID, receiptNumber, receiptDate, status, createdAt)
        VALUES (@poID, @wRAW, 'GR-2024-'+@mStr+'-POLIMER', @grDate, 'POSTED', @grDate);
        SET @grID = SCOPE_IDENTITY();

        INSERT INTO dbo.GoodsReceiptItem (goodsReceiptID, purchaseOrderItemID, lineNo_, productID, quantity)
        VALUES (@grID, @poi1, 1, @pRaw6, @qR6),
               (@grID, @poi2, 2, @pRaw7, @qR7);

        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw6, 'PURCHASE_RECEIPT', @qR6, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate),
               (@wRAW, @pRaw7, 'PURCHASE_RECEIPT', @qR7, 0, @grDate, 'GoodsReceipt', @grID, NULL, @grDate);
    END;

    -- ====================================================
    -- D. ÜRETİM — FG-001 (her ay, RAW → MAIN)
    -- ====================================================
    IF NOT EXISTS (SELECT 1 FROM dbo.ProductionOrder WHERE orderNumber='PRD-2024-'+@mStr+'-FG1')
    BEGIN
        INSERT INTO dbo.ProductionOrder
            (orderNumber, productID, bomID, plannedQuantity, producedQuantity,
             sourceWarehouseID, targetWarehouseID, status, startDate, endDate, createdAt, updatedAt)
        VALUES
            ('PRD-2024-'+@mStr+'-FG1', @pFG1, @bomFG1, @qFG1p, @qFG1p,
             @wRAW, @wMAIN, 'COMPLETED', @prdDate, @prdDate, @prdDate, @prdDate);
        SET @prdID = SCOPE_IDENTITY();

        -- Tüketim: RAW-001
        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw1, @cR1fg1, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw1, 'PRODUCTION_CONSUMPTION', 0, @cR1fg1, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        -- Tüketim: RAW-002
        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw2, @cR2fg1, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw2, 'PRODUCTION_CONSUMPTION', 0, @cR2fg1, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        -- Çıktı: FG-001 → MAIN
        INSERT INTO dbo.ProductionOutput (productionOrderID, warehouseID, productID, quantity, outputDate, createdAt)
        VALUES (@prdID, @wMAIN, @pFG1, @qFG1p, @prdDate, @prdDate);
        SET @outID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wMAIN, @pFG1, 'PRODUCTION_OUTPUT', @qFG1p, 0, @prdDate, 'ProductionOutput', @outID, NULL, @prdDate);
    END;

    -- ====================================================
    -- E. ÜRETİM — FG-002 (ay 2+, RAW → MAIN)
    -- ====================================================
    IF @m >= 2 AND NOT EXISTS (SELECT 1 FROM dbo.ProductionOrder WHERE orderNumber='PRD-2024-'+@mStr+'-FG2')
    BEGIN
        INSERT INTO dbo.ProductionOrder
            (orderNumber, productID, bomID, plannedQuantity, producedQuantity,
             sourceWarehouseID, targetWarehouseID, status, startDate, endDate, createdAt, updatedAt)
        VALUES
            ('PRD-2024-'+@mStr+'-FG2', @pFG2, @bomFG2, @qFG2p, @qFG2p,
             @wRAW, @wMAIN, 'COMPLETED', @prdDate, @prdDate, @prdDate, @prdDate);
        SET @prdID = SCOPE_IDENTITY();

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw1, @cR1fg2, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw1, 'PRODUCTION_CONSUMPTION', 0, @cR1fg2, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw2, @cR2fg2, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw2, 'PRODUCTION_CONSUMPTION', 0, @cR2fg2, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw6, @cR6fg2, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw6, 'PRODUCTION_CONSUMPTION', 0, @cR6fg2, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionOutput (productionOrderID, warehouseID, productID, quantity, outputDate, createdAt)
        VALUES (@prdID, @wMAIN, @pFG2, @qFG2p, @prdDate, @prdDate);
        SET @outID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wMAIN, @pFG2, 'PRODUCTION_OUTPUT', @qFG2p, 0, @prdDate, 'ProductionOutput', @outID, NULL, @prdDate);
    END;

    -- ====================================================
    -- F. ÜRETİM — FG-003 (ay 3+, RAW → MAIN)
    -- ====================================================
    IF @m >= 3 AND NOT EXISTS (SELECT 1 FROM dbo.ProductionOrder WHERE orderNumber='PRD-2024-'+@mStr+'-FG3')
    BEGIN
        INSERT INTO dbo.ProductionOrder
            (orderNumber, productID, bomID, plannedQuantity, producedQuantity,
             sourceWarehouseID, targetWarehouseID, status, startDate, endDate, createdAt, updatedAt)
        VALUES
            ('PRD-2024-'+@mStr+'-FG3', @pFG3, @bomFG3, @qFG3p, @qFG3p,
             @wRAW, @wMAIN, 'COMPLETED', @prdDate, @prdDate, @prdDate, @prdDate);
        SET @prdID = SCOPE_IDENTITY();

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw4, @cR4fg3, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw4, 'PRODUCTION_CONSUMPTION', 0, @cR4fg3, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw5, @cR5fg3, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw5, 'PRODUCTION_CONSUMPTION', 0, @cR5fg3, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionConsumption (productionOrderID, warehouseID, productID, quantity, consumptionDate, createdAt)
        VALUES (@prdID, @wRAW, @pRaw8, @cR8fg3, @prdDate, @prdDate);
        SET @pcID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wRAW, @pRaw8, 'PRODUCTION_CONSUMPTION', 0, @cR8fg3, @prdDate, 'ProductionConsumption', @pcID, NULL, @prdDate);

        INSERT INTO dbo.ProductionOutput (productionOrderID, warehouseID, productID, quantity, outputDate, createdAt)
        VALUES (@prdID, @wMAIN, @pFG3, @qFG3p, @prdDate, @prdDate);
        SET @outID = SCOPE_IDENTITY();
        INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
        VALUES (@wMAIN, @pFG3, 'PRODUCTION_OUTPUT', @qFG3p, 0, @prdDate, 'ProductionOutput', @outID, NULL, @prdDate);
    END;

    -- ====================================================
    -- G. SATIŞ — MEGA CUSTOMER (FG-001, ay 2+)
    --            (FG-001 + FG-002, ay 3+)
    -- ====================================================
    IF @m >= 2 AND NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE orderNumber='SO-2024-'+@mStr+'-MEGA')
    BEGIN
        SET @totalAmt = @qFG1mega * @pFG1pr +
                        CASE WHEN @m >= 3 THEN @qFG2mega * @pFG2pr ELSE 0 END;

        INSERT INTO dbo.SalesOrder
            (customerPartnerID, orderNumber, orderDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@custMEGA, 'SO-2024-'+@mStr+'-MEGA', DATEADD(day,-5,@shipDate), @soStatus, @totalAmt, DATEADD(day,-5,@shipDate), @shipDate);
        SET @soID = SCOPE_IDENTITY();

        INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
        VALUES (@soID, 1, @pFG1, @qFG1mega, @pFG1pr,
                CASE WHEN @soStatus='SHIPPED' THEN @qFG1mega ELSE 0 END);
        SET @soiID = SCOPE_IDENTITY();

        IF @m >= 3
        BEGIN
            INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
            VALUES (@soID, 2, @pFG2, @qFG2mega, @pFG2pr,
                    CASE WHEN @soStatus='SHIPPED' THEN @qFG2mega ELSE 0 END);
            SET @soiID2 = SCOPE_IDENTITY();
        END;

        IF @soStatus = 'SHIPPED'
        BEGIN
            INSERT INTO dbo.Shipment
                (salesOrderID, warehouseID, customerPartnerID, shipmentNumber, shipmentDate, status, carrierPartnerID, createdAt)
            VALUES
                (@soID, @wMAIN, @custMEGA, 'SHP-2024-'+@mStr+'-MEGA', @shipDate, 'POSTED', @carrier, @shipDate);
            SET @shipID = SCOPE_IDENTITY();

            INSERT INTO dbo.ShipmentItem (shipmentID, salesOrderItemID, lineNo_, productID, quantity)
            VALUES (@shipID, @soiID, 1, @pFG1, @qFG1mega);
            INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
            VALUES (@wMAIN, @pFG1, 'SALES_SHIPMENT', 0, @qFG1mega, @shipDate, 'Shipment', @shipID, NULL, @shipDate);

            IF @m >= 3
            BEGIN
                INSERT INTO dbo.ShipmentItem (shipmentID, salesOrderItemID, lineNo_, productID, quantity)
                VALUES (@shipID, @soiID2, 2, @pFG2, @qFG2mega);
                INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
                VALUES (@wMAIN, @pFG2, 'SALES_SHIPMENT', 0, @qFG2mega, @shipDate, 'Shipment', @shipID, NULL, @shipDate);
            END;
        END;
    END;

    -- ====================================================
    -- H. SATIŞ — STAR MARKETİNG (FG-001 + FG-002, ay 3+)
    -- ====================================================
    IF @m >= 3 AND NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE orderNumber='SO-2024-'+@mStr+'-STAR')
    BEGIN
        SET @totalAmt = @qFG1star * @pFG1pr + @qFG2star * @pFG2pr;

        INSERT INTO dbo.SalesOrder
            (customerPartnerID, orderNumber, orderDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@custSTAR, 'SO-2024-'+@mStr+'-STAR', DATEADD(day,-4,@shipDate), @soStatus, @totalAmt, DATEADD(day,-4,@shipDate), @shipDate);
        SET @soID = SCOPE_IDENTITY();

        INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
        VALUES (@soID, 1, @pFG1, @qFG1star, @pFG1pr,
                CASE WHEN @soStatus='SHIPPED' THEN @qFG1star ELSE 0 END);
        SET @soiID = SCOPE_IDENTITY();

        INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
        VALUES (@soID, 2, @pFG2, @qFG2star, @pFG2pr,
                CASE WHEN @soStatus='SHIPPED' THEN @qFG2star ELSE 0 END);
        SET @soiID2 = SCOPE_IDENTITY();

        IF @soStatus = 'SHIPPED'
        BEGIN
            INSERT INTO dbo.Shipment
                (salesOrderID, warehouseID, customerPartnerID, shipmentNumber, shipmentDate, status, carrierPartnerID, createdAt)
            VALUES
                (@custSTAR, @wMAIN, @custSTAR, 'SHP-2024-'+@mStr+'-STAR', @shipDate, 'POSTED', @carrier, @shipDate);
            SET @shipID = SCOPE_IDENTITY();

            INSERT INTO dbo.ShipmentItem (shipmentID, salesOrderItemID, lineNo_, productID, quantity)
            VALUES (@shipID, @soiID,  1, @pFG1, @qFG1star),
                   (@shipID, @soiID2, 2, @pFG2, @qFG2star);

            INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
            VALUES (@wMAIN, @pFG1, 'SALES_SHIPMENT', 0, @qFG1star, @shipDate, 'Shipment', @shipID, NULL, @shipDate),
                   (@wMAIN, @pFG2, 'SALES_SHIPMENT', 0, @qFG2star, @shipDate, 'Shipment', @shipID, NULL, @shipDate);
        END;
    END;

    -- ====================================================
    -- I. SATIŞ — KOCAELİ ENDÜSTRİ (FG-002, ay 4+)
    --                               (FG-002 + FG-003, ay 5+)
    -- ====================================================
    IF @m >= 4 AND NOT EXISTS (SELECT 1 FROM dbo.SalesOrder WHERE orderNumber='SO-2024-'+@mStr+'-KOCA')
    BEGIN
        SET @totalAmt = @qFG2koca * @pFG2pr +
                        CASE WHEN @m >= 5 THEN @qFG3koca * @pFG3pr ELSE 0 END;

        INSERT INTO dbo.SalesOrder
            (customerPartnerID, orderNumber, orderDate, status, totalAmount, createdAt, updatedAt)
        VALUES
            (@custKOCA, 'SO-2024-'+@mStr+'-KOCA', DATEADD(day,-3,@shipDate), @soStatus, @totalAmt, DATEADD(day,-3,@shipDate), @shipDate);
        SET @soID = SCOPE_IDENTITY();

        INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
        VALUES (@soID, 1, @pFG2, @qFG2koca, @pFG2pr,
                CASE WHEN @soStatus='SHIPPED' THEN @qFG2koca ELSE 0 END);
        SET @soiID = SCOPE_IDENTITY();

        IF @m >= 5
        BEGIN
            INSERT INTO dbo.SalesOrderItem (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
            VALUES (@soID, 2, @pFG3, @qFG3koca, @pFG3pr,
                    CASE WHEN @soStatus='SHIPPED' THEN @qFG3koca ELSE 0 END);
            SET @soiID2 = SCOPE_IDENTITY();
        END;

        IF @soStatus = 'SHIPPED'
        BEGIN
            INSERT INTO dbo.Shipment
                (salesOrderID, warehouseID, customerPartnerID, shipmentNumber, shipmentDate, status, carrierPartnerID, createdAt)
            VALUES
                (@soID, @wMAIN, @custKOCA, 'SHP-2024-'+@mStr+'-KOCA', @shipDate, 'POSTED', @carrier, @shipDate);
            SET @shipID = SCOPE_IDENTITY();

            INSERT INTO dbo.ShipmentItem (shipmentID, salesOrderItemID, lineNo_, productID, quantity)
            VALUES (@shipID, @soiID, 1, @pFG2, @qFG2koca);
            INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
            VALUES (@wMAIN, @pFG2, 'SALES_SHIPMENT', 0, @qFG2koca, @shipDate, 'Shipment', @shipID, NULL, @shipDate);

            IF @m >= 5
            BEGIN
                INSERT INTO dbo.ShipmentItem (shipmentID, salesOrderItemID, lineNo_, productID, quantity)
                VALUES (@shipID, @soiID2, 2, @pFG3, @qFG3koca);
                INSERT INTO dbo.StockMovement (warehouseID, productID, movementType, qtyIn, qtyOut, movementDate, refType, refID, note, createdAt)
                VALUES (@wMAIN, @pFG3, 'SALES_SHIPMENT', 0, @qFG3koca, @shipDate, 'Shipment', @shipID, NULL, @shipDate);
            END;
        END;
    END;

    PRINT '  Ay ' + @mStr + ' OK';
    SET @m = @m + 1;
END; -- while

-- ==================================================
-- ÖZET
-- ==================================================
PRINT '';
PRINT '=================================================';
PRINT 'TAMAMLANDI';
PRINT '=================================================';

SELECT Tablo, ToplamKayit FROM (
    SELECT 'PurchaseOrder'     AS Tablo, COUNT(*) AS ToplamKayit FROM dbo.PurchaseOrder    UNION ALL
    SELECT 'GoodsReceipt',               COUNT(*)               FROM dbo.GoodsReceipt      UNION ALL
    SELECT 'ProductionOrder',            COUNT(*)               FROM dbo.ProductionOrder   UNION ALL
    SELECT 'SalesOrder',                 COUNT(*)               FROM dbo.SalesOrder        UNION ALL
    SELECT 'Shipment',                   COUNT(*)               FROM dbo.Shipment          UNION ALL
    SELECT 'StockMovement',              COUNT(*)               FROM dbo.StockMovement
) x ORDER BY Tablo;

PRINT '';
PRINT '--- AYLIK SATIŞ CİROSU (2024) ---';
SELECT
    MONTH(CAST(so.orderDate AS DATE))   AS Ay,
    COUNT(DISTINCT so.salesOrderID)     AS SiparisSayisi,
    SUM(so.totalAmount)                 AS ToplamCiro_TL
FROM dbo.SalesOrder so
WHERE so.orderNumber LIKE 'SO-2024-__-%'
GROUP BY MONTH(CAST(so.orderDate AS DATE))
ORDER BY Ay;

PRINT '';
PRINT '--- STOK DURUMU ---';
SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty,
       ib.onHandQty - ib.reservedQty AS Kullanilabilir
FROM dbo.InventoryBalance ib
JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
JOIN dbo.Product   p ON p.productID   = ib.productID
ORDER BY w.warehouseCode, p.SKU;

END TRY
BEGIN CATCH
    PRINT 'HATA (Ay: ' + ISNULL(@mStr,'?') + '): ' + ERROR_MESSAGE();
    SELECT ERROR_NUMBER() EN, ERROR_LINE() EL, ERROR_MESSAGE() EM;
END CATCH;
GO
