USE [SCM_3];
GO
SET NOCOUNT ON;

-- TownID'leri bul (şehir + ilçe adına göre)
DECLARE @Kadikoy   int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='İstanbul' AND t.townName='Kadıköy');
DECLARE @Besiktas  int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='İstanbul' AND t.townName='Beşiktaş');
DECLARE @Cankaya   int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='Ankara'  AND t.townName='Çankaya');
DECLARE @Konak     int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='İzmir'   AND t.townName='Konak');
DECLARE @Nilufer   int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='Bursa'   AND t.townName='Nilüfer');
DECLARE @Muratpasa int = (SELECT t.townID FROM dbo.Town t JOIN dbo.City c ON c.cityID=t.cityID WHERE c.cityName='Antalya' AND t.townName='Muratpaşa');

IF @Kadikoy IS NULL OR @Besiktas IS NULL OR @Cankaya IS NULL OR @Konak IS NULL OR @Nilufer IS NULL OR @Muratpasa IS NULL
BEGIN
    PRINT 'Bazı Town kayıtları yok. Önce Town tablosuna ilgili ilçe kayıtlarını eklediğinden emin ol.';
END

;WITH data AS
(
    SELECT @Kadikoy AS townID, v.districtName
    FROM (VALUES
        ('Moda'),('Fenerbahçe'),('Erenköy'),('Bostancı'),('Göztepe'),('Kozyatağı')
    ) v(districtName)
    WHERE @Kadikoy IS NOT NULL

    UNION ALL
    SELECT @Besiktas, v.districtName
    FROM (VALUES
        ('Levent'),('Etiler'),('Ortaköy'),('Bebek'),('Arnavutköy'),('Gayrettepe')
    ) v(districtName)
    WHERE @Besiktas IS NOT NULL

    UNION ALL
    SELECT @Cankaya, v.districtName
    FROM (VALUES
        ('Kızılay'),('Bahçelievler'),('Ayrancı'),('Balgat'),('Çayyolu'),('Ümitköy')
    ) v(districtName)
    WHERE @Cankaya IS NOT NULL

    UNION ALL
    SELECT @Konak, v.districtName
    FROM (VALUES
        ('Alsancak'),('Göztepe'),('Güzelyalı'),('Kahramanlar'),('Eşrefpaşa')
    ) v(districtName)
    WHERE @Konak IS NOT NULL

    UNION ALL
    SELECT @Nilufer, v.districtName
    FROM (VALUES
        ('Görükle'),('Özlüce'),('Balat'),('İhsaniye'),('Beşevler')
    ) v(districtName)
    WHERE @Nilufer IS NOT NULL

    UNION ALL
    SELECT @Muratpasa, v.districtName
    FROM (VALUES
        ('Lara'),('Fener'),('Güzeloba'),('Meltem'),('Şirinyalı')
    ) v(districtName)
    WHERE @Muratpasa IS NOT NULL
)
INSERT INTO dbo.District (townID, districtName)
SELECT d.townID, d.districtName
FROM data d
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.District x
    WHERE x.townID = d.townID
      AND x.districtName = d.districtName
);

-- Kontrol
SELECT c.cityName, t.townName, d.districtID, d.districtName
FROM dbo.District d
JOIN dbo.Town t ON t.townID = d.townID
JOIN dbo.City c ON c.cityID = t.cityID
WHERE (c.cityName='İstanbul' AND t.townName IN ('Kadıköy','Beşiktaş'))
   OR (c.cityName='Ankara'  AND t.townName='Çankaya')
   OR (c.cityName='İzmir'   AND t.townName='Konak')
   OR (c.cityName='Bursa'   AND t.townName='Nilüfer')
   OR (c.cityName='Antalya' AND t.townName='Muratpaşa')
ORDER BY c.cityName, t.townName, d.districtName;
GO