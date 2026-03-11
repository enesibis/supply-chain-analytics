USE [SCM_3];
GO
SET QUOTED_IDENTIFIER ON;
GO
SET ANSI_NULLS ON;
GO
-- FIX 05: TR_StockMovement_UpdateInventoryBalance
-- Sorun: InventoryBalance önce güncelleniyor, sonra negatif stok kontrolü yapılıyordu.
-- Güncelleme kısmen uygulandıktan sonra rollback tetikleniyordu.
-- Düzeltme: Kontrol ÖNCE yapılır, sonra güncellenir.
ALTER TRIGGER dbo.TR_StockMovement_UpdateInventoryBalance
ON dbo.StockMovement
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1) Inserted batch'i topla
    SELECT
        i.warehouseID,
        i.productID,
        SUM(ISNULL(i.qtyIn,0) - ISNULL(i.qtyOut,0)) AS qtyDelta
    INTO #delta
    FROM inserted i
    GROUP BY i.warehouseID, i.productID;

    -- 2) FIX: Negatif stok kontrolü ÖNCE yapılır (güncelleme olmadan)
    IF EXISTS
    (
        SELECT 1
        FROM #delta d
        LEFT JOIN dbo.InventoryBalance ib
          ON ib.warehouseID = d.warehouseID
         AND ib.productID   = d.productID
        WHERE (ISNULL(ib.onHandQty, 0) + d.qtyDelta) < 0
    )
    BEGIN
        RAISERROR('Stok eksiye düşüyor. StockMovement iptal edildi.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END;

    -- 3) Mevcut satırları güncelle
    UPDATE ib
        SET ib.onHandQty = ISNULL(ib.onHandQty,0) + d.qtyDelta,
            ib.updatedAt = SYSUTCDATETIME()
    FROM dbo.InventoryBalance ib
    JOIN #delta d
      ON d.warehouseID = ib.warehouseID
     AND d.productID   = ib.productID;

    -- 4) Olmayan satırları aç
    INSERT INTO dbo.InventoryBalance (warehouseID, productID, onHandQty, reservedQty, updatedAt)
    SELECT
        d.warehouseID,
        d.productID,
        d.qtyDelta,
        0,
        SYSUTCDATETIME()
    FROM #delta d
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM dbo.InventoryBalance ib
        WHERE ib.warehouseID = d.warehouseID
          AND ib.productID   = d.productID
    );
END;
GO
