-- ============================================================
-- SCM_3 — PARAMETRİK SORGULAR
-- TVF  : Power BI'dan tablo gibi çağrılır
-- SP   : SSMS / uygulama tarafından çağrılır
--
-- PERFORMANS TEDBİRLERİ:
--   • Inline TVF → optimizer tarafından düzleştirilir (view gibi)
--   • SP'lerde OPTION(RECOMPILE) → parameter sniffing'i önler
--   • Tüm WHERE sütunları indekslenmiş olmalı (öneriler sonda)
-- ============================================================

-- ============================================================
-- BÖLÜM 1: TABLE-VALUED FUNCTIONS (TVF)
-- Power BI → Get Data → SQL Server → Function olarak bağlanır
-- ============================================================

-- ── TVF 1: Satış Raporu (tarih / şube / kategori) ────────────
-- (Zaten mevcut — güncellendi)
CREATE OR ALTER FUNCTION dbo.fn_SatisRaporu (
    @baslangic DATE,
    @bitis     DATE,
    @subeKodu  NVARCHAR(20)  = NULL,
    @kategori  NVARCHAR(100) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        so.orderNumber                      AS SiparisNo,
        CAST(so.orderDate AS DATE)          AS SiparisTarihi,
        YEAR(so.orderDate)                  AS Yil,
        MONTH(so.orderDate)                 AS Ay,
        s.subeKodu,
        s.subeAdi                           AS Sube,
        bp.partnerName                      AS Musteri,
        p.productName                       AS UrunAdi,
        pc.categoryName                     AS Kategori,
        soi.quantity                        AS Miktar,
        soi.unitPrice                       AS BirimFiyat,
        soi.totalPrice                      AS Tutar,
        so.totalAmount                      AS SiparisToplam,
        so.status                           AS Durum
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s             ON so.subeID = s.subeID
    JOIN dbo.BusinessPartner bp ON so.customerPartnerID = bp.partnerID
    JOIN dbo.SalesOrderItem soi ON so.salesOrderID = soi.salesOrderID
    JOIN dbo.Product p          ON soi.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE CAST(so.orderDate AS DATE) BETWEEN @baslangic AND @bitis
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND (@kategori IS NULL OR pc.categoryName = @kategori)
      AND so.status != 'CANCELLED'
);
GO

-- ── TVF 2: Dönem Karşılaştırma ────────────────────────────────
-- (Zaten mevcut — güncellendi)
CREATE OR ALTER FUNCTION dbo.fn_DonemKarsilastirma (
    @yil1     INT,
    @yil2     INT,
    @subeKodu NVARCHAR(20) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        MONTH(so.orderDate)                 AS Ay,
        DATENAME(MONTH, so.orderDate)       AS AyAdi,
        s.subeKodu,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END) AS Donem1Tutar,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) AS Donem2Tutar,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil1 THEN 1 END)                   AS Donem1Siparis,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil2 THEN 1 END)                   AS Donem2Siparis,
        ROUND(100.0 *
            (SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) -
             SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END)) /
            NULLIF(SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END),0)
        , 1)                                AS BuyumeOrani
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s ON so.subeID = s.subeID
    WHERE YEAR(so.orderDate) IN (@yil1, @yil2)
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND so.status != 'CANCELLED'
    GROUP BY MONTH(so.orderDate), DATENAME(MONTH, so.orderDate), s.subeKodu
);
GO

-- ── TVF 3: Tedarikçi Teslim Analizi ──────────────────────────
-- (Zaten mevcut — güncellendi)
CREATE OR ALTER FUNCTION dbo.fn_TedarikciTeslimAnalizi (
    @yil      INT,
    @subeKodu NVARCHAR(20) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        bp.partnerName                      AS Tedarikci,
        s.subeKodu,
        COUNT(po.purchaseOrderID)           AS ToplamSiparis,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.orderDate,          gr_min.minRec) AS FLOAT)),1) AS OrtTeslimGun,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.expectedDeliveryDate, gr_min.minRec) AS FLOAT)),1) AS OrtGecikmeGun,
        SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)  AS TamamlananSiparis,
        ROUND(100.0 * SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*),0), 1)      AS ZamanindaTeslimOrani
    FROM dbo.PurchaseOrder po
    JOIN dbo.BusinessPartner bp ON po.supplierPartnerID = bp.partnerID
    JOIN dbo.Sube s             ON po.subeID = s.subeID
    LEFT JOIN (
        SELECT purchaseOrderID, MIN(receiptDate) AS minRec
        FROM dbo.GoodsReceipt GROUP BY purchaseOrderID
    ) gr_min ON gr_min.purchaseOrderID = po.purchaseOrderID
    WHERE YEAR(po.orderDate) = @yil
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND po.status != 'CANCELLED'
    GROUP BY bp.partnerName, s.subeKodu
);
GO

-- ── TVF 4: Stok Durum Raporu ──────────────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_StokDurumRaporu (
    @subeKodu    NVARCHAR(20)  = NULL,
    @kategori    NVARCHAR(100) = NULL,
    @sadeceDusuk BIT           = 0     -- 1 = sadece kritik/düşük stoklar
)
RETURNS TABLE AS RETURN (
    SELECT
        s.subeKodu,
        s.subeAdi                           AS Sube,
        w.warehouseName                     AS Depo,
        p.productName                       AS UrunAdi,
        p.SKU,
        pc.categoryName                     AS Kategori,
        ISNULL(ib.onHandQty,0)              AS EldeKi,
        ISNULL(ib.reservedQty,0)            AS Rezerveli,
        ISNULL(ib.onHandQty,0) - ISNULL(ib.reservedQty,0) AS Kullanilabilir,
        p.minStockLevel                     AS MinStokSeviyesi,
        CASE
            WHEN ISNULL(ib.onHandQty,0) <= 0               THEN N'Stok Yok'
            WHEN ISNULL(ib.onHandQty,0) <= p.minStockLevel THEN N'Kritik'
            WHEN ISNULL(ib.onHandQty,0) <= p.minStockLevel * 1.5 THEN N'Dusuk'
            ELSE N'Normal'
        END                                 AS StokDurumu,
        ib.updatedAt                        AS SonGuncelleme
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w        ON ib.warehouseID = w.warehouseID
    JOIN dbo.Sube s             ON w.subeID = s.subeID
    JOIN dbo.Product p          ON ib.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND (@kategori IS NULL OR pc.categoryName = @kategori)
      AND (@sadeceDusuk = 0
           OR ISNULL(ib.onHandQty,0) <= p.minStockLevel * 1.5)
);
GO

-- ── TVF 5: Müşteri RFM Analizi ────────────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_MusteriRFM (
    @subeKodu NVARCHAR(20) = NULL,
    @segment  NVARCHAR(20) = NULL   -- 'VIP', 'Aktif', 'Pasif', 'Kayip Risk'
)
RETURNS TABLE AS RETURN (
    SELECT
        bp.partnerID                        AS MusteriID,
        bp.partnerName                      AS Musteri,
        s.subeKodu,
        COUNT(DISTINCT so.salesOrderID)     AS ToplamSiparis,
        SUM(so.totalAmount)                 AS ToplamCiro,
        AVG(so.totalAmount)                 AS OrtSiparisTutari,
        MIN(CAST(so.orderDate AS DATE))     AS IlkSiparis,
        MAX(CAST(so.orderDate AS DATE))     AS SonSiparis,
        DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) AS RecencyGun,
        CASE
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 90
                 AND COUNT(DISTINCT so.salesOrderID) >= 5 THEN N'VIP'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 180 THEN N'Aktif'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 365 THEN N'Pasif'
            ELSE N'Kayip Risk'
        END                                 AS MusteriSegment
    FROM dbo.BusinessPartner bp
    JOIN dbo.SalesOrder so ON so.customerPartnerID = bp.partnerID
    LEFT JOIN dbo.Sube s   ON bp.subeID = s.subeID
    WHERE so.status != 'CANCELLED'
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
    GROUP BY bp.partnerID, bp.partnerName, s.subeKodu
    HAVING (@segment IS NULL OR
        CASE
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 90
                 AND COUNT(DISTINCT so.salesOrderID) >= 5 THEN N'VIP'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 180 THEN N'Aktif'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 365 THEN N'Pasif'
            ELSE N'Kayip Risk'
        END = @segment)
);
GO

-- ── TVF 6: Üretim Performans Raporu ──────────────────────────
CREATE OR ALTER FUNCTION dbo.fn_UretimPerformans (
    @baslangic DATE,
    @bitis     DATE,
    @subeKodu  NVARCHAR(20) = NULL
)
RETURNS TABLE AS RETURN (
    SELECT
        prod.orderNumber                    AS EmirNo,
        CAST(prod.startDate AS DATE)        AS BaslangicTarihi,
        CAST(prod.endDate AS DATE)          AS BitisTarihi,
        DATEDIFF(DAY, prod.startDate, prod.endDate) AS UretimSuresiGun,
        YEAR(prod.startDate)                AS Yil,
        MONTH(prod.startDate)               AS Ay,
        prod.status                         AS Durum,
        s.subeKodu,
        s.subeAdi                           AS Sube,
        p.productName                       AS UrunAdi,
        pc.categoryName                     AS Kategori,
        prod.plannedQuantity                AS PlanlananMiktar,
        prod.producedQuantity               AS UretilenMiktar,
        prod.plannedQuantity - prod.producedQuantity AS Sapma,
        CASE WHEN prod.plannedQuantity > 0
             THEN ROUND(100.0 * prod.producedQuantity / prod.plannedQuantity, 1)
             ELSE 0 END                     AS GerceklesmeOrani
    FROM dbo.ProductionOrder prod
    JOIN dbo.Sube s     ON prod.subeID = s.subeID
    JOIN dbo.Product p  ON prod.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE prod.startDate IS NOT NULL
      AND CAST(prod.startDate AS DATE) BETWEEN @baslangic AND @bitis
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
);
GO

PRINT '6 TVF olusturuldu/guncellendi.';
GO

-- ============================================================
-- BÖLÜM 2: STORED PROCEDURES (SP)
-- SSMS / uygulama tarafından çağrılır
-- OPTION(RECOMPILE) → parameter sniffing önlenir
-- ============================================================

-- ── SP 1: Satış Raporu ────────────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_SatisRaporu
    @baslangic DATE,
    @bitis     DATE,
    @subeKodu  NVARCHAR(20)  = NULL,
    @kategori  NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        so.orderNumber                      AS SiparisNo,
        CAST(so.orderDate AS DATE)          AS SiparisTarihi,
        YEAR(so.orderDate)                  AS Yil,
        MONTH(so.orderDate)                 AS Ay,
        s.subeKodu,
        s.subeAdi                           AS Sube,
        bp.partnerName                      AS Musteri,
        p.productName                       AS UrunAdi,
        pc.categoryName                     AS Kategori,
        soi.quantity                        AS Miktar,
        soi.unitPrice                       AS BirimFiyat,
        soi.totalPrice                      AS KalemTutar,
        so.totalAmount                      AS SiparisToplam,
        so.status                           AS Durum
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s             ON so.subeID = s.subeID
    JOIN dbo.BusinessPartner bp ON so.customerPartnerID = bp.partnerID
    JOIN dbo.SalesOrderItem soi ON so.salesOrderID = soi.salesOrderID
    JOIN dbo.Product p          ON soi.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE CAST(so.orderDate AS DATE) BETWEEN @baslangic AND @bitis
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND (@kategori IS NULL OR pc.categoryName = @kategori)
      AND so.status != 'CANCELLED'
    ORDER BY so.orderDate DESC
    OPTION (RECOMPILE);
END;
GO

-- ── SP 2: Dönem Karşılaştırma ─────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_DonemKarsilastirma
    @yil1     INT,
    @yil2     INT,
    @subeKodu NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        MONTH(so.orderDate)                 AS Ay,
        DATENAME(MONTH, so.orderDate)       AS AyAdi,
        s.subeKodu,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END) AS Donem1Tutar,
        SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) AS Donem2Tutar,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil1 THEN 1 END)                   AS Donem1Siparis,
        COUNT(CASE WHEN YEAR(so.orderDate)=@yil2 THEN 1 END)                   AS Donem2Siparis,
        ROUND(100.0 *
            (SUM(CASE WHEN YEAR(so.orderDate)=@yil2 THEN so.totalAmount ELSE 0 END) -
             SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END)) /
            NULLIF(SUM(CASE WHEN YEAR(so.orderDate)=@yil1 THEN so.totalAmount ELSE 0 END),0)
        , 1)                                AS BuyumeOrani
    FROM dbo.SalesOrder so
    JOIN dbo.Sube s ON so.subeID = s.subeID
    WHERE YEAR(so.orderDate) IN (@yil1, @yil2)
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND so.status != 'CANCELLED'
    GROUP BY MONTH(so.orderDate), DATENAME(MONTH, so.orderDate), s.subeKodu
    ORDER BY Ay
    OPTION (RECOMPILE);
END;
GO

-- ── SP 3: Tedarikçi Teslim Analizi ───────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_TedarikciTeslimAnalizi
    @yil      INT,
    @subeKodu NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        bp.partnerName                      AS Tedarikci,
        s.subeKodu,
        COUNT(po.purchaseOrderID)           AS ToplamSiparis,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.orderDate, gr_min.minRec) AS FLOAT)),1)           AS OrtTeslimGun,
        ROUND(AVG(CAST(DATEDIFF(DAY, po.expectedDeliveryDate, gr_min.minRec) AS FLOAT)),1) AS OrtGecikmeGun,
        SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)  AS TamamlananSiparis,
        ROUND(100.0 * SUM(CASE WHEN po.status='RECEIVED' THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*),0), 1)      AS ZamanindaTeslimOrani
    FROM dbo.PurchaseOrder po
    JOIN dbo.BusinessPartner bp ON po.supplierPartnerID = bp.partnerID
    JOIN dbo.Sube s             ON po.subeID = s.subeID
    LEFT JOIN (
        SELECT purchaseOrderID, MIN(receiptDate) AS minRec
        FROM dbo.GoodsReceipt GROUP BY purchaseOrderID
    ) gr_min ON gr_min.purchaseOrderID = po.purchaseOrderID
    WHERE YEAR(po.orderDate) = @yil
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND po.status != 'CANCELLED'
    GROUP BY bp.partnerName, s.subeKodu
    ORDER BY OrtTeslimGun
    OPTION (RECOMPILE);
END;
GO

-- ── SP 4: Stok Durum Raporu ───────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_StokDurumRaporu
    @subeKodu    NVARCHAR(20)  = NULL,
    @kategori    NVARCHAR(100) = NULL,
    @sadeceDusuk BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        s.subeKodu,
        s.subeAdi                           AS Sube,
        w.warehouseName                     AS Depo,
        p.productName                       AS UrunAdi,
        p.SKU,
        pc.categoryName                     AS Kategori,
        ISNULL(ib.onHandQty,0)              AS EldeKi,
        ISNULL(ib.reservedQty,0)            AS Rezerveli,
        ISNULL(ib.onHandQty,0) - ISNULL(ib.reservedQty,0) AS Kullanilabilir,
        p.minStockLevel                     AS MinStokSeviyesi,
        CASE
            WHEN ISNULL(ib.onHandQty,0) <= 0               THEN N'Stok Yok'
            WHEN ISNULL(ib.onHandQty,0) <= p.minStockLevel THEN N'Kritik'
            WHEN ISNULL(ib.onHandQty,0) <= p.minStockLevel * 1.5 THEN N'Dusuk'
            ELSE N'Normal'
        END                                 AS StokDurumu,
        ib.updatedAt                        AS SonGuncelleme
    FROM dbo.InventoryBalance ib
    JOIN dbo.Warehouse w        ON ib.warehouseID = w.warehouseID
    JOIN dbo.Sube s             ON w.subeID = s.subeID
    JOIN dbo.Product p          ON ib.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
      AND (@kategori IS NULL OR pc.categoryName = @kategori)
      AND (@sadeceDusuk = 0
           OR ISNULL(ib.onHandQty,0) <= p.minStockLevel * 1.5)
    ORDER BY EldeKi ASC
    OPTION (RECOMPILE);
END;
GO

-- ── SP 5: Müşteri RFM Analizi ─────────────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_MusteriRFM
    @subeKodu NVARCHAR(20) = NULL,
    @segment  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        bp.partnerID                        AS MusteriID,
        bp.partnerName                      AS Musteri,
        s.subeKodu,
        COUNT(DISTINCT so.salesOrderID)     AS ToplamSiparis,
        SUM(so.totalAmount)                 AS ToplamCiro,
        AVG(so.totalAmount)                 AS OrtSiparisTutari,
        MIN(CAST(so.orderDate AS DATE))     AS IlkSiparis,
        MAX(CAST(so.orderDate AS DATE))     AS SonSiparis,
        DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) AS RecencyGun,
        CASE
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 90
                 AND COUNT(DISTINCT so.salesOrderID) >= 5 THEN N'VIP'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 180 THEN N'Aktif'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 365 THEN N'Pasif'
            ELSE N'Kayip Risk'
        END                                 AS MusteriSegment
    FROM dbo.BusinessPartner bp
    JOIN dbo.SalesOrder so ON so.customerPartnerID = bp.partnerID
    LEFT JOIN dbo.Sube s   ON bp.subeID = s.subeID
    WHERE so.status != 'CANCELLED'
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
    GROUP BY bp.partnerID, bp.partnerName, s.subeKodu
    HAVING (@segment IS NULL OR
        CASE
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 90
                 AND COUNT(DISTINCT so.salesOrderID) >= 5 THEN N'VIP'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 180 THEN N'Aktif'
            WHEN DATEDIFF(DAY, MAX(so.orderDate), GETDATE()) <= 365 THEN N'Pasif'
            ELSE N'Kayip Risk'
        END = @segment)
    ORDER BY ToplamCiro DESC
    OPTION (RECOMPILE);
END;
GO

-- ── SP 6: Üretim Performans Raporu ───────────────────────────
CREATE OR ALTER PROCEDURE dbo.sp_UretimPerformans
    @baslangic DATE,
    @bitis     DATE,
    @subeKodu  NVARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT
        prod.orderNumber                    AS EmirNo,
        CAST(prod.startDate AS DATE)        AS BaslangicTarihi,
        CAST(prod.endDate AS DATE)          AS BitisTarihi,
        DATEDIFF(DAY, prod.startDate, prod.endDate) AS UretimSuresiGun,
        YEAR(prod.startDate)                AS Yil,
        MONTH(prod.startDate)               AS Ay,
        prod.status                         AS Durum,
        s.subeKodu,
        s.subeAdi                           AS Sube,
        p.productName                       AS UrunAdi,
        pc.categoryName                     AS Kategori,
        prod.plannedQuantity                AS PlanlananMiktar,
        prod.producedQuantity               AS UretilenMiktar,
        prod.plannedQuantity - prod.producedQuantity AS Sapma,
        CASE WHEN prod.plannedQuantity > 0
             THEN ROUND(100.0 * prod.producedQuantity / prod.plannedQuantity, 1)
             ELSE 0 END                     AS GerceklesmeOrani
    FROM dbo.ProductionOrder prod
    JOIN dbo.Sube s     ON prod.subeID = s.subeID
    JOIN dbo.Product p  ON prod.productID = p.productID
    JOIN dbo.ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE prod.startDate IS NOT NULL
      AND CAST(prod.startDate AS DATE) BETWEEN @baslangic AND @bitis
      AND (@subeKodu IS NULL OR s.subeKodu = @subeKodu)
    ORDER BY GerceklesmeOrani ASC
    OPTION (RECOMPILE);
END;
GO

PRINT '6 SP olusturuldu/guncellendi.';
GO

-- ============================================================
-- KULLANIM ÖRNEKLERİ
-- ============================================================

-- TVF örnekleri (Power BI veya SSMS):
-- SELECT * FROM fn_SatisRaporu('2024-01-01', '2024-12-31', 'IST-001', NULL)
-- SELECT * FROM fn_SatisRaporu('2024-01-01', '2024-12-31', NULL, 'Elektronik')
-- SELECT * FROM fn_DonemKarsilastirma(2023, 2024, NULL)
-- SELECT * FROM fn_TedarikciTeslimAnalizi(2024, 'ANK-001')
-- SELECT * FROM fn_StokDurumRaporu(NULL, NULL, 1)   -- sadece kritik/düşük stoklar
-- SELECT * FROM fn_MusteriRFM(NULL, 'VIP')           -- tüm şubelerin VIP müşterileri
-- SELECT * FROM fn_UretimPerformans('2024-01-01', '2024-12-31', NULL)

-- SP örnekleri (SSMS):
-- EXEC sp_SatisRaporu '2024-01-01', '2024-12-31', 'IST-001'
-- EXEC sp_SatisRaporu '2024-01-01', '2024-12-31'              -- tüm şubeler
-- EXEC sp_DonemKarsilastirma 2023, 2024
-- EXEC sp_TedarikciTeslimAnalizi 2024, 'ANK-001'
-- EXEC sp_StokDurumRaporu NULL, NULL, 1                        -- kritik stoklar
-- EXEC sp_MusteriRFM NULL, 'VIP'
-- EXEC sp_UretimPerformans '2024-01-01', '2024-12-31', 'IZM-001'

-- ============================================================
-- ÖNERİLEN İNDEKSLER (performans için)
-- ============================================================

-- SELECT * FROM sys.indexes WHERE object_id = OBJECT_ID('SalesOrder')
-- ile mevcut indeksleri kontrol et, yoksa ekle:

-- CREATE INDEX IX_SO_OrderDate  ON dbo.SalesOrder(orderDate)  INCLUDE(subeID, status, totalAmount, customerPartnerID);
-- CREATE INDEX IX_SO_SubeID     ON dbo.SalesOrder(subeID);
-- CREATE INDEX IX_PO_OrderDate  ON dbo.PurchaseOrder(orderDate) INCLUDE(subeID, status, totalAmount);
-- CREATE INDEX IX_ProdO_Start   ON dbo.ProductionOrder(startDate) INCLUDE(subeID, status, plannedQuantity, producedQuantity);
-- CREATE INDEX IX_IB_Warehouse  ON dbo.InventoryBalance(warehouseID) INCLUDE(productID, onHandQty, reservedQty);
