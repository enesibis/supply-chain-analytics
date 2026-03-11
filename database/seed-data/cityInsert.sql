USE [SCM_3];
GO
SET NOCOUNT ON;

DECLARE @TR smallint = (SELECT countryID FROM dbo.Country WHERE iso2 = 'TR');

IF @TR IS NULL
BEGIN
    RAISERROR('Country tablosunda TR yok. Önce dbo.Country içine TR ekle.', 16, 1);
    RETURN;
END

INSERT INTO dbo.City (countryID, cityName)
SELECT @TR, v.cityName
FROM (VALUES
    ('İstanbul'),
    ('Ankara'),
    ('İzmir'),
    ('Bursa'),
    ('Antalya'),
    ('Adana'),
    ('Konya'),
    ('Gaziantep'),
    ('Kayseri'),
    ('Mersin'),
    ('Kocaeli'),
    ('Eskişehir'),
    ('Diyarbakır'),
    ('Samsun'),
    ('Trabzon')
) AS v(cityName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.City c
    WHERE c.countryID = @TR
      AND c.cityName = v.cityName
);

SELECT * FROM dbo.City WHERE countryID = @TR ORDER BY cityID;
GO