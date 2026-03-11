USE [SCM_3];
GO

SET NOCOUNT ON;

INSERT INTO dbo.Country (iso2, countryName)
SELECT v.iso2, v.countryName
FROM (VALUES
    ('TR','Türkiye'),
    ('US','United States'),
    ('DE','Germany'),
    ('FR','France'),
    ('GB','United Kingdom'),
    ('IT','Italy'),
    ('ES','Spain'),
    ('NL','Netherlands'),
    ('BE','Belgium'),
    ('CH','Switzerland'),
    ('SE','Sweden'),
    ('NO','Norway'),
    ('DK','Denmark'),
    ('PL','Poland'),
    ('RO','Romania'),
    ('BG','Bulgaria'),
    ('GR','Greece'),
    ('RU','Russia'),
    ('CN','China'),
    ('JP','Japan')
) AS v(iso2, countryName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Country c
    WHERE c.iso2 = v.iso2
       OR c.countryName = v.countryName
);

SELECT * FROM dbo.Country ORDER BY countryID;
GO