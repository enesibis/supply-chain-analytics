"""
SCM_3 -- Talep Tahmini icin Sentetik Veri Uretici
2022-2023 yillari icin SalesOrder + SalesOrderItem verileri uretir.
"""

import pyodbc
import pandas as pd
import numpy as np
from datetime import datetime
import random

# Baglanti
CONN_STR = (
    "DRIVER={SQL Server};"
    "SERVER=ENES\\SQLEXPRESS;"
    "DATABASE=SCM_3;"
    "Trusted_Connection=yes;"
)

conn = pyodbc.connect(CONN_STR)
cursor = conn.cursor()
print("SQL Server baglantisi kuruldu")

# Mevcut verileri cek
cursor.execute("""
    SELECT p.productID, p.productName, pc.categoryName
    FROM Product p
    JOIN ProductCategory pc ON p.categoryID = pc.categoryID
    WHERE p.isActive = 1
""")
# Kategori bazlı makul fiyat aralikları (TL)
CATEGORY_PRICE = {
    'Ham Madde': (50, 500),
    'Yari Mamul': (200, 2000),
    'Bileşen': (100, 1000),
    'Aksesuar': (30, 300),
}
random.seed(42)
products = []
for r in cursor.fetchall():
    cat = r[2] or ''
    price_range = next((v for k, v in CATEGORY_PRICE.items() if k.lower() in cat.lower()), (100, 1000))
    price = round(random.uniform(*price_range), 2)
    products.append({'productID': r[0], 'productName': r[1], 'unitPrice': price, 'categoryName': cat})

cursor.execute("""
    SELECT bp.partnerID FROM BusinessPartner bp
    JOIN BusinessPartnerRole bpr ON bp.partnerID = bpr.partnerID
    WHERE bpr.roleType = 'CUSTOMER' AND bpr.isActive = 1
""")
customer_ids = [r[0] for r in cursor.fetchall()]

cursor.execute("SELECT subeID, subeKodu FROM Sube WHERE isActive = 1")
subes = [{'subeID': r[0], 'subeKodu': r[1]} for r in cursor.fetchall()]

cursor.execute("SELECT ISNULL(MAX(salesOrderID), 0) FROM SalesOrder")
max_so = cursor.fetchone()[0]

cursor.execute("SELECT ISNULL(MAX(salesOrderItemID), 0) FROM SalesOrderItem")
max_soi = cursor.fetchone()[0]

print(f"{len(products)} urun, {len(customer_ids)} musteri, {len(subes)} sube")
print(f"Max SalesOrder ID: {max_so}, Max Item ID: {max_soi}")

# Parametreler
np.random.seed(42)
random.seed(42)

SEASONALITY = {
    1: 0.70, 2: 0.65, 3: 0.85, 4: 0.90,
    5: 1.00, 6: 1.05, 7: 0.95, 8: 1.00,
    9: 1.10, 10: 1.15, 11: 1.30, 12: 1.25,
}

SUBE_WEIGHT = {
    'IST-001': 1.40,
    'ANK-001': 1.10,
    'IZM-001': 1.00,
    'BRS-001': 0.75,
}

YEAR_TREND = {2022: 0.75, 2023: 0.90}

product_weights = np.random.uniform(0.5, 2.0, len(products))
product_weights = product_weights / product_weights.sum()

# Veri uret
sales_orders = []
sales_items = []

order_id = int(max_so) + 1
item_id = int(max_soi) + 1

for year in [2022, 2023]:
    year_trend = YEAR_TREND[year]

    for month in range(1, 13):
        season_factor = SEASONALITY[month]

        for sube in subes:
            sube_kodu = sube['subeKodu']
            sube_weight = SUBE_WEIGHT.get(sube_kodu, 1.0)

            n_orders = max(1, int(np.random.poisson(5 * season_factor * sube_weight * year_trend)))

            for _ in range(n_orders):
                day = random.randint(1, 28)
                order_date = datetime(year, month, day)
                customer_id = random.choice(customer_ids)
                status = random.choices(
                    ['SHIPPED', 'PARTIALLY_SHIPPED', 'CANCELLED'],
                    weights=[0.75, 0.15, 0.10]
                )[0]
                order_no = f"SO-{year}-{order_id:05d}"

                sales_orders.append({
                    'orderID': order_id,
                    'orderNo': order_no,
                    'orderDate': order_date,
                    'customerID': customer_id,
                    'status': status,
                    'subeID': sube['subeID'],
                })

                n_items = random.randint(2, 5)
                selected_idx = np.random.choice(
                    len(products),
                    size=min(n_items, len(products)),
                    replace=False,
                    p=product_weights
                )

                line_no = 1
                for idx in selected_idx:
                    product = products[idx]
                    base_qty = random.randint(5, 50)
                    qty = max(1, int(base_qty * season_factor * sube_weight * year_trend * np.random.uniform(0.8, 1.2)))
                    unit_price = round(float(product['unitPrice']) * np.random.uniform(0.90, 1.10), 2)

                    if status == 'SHIPPED':
                        shipped_qty = qty
                    elif status == 'PARTIALLY_SHIPPED':
                        shipped_qty = qty // 2
                    else:
                        shipped_qty = 0

                    total_price = round(qty * unit_price, 2)

                    sales_items.append({
                        'itemID': item_id,
                        'orderID': order_id,
                        'lineNo': line_no,
                        'productID': product['productID'],
                        'quantity': qty,
                        'unitPrice': unit_price,
                        'shippedQty': shipped_qty,
                        'totalPrice': total_price,
                    })
                    item_id += 1
                    line_no += 1

                order_id += 1

print(f"Uretildi: {len(sales_orders)} SalesOrder, {len(sales_items)} SalesOrderItem")

# SQL Server'a yukle
batch_size = 50

try:
    print("SalesOrder ekleniyor...")
    # ID'yi otomatik uret (IDENTITY), orderNo icin sonradan guncelle
    insert_so = """
        INSERT INTO SalesOrder
            (orderNumber, orderDate, customerPartnerID, status, totalAmount, subeID)
        VALUES (?, ?, ?, ?, 0, ?)
    """
    # INSERT + SELECT @@IDENTITY ayni execute'da
    insert_so_with_id = """
        INSERT INTO SalesOrder
            (orderNumber, orderDate, customerPartnerID, status, totalAmount, subeID)
        VALUES (?, ?, ?, ?, 0, ?);
        SELECT CAST(SCOPE_IDENTITY() AS INT);
    """
    old_to_new = {}
    for order in sales_orders:
        cursor.execute(insert_so_with_id, (
            order['orderNo'], order['orderDate'],
            order['customerID'], order['status'], order['subeID']
        ))
        cursor.nextset()  # INSERT sonucu atla
        new_id = cursor.fetchone()[0]
        old_to_new[order['orderID']] = int(new_id)

    conn.commit()
    print(f"  {len(sales_orders)}/{len(sales_orders)} tamam")

    print("SalesOrderItem ekleniyor...")
    # totalPrice computed column oldugu icin INSERT'e dahil edilmiyor
    insert_soi = """
        INSERT INTO SalesOrderItem
            (salesOrderID, lineNo_, productID, quantity, unitPrice, shippedQuantity)
        VALUES (?, ?, ?, ?, ?, ?)
    """
    for i in range(0, len(sales_items), batch_size):
        batch = sales_items[i:i+batch_size]
        cursor.executemany(insert_soi, [
            (old_to_new[r['orderID']], r['lineNo'], r['productID'],
             r['quantity'], r['unitPrice'], r['shippedQty'])
            for r in batch
        ])
        conn.commit()
        print(f"  {min(i+batch_size, len(sales_items))}/{len(sales_items)}")

    # totalAmount guncelle
    print("totalAmount guncelleniyor...")
    cursor.execute("""
        UPDATE so
        SET so.totalAmount = sub.total
        FROM SalesOrder so
        JOIN (
            SELECT salesOrderID, SUM(totalPrice) as total
            FROM SalesOrderItem
            GROUP BY salesOrderID
        ) sub ON so.salesOrderID = sub.salesOrderID
        WHERE YEAR(so.orderDate) IN (2022, 2023)
    """)
    conn.commit()

    print("Tum veriler basariyla eklendi!")

except Exception as e:
    conn.rollback()
    print(f"HATA: {e}")
    raise

# Ozet
cursor.execute("""
    SELECT YEAR(orderDate) as Yil, COUNT(*) as SiparisAdet,
           SUM(totalAmount) as ToplamCiro
    FROM SalesOrder
    WHERE YEAR(orderDate) IN (2022, 2023)
    GROUP BY YEAR(orderDate)
    ORDER BY Yil
""")
print("\n-- Yillik Ozet --")
for row in cursor.fetchall():
    print(f"  {row[0]}: {row[1]} siparis, {row[2]:,.0f} TL ciro")

# ML icin CSV kaydet
cursor.execute("""
    SELECT
        YEAR(so.orderDate) as yil,
        MONTH(so.orderDate) as ay,
        s.subeKodu,
        p.productID,
        p.productName,
        pc.categoryName,
        SUM(soi.quantity) as toplamMiktar,
        SUM(soi.totalPrice) as toplamCiro,
        COUNT(DISTINCT so.salesOrderID) as siparisAdet
    FROM SalesOrder so
    JOIN SalesOrderItem soi ON so.salesOrderID = soi.salesOrderID
    JOIN Product p ON soi.productID = p.productID
    JOIN ProductCategory pc ON p.categoryID = pc.categoryID
    JOIN Sube s ON so.subeID = s.subeID
    WHERE YEAR(so.orderDate) IN (2022, 2023, 2024)
      AND so.status != 'CANCELLED'
    GROUP BY YEAR(so.orderDate), MONTH(so.orderDate), s.subeKodu,
             p.productID, p.productName, pc.categoryName
    ORDER BY yil, ay, subeKodu, productID
""")
rows = cursor.fetchall()
cols_names = ['yil', 'ay', 'subeKodu', 'productID', 'productName', 'categoryName',
              'toplamMiktar', 'toplamCiro', 'siparisAdet']
df = pd.DataFrame([list(r) for r in rows], columns=cols_names)
df.to_csv(r"C:\Users\enesi\supply-chain-analytics\python\demand_data.csv",
          index=False, encoding='utf-8-sig')
print(f"\ndemand_data.csv kaydedildi: {len(df)} satir (ML egitimi icin hazir)")

conn.close()
