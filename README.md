<div align="center">

# Supply Chain Analytics Platform

**End-to-end supply chain intelligence — from normalized SQL database to Power BI dashboards and ML-driven demand forecasting.**

[![SQL Server](https://img.shields.io/badge/SQL%20Server%20Express-CC2927?style=for-the-badge&logo=microsoft-sql-server&logoColor=white)](https://www.microsoft.com/sql-server)
[![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)](https://powerbi.microsoft.com)
[![Python](https://img.shields.io/badge/Python-3.14-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org)
[![scikit-learn](https://img.shields.io/badge/scikit--learn-in%20progress-F7931E?style=for-the-badge&logo=scikit-learn&logoColor=white)](https://scikit-learn.org)

</div>

---

## Overview

This project simulates a real-world Supply Chain Management system across **4 regional branches** in Turkey. It covers the full analytics stack:

- **Database layer** — fully normalized SQL Server schema with stored procedures, triggers, and views
- **Reporting layer** — interactive Power BI dashboard with Row Level Security (RLS)
- **ML layer** — synthetic data generation + demand forecasting model (in progress)

---

## Dashboard

> 5-page Power BI report. Each branch (Istanbul, Ankara, Izmir, Bursa) sees only its own data via RLS.

<table>
  <tr>
    <td align="center"><b>Özet</b></td>
    <td align="center"><b>Satış & Satın Alma</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/01_ozet.png" alt="Özet" width="420"/></td>
    <td><img src="docs/screenshots/02_satis_satinalma.png" alt="Satış & Satın Alma" width="420"/></td>
  </tr>
  <tr>
    <td align="center"><b>Stok Yönetimi</b></td>
    <td align="center"><b>Üretim</b></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/03_stok_yonetimi.png" alt="Stok Yönetimi" width="420"/></td>
    <td><img src="docs/screenshots/04_uretim.png" alt="Üretim" width="420"/></td>
  </tr>
  <tr>
    <td align="center" colspan="2"><b>Müşteri & Ürün Analizi</b></td>
  </tr>
  <tr>
    <td colspan="2" align="center"><img src="docs/screenshots/05_musteri_urun_analizi.png" alt="Müşteri & Ürün Analizi" width="420"/></td>
  </tr>
</table>

| Page | Visuals |
|---|---|
| **Özet** | KPI cards, production completion gauge, monthly trend |
| **Satış & Satın Alma** | Sales waterfall, trend line, purchasing funnel by status |
| **Stok Yönetimi** | Treemap by category, stock bar chart, critical stock alerts |
| **Üretim** | Status pie, planned vs actual comparison |
| **Müşteri & Ürün Analizi** | Scatter (RFM), customer ranking, product revenue breakdown |

**RLS Roles:** `IST-001` Istanbul · `ANK-001` Ankara · `IZM-001` Izmir · `BRS-001` Bursa

---

## Machine Learning — Demand Forecasting

To enable predictive analytics, 2 years of synthetic sales data (2022–2023) was programmatically generated to complement real 2024 data.

### Data Generation Pipeline

```
generate_demand_data.py
  → Seasonality weights (Nov–Dec peak, Jan–Feb low)
  → Branch weights   (Istanbul 1.4x, Bursa 0.75x)
  → Year-over-year growth trend (2022: 0.75x → 2023: 0.90x → 2024: 1.0x)
  → ±20% random noise per order
  → INSERT into SalesOrder + SalesOrderItem (SQL Server)
  → Export to demand_data.csv
```

### Dataset

| Stat | Value |
|---|---|
| File | `python/demand_data.csv` |
| Rows | 905 (year × month × branch × product) |
| Period | Jan 2022 – Dec 2024 (3 years) |
| Orders | 2022: 193 · 2023: 204 · 2024: actual |
| Features | `yil, ay, subeKodu, productID, productName, categoryName, toplamMiktar, toplamCiro, siparisAdet` |

### Planned Model

- **Algorithm:** XGBoost (primary) + Facebook Prophet (seasonal baseline)
- **Target:** `toplamMiktar` — monthly demand per product per branch
- **Features:** month, branch, category, lag values, rolling averages, seasonality flags
- **Output:** Next-month demand forecast with confidence interval

---

## Database

**Platform:** SQL Server Express · **Instance:** `ENES\SQLEXPRESS` · **Database:** `SCM_3`

### Schema

| Module | Tables |
|---|---|
| Geography | `Country`, `City`, `Town`, `District`, `Address` |
| Partners | `BusinessPartner`, `BusinessPartnerRole`, `BusinessPartnerAddress` |
| Products | `Unit`, `ProductCategory`, `Product`, `BOM`, `BOMItem` |
| Warehouse | `Warehouse`, `InventoryBalance`, `StockMovement` |
| Purchasing | `PurchaseOrder`, `PurchaseOrderItem`, `GoodsReceipt`, `GoodsReceiptItem` |
| Sales | `SalesOrder`, `SalesOrderItem`, `Shipment`, `ShipmentItem` |
| Production | `ProductionOrder`, `ProductionConsumption`, `ProductionOutput` |
| Branch | `Sube`, `SubeKullanici` |
| Time | `DimTarih` (date dimension) |

### Status Flows

```
PurchaseOrder:   DRAFT → APPROVED → PARTIALLY_RECEIVED → RECEIVED → CANCELLED
SalesOrder:      DRAFT → APPROVED → RESERVED → PARTIALLY_SHIPPED → SHIPPED → CANCELLED
ProductionOrder: DRAFT → RELEASED → IN_PROGRESS → COMPLETED → CANCELLED
```

### Key Technical Features

| Feature | Detail |
|---|---|
| **Stored Procedures** | `CreatePurchaseOrder`, `PostGoodsReceipt`, `ReserveSalesOrder`, `PostShipment`, `PostProductionOutput`, `sp_RefreshAllSnapshots` |
| **Triggers** | `TR_StockMovement_UpdateInventoryBalance` — auto-updates inventory, blocks negative stock |
| **Auto-Numbering Triggers** | `TR_SalesOrder_AutoNumber`, `TR_PurchaseOrder_AutoNumber`, `TR_ProductionOrder_AutoNumber` — branch-prefixed document numbers |
| **Views** | 13 Power BI-ready views with Turkish labels, branch joins, and status translations |
| **Snapshot Tables** | 4 pre-computed summary tables (`snap_AylikSatis`, `snap_AylikSatinAlma`, `snap_AylikUretim`, `snap_UrunPerformans`) for fast BI queries |
| **TVFs** | 3 parametric table-valued functions for date range, period comparison, and supplier delivery analysis |
| **RLS** | 4 branch roles enforced via DAX filter on `Sube` table |
| **Conditional Formatting** | Stock status (Critical / Low / Normal) driven by `minStockLevel` per product |
| **Data Volume** | 2022–2024: ~600 sales orders, ~1,800 order items, 272+ stock movements |

---

## Branch-Based Document Numbering

All transactional documents follow a structured format:

```
{DocType}-{BranchCode}-{Year}-{Sequence}
SO-IST-2024-00001   ← Sales Order, Istanbul, 2024, 1st
PO-ANK-2023-00015   ← Purchase Order, Ankara, 2023, 15th
PRO-IZM-2024-00003  ← Production Order, Izmir, 2024, 3rd
```

Implemented via `DocNumberSequence` table + `AFTER INSERT` triggers using atomic `MERGE` operations. All historical records were backfilled with the new format.

---

## Analytics Architecture

```
Layer 1 — Core Views (13)
  vw_SatisSiparisleri, vw_SatinAlmaSiparisleri, vw_UretimEmirleri,
  vw_Sevkiyatlar, vw_StokDurumu, vw_StokHareketleri, vw_KPI,
  vw_TedarikciPerformansi, vw_MusteriAnalizi (RFM),
  vw_SubeOzeti, vw_UrunSatisAnalizi, vw_AylikNakitAkisi, vw_KritikStok

Layer 2 — Snapshot Tables (4)
  snap_AylikSatis, snap_AylikSatinAlma, snap_AylikUretim, snap_UrunPerformans
  → Refreshed nightly via sp_RefreshAllSnapshots

Layer 3 — Parametric TVFs (3)
  fn_SatisRaporu(@baslangic, @bitis, @subeKodu, @kategori)
  fn_DonemKarsilastirma(@yil1, @yil2, @subeKodu)
  fn_TedarikciTeslimAnalizi(@yil, @subeKodu)

Layer 4 — Automation
  scripts/refresh_snapshots.bat → Windows Task Scheduler (daily 02:00)
```

---

## Project Structure

```
supply-chain-analytics/
│
├── database/
│   ├── seed-data/               # Master & transactional INSERT scripts
│   ├── views/
│   │   ├── createViews.sql      # Original views
│   │   └── analytics_system.sql # 13 views + 4 snap tables + 3 TVFs + sp_RefreshAllSnapshots
│   ├── stored-procedures/       # Business logic + branch prefix numbering system
│   └── tests/                   # Validation scripts
│
├── powerbi/
│   └── SCM_SupplyChain_Dashboard.pbix
│
├── scripts/
│   └── refresh_snapshots.bat    # Nightly snapshot refresh (Windows Task Scheduler)
│
├── docs/
│   └── screenshots/             # Dashboard page screenshots
│
└── README.md
```

---

## Author

<div align="center">

**Enes İbiş**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/enesibis/)
[![GitHub](https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/Enesibis)

</div>
