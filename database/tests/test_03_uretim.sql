SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
USE [SCM_3];
GO
SET NOCOUNT ON;
PRINT '============================================================';
PRINT 'TEST 03 — ÜRETİM DÖNGÜSÜ';
PRINT 'CreateProductionOrder -> ReleaseProductionOrder';
PRINT '-> StartProductionOrder -> PostProductionConsumption';
PRINT '-> PostProductionOutput -> CompleteProductionOrder';
PRINT 'FIX TEST: Fazla üretim engeli, transaction içi validasyon';
PRINT '============================================================';

BEGIN TRY
    -------------------------------------------------------
    -- 1) CreateProductionOrder
    -------------------------------------------------------
    DECLARE @poID BIGINT;

    EXEC dbo.CreateProductionOrder
        @orderNumber       = 'PROD-TEST-001',
        @productID         = 6,     -- FG-001 Metal Masa
        @bomID             = 1,     -- BOM V1
        @plannedQuantity   = 5.000,
        @sourceWarehouseID = 2,     -- RAW deposu (hammadde oradan)
        @targetWarehouseID = 1,     -- MAIN deposu (mamul oraya)
        @productionOrderID = @poID OUTPUT;

    PRINT 'OK 1 | CreateProductionOrder -> productionOrderID: ' + CAST(@poID AS VARCHAR);

    -- Hata testi: Aynı orderNumber tekrar
    BEGIN TRY
        DECLARE @dummy BIGINT;
        EXEC dbo.CreateProductionOrder @orderNumber='PROD-TEST-001', @productID=6, @bomID=1,
             @plannedQuantity=1, @sourceWarehouseID=2, @targetWarehouseID=1, @productionOrderID=@dummy OUTPUT;
        PRINT 'FAIL | Duplicate orderNumber kabul edilmemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 1b | Beklenen hata (duplicate): ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 2) CancelProductionOrder (FIX 08 — DRAFT iptal testi)
    -------------------------------------------------------
    DECLARE @poID2 BIGINT;

    EXEC dbo.CreateProductionOrder
        @orderNumber='PROD-TEST-CANCEL', @productID=6, @bomID=1,
        @plannedQuantity=2, @sourceWarehouseID=2, @targetWarehouseID=1,
        @productionOrderID=@poID2 OUTPUT;

    EXEC dbo.CancelProductionOrder @productionOrderID = @poID2;
    PRINT 'OK 2 | CancelProductionOrder (DRAFT) çalıştı';

    -- Hata testi: CANCELLED'ı tekrar iptal
    BEGIN TRY
        EXEC dbo.CancelProductionOrder @productionOrderID = @poID2;
        PRINT 'FAIL | Zaten CANCELLED iptal edilemez!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 2b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 3) ReleaseProductionOrder
    -------------------------------------------------------
    EXEC dbo.ReleaseProductionOrder @productionOrderID = @poID;
    PRINT 'OK 3 | ReleaseProductionOrder -> RELEASED';

    -------------------------------------------------------
    -- 4) StartProductionOrder
    -------------------------------------------------------
    EXEC dbo.StartProductionOrder @productionOrderID = @poID;
    PRINT 'OK 4 | StartProductionOrder -> IN_PROGRESS';

    -- Hata testi: IN_PROGRESS'i Release etmeye çalış
    BEGIN TRY
        EXEC dbo.ReleaseProductionOrder @productionOrderID = @poID;
        PRINT 'FAIL | IN_PROGRESS olan RELEASE edilemez!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 4b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- 5) PostProductionConsumption (FIX 02 testi)
    -- BOM: FG-001 için 5 adet = RAW-001 x25, RAW-002 x10
    -------------------------------------------------------
    DECLARE @pcID1 BIGINT, @pcID2 BIGINT;

    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @poID,
        @componentProductID      = 4,        -- RAW-001
        @quantity                = 25.000,
        @productionConsumptionID = @pcID1 OUTPUT;

    PRINT 'OK 5 | PostProductionConsumption RAW-001 x25';

    EXEC dbo.PostProductionConsumption
        @productionOrderID       = @poID,
        @componentProductID      = 5,        -- RAW-002
        @quantity                = 10.000,
        @productionConsumptionID = @pcID2 OUTPUT;

    PRINT 'OK 5b | PostProductionConsumption RAW-002 x10';

    -- Hata testi (FIX 02): quantity negatif — transaction içinde doğru rollback olmalı
    BEGIN TRY
        DECLARE @dummy2 BIGINT;
        EXEC dbo.PostProductionConsumption @productionOrderID=@poID, @componentProductID=4,
             @quantity=-1, @productionConsumptionID=@dummy2 OUTPUT;
        PRINT 'FAIL | Negatif miktar kabul edilmemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 5c | Beklenen hata (negatif miktar, FIX 02): ' + ERROR_MESSAGE();
    END CATCH;

    -- Hata testi: Yetersiz stok
    BEGIN TRY
        EXEC dbo.PostProductionConsumption @productionOrderID=@poID, @componentProductID=4,
             @quantity=9999.000, @productionConsumptionID=@dummy2 OUTPUT;
        PRINT 'FAIL | Yetersiz stok kabul edilmemeli!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 5d | Beklenen hata (yetersiz stok): ' + ERROR_MESSAGE();
    END CATCH;

    PRINT '--- RAW deposu stok tüketildi mi? ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    WHERE ib.warehouseID = 2 ORDER BY p.SKU;

    -------------------------------------------------------
    -- 6) PostProductionOutput (FIX 03 testi)
    -------------------------------------------------------
    EXEC dbo.PostProductionOutput
        @productionOrderID = @poID,
        @quantity          = 3.000;    -- 5 planlı, 3 üret

    PRINT 'OK 6 | PostProductionOutput x3';

    -- Hata testi (FIX 03): Fazla üretim engeli — planlanandan fazla üretilemez
    BEGIN TRY
        EXEC dbo.PostProductionOutput @productionOrderID=@poID, @quantity=99.000;
        PRINT 'FAIL | Fazla üretim engellenmeli! (FIX 03)';
    END TRY
    BEGIN CATCH
        PRINT 'OK 6b | Beklenen hata (fazla üretim, FIX 03): ' + ERROR_MESSAGE();
    END CATCH;

    -- Kalan 2 adet üret
    EXEC dbo.PostProductionOutput @productionOrderID=@poID, @quantity=2.000;
    PRINT 'OK 6c | PostProductionOutput x2 (toplam 5/5)';

    -------------------------------------------------------
    -- 7) CompleteProductionOrder
    -------------------------------------------------------
    EXEC dbo.CompleteProductionOrder @productionOrderID=@poID, @allowPartial=0;
    PRINT 'OK 7 | CompleteProductionOrder -> COMPLETED';

    -- Hata testi: COMPLETED'ı iptal etmeye çalış
    BEGIN TRY
        EXEC dbo.CancelProductionOrder @productionOrderID = @poID;
        PRINT 'FAIL | COMPLETED iptal edilemez!';
    END TRY
    BEGIN CATCH
        PRINT 'OK 7b | Beklenen hata: ' + ERROR_MESSAGE();
    END CATCH;

    -------------------------------------------------------
    -- SONUÇ SELECTLERİ
    -------------------------------------------------------
    PRINT '';
    PRINT '--- ProductionOrder (COMPLETED, producedQty=5) ---';
    SELECT productionOrderID, orderNumber, status, plannedQuantity, producedQuantity, startDate, endDate
    FROM dbo.ProductionOrder WHERE productionOrderID = @poID;

    PRINT '--- ProductionConsumption kayıtları ---';
    SELECT pc.productionConsumptionID, p.SKU, pc.quantity, pc.consumptionDate
    FROM dbo.ProductionConsumption pc
    JOIN dbo.Product p ON p.productID = pc.productID
    WHERE pc.productionOrderID = @poID;

    PRINT '--- ProductionOutput kayıtları ---';
    SELECT po2.productionOutputID, p.SKU, po2.quantity, po2.outputDate
    FROM dbo.ProductionOutput po2
    JOIN dbo.Product p ON p.productID = po2.productID
    WHERE po2.productionOrderID = @poID;

    PRINT '--- InventoryBalance (MAIN deposuna FG-001 geldi mi? RAW azaldı mı?) ---';
    SELECT w.warehouseCode, p.SKU, ib.onHandQty, ib.reservedQty
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w ON w.warehouseID = ib.warehouseID
    JOIN dbo.Product p ON p.productID = ib.productID
    ORDER BY w.warehouseCode, p.SKU;

    PRINT '--- StockMovement (üretim kayıtları) ---';
    SELECT sm.movementType, p.SKU, sm.qtyIn, sm.qtyOut, sm.refType
    FROM dbo.StockMovement sm
    JOIN dbo.Product p ON p.productID = sm.productID
    WHERE sm.refType IN ('ProductionConsumption','ProductionOutput')
      AND sm.refID IN (
            SELECT productionConsumptionID FROM dbo.ProductionConsumption WHERE productionOrderID=@poID
            UNION ALL
            SELECT productionOutputID FROM dbo.ProductionOutput WHERE productionOrderID=@poID
      )
    ORDER BY sm.stockMovementID;

    PRINT '============================================================';
    PRINT 'TEST 03 BAŞARILI';
    PRINT '============================================================';
END TRY
BEGIN CATCH
    PRINT 'TEST HATASI: ' + ERROR_MESSAGE();
END CATCH;
GO
