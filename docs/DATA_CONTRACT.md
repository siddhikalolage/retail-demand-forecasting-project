# DATA_CONTRACT.md — Phase 3 Dataset Definitions & Grain Specifications

**Date:** 2026-09-02  
**Scope:** Complete definition of dataset, date ranges, and analytical grain  
**Status:** PRELIMINARY — Requires validation against actual data query results (Phase 4)  

---

## Executive Summary

This document defines the data contract for the retail demand forecasting project. It establishes:

1. **Source Dataset** — Kaggle M5 Forecasting Competition dataset (Walmart sales)
2. **Date Ranges** — Exact training, validation, and evaluation periods
3. **Grain Definitions** — What constitutes "one row" in each key table
4. **Forecast Contract** — Forecast input grain vs. output grain vs. actual sales grain

**Critical Note:** All values below are PRELIMINARY pending validation against actual SQL query results in Phase 4 (Data Profiling).

---

## Source Dataset Definition

### Dataset Name
**Walmart M5 Forecasting Challenge Dataset** (Kaggle Public Dataset)

**Source:** https://www.kaggle.com/competitions/m5-forecasting-accuracy/data

**Domain:** Retail demand forecasting

**Real-World Context:** Actual historical sales data from Walmart stores in the United States, 2011–2016.

**Dataset Owner/Rights:** Kaggle Competition data (Public use license applies)

**Size (Raw):** ~58M daily sales transactions across 30K+ SKUs and 10 stores

---

## Date Range Definition

### M5 Dataset Historical Period

| Period | Dates | Days | Purpose |
|--------|-------|------|---------|
| **Full Historical** | 2011-01-29 to 2016-06-19 | ~1,941 days | All available data |
| **Year 1 (2011)** | 2011-01-29 to 2011-12-31 | 336 days | Baseline |
| **Year 2 (2012)** | 2012-01-01 to 2012-12-31 | 366 days | Training period |
| **Year 3 (2013)** | 2013-01-01 to 2013-12-31 | 365 days | Training period |
| **Year 4 (2014)** | 2014-01-01 to 2014-12-31 | 365 days | Training + Validation |
| **Year 5 (2015)** | 2015-01-01 to 2015-06-19 | 170 days | Evaluation start |
| **Year 6 (2016)** | (Not in dataset) | — | N/A |

### Forecast Cutoff & Horizon

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Latest Actual Sales Date** | 2016-06-19 | Last day with observed sales data |
| **Forecast Cutoff Date** | 2016-06-19 | As-of date for forecast generation |
| **Forecast Horizon** | 28 days | Forecast period: 2016-06-20 to 2016-07-17 |
| **Actual Evaluation Period** | (Not available) | M5 dataset does not include post-cutoff actuals |

**Important:** The M5 dataset is historical only. Post-cutoff actuals are not available in this dataset, which means true out-of-sample forecast evaluation is not directly possible with M5 data alone. Backtesting requires using earlier forecast origins (see Phase 9).

---

## Source Data Tables: Grain & Dimensions

### 1. Sales Training Data (`sales_train.csv`)

**Purpose:** Daily sales transactions for all items across all stores

**Grain:** **Item × Store × Day** (one row = sales for one SKU at one location on one day)

**Date Range:** 2011-01-29 to 2016-06-19

**Key Columns:**
| Column | Type | Notes |
|--------|------|-------|
| `store_id` | Integer | Store identifier (1-10) — 10 unique stores |
| `item_id` | Integer | Product SKU identifier (1-3049) — ~3,000 unique items |
| `date` | Date | Sales date (YYYY-MM-DD) |
| `sales` | Integer | Units sold on that day (0 to ~1,000) |

**Cardinality:** ~1,941 days × 10 stores × ~3,000 items = ~58M rows (exact subject to data quality)

**Expected Properties:**
- One row per store × item × day combination (dense array possible)
- Sales values ≥ 0 (no negative units)
- Sparsity possible (some items may not sell on some days → sales = 0)
- No NULL values expected in sales column (0 used for non-sales days)

---

### 2. Pricing Data (`sell_prices.csv`)

**Purpose:** Selling prices for items at stores over time

**Grain:** **Item × Store × Date Range** (one row = price valid for one item at one store during a date range)

**Key Columns:**
| Column | Type | Notes |
|--------|------|-------|
| `store_id` | Integer | Store identifier (1-10) |
| `item_id` | Integer | Product SKU |
| `wm_yr_wk` | String | Walmart week identifier (YYYYWW format) |
| `sell_price` | Decimal | Price in USD (2 decimal places) |

**Grain Note:** Price changes are aligned to Walmart's weekly calendar (`wm_yr_wk`), not daily. A single price row covers one week for one item at one store.

**Important:** Prices may be NULL for some item × store × week combinations, indicating either:
1. Item was not sold at that store that week, or
2. Price data is missing

**Cardinality:** Expected ~1M-2M rows (much sparser than daily sales due to weekly aggregation and possible gaps)

---

### 3. Calendar Data (`calendar.csv`)

**Purpose:** Calendar attributes and holiday/event flags

**Grain:** **Day** (one row = one calendar date)

**Date Range:** 2011-01-29 to 2016-06-19

**Key Columns:**
| Column | Type | Notes |
|--------|------|-------|
| `date` | Date | Calendar date (YYYY-MM-DD) |
| `wm_yr_wk` | String | Walmart week identifier matching pricing data |
| `weekday` | Integer | Day of week (1=Monday through 7=Sunday?) |
| `month` | Integer | Month number (1-12) |
| `year` | Integer | Year (2011-2016) |
| `d` | Integer | Days since epoch or custom sequence? |
| `event_name_1` | String | Primary event (e.g., "Valentine's Day", "Super Bowl") |
| `event_type_1` | String | Event category (e.g., "Holiday", "Sporting") |
| `event_name_2` | String | Secondary event (if any) |
| `event_type_2` | String | Secondary event category |

**Cardinality:** 1,941 rows (one per day in the dataset)

**Important Notes:**
- Event columns may be NULL for non-event days
- Exact event definitions should be validated in Phase 4
- SNAP benefit days may be inferrable from event flags or require external calendar

---

## Derived Dataset Grains: dbt Transformation Layers

### Staging Layer (stg_*) — Raw → Type-Converted

| Model | Grain | Notes |
|-------|-------|-------|
| `stg_m5_sales_train` | Item × Store × Day | 1:1 mapping from source; INT cast for sales |
| `stg_m5_sell_prices` | Item × Store × Week | 1:1 mapping from source; DECIMAL cast for prices |
| `stg_m5_calendar` | Day | 1:1 mapping from source; DATE cast for dates |

### Intermediate Layer (int_*) — Business Logic

| Model | Grain | Logic |
|-------|-------|-------|
| `int_sales_with_prices` | Item × Store × Day | **CRITICAL JOIN:** Sales grain preserved (Item × Store × Day). Price is joined from weekly table. Multiple price matches possible if week spans multiple dates; must resolve to single price per day. |
| `int_forecast_input` | **Item × Day (Aggregate)** | **AGGREGATE ACROSS STORES:** Sum daily sales by item across all stores. Grain becomes Item × Day. This is the input grain for forecast model training. |

**Critical Grain Change at int_forecast_input:** This is where sales move from disaggregated (by store) to aggregated (across stores). This is intentional and important for understanding forecast scope.

### Warehouse Layer (dim_* / fact_*)

| Model | Grain | Cardinality |
|-------|-------|-------------|
| `dim_calendar` | Day | 1,941 rows |
| `dim_item` | Item | ~3,000 rows |
| `dim_store` | Store | 10 rows |
| `fact_daily_sales` | **Item × Store × Day** | ~58M rows |
| `fact_forecast_daily` | **Item × Day (Aggregate)** | ~28 days × ~3,000 items = ~84K rows |

**Important Distinction:**
- `fact_daily_sales` preserves store disaggregation (Item × Store × Day)
- `fact_forecast_daily` is already aggregated (Item × Day) — forecast trained and generated at aggregate level

### Marts Layer (mart_*)

| Model | Grain | Purpose |
|-------|-------|---------|
| `mart_forecast_vs_actual` | Item × Day | Join forecast (aggregated) to actual sales (must aggregate from fact_daily_sales) |
| `agg_sales_daily` | Day | Aggregate sales across all items and stores (portfolio-level KPI) |
| `agg_sales_daily_item_cat` | Item Category × Day | Sales by category across all stores |

---

## Forecast Grain Contract

### Input Grain (What the Model Sees)

**Training Data Grain:** Item × Day (aggregate across stores)  
**Source:** `int_forecast_input` model  
**Row Count per Day:** ~3,000 items (one row per unique SKU)  
**Total Training Rows:** ~1,900 days × ~3,000 items = ~5.7M rows  

**Training Features:**
- `item_id`: Unique item identifier
- `day`: Calendar date
- `aggregate_sales`: Sum of units sold across all 10 stores
- Additional features TBD (see Phase 7)

### Forecast Model Specification

| Parameter | Value | Notes |
|-----------|-------|-------|
| **Model Type** | Snowflake Cortex ML FORECAST | Auto-selected ARIMA/Exponential Smoothing variant |
| **Training Window** | Full available history | 2011-01-29 to 2016-06-19 |
| **Forecast Horizon** | 28 days | 2016-06-20 to 2016-07-17 |
| **Aggregation Level** | Item (across stores) | Forecast generated for each SKU, not by store |
| **Confidence Level** | 95% | Confidence intervals computed |

### Output Grain (What We Get Back)

**Forecast Output Grain:** Item × Day  
**Count:** 28 forecast days × ~3,000 items = ~84K rows  

**Forecast Columns:**
| Column | Type | Notes |
|--------|------|-------|
| `item_id` | Integer | Item identifier |
| `forecast_date` | Date | Forecasted date (2016-06-20 to 2016-07-17) |
| `forecast_value` | Decimal | Predicted units for this item on this day |
| `lower_bound_95` | Decimal | 95% confidence interval lower bound |
| `upper_bound_95` | Decimal | 95% confidence interval upper bound |

### Comparison Grain (Actual vs. Forecast)

**To compare forecast vs. actuals, must aggregate actuals to Item × Day:**

```sql
SELECT
    item_id,
    date,
    SUM(sales) AS actual_units  -- Aggregate across 10 stores
FROM fact_daily_sales
WHERE date BETWEEN '2016-06-20' AND '2016-07-17'
GROUP BY item_id, date
```

**Then join to forecast:**

```sql
SELECT
    f.item_id,
    f.forecast_date,
    f.forecast_value,
    a.actual_units,
    a.actual_units - f.forecast_value AS error
FROM fact_forecast_daily f
LEFT JOIN actual_aggregated a
    ON f.item_id = a.item_id
    AND f.forecast_date = a.date
```

**Note:** The M5 dataset does not include actuals for the forecast period (2016-06-20+), so this comparison cannot be performed with the base dataset alone. Backtesting requires using earlier forecast origins.

---

## Key Business Grains & Hierarchies

### Product Hierarchy

**Grain Structure:** Store → Category → Department → Item

| Level | Cardinality | Examples |
|-------|-------------|----------|
| Item (SKU) | ~3,000 | Walmart item codes |
| Department | ~7-10 | (TBD — requires source inspection) |
| Category | 3 | FOODS, HOUSEHOLD, HOBBIES |
| Store | 10 | STORE_1 through STORE_10 |

**Cross-Product Hierarchy:** Categories are consistent across all stores and items.

### Time Hierarchy

**Grain Structure:** Year → Quarter → Month → Week → Day

| Level | Cardinality | Notes |
|-------|-------------|-------|
| Year | 6 | 2011–2016 (partial) |
| Quarter | ~24 | 4 per year |
| Month | ~72 | 12 per year |
| Week (Walmart) | ~312 | Walmart fiscal week (wm_yr_wk) |
| Day | 1,941 | Individual dates |

### Geographic Hierarchy (Stores)

**Grain Structure:** Store → State

| Store ID | State | Details |
|----------|-------|---------|
| 1–10 | TBD | (Requires inspection; M5 does not expose state in sales data) |

---

## Volume & Sparsity

### Expected Data Density

| Dataset | Expected Rows | Sparsity | Notes |
|---------|---------------|----------|-------|
| `stg_m5_sales_train` | ~58M | Dense | Most item × store × day combos have a value (0 or >0) |
| `stg_m5_sell_prices` | 1M–2M | Sparse | Prices not available for every item × store × week |
| `int_sales_with_prices` | ~58M | Depends on join | May have NULLs where price is unavailable |
| `int_forecast_input` | ~5.7M | Dense | 1,900 days × ~3,000 items |
| `fact_daily_sales` | ~58M | Dense | Warehouse-conformed sales fact |
| `fact_forecast_daily` | ~84K | Dense | 28 days × ~3,000 items |
| `mart_forecast_vs_actual` | ~84K | Depends | forecast rows × actual rows (will have NULLs for forecast-only dates) |

---

## Known Unknowns (To Verify in Phase 4)

These assumptions must be validated against actual data queries:

1. **Exact Item Count** — Currently assumed ~3,000 items; verify actual `SELECT DISTINCT(item_id)` count
2. **Store Count & Names** — Currently assumed 10 stores (STORE_1 through STORE_10); verify exact names
3. **Category Definitions** — Assumed 3 categories (FOODS, HOUSEHOLD, HOBBIES); verify against source
4. **Department Count** — Number and names TBD
5. **Calendar Completeness** — Are all days 2011-01-29 to 2016-06-19 present? Any gaps?
6. **Price Sparsity** — What % of item × store × week combos have price data?
7. **Sales Sparsity** — What % of item × store × day combos have non-zero sales?
8. **SNAP Indicator** — Is a SNAP benefit day flag available in the calendar data?
9. **Event Definitions** — What events are flagged? How many unique event types?
10. **Forecast Grain Validation** — Confirm forecast is generated at Item × Day level (not Item × Store × Day)

---

## Data Contract Sign-Off

**This document establishes the baseline understanding of dataset structure and grain.**

**Status:** PRELIMINARY — Validation required in Phase 4

**Next Step:** Phase 4 will execute actual SQL queries to verify each grain definition and cardinality assumption.

**Phase 4 Deliverable:** DATA_QUALITY.md with actual measurement results replacing these assumptions.

