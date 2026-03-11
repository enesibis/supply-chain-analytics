USE [SCM_3];
GO
SET NOCOUNT ON;

INSERT INTO dbo.Unit (unitCode, unitName)
SELECT v.unitCode, v.unitName
FROM (VALUES
    ('EA',  'Adet'),
    ('PCS', 'Parça'),
    ('SET', 'Set'),
    ('BOX', 'Kutu'),
    ('PK',  'Paket'),
    ('PAL', 'Palet'),

    ('KG',  'Kilogram'),
    ('G',   'Gram'),
    ('TON', 'Ton'),

    ('M',   'Metre'),
    ('CM',  'Santimetre'),
    ('MM',  'Milimetre'),

    ('M2',  'Metrekare'),
    ('M3',  'Metreküp'),

    ('L',   'Litre'),
    ('ML',  'Mililitre'),

    ('HR',  'Saat'),
    ('DAY', 'Gün')
) AS v(unitCode, unitName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Unit u
    WHERE u.unitCode = v.unitCode
);

SELECT * FROM dbo.Unit ORDER BY unitID;
GO