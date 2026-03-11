USE [SCM_3];
GO
SET NOCOUNT ON;

-- DistrictID'leri bul (City + Town + District ile netleştiriyoruz)
DECLARE @Moda int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='İstanbul' AND t.townName='Kadıköy' AND d.districtName='Moda'
);

DECLARE @Levent int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='İstanbul' AND t.townName='Beşiktaş' AND d.districtName='Levent'
);

DECLARE @Kizilay int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='Ankara' AND t.townName='Çankaya' AND d.districtName='Kızılay'
);

DECLARE @Alsancak int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='İzmir' AND t.townName='Konak' AND d.districtName='Alsancak'
);

DECLARE @Gorukle int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='Bursa' AND t.townName='Nilüfer' AND d.districtName='Görükle'
);

DECLARE @Lara int =
(
    SELECT d.districtID
    FROM dbo.District d
    JOIN dbo.Town t ON t.townID = d.townID
    JOIN dbo.City c ON c.cityID = t.cityID
    WHERE c.cityName='Antalya' AND t.townName='Muratpaşa' AND d.districtName='Lara'
);

-- Eğer bazı district yoksa uyar
IF @Moda IS NULL OR @Levent IS NULL OR @Kizilay IS NULL OR @Alsancak IS NULL OR @Gorukle IS NULL OR @Lara IS NULL
BEGIN
    PRINT 'Bazı District kayıtları yok. Önce District tablosunu doldurduğundan emin ol.';
END

-- Address insert (districtID NULL olabilir ama biz dolu giriyoruz)
INSERT INTO dbo.Address (districtID, postalCode, addressLine1, addressLine2)
SELECT v.districtID, v.postalCode, v.addressLine1, v.addressLine2
FROM (VALUES
    (@Moda,    '34710', 'Caferağa Mah. Moda Cd. No:10',        'Daire 3'),
    (@Levent,  '34330', 'Levent Mah. Büyükdere Cd. No:100',    'Kat 5'),
    (@Kizilay, '06420', 'Kızılay Mah. Atatürk Blv. No:25',     'Ofis 12'),
    (@Alsancak,'35220', 'Alsancak Mah. Kıbrıs Şehitleri Cd. 45','Daire 8'),
    (@Gorukle, '16285', 'Görükle Mah. Üniversite Cd. No:7',    NULL),
    (@Lara,    '07230', 'Lara Mah. Tekelioğlu Cd. No:18',      'Blok B')
) v(districtID, postalCode, addressLine1, addressLine2)
WHERE v.districtID IS NOT NULL; -- district bulunamadıysa ekleme

-- Kontrol: son eklenen adresler
SELECT TOP (50)
    a.addressID, a.createdAt, a.postalCode, a.addressLine1, a.addressLine2,
    c.cityName, t.townName, d.districtName
FROM dbo.Address a
LEFT JOIN dbo.District d ON d.districtID = a.districtID
LEFT JOIN dbo.Town t ON t.townID = d.townID
LEFT JOIN dbo.City c ON c.cityID = t.cityID
ORDER BY a.addressID DESC;
GO