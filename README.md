# Supply Chain Analytics

End-to-end supply chain analytics project — SQL Server database design, T-SQL stored procedures, Power BI dashboards, and Python analysis.

## Project Structure

```
supply-chain-analytics/
│
├── database/
│   ├── seed-data/          # Master & transactional data insert scripts
│   ├── views/              # Power BI-ready SQL views
│   ├── stored-procedures/  # Business logic (T-SQL stored procedures & fixes)
│   └── tests/              # Test scripts
│
├── powerbi/                # Power BI dashboard (.pbix)
├── python/                 # Data analysis notebooks & scripts
└── README.md
```

## Database Overview

**Platform:** SQL Server Express (`ENES\SQLEXPRESS`) — Database: `SCM_3`

A fully normalized Supply Chain Management database covering:

| Module | Tables |
|---|---|
| Geography | Country, City, Town, District, Address |
| Partners | BusinessPartner, BusinessPartnerRole, BusinessPartnerAddress |
| Products | Unit, ProductCategory, Product, BOM, BOMItem |
| Warehouse | Warehouse, InventoryBalance, StockMovement |
| Purchasing | PurchaseOrder, PurchaseOrderItem, GoodsReceipt, GoodsReceiptItem |
| Sales | SalesOrder, SalesOrderItem, Shipment, ShipmentItem |
| Production | ProductionOrder, ProductionConsumption, ProductionOutput |

## Key Technical Features

- **Stored Procedures** — Full business logic layer: CreatePurchaseOrder, PostGoodsReceipt, ReserveSalesOrder, PostShipment, PostProductionOutput, and more
- **Trigger** — `TR_StockMovement_UpdateInventoryBalance` auto-updates inventory on every stock movement (handles multi-row inserts with negative stock protection)
- **Views** — 7 Power BI-optimized views: `vw_KPI`, `vw_StokDurumu`, `vw_StokHareketleri`, `vw_SatinAlmaSiparisleri`, `vw_SatisSiparisleri`, `vw_UretimEmirleri`, `vw_Sevkiyatlar`
- **Bulk Data** — 12 months (Jan–Dec 2024) of transactional data: 40 POs, 38 Production Orders, 35 Sales Orders, 272 Stock Movements

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
![Python](https://img.shields.io/badge/Python-coming%20soon-3776AB?style=flat&logo=python&logoColor=white)

## Author

**Enes İbiş** — [LinkedIn](https://www.linkedin.com/in/enesibis/) · [GitHub](https://github.com/Enesibis)
