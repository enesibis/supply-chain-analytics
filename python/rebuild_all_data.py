"""
SCM_3 - Tam Veri Yeniden Olusturma
2022-2023 icin TUM tablolarda gercekci sentetik veri uretir.
Gercek 2024 verisi korunur, sadece eski yanlis olcekli veri silinir.

Tablo zinciri:
  PurchaseOrder -> GoodsReceipt -> StockMovement(IN)
  SalesOrder -> Shipment -> StockMovement(OUT)
  ProductionOrder -> Consumption/Output -> StockMovement
"""

import pyodbc
import random
import numpy as np
from datetime import datetime, timedelta

CONN_STR = (
    "DRIVER={SQL Server};"
    "SERVER=ENES\\SQLEXPRESS;"
    "DATABASE=SCM_3;"
    "Trusted_Connection=yes;"
)

conn = pyodbc.connect(CONN_STR)
conn.autocommit = False
cursor = conn.cursor()
random.seed(42)
np.random.seed(42)

print("=" * 65)
print("SCM_3 - TAM VERİ YENİDEN OLUŞTURMA (2022-2023)")
print("=" * 65)

# ── REFERANS VERİLERİ ────────────────────────────────────────────────────────
def q(sql):
    cursor.execute(sql)
    return cursor.fetchall()

products   = q("SELECT productID, productName, categoryID FROM Product WHERE isActive=1")
subes      = q("SELECT subeID, subeKodu FROM Sube WHERE isActive=1")
warehouses = q("SELECT warehouseID, subeID FROM Warehouse WHERE isActive=1")
customers  = q("""SELECT bp.partnerID FROM BusinessPartner bp
                  JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
                  WHERE bpr.roleType='CUSTOMER' AND bpr.isActive=1""")
suppliers  = q("""SELECT bp.partnerID FROM BusinessPartner bp
                  JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
                  WHERE bpr.roleType='SUPPLIER' AND bpr.isActive=1""")
carriers   = q("""SELECT bp.partnerID FROM BusinessPartner bp
                  JOIN BusinessPartnerRole bpr ON bp.partnerID=bpr.partnerID
                  WHERE bpr.roleType='CARRIER' AND bpr.isActive=1""")
boms       = q("SELECT bomID, productID FROM BOM")

# Sube -> warehouse eslesme
sube_wh = {}
for wh_id, sube_id in warehouses:
    if sube_id not in sube_wh:
        sube_wh[sube_id] = wh_id

# Sube kodu -> ID
sube_id_map = {kod: sid for sid, kod in subes}

print(f"\nReferans: {len(products)} urun | {len(subes)} sube | {len(warehouses)} depo")
print(f"         {len(customers)} musteri | {len(suppliers)} tedarikci | {len(carriers)} tasiyici")

# ── MEVSIMSELLIK VE AGIRLIKLAR ───────────────────────────────────────────────
SEASON = {1:0.70,2:0.65,3:0.85,4:0.90,5:1.00,6:1.05,
          7:0.95,8:1.00,9:1.10,10:1.15,11:1.30,12:1.25}
SUBE_W = {'IST-001':1.40,'ANK-001':1.10,'IZM-001':1.00,'BRS-001':0.75}
YEAR_T = {2022:0.72,2023:0.88}

def rand_date(year, month):
    day = random.randint(1, 28)
    return datetime(year, month, day)

def rand_qty_sales():
    """Gercek 2024 dagilimina gore: ort 6.4, min 2, max 35"""
    return max(2, int(np.random.exponential(5) + 2))

def rand_qty_purchase(scale=3):
    """Satin alma: satisi karsilayacak kadar, ort ~20"""
    return max(5, int(np.random.exponential(10) * scale + 5))

def rand_price(low, high):
    return round(random.uniform(low, high), 2)

# Urun bazli fiyat araligim
PROD_PRICES = {}
cat_price = {1:(50,300),2:(100,500),3:(200,800),4:(30,200),5:(500,2000),
             6:(100,400),7:(50,250),8:(300,1000),9:(80,400),10:(200,600)}
for pid, pname, cat_id in products:
    lo, hi = cat_price.get(cat_id, (50, 500))
    PROD_PRICES[pid] = (lo, hi)

# ── ESKI SENTETIK VERİ SİL ───────────────────────────────────────────────────
print("\n[1] 2022-2023 eski veriler siliniyor...")

# Cascade siralama (FK bagimlilik sirasina gore)
cursor.execute("DISABLE TRIGGER TR_StockMovement_UpdateInventoryBalance ON StockMovement")

# Shipment zinciri
cursor.execute("""DELETE si FROM ShipmentItem si
    JOIN Shipment sh ON si.shipmentID=sh.shipmentID
    JOIN SalesOrder so ON sh.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2022,2023)""")
print(f"  ShipmentItem silindi: {cursor.rowcount}")

cursor.execute("""DELETE sh FROM Shipment sh
    JOIN SalesOrder so ON sh.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2022,2023)""")
print(f"  Shipment silindi: {cursor.rowcount}")

# SalesOrder zinciri
cursor.execute("""DELETE soi FROM SalesOrderItem soi
    JOIN SalesOrder so ON soi.salesOrderID=so.salesOrderID
    WHERE YEAR(so.orderDate) IN (2022,2023)""")
print(f"  SalesOrderItem silindi: {cursor.rowcount}")

cursor.execute("DELETE FROM SalesOrder WHERE YEAR(orderDate) IN (2022,2023)")
print(f"  SalesOrder silindi: {cursor.rowcount}")

# GoodsReceipt zinciri
cursor.execute("""DELETE gri FROM GoodsReceiptItem gri
    JOIN GoodsReceipt gr ON gri.goodsReceiptID=gr.goodsReceiptID
    JOIN PurchaseOrder po ON gr.purchaseOrderID=po.purchaseOrderID
    WHERE YEAR(po.orderDate) IN (2022,2023)""")
print(f"  GoodsReceiptItem silindi: {cursor.rowcount}")

cursor.execute("""DELETE gr FROM GoodsReceipt gr
    JOIN PurchaseOrder po ON gr.purchaseOrderID=po.purchaseOrderID
    WHERE YEAR(po.orderDate) IN (2022,2023)""")
print(f"  GoodsReceipt silindi: {cursor.rowcount}")

# PurchaseOrder zinciri
cursor.execute("""DELETE poi FROM PurchaseOrderItem poi
    JOIN PurchaseOrder po ON poi.purchaseOrderID=po.purchaseOrderID
    WHERE YEAR(po.orderDate) IN (2022,2023)""")
print(f"  PurchaseOrderItem silindi: {cursor.rowcount}")

cursor.execute("DELETE FROM PurchaseOrder WHERE YEAR(orderDate) IN (2022,2023)")
print(f"  PurchaseOrder silindi: {cursor.rowcount}")

# Production zinciri
cursor.execute("""DELETE pc FROM ProductionConsumption pc
    JOIN ProductionOrder po ON pc.productionOrderID=po.productionOrderID
    WHERE YEAR(po.startDate) IN (2022,2023)""")
print(f"  ProductionConsumption silindi: {cursor.rowcount}")

cursor.execute("""DELETE po2 FROM ProductionOutput po2
    JOIN ProductionOrder po ON po2.productionOrderID=po.productionOrderID
    WHERE YEAR(po.startDate) IN (2022,2023)""")
print(f"  ProductionOutput silindi: {cursor.rowcount}")

cursor.execute("DELETE FROM ProductionOrder WHERE YEAR(startDate) IN (2022,2023)")
print(f"  ProductionOrder silindi: {cursor.rowcount}")

# StockMovement 2022-2023
cursor.execute("DELETE FROM StockMovement WHERE YEAR(movementDate) IN (2022,2023)")
print(f"  StockMovement silindi: {cursor.rowcount}")

conn.commit()

# ── MAX ID'LERİ AL ───────────────────────────────────────────────────────────
def get_max(table, id_col):
    cursor.execute(f"SELECT ISNULL(MAX({id_col}),0) FROM {table}")
    return cursor.fetchone()[0]


print("\n[2] Yeni veriler uretiliyor (2022-2023)...")
print("    Hedef: gercek 2024 dagilimina kalibre edilmis")

# ── YARDIMCI INSERT FONK. ─────────────────────────────────────────────────────
def add_stock_movement(wh_id, prod_id, mv_type, qty_in, qty_out, mv_date, ref_type, ref_id):
    cursor.execute("""
        INSERT INTO StockMovement
            (warehouseID,productID,movementType,qtyIn,qtyOut,
             movementDate,refType,refID,createdAt)
        VALUES (?,?,?,?,?,?,?,?,?)
    """, (wh_id, prod_id, mv_type,
          qty_in, qty_out, mv_date, ref_type, ref_id, mv_date))

# ═══════════════════════════════════════════════════════════════════════════
# SATIN ALMA ZİNCİRİ: PurchaseOrder -> GoodsReceipt -> StockMovement
# ═══════════════════════════════════════════════════════════════════════════
print("\n  [A] PurchaseOrder + GoodsReceipt + StockMovement(IN)...")

po_count = 0; poi_count = 0; gr_count = 0; gri_count = 0; sm_in_count = 0

for year in [2022, 2023]:
    year_t = YEAR_T[year]
    for month in range(1, 13):
        season = SEASON[month]
        for sube_id, sube_kodu in subes:
            sube_w = SUBE_W.get(sube_kodu, 1.0)
            wh_id  = sube_wh.get(sube_id, warehouses[0][0])

            # Bu ay kac satin alma siparisi?
            n_po = max(1, int(np.random.poisson(3 * season * sube_w * year_t)))

            for _ in range(n_po):
                order_date = rand_date(year, month)
                delivery_days = random.randint(7, 30)
                delivery_date = order_date + timedelta(days=delivery_days)
                supplier_id = random.choice(suppliers)[0]
                po_status = random.choices(
                    ['RECEIVED','PARTIALLY_RECEIVED','CANCELLED'],
                    weights=[0.75, 0.15, 0.10])[0]

                cursor.execute("""
                    INSERT INTO PurchaseOrder
                        (orderNumber,orderDate,expectedDeliveryDate,supplierPartnerID,
                         status,totalAmount,subeID,createdAt)
                    VALUES (?,?,?,?,?,0,?,?)
                """, (f"PO-{year}-{po_count:05d}", order_date, delivery_date,
                      supplier_id, po_status, sube_id, order_date))
                cursor.execute("SELECT @@IDENTITY")
                po_id = int(cursor.fetchone()[0])
                po_count += 1

                # Kalemler (2-4 urun)
                n_items = random.randint(2, 4)
                selected = random.sample(products, min(n_items, len(products)))
                po_total = 0
                items_data = []

                for ln, (prod_id, _, _) in enumerate(selected, 1):
                    qty = rand_qty_purchase(scale=2)
                    lo, hi = PROD_PRICES[prod_id]
                    unit_price = rand_price(lo * 0.8, hi * 0.8)
                    received = qty if po_status=='RECEIVED' else (qty//2 if po_status=='PARTIALLY_RECEIVED' else 0)

                    cursor.execute("""
                        INSERT INTO PurchaseOrderItem
                            (purchaseOrderID,lineNo_,productID,quantity,unitPrice,receivedQuantity)
                        VALUES (?,?,?,?,?,?)
                    """, (po_id, ln, prod_id, qty, unit_price, received))
                    cursor.execute("SELECT @@IDENTITY")
                    poi_id = int(cursor.fetchone()[0])
                    poi_count += 1
                    po_total += qty * unit_price
                    items_data.append((prod_id, qty, received, poi_id))

                # totalAmount guncelle
                cursor.execute("UPDATE PurchaseOrder SET totalAmount=? WHERE purchaseOrderID=?",
                               (round(po_total,2), po_id))

                # GoodsReceipt (iptal degilse)
                if po_status != 'CANCELLED':
                    receipt_date = delivery_date + timedelta(days=random.randint(0,5))
                    gr_status = 'POSTED'

                    cursor.execute("""
                        INSERT INTO GoodsReceipt
                            (purchaseOrderID,warehouseID,receiptNumber,receiptDate,status,createdAt)
                        VALUES (?,?,?,?,?,?)
                    """, (po_id, wh_id, f"GR-{year}-{gr_count:05d}",
                          receipt_date, gr_status, receipt_date))
                    cursor.execute("SELECT @@IDENTITY")
                    gr_id = int(cursor.fetchone()[0])
                    gr_count += 1

                    # GoodsReceiptItem + StockMovement
                    for ln, (prod_id, qty, received, poi_id) in enumerate(items_data, 1):
                        if received > 0:
                            cursor.execute("""
                                INSERT INTO GoodsReceiptItem
                                    (goodsReceiptID,purchaseOrderItemID,lineNo_,productID,quantity)
                                VALUES (?,?,?,?,?)
                            """, (gr_id, poi_id, ln, prod_id, received))
                            gri_count += 1

                            add_stock_movement(
                                wh_id, prod_id, 'PURCHASE_RECEIPT',
                                received, 0, receipt_date, 'GoodsReceipt', gr_id)
                            sm_in_count += 1

                if po_count % 50 == 0:
                    conn.commit()

conn.commit()
print(f"    PurchaseOrder: {po_count} | PurchaseOrderItem: {poi_count}")
print(f"    GoodsReceipt: {gr_count} | GoodsReceiptItem: {gri_count}")
print(f"    StockMovement IN: {sm_in_count}")

# ═══════════════════════════════════════════════════════════════════════════
# SATIŞ ZİNCİRİ: SalesOrder -> SalesOrderItem -> Shipment -> StockMovement
# ═══════════════════════════════════════════════════════════════════════════
print("\n  [B] SalesOrder + SalesOrderItem + Shipment + StockMovement(OUT)...")

so_count = 0; soi_count = 0; sh_count = 0; shi_count = 0; sm_out_count = 0

for year in [2022, 2023]:
    year_t = YEAR_T[year]
    for month in range(1, 13):
        season = SEASON[month]
        for sube_id, sube_kodu in subes:
            sube_w = SUBE_W.get(sube_kodu, 1.0)
            wh_id  = sube_wh.get(sube_id, warehouses[0][0])
            carrier_id = random.choice(carriers)[0]

            # Bu ay kac satis siparisi?
            n_so = max(1, int(np.random.poisson(3.5 * season * sube_w * year_t)))

            for _ in range(n_so):
                order_date  = rand_date(year, month)
                customer_id = random.choice(customers)[0]
                so_status = random.choices(
                    ['SHIPPED','PARTIALLY_SHIPPED','CANCELLED'],
                    weights=[0.70, 0.20, 0.10])[0]

                cursor.execute("""
                    INSERT INTO SalesOrder
                        (orderNumber,orderDate,customerPartnerID,status,totalAmount,
                         subeID,createdAt)
                    VALUES (?,?,?,?,0,?,?)
                """, (f"SO-{year}-{so_count:05d}", order_date,
                      customer_id, so_status, sube_id, order_date))
                cursor.execute("SELECT @@IDENTITY")
                so_id = int(cursor.fetchone()[0])
                so_count += 1

                # Kalemler (1-4 urun)
                n_items = random.randint(1, 4)
                selected = random.sample(products, min(n_items, len(products)))
                so_total = 0
                items_data = []

                for ln, (prod_id, _, _) in enumerate(selected, 1):
                    qty = rand_qty_sales()
                    lo, hi = PROD_PRICES[prod_id]
                    unit_price = rand_price(lo, hi)
                    shipped = qty if so_status=='SHIPPED' else (qty//2 if so_status=='PARTIALLY_SHIPPED' else 0)

                    cursor.execute("""
                        INSERT INTO SalesOrderItem
                            (salesOrderID,lineNo_,productID,quantity,unitPrice,shippedQuantity)
                        VALUES (?,?,?,?,?,?)
                    """, (so_id, ln, prod_id, qty, unit_price, shipped))
                    soi_count += 1
                    so_total += qty * unit_price
                    items_data.append((prod_id, qty, shipped, ln))

                # totalAmount guncelle
                cursor.execute("UPDATE SalesOrder SET totalAmount=? WHERE salesOrderID=?",
                               (round(so_total,2), so_id))

                # Shipment (iptal degilse)
                if so_status != 'CANCELLED':
                    ship_date = order_date + timedelta(days=random.randint(2, 10))
                    sh_status = 'POSTED'

                    cursor.execute("""
                        INSERT INTO Shipment
                            (salesOrderID,warehouseID,customerPartnerID,shipmentNumber,
                             shipmentDate,status,carrierPartnerID,createdAt)
                        VALUES (?,?,?,?,?,?,?,?)
                    """, (so_id, wh_id, customer_id,
                          f"SH-{year}-{sh_count:05d}",
                          ship_date, sh_status, carrier_id, ship_date))
                    cursor.execute("SELECT @@IDENTITY")
                    sh_id = int(cursor.fetchone()[0])
                    sh_count += 1

                    for prod_id, qty, shipped, ln in items_data:
                        if shipped > 0:
                            # SalesOrderItem ID bul
                            cursor.execute("""
                                SELECT salesOrderItemID FROM SalesOrderItem
                                WHERE salesOrderID=? AND lineNo_=?
                            """, (so_id, ln))
                            soi_row = cursor.fetchone()
                            soi_id = soi_row[0] if soi_row else None

                            cursor.execute("""
                                INSERT INTO ShipmentItem
                                    (shipmentID,salesOrderItemID,lineNo_,productID,quantity)
                                VALUES (?,?,?,?,?)
                            """, (sh_id, soi_id, ln, prod_id, shipped))
                            shi_count += 1

                            add_stock_movement(
                                wh_id, prod_id, 'SALES_SHIPMENT',
                                0, shipped, ship_date, 'Shipment', sh_id)
                            sm_out_count += 1

                if so_count % 50 == 0:
                    conn.commit()

conn.commit()
print(f"    SalesOrder: {so_count} | SalesOrderItem: {soi_count}")
print(f"    Shipment: {sh_count} | ShipmentItem: {shi_count}")
print(f"    StockMovement OUT: {sm_out_count}")

# ═══════════════════════════════════════════════════════════════════════════
# ÜRETİM ZİNCİRİ: ProductionOrder -> Consumption -> Output -> StockMovement
# ═══════════════════════════════════════════════════════════════════════════
print("\n  [C] ProductionOrder + Consumption + Output + StockMovement...")

prod_count = 0; pc_count = 0; po_out_count = 0; sm_prod_count = 0

# BOM'u olan mamul urunler
bom_map = {}
for bom_id, bom_prod_id in boms:
    bom_map[bom_prod_id] = bom_id
mamul_products = [(pid, pname, cid) for pid, pname, cid in products if pid in bom_map]

for year in [2022, 2023]:
    year_t = YEAR_T[year]
    for month in range(1, 13):
        season = SEASON[month]
        for sube_id, sube_kodu in subes:
            sube_w = SUBE_W.get(sube_kodu, 1.0)
            wh_id  = sube_wh.get(sube_id, warehouses[0][0])

            if not mamul_products:
                continue

            n_prod = max(1, int(np.random.poisson(1.5 * season * sube_w * year_t)))

            for _ in range(n_prod):
                prod_obj = random.choice(mamul_products)
                prod_id  = prod_obj[0]
                bom_id   = bom_map[prod_id]
                start    = rand_date(year, month)
                duration = random.randint(3, 14)
                end      = start + timedelta(days=duration)
                plan_qty = max(5, int(np.random.exponential(15) + 5))

                prod_status = random.choices(
                    ['COMPLETED','IN_PROGRESS','CANCELLED'],
                    weights=[0.70, 0.20, 0.10])[0]
                produced = plan_qty if prod_status=='COMPLETED' else (plan_qty//2 if prod_status=='IN_PROGRESS' else 0)

                cursor.execute("""
                    INSERT INTO ProductionOrder
                        (orderNumber,productID,bomID,plannedQuantity,producedQuantity,
                         sourceWarehouseID,targetWarehouseID,status,startDate,endDate,
                         subeID,createdAt)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
                """, (f"PRO-{year}-{prod_count:05d}", prod_id, bom_id,
                      plan_qty, produced, wh_id, wh_id, prod_status,
                      start, end, sube_id, start))
                cursor.execute("SELECT @@IDENTITY")
                pord_id = int(cursor.fetchone()[0])
                prod_count += 1

                if produced > 0:
                    # BOM malzemelerini cek
                    cursor.execute("""
                        SELECT bi.componentProductID, bi.quantityPer
                        FROM BOMItem bi WHERE bi.bomID=?
                    """, (bom_id,))
                    bom_items = cursor.fetchall()

                    # Hammadde tuketimi
                    for comp_prod_id, comp_qty in bom_items:
                        consume_qty = round(comp_qty * produced, 2)
                        cursor.execute("""
                            INSERT INTO ProductionConsumption
                                (productionOrderID,warehouseID,productID,quantity,
                                 consumptionDate,createdAt)
                            VALUES (?,?,?,?,?,?)
                        """, (pord_id, wh_id, comp_prod_id, consume_qty, end, end))
                        pc_count += 1

                        add_stock_movement(
                            wh_id, comp_prod_id, 'PRODUCTION_CONSUMPTION',
                            0, consume_qty, end, 'ProductionOrder', pord_id)
                        sm_prod_count += 1

                    # Mamul ciktisi
                    cursor.execute("""
                        INSERT INTO ProductionOutput
                            (productionOrderID,warehouseID,productID,quantity,
                             outputDate,createdAt)
                        VALUES (?,?,?,?,?,?)
                    """, (pord_id, wh_id, prod_id, produced, end, end))
                    po_out_count += 1

                    add_stock_movement(
                        wh_id, prod_id, 'PRODUCTION_OUTPUT',
                        produced, 0, end, 'ProductionOrder', pord_id)
                    sm_prod_count += 1

                if prod_count % 30 == 0:
                    conn.commit()

conn.commit()
print(f"    ProductionOrder: {prod_count} | Consumption: {pc_count} | Output: {po_out_count}")
print(f"    StockMovement Production: {sm_prod_count}")

# ── TETİKLEYİCİYİ YENİDEN AKTİF ET ─────────────────────────────────────────
cursor.execute("ENABLE TRIGGER TR_StockMovement_UpdateInventoryBalance ON StockMovement")
conn.commit()

# ── ÖZET ─────────────────────────────────────────────────────────────────────
print("\n" + "=" * 65)
print("ÖZET - Tüm yıllar")
print("=" * 65)

for tablo, tarih_kol in [
    ('SalesOrder','orderDate'),
    ('PurchaseOrder','orderDate'),
    ('ProductionOrder','startDate'),
    ('StockMovement','movementDate'),
]:
    cursor.execute(f"""
        SELECT YEAR({tarih_kol}) yil, COUNT(*) cnt
        FROM {tablo}
        WHERE {tarih_kol} IS NOT NULL
        GROUP BY YEAR({tarih_kol})
        ORDER BY yil
    """)
    rows = cursor.fetchall()
    print(f"\n  {tablo}:")
    for yil, cnt in rows:
        bar = '=' * (cnt // 5)
        print(f"    {yil}: {cnt:>4} kayit  {bar}")

cursor.execute("""
    SELECT movementType, COUNT(*) FROM StockMovement
    WHERE YEAR(movementDate) IN (2022,2023)
    GROUP BY movementType ORDER BY movementType
""")
print("\n  StockMovement tipleri (2022-2023):")
for mt, cnt in cursor.fetchall():
    print(f"    {mt:<30} {cnt:>4}")

cursor.execute("""
    SELECT
        YEAR(so.orderDate) as yil,
        AVG(soi.quantity) as ort_qty,
        MIN(soi.quantity) as min_qty,
        MAX(soi.quantity) as max_qty
    FROM SalesOrder so
    JOIN SalesOrderItem soi ON so.salesOrderID=soi.salesOrderID
    WHERE YEAR(so.orderDate) IN (2022,2023,2024)
    GROUP BY YEAR(so.orderDate)
    ORDER BY yil
""")
print("\n  SalesOrderItem miktar dagilimi:")
for yil, avg, mn, mx in cursor.fetchall():
    print(f"    {yil}: ort={avg:.1f}  min={mn}  max={mx}")

conn.close()
print("\nTamamlandi!")
