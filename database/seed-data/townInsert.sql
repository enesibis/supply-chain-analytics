USE [SCM_3];
GO
SET NOCOUNT ON;

-- Şehir ID'lerini al
DECLARE @IST int = (SELECT cityID FROM dbo.City WHERE cityName='İstanbul');
DECLARE @ANK int = (SELECT cityID FROM dbo.City WHERE cityName='Ankara');
DECLARE @IZM int = (SELECT cityID FROM dbo.City WHERE cityName='İzmir');
DECLARE @BUR int = (SELECT cityID FROM dbo.City WHERE cityName='Bursa');
DECLARE @ANT int = (SELECT cityID FROM dbo.City WHERE cityName='Antalya');

IF @IST IS NULL OR @ANK IS NULL OR @IZM IS NULL OR @BUR IS NULL OR @ANT IS NULL
BEGIN
    PRINT 'Bazı şehirler City tablosunda yok. Önce City verisini eklediğinden emin ol.';
END

;WITH data AS
(
    SELECT @IST AS cityID, v.townName
    FROM (VALUES
        ('Kadıköy'),('Beşiktaş'),('Şişli'),('Üsküdar'),('Bakırköy'),
        ('Fatih'),('Beylikdüzü'),('Pendik'),('Ataşehir'),('Sarıyer')
    ) v(townName)
    WHERE @IST IS NOT NULL

    UNION ALL
    SELECT @ANK, v.townName
    FROM (VALUES
        ('Çankaya'),('Keçiören'),('Yenimahalle'),('Mamak'),('Etimesgut'),
        ('Sincan'),('Altındağ'),('Gölbaşı'),('Pursaklar')
    ) v(townName)
    WHERE @ANK IS NOT NULL

    UNION ALL
    SELECT @IZM, v.townName
    FROM (VALUES
        ('Konak'),('Karşıyaka'),('Bornova'),('Buca'),('Bayraklı'),
        ('Gaziemir'),('Balçova'),('Çiğli'),('Menemen')
    ) v(townName)
    WHERE @IZM IS NOT NULL

    UNION ALL
    SELECT @BUR, v.townName
    FROM (VALUES
        ('Osmangazi'),('Nilüfer'),('Yıldırım'),('İnegöl'),('Gemlik'),
        ('Mudanya')
    ) v(townName)
    WHERE @BUR IS NOT NULL

    UNION ALL
    SELECT @ANT, v.townName
    FROM (VALUES
        ('Muratpaşa'),('Kepez'),('Konyaaltı'),('Alanya'),('Manavgat'),
        ('Kemer'),('Serik')
    ) v(townName)
    WHERE @ANT IS NOT NULL
)
INSERT INTO dbo.Town (cityID, townName)
SELECT d.cityID, d.townName
FROM data d
WHERE NOT EXISTS
(
    SELECT 1
    FROM dbo.Town t
    WHERE t.cityID = d.cityID
      AND t.townName = d.townName
);

-- Kontrol: Eklenenleri göster
SELECT c.cityName, t.townID, t.townName
FROM dbo.Town t
JOIN dbo.City c ON c.cityID = t.cityID
WHERE c.cityName IN ('İstanbul','Ankara','İzmir','Bursa','Antalya')
ORDER BY c.cityName, t.townName;
GO