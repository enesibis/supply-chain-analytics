SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'TEST 02 — SATIŞ DÖNGÜSÜ';
PRINT 'CreateSalesOrder -> AddSOItem -> ApproveSO -> ReserveSO';
PRINT '-> CreateShipment -> AddShipmentItem -> PostShipment';
PRINT '-> UnreserveSalesOrder (test)';
PRINT '============================================================';

BEGIN TRY
    -------------------------------------------------------
    -- 1) CreateSalesOrder
    -------------------------------------------------------
    DECLARE @soID BIGINT;

    EXEC dbo.CreateSalesOrder
        @orderNumber       = 'SO-TEST-001',
        @customerPartnerID = 2,          -- MEGA CUSTOMER LTD
        @salesOrderID      = @soID OUTPUT;

    PRINT 'OK 1 | CreateSalesOrder -> salesOrderID: ' + CAST(@soID AS VARCHAR);

    -------------------------------------------------------
    -- 2) AddSalesOrderItem
    -------------------------------------------------------
    DECLARE @soiID BIGINT;

    EXEC dbo.AddSalesOrderItem
        @salesOrderID     = @soID,
        @productID        = 6,           -- FG-001 Metal Masa
        @quantity         = 2.000,
        @unitPrice        = 500.0000,
        @salesOrderItemID = @soiID OUTPUT;

    PRINT 'OK 2 | AddSalesOrderItem -> salesOrderItemID: ' + CAST(@soiID AS VARCHAR);

    -- Hata testi: Negatif miktar
    BEGIN TRY
        DECLARE @dummy BIGINT;
        EXEC dbo.AddSalesOrderItem @salesOrderID=@soID, @productID=6, @quantity=-1, @unitPrice=500, @salesOrderItemID=@dummy OUTPUT;
        PRINT 'FAIL | Negatif miktara izin vermemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 2b | Beklenen hata (negatif miktar): ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 3) ApproveSalesOrder
    -------------------------------------------------------
    EXEC dbo.ApproveSalesOrder @salesOrderID = @soID;
    PRINT 'OK 3 | ApproveSalesOrder';

    -- Hata testi: DRAFT olmayan SO'ya satır eklenemez
    BEGIN TRY
        EXEC dbo.AddSalesOrderItem @salesOrderID=@soID, @productID=6, @quantity=1, @unitPrice=500, @salesOrderItemID=@soiID OUTPUT;
        PRINT 'FAIL | APPROVED SO''ya satır eklenebilmemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 3b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 4) ReserveSalesOrder (FIX 04 testi: onHand - reserved kontrolü)
    -------------------------------------------------------
    EXEC dbo.ReserveSalesOrder @salesOrderID = @soID, @warehouseID = 1;  -- MAIN deposu
    PRINT 'OK 4 | ReserveSalesOrder (MAIN deposu)';

    -- Hata testi: Zaten rezerve — tekrar reserve edilemez
    BEGIN TRY
        EXEC dbo.ReserveSalesOrder @salesOrderID = @soID, @warehouseID = 1;
        PRINT 'FAIL | Zaten rezerve olan SO tekrar reserve edilemez!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 4b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    PRINT '--- InventoryBalance (reservedQty güncellendi mi?) ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    WHERE ib.warehouseID = 1;

    -------------------------------------------------------
    -- 5) UnreserveSalesOrder (FIX 09 testi)
    -------------------------------------------------------
    EXEC dbo.UnreserveSalesOrder @salesOrderID = @soID;
    PRINT 'OK 5 | UnreserveSalesOrder (rezervasyon çözüldü)';

    PRINT '--- InventoryBalance (reservedQty sıfırlandı mı?) ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    WHERE ib.warehouseID = 1;

    -- Tekrar reserve et (sevkiyat için gerekli)
    EXEC dbo.ReserveSalesOrder @salesOrderID = @soID, @warehouseID = 1;
    PRINT 'OK 5b | ReserveSalesOrder tekrar yapıldı';

    -------------------------------------------------------
    -- 6) CreateShipment
    -------------------------------------------------------
    DECLARE @shipID BIGINT;

    EXEC dbo.CreateShipment
        @salesOrderID     = @soID,
        @warehouseID      = 1,            -- MAIN deposu
        @shipmentNumber   = 'SHP-TEST-001',
        @carrierPartnerID = 3,            -- FAST CARRIER
        @shipmentID       = @shipID OUTPUT;

    PRINT 'OK 6 | CreateShipment -> shipmentID: ' + CAST(@shipID AS VARCHAR);

    -------------------------------------------------------
    -- 7) AddShipmentItem (FIX 04: onHand - reserved kontrolü)
    -------------------------------------------------------
    DECLARE @smiID BIGINT;

    EXEC dbo.AddShipmentItem
        @shipmentID       = @shipID,
        @salesOrderItemID = @soiID,
        @quantity         = 2.000,
        @shipmentItemID   = @smiID OUTPUT;

    PRINT 'OK 7 | AddShipmentItem -> shipmentItemID: ' + CAST(@smiID AS VARCHAR);

    -- Hata testi: Stok aşımı (4 tane var, 2 reserve, kullanılabilir 2, 3 istiyoruz)
    BEGIN TRY
        DECLARE @dummy2 BIGINT;
        -- Önce yeni bir SO satırı ekleyemeyiz (SO approved), stok aşımı doğrudan test
        -- AddShipmentItem'daki onHand-reserved kontrolü: 4-2=2 available, şimdi 2 ekledik,
        -- DRAFT shipment içindeki 2'yi de sayınca kalan 0 olur
        -- Bu yüzden başka bir SO/Shipment üzerinden değil, fazla miktar deneyelim:
        EXEC dbo.AddShipmentItem @shipmentID=@shipID, @salesOrderItemID=@soiID, @quantity=999, @shipmentItemID=@dummy2 OUTPUT;
        PRINT 'FAIL | Stok aşımına izin vermemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 7b | Beklenen hata (stok/miktar aşımı): ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 8) PostShipment (FIX 06: temizlenmiş validasyon)
    -------------------------------------------------------
    EXEC dbo.PostShipment @shipmentID = @shipID;
    PRINT 'OK 8 | PostShipment';

    -------------------------------------------------------
    -- SONUÇ SELECTLERİ
    -------------------------------------------------------
    PRINT '';
    PRINT '--- SalesOrder (status SHIPPED mi?) ---';
    SELECT salesOrderID, orderNumber, status, totalAmount, reservedWarehouseID FROM dbo.SalesOrder WHERE salesOrderID = @soID;

    PRINT '--- SalesOrderItem (shippedQuantity güncellendi mi?) ---';
    SELECT soi.lineNo_, p.SKU, soi.quantity, soi.shippedQuantity, soi.unitPrice
    FROM dbo.SalesOrderItem soi
    JOIN dbo.Product p ON p.productID = soi.productID
    WHERE soi.salesOrderID = @soID;

    PRINT '--- Shipment ---';
    SELECT shipmentID, shipmentNumber, status FROM dbo.Shipment WHERE shipmentID = @shipID;

    PRINT '--- InventoryBalance (MAIN deposu stok azaldı mı?) ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    WHERE ib.warehouseID = 1;

    PRINT '--- StockMovement (SALES_SHIPMENT kaydı) ---';
    SELECT sm.movementType, p.SKU, sm.qtyIn, sm.qtyOut
    FROM dbo.StockMovement sm
    JOIN dbo.Product p ON p.productID = sm.productID
    WHERE sm.refID = @shipID AND sm.refType = 'Shipment';

    PRINT '============================================================';
    PRINT 'TEST 02 BAŞARILI';
    PRINT '============================================================';
END TRY
BEGIN CATCH
    PRINT 'TEST HATASI: ' + ERROR_MESSAGE();
END CATCH;
GO
