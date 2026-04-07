"""
SCM_3 - Veri Eksikligi Giderme
Tespit edilen 6 eksiklik sistematik olarak duzeltilir:
  1. DimTarih 2022-2023 eklenir
  2. 2025-2026 test verisi temizlenir
  3. ProductionOrder NULL startDate duzeltilir
  4. BusinessPartnerAddress eksikleri tamamlanir
  5. InventoryBalance tum urun-depo kombinasyonlari tamamlanir
  6. 2024 satislari tum urunlere yayilir (14 urun eksikti)
"""

import pyodbc
import random
import numpy as np
from datetime import datetime, timedelta, date

CONN_STR = (
    "DRIVER={SQL Server};"
    "SERVER=ENES\\SQLEXPRESS;"
    "DATABASE=SCM_3;"
    "Trusted_Connection=yes;"
)
conn = pyodbc.connect(CONN_STR)
conn.autocommit = False
cursor = conn.cursor()
random.seed(99)
np.random.seed(99)

print("=" * 65)
print("SCM_3 - VERİ EKSİKLİĞİ GİDERME")
print("=" * 65)

# ── YARDIMCI ─────────────────────────────────────────────────────────────────
def q(sql, *args):
    cursor.execute(sql, *args) if args else cursor.execute(sql)
    return cursor.fetchall()

def get_id(sql, *args):
    cursor.execute(sql, *args) if args else cursor.execute(sql)
    return cursor.fetchone()[0]

def rand_date(year, month, day_lo=1, day_hi=28):
    return datetime(year, month, random.randint(day_lo, day_hi))

# ── 1. DimTarih: 2022-2023 EKLE ──────────────────────────────────────────────
print("\n[1] DimTarih — 2022-2023 gunleri ekleniyor...")

existing = get_id("SELECT COUNT(*) FROM DimTarih WHERE tarih < '2024-01-01'")
if existing > 0:
    print(f"    Zaten {existing} kayit var, atlanıyor.")
else:
    TR_AYLAR = {1:'Ocak',2:'Subat',3:'Mart',4:'Nisan',5:'Mayis',6:'Haziran',
                7:'Temmuz',8:'Agustos',9:'Eylul',10:'Ekim',11:'Kasim',12:'Aralik'}
    TR_GUNLER = {0:'Pazartesi',1:'Sali',2:'Carsamba',3:'Persembe',4:'Cuma',5:'Cumartesi',6:'Pazar'}

    rows = []
    dt = date(2022, 1, 1)
    end = date(2024, 1, 1)
    while dt < end:
        rows.append((
            int(dt.strftime('%Y%m%d')),
            dt.strftime('%Y-%m-%d'),     # string olarak gonder
            dt.year,
            (dt.month - 1) // 3 + 1,
            dt.month,
            TR_AYLAR[dt.month],
            dt.isocalendar()[1],
            dt.weekday() + 1,
            TR_GUNLER[dt.weekday()],
            1 if dt.weekday() < 5 else 0
        ))
        dt += timedelta(days=1)

    cursor.executemany("""
        INSERT INTO DimTarih (tarihID,tarih,yil,ceyrek,ay,ayAdi,hafta,gun,gunAdi,isHaftaici)
        VALUES (?,?,?,?,?,?,?,?,?,?)
    """, rows)
    conn.commit()
    print(f"    {len(rows)} gun eklendi (2022-01-01 .. 2023-12-31)")

# ── 2. 2025-2026 TEST VERİSİNİ TEMİZLE ───────────────────────────────────────
print("\n[2] 2025-2026 test verisi temizleniyor...")

cursor.execute("DISABLE TRIGGER TR_StockMovement_UpdateInventoryBalance ON StockMovement")

cursor.execute("""DELETE si FROM ShipmentItem si
    JOIN Shipment sh ON si.shipmentID=sh.shipmentID
    WHERE YEAR(sh.shipmentDate) IN (2025,2026)""")
print(f"    ShipmentItem(shipmentDate): {cursor.rowcount} silindi")

cursor.execute("""DELETE si FROM ShipmentItem si
    JOIN Shipment sh ON si.shipmentID=sh.shipmentID
    JOIN SalesOrder so ON sh.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2025,2026)""")
print(f"    ShipmentItem(orderDate): {cursor.rowcount} silindi")

cursor.execute("DELETE FROM Shipment WHERE YEAR(shipmentDate) IN (2025,2026)")
print(f"    Shipment(shipmentDate): {cursor.rowcount} silindi")

cursor.execute("""DELETE sh FROM Shipment sh
    JOIN SalesOrder so ON sh.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2025,2026)""")
print(f"    Shipment(orderDate): {cursor.rowcount} silindi")

cursor.execute("""DELETE gri FROM GoodsReceiptItem gri
    JOIN GoodsReceipt gr ON gri.goodsReceiptID=gr.goodsReceiptID
    WHERE YEAR(gr.receiptDate) IN (2025,2026)""")
print(f"    GoodsReceiptItem: {cursor.rowcount} silindi")
cursor.execute("DELETE FROM GoodsReceipt WHERE YEAR(receiptDate) IN (2025,2026)")
print(f"    GoodsReceipt: {cursor.rowcount} silindi")

cursor.execute("""DELETE soi FROM SalesOrderItem soi
    JOIN SalesOrder so ON soi.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2025,2026)""")
print(f"    SalesOrderItem: {cursor.rowcount} silindi")
cursor.execute("DELETE FROM SalesOrder WHERE YEAR(orderDate) IN (2025,2026)")
print(f"    SalesOrder: {cursor.rowcount} silindi")

cursor.execute("""DELETE poi FROM PurchaseOrderItem poi
    JOIN PurchaseOrder po ON poi.purchaseOrderID=po.purchaseOrderID
    WHERE YEAR(po.orderDate) IN (2025,2026)""")
print(f"    PurchaseOrderItem: {cursor.rowcount} silindi")
cursor.execute("DELETE FROM PurchaseOrder WHERE YEAR(orderDate) IN (2025,2026)")
print(f"    PurchaseOrder: {cursor.rowcount} silindi")

cursor.execute("""DELETE pc FROM ProductionConsumption pc
    JOIN ProductionOrder po ON pc.productionOrderID=po.productionOrderID
    WHERE YEAR(po.startDate) IN (2025,2026)""")
cursor.execute("""DELETE po2 FROM ProductionOutput po2
    JOIN ProductionOrder po ON po2.productionOrderID=po.productionOrderID
    WHERE YEAR(po.startDate) IN (2025,2026)""")
cursor.execute("DELETE FROM ProductionOrder WHERE YEAR(startDate) IN (2025,2026)")
print(f"    ProductionOrder (2025-2026): {cursor.rowcount} silindi")

cursor.execute("DELETE FROM StockMovement WHERE YEAR(movementDate) IN (2025,2026)")
print(f"    StockMovement: {cursor.rowcount} silindi")

conn.commit()

# ── 3. NULL startDate DUZELT ──────────────────────────────────────────────────
print("\n[3] ProductionOrder NULL startDate duzeltiliyor...")
cursor.execute("SELECT COUNT(*) FROM ProductionOrder WHERE startDate IS NULL")
cnt = cursor.fetchone()[0]
if cnt > 0:
    cursor.execute("""
        UPDATE ProductionOrder
        SET startDate = '2024-01-15', endDate = '2024-01-29', updatedAt = GETDATE()
        WHERE startDate IS NULL
    """)
    conn.commit()
    print(f"    {cursor.rowcount} kayit duzeltildi (startDate=2024-01-15)")
else:
    print("    NULL kayit yok, atlanıyor.")

# ── 4. BusinessPartnerAddress EKSİKLERİ ──────────────────────────────────────
print("\n[4] BusinessPartnerAddress eksikleri tamamlaniyor...")

# Eksik adres olan partner'lari bul
missing_addr = q("""
    SELECT bp.partnerID, bp.partnerName, bpr.roleType
    FROM BusinessPartner bp
    JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
    WHERE bp.partnerID NOT IN (SELECT DISTINCT partnerID FROM BusinessPartnerAddress)
    GROUP BY bp.partnerID, bp.partnerName, bpr.roleType
    ORDER BY bpr.roleType, bp.partnerName
""")
print(f"    Adres eksik {len(missing_addr)} partner bulundu")

# Mevcut adreslerden birini baz al (districtID referansi icin)
districts = q("SELECT districtID FROM District ORDER BY districtID")
district_ids = [r[0] for r in districts]

# Adres tipleri: musteri ve tedarikci HQ, tasiyici SHIPPING
for partner_id, partner_name, role_type in missing_addr:
    # Bu partner icin Address ekle
    district_id = random.choice(district_ids)
    cursor.execute("""
        INSERT INTO Address (districtID, postalCode, addressLine1, addressLine2, createdAt)
        VALUES (?, ?, ?, NULL, GETDATE())
    """, (district_id,
          f"{random.randint(10000,99999)}",
          f"{partner_name[:20]} Cad. No:{random.randint(1,200)}"))
    cursor.execute("SELECT @@IDENTITY")
    addr_id = int(cursor.fetchone()[0])

    addr_type = 'HQ' if role_type in ('CUSTOMER','SUPPLIER') else 'SHIPPING'
    cursor.execute("""
        INSERT INTO BusinessPartnerAddress (partnerID, addressID, addressType, isPrimary, createdAt)
        VALUES (?, ?, ?, 1, GETDATE())
    """, (partner_id, addr_id, addr_type))
    print(f"    + {partner_name:<35} ({role_type}) -> {addr_type}")

conn.commit()

# ── 5. InventoryBalance: TUM KOMBINASYONLARI TAMAMLA ─────────────────────────
print("\n[5] InventoryBalance tum urun-depo kombinasyonlari tamamlaniyor...")

products = q("SELECT productID FROM Product WHERE isActive=1")
warehouses = q("SELECT warehouseID FROM Warehouse WHERE isActive=1")

added = 0
for (prod_id,) in products:
    for (wh_id,) in warehouses:
        cursor.execute("""
            SELECT COUNT(*) FROM InventoryBalance
            WHERE productID=? AND warehouseID=?
        """, (prod_id, wh_id))
        if cursor.fetchone()[0] == 0:
            # Makul bir stok miktari ata
            on_hand = random.randint(0, 50)
            cursor.execute("""
                INSERT INTO InventoryBalance (warehouseID, productID, onHandQty, reservedQty, updatedAt)
                VALUES (?, ?, ?, 0, GETDATE())
            """, (wh_id, prod_id, on_hand))
            added += 1

conn.commit()
print(f"    {added} yeni InventoryBalance kaydi eklendi")
cursor.execute("SELECT COUNT(*) FROM InventoryBalance")
print(f"    Toplam: {cursor.fetchone()[0]} / 102 kombinasyon")

# ── 6. 2024 SATIŞ EKSİKLERİNİ TAMAMLA ───────────────────────────────────────
print("\n[6] 2024 satislari — 14 eksik urun icin veri uretiliyor...")

# Referans veriler
subes      = q("SELECT subeID, subeKodu FROM Sube WHERE isActive=1")
sube_wh    = {sid: None for sid, _ in subes}
for wh_id, sube_id in q("SELECT warehouseID, subeID FROM Warehouse WHERE isActive=1"):
    if sube_id and sube_id in sube_wh and sube_wh[sube_id] is None:
        sube_wh[sube_id] = wh_id

customers  = [r[0] for r in q("""
    SELECT bp.partnerID FROM BusinessPartner bp
    JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
    WHERE bpr.roleType='CUSTOMER' AND bpr.isActive=1""")]
carriers   = [r[0] for r in q("""
    SELECT bp.partnerID FROM BusinessPartner bp
    JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
    WHERE bpr.roleType='CARRIER' AND bpr.isActive=1""")]

SUBE_W = {'IST-001':1.40,'ANK-001':1.10,'IZM-001':1.00,'BRS-001':0.75}
SEASON = {1:0.70,2:0.65,3:0.85,4:0.90,5:1.00,6:1.05,
          7:0.95,8:1.00,9:1.10,10:1.15,11:1.30,12:1.25}

# Eksik urunleri bul
missing_products = q("""
    SELECT p.productID, p.productName
    FROM Product p
    WHERE p.isActive=1
      AND p.productID NOT IN (
        SELECT DISTINCT soi.productID
        FROM SalesOrder so
        JOIN SalesOrderItem soi ON so.salesOrderID=soi.salesOrderID
        WHERE YEAR(so.orderDate)=2024
      )
""")
print(f"    {len(missing_products)} eksik urun bulundu")

# Urun bazli fiyat araligı (kategoriye gore)
cat_prices = {r[0]:r[1] for r in q("""
    SELECT p.productID,
        CASE pc.categoryName
            WHEN 'Baglanti Elemanlari' THEN 150.0
            WHEN 'Metal' THEN 800.0
            WHEN 'Plastik' THEN 200.0
            WHEN 'Ambalaj' THEN 100.0
            WHEN 'Boya' THEN 300.0
            WHEN 'Mamul' THEN 1200.0
            ELSE 250.0
        END
    FROM Product p
    JOIN ProductCategory pc ON p.categoryID=pc.categoryID
""")}

so_added = 0; soi_added = 0; sh_added = 0; shi_added = 0

for month in range(1, 13):
    season = SEASON[month]
    for sube_id, sube_kodu in subes:
        sube_w  = SUBE_W.get(sube_kodu, 1.0)
        wh_id   = sube_wh.get(sube_id)
        if not wh_id:
            continue

        # Her ay icin eksik urunlerden 2-4 tanesini sat
        n_products = random.randint(2, min(5, len(missing_products)))
        selected = random.sample(missing_products, n_products)

        for prod_id, prod_name in selected:
            order_date  = rand_date(2024, month)
            customer_id = random.choice(customers)
            status = random.choices(
                ['SHIPPED','PARTIALLY_SHIPPED','CANCELLED'],
                weights=[0.72, 0.18, 0.10])[0]

            cursor.execute("""
                INSERT INTO SalesOrder
                    (orderNumber,orderDate,customerPartnerID,status,totalAmount,subeID,createdAt)
                VALUES (?,?,?,?,0,?,?)
            """, (f"SO-2024-FIX-{so_added:04d}", order_date,
                  customer_id, status, sube_id, order_date))
            cursor.execute("SELECT @@IDENTITY")
            so_id = int(cursor.fetchone()[0])
            so_added += 1

            qty = max(2, int(np.random.exponential(4) + 2))
            base_price = float(cat_prices.get(prod_id, 250.0))
            unit_price = round(base_price * random.uniform(0.9, 1.1), 2)
            shipped = qty if status=='SHIPPED' else (qty//2 if status=='PARTIALLY_SHIPPED' else 0)

            cursor.execute("""
                INSERT INTO SalesOrderItem
                    (salesOrderID,lineNo_,productID,quantity,unitPrice,shippedQuantity)
                VALUES (?,1,?,?,?,?)
            """, (so_id, prod_id, qty, unit_price, shipped))
            cursor.execute("SELECT @@IDENTITY")
            soi_id = int(cursor.fetchone()[0])
            soi_added += 1

            cursor.execute("UPDATE SalesOrder SET totalAmount=? WHERE salesOrderID=?",
                           (round(qty * unit_price, 2), so_id))

            # Shipment
            if shipped > 0:
                ship_date = order_date + timedelta(days=random.randint(2,10))
                carrier_id = random.choice(carriers)
                cursor.execute("""
                    INSERT INTO Shipment
                        (salesOrderID,warehouseID,customerPartnerID,shipmentNumber,
                         shipmentDate,status,carrierPartnerID,createdAt)
                    VALUES (?,?,?,?,?,'POSTED',?,?)
                """, (so_id, wh_id, customer_id,
                      f"SH-2024-FIX-{sh_added:04d}",
                      ship_date, carrier_id, ship_date))
                cursor.execute("SELECT @@IDENTITY")
                sh_id = int(cursor.fetchone()[0])
                sh_added += 1

                cursor.execute("""
                    INSERT INTO ShipmentItem
                        (shipmentID,salesOrderItemID,lineNo_,productID,quantity)
                    VALUES (?,?,1,?,?)
                """, (sh_id, soi_id, prod_id, shipped))
                shi_added += 1

                # StockMovement
                cursor.execute("""
                    INSERT INTO StockMovement
                        (warehouseID,productID,movementType,qtyIn,qtyOut,
                         movementDate,refType,refID,createdAt)
                    VALUES (?,?,'SALES_SHIPMENT',0,?,?,?,?,?)
                """, (wh_id, prod_id, shipped, ship_date, 'Shipment', sh_id, ship_date))

    if month % 3 == 0:
        conn.commit()
        print(f"    {month}. ay tamamlandi...")

conn.commit()
print(f"    Eklendi: {so_added} SalesOrder | {soi_added} SalesOrderItem")
print(f"             {sh_added} Shipment | {shi_added} ShipmentItem")

# ── TETİKLEYİCİ YENİDEN AKTİF ──────────────────────────────────────────────
cursor.execute("ENABLE TRIGGER TR_StockMovement_UpdateInventoryBalance ON StockMovement")
conn.commit()

# ── FINAL DOĞRULAMA ──────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("FINAL DOĞRULAMA")
print("=" * 65)

print("\n  Tablo            2022    2023    2024   Toplam")
print("  " + "-" * 55)
for tablo, tarih in [
    ('SalesOrder','orderDate'),
    ('PurchaseOrder','orderDate'),
    ('ProductionOrder','startDate'),
    ('StockMovement','movementDate'),
    ('GoodsReceipt','receiptDate'),
    ('Shipment','shipmentDate'),
]:
    cursor.execute(f"""
        SELECT
            SUM(CASE WHEN YEAR({tarih})=2022 THEN 1 ELSE 0 END),
            SUM(CASE WHEN YEAR({tarih})=2023 THEN 1 ELSE 0 END),
            SUM(CASE WHEN YEAR({tarih})=2024 THEN 1 ELSE 0 END),
            COUNT(*)
        FROM {tablo}
        WHERE {tarih} IS NOT NULL AND YEAR({tarih}) BETWEEN 2022 AND 2024
    """)
    r = cursor.fetchone()
    print(f"  {tablo:<20} {r[0]:>5}   {r[1]:>5}   {r[2]:>5}  {r[3]:>6}")

print()
print("  2024 Urun Bazi Satis:")
cursor.execute("""
    SELECT p.productName, COUNT(DISTINCT so.salesOrderID) cnt
    FROM SalesOrder so
    JOIN SalesOrderItem soi ON so.salesOrderID=soi.salesOrderID
    JOIN Product p ON soi.productID=p.productID
    WHERE YEAR(so.orderDate)=2024
    GROUP BY p.productName ORDER BY cnt DESC
""")
for r in cursor.fetchall():
    print(f"    {r[0]:<35} {r[1]:>3} siparis")

print()
cursor.execute("SELECT COUNT(*) FROM BusinessPartnerAddress")
print(f"  BusinessPartnerAddress: {cursor.fetchone()[0]} kayit")
cursor.execute("SELECT COUNT(*) FROM InventoryBalance")
print(f"  InventoryBalance: {cursor.fetchone()[0]} / 102 kombinasyon")
cursor.execute("SELECT COUNT(*) FROM DimTarih WHERE YEAR(tarih)=2022")
print(f"  DimTarih 2022: {cursor.fetchone()[0]} gun")
cursor.execute("SELECT COUNT(*) FROM DimTarih WHERE YEAR(tarih)=2023")
print(f"  DimTarih 2023: {cursor.fetchone()[0]} gun")

conn.close()
print("\nTum eksiklikler giderildi!")
