SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'TEST 01 — SATIN ALMA DÖNGÜSÜ';
PRINT 'CreatePurchaseOrder -> AddPOItem -> ApprovePO';
PRINT '-> CreateGoodsReceipt -> AddGRItem -> PostGoodsReceipt';
PRINT '============================================================';

BEGIN TRY
    -------------------------------------------------------
    -- 1) CreatePurchaseOrder (YENİ PROSEDÜR — fix_07)
    -------------------------------------------------------
    DECLARE @poID BIGINT;

    EXEC dbo.CreatePurchaseOrder
        @orderNumber          = 'PO-TEST-001',
        @supplierPartnerID    = 1,          -- ACME STEEL SUPPLY
        @expectedDeliveryDate = NULL,
        @purchaseOrderID      = @poID OUTPUT;

    PRINT 'OK 1 | CreatePurchaseOrder -> purchaseOrderID: ' + CAST(@poID AS VARCHAR);

    -------------------------------------------------------
    -- 2) PurchaseOrderItem direkt INSERT (AddPurchaseOrderItem prosedürü yok)
    -------------------------------------------------------
    INSERT INTO dbo.PurchaseOrderItem (purchaseOrderID, lineNo_, productID, quantity, unitPrice, receivedQuantity)
    VALUES (@poID, 1, 4, 20.000, 15.0000, 0),   -- RAW-001: 20 adet, 15 TL
           (@poID, 2, 5, 10.000,  5.0000, 0);   -- RAW-002: 10 adet, 5 TL

    UPDATE dbo.PurchaseOrder SET totalAmount = 20*15 + 10*5 WHERE purchaseOrderID = @poID;
    PRINT 'OK 2 | PurchaseOrderItem eklendi (2 satır)';

    -------------------------------------------------------
    -- 3) ApprovePurchaseOrder
    -------------------------------------------------------
    EXEC dbo.ApprovePurchaseOrder @purchaseOrderID = @poID;
    PRINT 'OK 3 | ApprovePurchaseOrder';

    -- Hata testi: APPROVED PO tekrar approve edilemez
    BEGIN TRY
        EXEC dbo.ApprovePurchaseOrder @purchaseOrderID = @poID;
        PRINT 'FAIL | Tekrar approve edilmemeli!'
    END TRY
    BEGIN CATCH
        PRINT 'OK 3b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 4) CreateGoodsReceipt
    -------------------------------------------------------
    DECLARE @grID BIGINT;

    EXEC dbo.CreateGoodsReceipt
        @purchaseOrderID = @poID,
        @warehouseID     = 2,           -- RAW deposu
        @receiptNumber   = 'GR-TEST-001',
        @goodsReceiptID  = @grID OUTPUT;

    PRINT 'OK 4 | CreateGoodsReceipt -> goodsReceiptID: ' + CAST(@grID AS VARCHAR);

    -------------------------------------------------------
    -- 5) AddGoodsReceiptItem
    -------------------------------------------------------
    DECLARE @poItem1 BIGINT, @poItem2 BIGINT;
    SELECT @poItem1 = MIN(purchaseOrderItemID), @poItem2 = MAX(purchaseOrderItemID)
    FROM dbo.PurchaseOrderItem WHERE purchaseOrderID = @poID;

    DECLARE @griID1 BIGINT, @griID2 BIGINT;

    EXEC dbo.AddGoodsReceiptItem
        @goodsReceiptID      = @grID,
        @purchaseOrderItemID = @poItem1,
        @quantity            = 20.000,
        @goodsReceiptItemID  = @griID1 OUTPUT;

    EXEC dbo.AddGoodsReceiptItem
        @goodsReceiptID      = @grID,
        @purchaseOrderItemID = @poItem2,
        @quantity            = 10.000,
        @goodsReceiptItemID  = @griID2 OUTPUT;

    PRINT 'OK 5 | AddGoodsReceiptItem x2';

    -- Hata testi: Miktar aşımı
    BEGIN TRY
        EXEC dbo.AddGoodsReceiptItem
            @goodsReceiptID      = @grID,
            @purchaseOrderItemID = @poItem1,
            @quantity            = 99.000,
            @goodsReceiptItemID  = @griID1 OUTPUT;
        PRINT 'FAIL | Miktar aşımına izin vermemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 5b | Beklenen hata (miktar aşımı): ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 6) PostGoodsReceipt
    -------------------------------------------------------
    EXEC dbo.PostGoodsReceipt @goodsReceiptID = @grID;
    PRINT 'OK 6 | PostGoodsReceipt';

    -- Hata testi: POSTED GR tekrar post edilemez
    BEGIN TRY
        EXEC dbo.PostGoodsReceipt @goodsReceiptID = @grID;
        PRINT 'FAIL | Tekrar post edilmemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 6b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- SONUÇ SELECTLERİ
    -------------------------------------------------------
    PRINT '';
    PRINT '--- PurchaseOrder ---';
    SELECT purchaseOrderID, orderNumber, status, totalAmount FROM dbo.PurchaseOrder WHERE purchaseOrderID = @poID;

    PRINT '--- PurchaseOrderItem (receivedQuantity güncellendi mi?) ---';
    SELECT poi.lineNo_, p.SKU, poi.quantity, poi.receivedQuantity, poi.unitPrice
    FROM dbo.PurchaseOrderItem poi
    JOIN dbo.Product p ON p.productID = poi.productID
    WHERE poi.purchaseOrderID = @poID;

    PRINT '--- GoodsReceipt ---';
    SELECT goodsReceiptID, receiptNumber, status FROM dbo.GoodsReceipt WHERE goodsReceiptID = @grID;

    PRINT '--- InventoryBalance (RAW deposu stok arttı mı?) ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    WHERE ib.warehouseID = 2
    ORDER BY p.SKU;

    PRINT '--- StockMovement (PURCHASE_RECEIPT kayıtları) ---';
    SELECT sm.movementType, p.SKU, sm.qtyIn, sm.qtyOut, sm.refType
    FROM dbo.StockMovement sm
    JOIN dbo.Product p ON p.productID = sm.productID
    WHERE sm.refID = @grID AND sm.refType = 'GoodsReceipt';

    PRINT '============================================================';
    PRINT 'TEST 01 BAŞARILI';
    PRINT '============================================================';
END TRY
BEGIN CATCH
    PRINT 'TEST HATASI: ' + ERROR_MESSAGE();
END CATCH;
GO
