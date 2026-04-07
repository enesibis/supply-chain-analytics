# Supply Chain Analytics

End-to-end supply chain analytics project — SQL Server database design, T-SQL stored procedures, Power BI dashboards with RLS, and Python-based demand forecasting.

## Project Structure

```
supply-chain-analytics/
│
├── database/
│   ├── seed-data/          # Master & transactional data insert scripts
│   ├── views/              # Power BI-ready SQL views
│   ├── stored-procedures/  # Business logic (T-SQL stored procedures)
│   └── tests/              # Test scripts
│
├── powerbi/
│   └── SCM_SupplyChain_Dashboard.pbix   # 8-page Power BI report with RLS
│
├── python/
│   ├── generate_demand_data.py          # Synthetic data generator (2022–2023)
│   └── demand_data.csv                  # Aggregated dataset for ML training
│
├── docs/
│   └── screenshots/        # Power BI report screenshots
│
└── README.md
```

## Power BI Dashboard

5-page interactive report with Row Level Security (RLS) — each branch sees only its own data.

| Page | Content |
|---|---|
| Özet | KPI cards, production completion gauge, trend charts |
| Satış & Satın Alma | Sales waterfall, monthly trend, purchasing funnel by status |
| Stok Yönetimi | Treemap by category, stock level bar chart, critical stock alerts |
| Üretim | Pie by status, planned vs actual comparison, production trend |
| Müşteri & Ürün Analizi | RFM scatter plot, customer ranking, product sales breakdown |

**RLS Roles:** Istanbul (IST-001) · Ankara (ANK-001) · Izmir (IZM-001) · Bursa (BRS-001)

### Screenshots

| Özet | Satış & Satın Alma |
|---|---|
| ![Özet](docs/screenshots/01_ozet.png) | ![Satış & Satın Alma](docs/screenshots/02_satis_satinalma.png) |

| Stok Yönetimi | Üretim |
|---|---|
| ![Stok Yönetimi](docs/screenshots/03_stok_yonetimi.png) | ![Üretim](docs/screenshots/04_uretim.png) |

| Müşteri & Ürün Analizi |
|---|
| ![Müşteri & Ürün Analizi](docs/screenshots/05_musteri_urun_analizi.png) |

## Machine Learning — Demand Forecasting

Synthetic sales data was generated for 2022–2023 using realistic supply chain patterns, then combined with actual 2024 data to build a 3-year training dataset.

**Data generation features:**
- Seasonality: Nov–Dec peak, Jan–Feb low
- Branch weighting: Istanbul > Ankara > Izmir > Bursa
- Year-over-year growth trend (2022 → 2023 → 2024)
- ±20% random noise per order

**Dataset stats (demand_data.csv):**
- 905 rows — year × month × branch × product aggregates
- 3 years: 2022 (193 orders), 2023 (204 orders), 2024 (actual)
- Columns: `yil, ay, subeKodu, productID, productName, categoryName, toplamMiktar, toplamCiro, siparisAdet`

**Planned model:** XGBoost / Prophet — monthly product-level demand prediction per branch

## Database Overview

**Platform:** SQL Server Express (`ENES\SQLEXPRESS`) — Database: `SCM_3`

| Module | Tables |
|---|---|
| Geography | Country, City, Town, District, Address |
| Partners | BusinessPartner, BusinessPartnerRole, BusinessPartnerAddress |
| Products | Unit, ProductCategory, Product, BOM, BOMItem |
| Warehouse | Warehouse, InventoryBalance, StockMovement |
| Purchasing | PurchaseOrder, PurchaseOrderItem, GoodsReceipt, GoodsReceiptItem |
| Sales | SalesOrder, SalesOrderItem, Shipment, ShipmentItem |
| Production | ProductionOrder, ProductionConsumption, ProductionOutput |
| Branch | Sube, SubeKullanici |
| Time | DimTarih (date dimension) |

## Key Technical Features

- **Stored Procedures** — Full business logic layer: CreatePurchaseOrder, PostGoodsReceipt, ReserveSalesOrder, PostShipment, PostProductionOutput
- **Triggers** — `TR_StockMovement_UpdateInventoryBalance` (negative stock protection), branch auto-assignment triggers
- **Views** — 11 Power BI-optimized views with Turkish labels and branch filtering
- **RLS** — Row Level Security with 4 branch roles, enforced via DAX filter on `Sube` table
- **Conditional Formatting** — Stock status (Critical / Low / Normal) based on `minStockLevel` per product
- **3 Years of Data** — 2022–2024: ~600 sales orders, ~1800 order items, 272+ stock movements

## Status Flows

```
PurchaseOrder:   DRAFT → APPROVED → PARTIALLY_RECEIVED → RECEIVED → CANCELLED
SalesOrder:      DRAFT → APPROVED → RESERVED → PARTIALLY_SHIPPED → SHIPPED → CANCELLED
ProductionOrder: DRAFT → RELEASED → IN_PROGRESS → COMPLETED → CANCELLED
```

## Tech Stack

![SQL Server](https://img.shields.io/badge/SQL%20Server-CC2927?style=flat&logo=microsoft-sql-server&logoColor=white)
![T-SQL](https://img.shields.io/badge/T--SQL-blue?style=flat)
![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=flat&logo=powerbi&logoColor=black)
![Python](https://img.shields.io/badge/Python-3.14-3776AB?style=flat&logo=python&logoColor=white)
![scikit-learn](https://img.shields.io/badge/scikit--learn-coming%20soon-F7931E?style=flat&logo=scikit-learn&logoColor=white)

## Author

**Enes İbiş** — [LinkedIn](https://www.linkedin.com/in/enesibis/) · [GitHub](https://github.com/Enesibis)
