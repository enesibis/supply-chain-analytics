USE [SCM_3];
GO
SET NOCOUNT ON;

INSERT INTO dbo.Warehouse (warehouseCode, warehouseName)
SELECT v.warehouseCode, v.warehouseName
FROM (VALUES
    ('MAIN', 'Ana Depo'),
    ('RAW',  'Hammadde Deposu'),
    ('FG',   'Mamul Deposu'),
    ('WIP',  'Yarı Mamul (WIP) Deposu'),
    ('QC',   'Kalite Kontrol Alanı'),
    ('RET',  'İade / Karantina Deposu')
) v(warehouseCode, warehouseName)
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Warehouse w
    WHERE w.warehouseCode = v.warehouseCode
);

SELECT * FROM dbo.Warehouse ORDER BY warehouseID;
GO