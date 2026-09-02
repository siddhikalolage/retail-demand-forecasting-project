# DATA_QUALITY.md

## Phase 4: Data Profiling & Quality Validation

**Document Version:** 1.0  
**Date Created:** 2026-09-02  
**Last Updated:** 2026-09-02  
**Status:** Framework established; results to be populated on next Snowflake execution

---

## Executive Summary

This document establishes the comprehensive data quality framework for the retail demand forecasting project. It defines:

1. **Data Quality Checks** — 30+ automated validations covering grain, cardinality, anomalies, and integrity
2. **Expected Values** — Baseline assumptions from DATA_CONTRACT.md that will be validated
3. **Profiling Methodology** — How checks are executed and results interpreted
4. **Remediation Guidelines** — Actions to take when checks fail
5. **Known Limitations** — Data issues that are acceptable in context

All profiling is executed via:
- **SQL Script:** `sql/profile/00_comprehensive_data_profile.sql`
- **Python Wrapper:** `scripts/profile_data.py`

---

## Part 1: Data Quality Checks Framework

### Category 1: Calendar Dimension (RAW.CALENDAR)

#### Check 1.1 — Date Range Completeness

**Purpose:** Verify calendar spans expected date range without gaps.

**Expected Values (from DATA_CONTRACT.md):**
- Min Date: 2011-01-29
- Max Date: 2016-06-19
- Total Days: 1,941
- Unique Dates: 1,941 (no duplicates)

**Check Logic:**
```sql
SELECT MIN(DATE) as min_date, MAX(DATE) as max_date, COUNT(DISTINCT DATE) as unique_dates
FROM RAW.CALENDAR
```

**Pass Criteria:**
- Min date = 2011-01-29 ✓
- Max date = 2016-06-19 ✓
- Unique dates = 1,941 ✓
- No date gaps in the sequence ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Remediation:** If gaps detected, rebuild calendar from source. If date range off, validate source dataset specifications.

---

#### Check 1.2 — Calendar Attributes

**Purpose:** Verify calendar contains required business attributes.

**Expected Attributes:**
- WEEKDAY (distinct: 7 expected — Mon-Sun)
- MONTH (distinct: 12 expected for multi-year data)
- YEAR (distinct: 6 expected — 2011-2016)
- WM_YR_WK (Walmart fiscal week code — ~313 unique expected)
- EVENT_NAME_1 & EVENT_NAME_2 (holiday/event markers)
- SNAP (SNAP indicator for food pricing impact)

**Check Logic:**
```sql
SELECT 
    COUNT(DISTINCT WEEKDAY) as unique_weekdays,
    COUNT(DISTINCT MONTH) as unique_months,
    COUNT(DISTINCT YEAR) as unique_years,
    COUNT(DISTINCT WM_YR_WK) as unique_weeks,
    SUM(CASE WHEN EVENT_NAME_1 IS NOT NULL THEN 1 ELSE 0 END) as days_with_events
FROM RAW.CALENDAR
```

**Pass Criteria:**
- Unique weekdays = 7 ✓
- Unique months ≥ 12 ✓
- Unique years = 6 ✓
- Unique Walmart weeks ≈ 310-320 ✓
- Events marked on 20+ days ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

### Category 2: Sales Fact Table (RAW.M5_SALES_TRAIN)

#### Check 2.1 — Grain Validation (Item × Store × Day)

**Purpose:** Verify fact table is at correct grain with no duplicate keys.

**Expected Grain:** Item × Store × Day (one row per unique combination)

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) as unique_keys
FROM RAW.M5_SALES_TRAIN
```

**Pass Criteria:**
- Total rows = Unique keys (no duplicates) ✓
- Expected ~58M rows ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Remediation:** If duplicates found:
1. Identify duplicate key combinations and dates
2. Verify source data was loaded correctly
3. Check for corrupted or double-loaded batches
4. Contact data engineering team for reload

---

#### Check 2.2 — Cardinality Validation

**Purpose:** Verify expected dimensional cardinalities.

**Expected Values (from DATA_CONTRACT.md):**
- Unique Items: ~3,000
- Unique Stores: 10
- Unique Dates: 1,941

**Check Logic:**
```sql
SELECT 
    COUNT(DISTINCT ITEM_ID) as unique_items,
    COUNT(DISTINCT STORE_ID) as unique_stores,
    COUNT(DISTINCT DATE) as unique_dates
FROM RAW.M5_SALES_TRAIN
```

**Pass Criteria:**
- Unique items: 2,950-3,050 (M5 has exactly 3,049) ✓
- Unique stores: 10 ✓
- Unique dates: 1,941 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Remediation:** If cardinalities off:
- 2,950-3,050 items: PASS (natural dataset variation)
- < 2,900 or > 3,100 items: INVESTIGATE (data loss or corruption)
- ≠ 10 stores: FAIL (check source data scope)
- ≠ 1,941 dates: FAIL (check date filter in extract)

---

#### Check 2.3 — Sales Value Distribution

**Purpose:** Identify outliers, invalid values, and anomalies in sales quantities.

**Expected Characteristics:**
- Min sales: ≥ 0 (no negative sales)
- Max sales: Varies by item/store; typically < 100 units/day
- Null values: < 0.1% (mostly complete)
- Zero sales: 5-15% (common for slow-moving SKUs)

**Check Logic:**
```sql
SELECT 
    MIN(SALES) as min_sales,
    MAX(SALES) as max_sales,
    AVG(SALES) as avg_sales,
    STDDEV(SALES) as stddev_sales,
    SUM(CASE WHEN SALES < 0 THEN 1 ELSE 0 END) as negative_count,
    SUM(CASE WHEN SALES = 0 THEN 1 ELSE 0 END) as zero_count,
    SUM(CASE WHEN SALES IS NULL THEN 1 ELSE 0 END) as null_count
FROM RAW.M5_SALES_TRAIN
```

**Pass Criteria:**
- Min sales ≥ 0 ✓
- Max sales < 500 ✓
- Avg sales 5-20 units ✓
- Negative sales = 0 ✓
- Null sales < 10,000 rows (< 0.02%) ✓
- Zero sales 5-15% of total ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Remediation:**
- Negative sales: FAIL — investigate source system issue
- Null sales > 1%: FAIL — data completeness issue
- Spiky outliers (e.g., max > 200): ACCEPTABLE for seasonal/promotional events

---

#### Check 2.4 — Date Range Alignment

**Purpose:** Verify sales date range matches calendar.

**Expected Values:**
- Min date in sales: 2011-01-29 (match calendar min)
- Max date in sales: 2016-06-19 (match calendar max)
- Continuity: All dates between min-max should exist

**Check Logic:**
```sql
SELECT 
    MIN(DATE) as min_date,
    MAX(DATE) as max_date,
    COUNT(DISTINCT DATE) as unique_dates
FROM RAW.M5_SALES_TRAIN
```

**Pass Criteria:**
- Min date = 2011-01-29 ✓
- Max date = 2016-06-19 ✓
- Unique dates = 1,941 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 2.5 — Completeness (Coverage)

**Purpose:** Measure what % of expected Item × Store × Day combinations have sales records.

**Expected Coverage:**
- Perfect universe: 3,049 items × 10 stores × 1,941 days = 59,095,890 rows
- Actual expected: ~58M rows
- Coverage: ~98%

**Check Logic:**
```sql
WITH dims AS (
    SELECT 
        COUNT(DISTINCT ITEM_ID) as item_count,
        COUNT(DISTINCT STORE_ID) as store_count,
        COUNT(DISTINCT DATE) as date_count
    FROM RAW.M5_SALES_TRAIN
)
SELECT 
    item_count * store_count * date_count as expected_dense_rows,
    COUNT(*) as actual_rows,
    ROUND(100.0 * COUNT(*) / (item_count * store_count * date_count), 2) as coverage_percent
FROM RAW.M5_SALES_TRAIN
CROSS JOIN dims
```

**Pass Criteria:**
- Coverage ≥ 97% ✓
- No unexplained gaps > 1% ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Known Limitation:** M5 dataset naturally has ~2% sparse cells (items not sold on certain days at certain stores). This is acceptable.

**Remediation:** If coverage < 95%, investigate for data loss during load.

---

### Category 3: Price Data (RAW.SELL_PRICES)

#### Check 3.1 — Grain Validation (Item × Store × Week)

**Purpose:** Verify price table is at correct grain with no duplicates.

**Expected Grain:** Item × Store × Walmart Week (one price per combination per week)

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || WM_YR_WK)) as unique_keys
FROM RAW.SELL_PRICES
```

**Pass Criteria:**
- Total rows = Unique keys ✓
- Expected ~3M-4M rows (sparse pricing) ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 3.2 — Price Value Distribution

**Purpose:** Identify invalid prices, sparsity, and anomalies.

**Expected Characteristics:**
- Min price: ≥ $0.01
- Max price: Typically < $50 (retail grocery)
- Null prices: 40-60% sparse (not all items on sale every week)
- Zero prices: < 0.5% (invalid)

**Check Logic:**
```sql
SELECT 
    MIN(SELL_PRICE) as min_price,
    MAX(SELL_PRICE) as max_price,
    AVG(SELL_PRICE) as avg_price,
    SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) as null_count,
    SUM(CASE WHEN SELL_PRICE = 0 THEN 1 ELSE 0 END) as zero_count,
    ROUND(100.0 * SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) as null_percent
FROM RAW.SELL_PRICES
```

**Pass Criteria:**
- Min price ≥ $0.01 ✓
- Max price < $50 ✓
- Avg price $3-$15 ✓
- Null prices 30-70% (sparse pricing acceptable) ✓
- Zero prices < 0.1% ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Known Limitation:** M5 pricing is sparse; not all items have prices every week. This is realistic for retail.

---

#### Check 3.3 — Price Coverage

**Purpose:** Measure temporal price availability.

**Expected Coverage:**
- Some items have continuous prices; others sporadic
- Overall coverage: 30-60% (not every item has price every week)

**Check Logic:**
```sql
SELECT 
    COUNT(DISTINCT ITEM_ID) as unique_items,
    COUNT(DISTINCT STORE_ID) as unique_stores,
    COUNT(DISTINCT WM_YR_WK) as unique_weeks,
    COUNT(*) as actual_prices,
    ROUND(100.0 * COUNT(*) / 
        (COUNT(DISTINCT ITEM_ID) * COUNT(DISTINCT STORE_ID) * COUNT(DISTINCT WM_YR_WK)), 2) 
        as coverage_percent
FROM RAW.SELL_PRICES
```

**Pass Criteria:**
- Coverage 30-60% ✓
- All dimensions represented ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

### Category 4: Data Integrity Checks

#### Check 4.1 — Cross-Table Date Alignment

**Purpose:** Verify calendar, sales, and forecast dates align correctly.

**Expected Alignment:**
- Calendar covers: 2011-01-29 to 2016-06-19
- Sales dates: Within calendar range
- Forecast dates: Based on last sales date + 1 to +28

**Check Logic:**
```sql
SELECT 'CALENDAR' as table_name, MIN(DATE) as min_date, MAX(DATE) as max_date
FROM RAW.CALENDAR
UNION ALL
SELECT 'SALES', MIN(DATE), MAX(DATE)
FROM RAW.M5_SALES_TRAIN
UNION ALL
SELECT 'FORECAST', MIN(FORECAST_DATE), MAX(FORECAST_DATE)
FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
```

**Pass Criteria:**
- Calendar min/max contains sales range ✓
- Forecast starts after sales end ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 4.2 — Referential Integrity (Dimension Keys)

**Purpose:** Verify no orphaned facts (sales referencing non-existent items/stores).

**Check Logic:**
```sql
SELECT 'Orphaned Items' as check_name, COUNT(*) as orphan_count
FROM RAW.M5_SALES_TRAIN s
LEFT JOIN RAW.M5_ITEMS i ON s.ITEM_ID = i.ITEM_ID
WHERE i.ITEM_ID IS NULL
```

**Pass Criteria:**
- Orphaned items = 0 ✓
- Orphaned stores = 0 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

### Category 5: Staging Layer Validation

#### Check 5.1 — Staging to Raw Alignment

**Purpose:** Verify staging layer is accurate 1:1 transformation of raw data.

**Expected Results:**
- stg_m5_sales_train: Same row count as RAW.M5_SALES_TRAIN
- stg_m5_calendar: Same row count as RAW.CALENDAR
- stg_m5_sell_prices: Same row count as RAW.SELL_PRICES

**Check Logic:**
```sql
SELECT 'stg_m5_sales_train' as model, COUNT(*) as row_count FROM DEV.STAGING.STG_M5_SALES_TRAIN
UNION ALL
SELECT 'RAW.M5_SALES_TRAIN', COUNT(*) FROM RAW.M5_SALES_TRAIN
```

**Pass Criteria:**
- Row counts match exactly ✓
- No nulls introduced where source had values ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

**Remediation:** If staging row counts differ:
1. Check for duplicate rows in staging
2. Verify dbt model logic (WHERE clauses, deduplication)
3. Run dbt debug to trace data lineage

---

### Category 6: Intermediate Layer Validation

#### Check 6.1 — int_sales_with_prices Grain

**Purpose:** Verify intermediate enriched sales layer maintains Item × Store × Day grain.

**Expected Characteristics:**
- Grain: Item × Store × Day (same as fact_daily_sales)
- Row count: ~58M (matches raw sales)
- Added columns: sell_price (may have NULLs due to price sparsity)

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT (ITEM_ID || '|' || STORE_ID || '|' || DATE)) as unique_keys,
    SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) as null_price_count
FROM DEV.INTERMEDIATE.INT_SALES_WITH_PRICES
```

**Pass Criteria:**
- Total rows = Unique keys ✓
- Row count ≈ 58M ✓
- Null prices: 30-60% (expected due to price sparsity) ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 6.2 — int_forecast_input Aggregation

**Purpose:** Verify Item × Day aggregate created correctly (sums across stores).

**Expected Characteristics:**
- Grain: Item × Day aggregate (NOT × Store)
- Row count: ~5.9M (3,049 items × 1,941 days, assuming dense)
- Values: SUM of sales across all 10 stores for each item/date combo

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT ITEM_ID) as unique_items,
    COUNT(DISTINCT DATE) as unique_dates,
    CASE WHEN COUNT(*) = COUNT(DISTINCT ITEM_ID) * COUNT(DISTINCT DATE) 
         THEN 'Dense' ELSE 'Sparse' END as structure
FROM DEV.INTERMEDIATE.INT_FORECAST_INPUT
```

**Pass Criteria:**
- Row count ≈ 5.9M (dense grain) ✓
- Unique items = 3,049 ✓
- Unique dates = 1,941 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

### Category 7: Warehouse Layer Validation

#### Check 7.1 — fact_daily_sales Integrity

**Purpose:** Validate warehouse fact table preserves raw data integrity.

**Expected Characteristics:**
- Grain: Item × Store × Day (preserved from raw)
- Row count: ~58M
- Values match raw source
- Dates align with calendar

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) as unique_keys,
    MIN(SALES_UNITS) as min_sales,
    MAX(SALES_UNITS) as max_sales,
    SUM(CASE WHEN SALES_UNITS < 0 THEN 1 ELSE 0 END) as negative_count
FROM DEV.WAREHOUSE.FACT_DAILY_SALES
```

**Pass Criteria:**
- Total rows = Unique keys ✓
- Row count ≈ 58M ✓
- Min sales ≥ 0 ✓
- Negative sales = 0 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 7.2 — Dimension Cardinality

**Purpose:** Verify dimensions load correctly with no duplicates or missing keys.

**Check Logic:**
```sql
SELECT 'dim_calendar' as table_name, COUNT(*) as rows, COUNT(DISTINCT DATE_ID) as unique_keys FROM DEV.WAREHOUSE.DIM_CALENDAR
UNION ALL
SELECT 'dim_item', COUNT(*), COUNT(DISTINCT ITEM_ID) FROM DEV.WAREHOUSE.DIM_ITEM
UNION ALL
SELECT 'dim_store', COUNT(*), COUNT(DISTINCT STORE_ID) FROM DEV.WAREHOUSE.DIM_STORE
```

**Pass Criteria:**
- dim_calendar: 1,941 rows, 1,941 unique ✓
- dim_item: 3,049 rows, 3,049 unique ✓
- dim_store: 10 rows, 10 unique ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

#### Check 7.3 — fact_forecast_daily Structure

**Purpose:** Validate forecast output table structure and 28-day horizon.

**Expected Characteristics:**
- Grain: Item × Forecast Date
- Row count: ≈84K (3,049 items × 28 days)
- Dates: From last sales date + 1 to + 28
- Confidence intervals: Not null (95% CI should exist)

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    COUNT(DISTINCT ITEM_ID) as unique_items,
    COUNT(DISTINCT FORECAST_DATE) as unique_dates,
    DATEDIFF(DAY, MIN(FORECAST_DATE), MAX(FORECAST_DATE)) + 1 as horizon_days,
    SUM(CASE WHEN FORECAST_VALUE IS NULL THEN 1 ELSE 0 END) as null_forecast_count,
    SUM(CASE WHEN LOWER_BOUND_95 IS NULL THEN 1 ELSE 0 END) as null_ci_lower_count
FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
```

**Pass Criteria:**
- Row count ≈ 84K (3,049 × 28) ✓
- Unique items = 3,049 ✓
- Unique dates = 28 ✓
- Horizon days = 28 ✓
- Null forecasts = 0 ✓
- Null CI bounds = 0 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

### Category 8: Mart Layer Validation

#### Check 8.1 — mart_forecast_vs_actual Structure

**Purpose:** Validate evaluation mart has correct join and comparison logic.

**Expected Characteristics:**
- Grain: Item × Date (aggregated)
- Contains: Actual sales vs. forecast
- Values properly aligned

**Check Logic:**
```sql
SELECT 
    COUNT(*) as total_rows,
    SUM(CASE WHEN ACTUAL_UNITS IS NULL THEN 1 ELSE 0 END) as null_actual,
    SUM(CASE WHEN FORECAST_VALUE IS NULL THEN 1 ELSE 0 END) as null_forecast,
    ROUND(AVG(CASE WHEN ACTUAL_UNITS > 0 THEN ABS(ACTUAL_UNITS - FORECAST_VALUE) / ACTUAL_UNITS ELSE NULL END) * 100, 2) as avg_ape
FROM DEV.MARTS.MART_FORECAST_VS_ACTUAL
```

**Pass Criteria:**
- Row count > 0 ✓
- Null actual values < 1% ✓
- Null forecast values = 0 ✓

**Actual Results:** _To be populated_

**Status:** ⬜ PENDING EXECUTION

---

## Part 2: Data Quality Summary Dashboard

### Overall Status

| Check Category | Total Checks | Passed | Failed | Blocked |
|---|---|---|---|---|
| Calendar Dimension | 2 | ⬜ | ⬜ | ⬜ |
| Sales Fact Table | 5 | ⬜ | ⬜ | ⬜ |
| Price Data | 3 | ⬜ | ⬜ | ⬜ |
| Data Integrity | 2 | ⬜ | ⬜ | ⬜ |
| Staging Layer | 1 | ⬜ | ⬜ | ⬜ |
| Intermediate Layer | 2 | ⬜ | ⬜ | ⬜ |
| Warehouse Layer | 3 | ⬜ | ⬜ | ⬜ |
| Mart Layer | 1 | ⬜ | ⬜ | ⬜ |
| **TOTAL** | **19** | ⬜ | ⬜ | ⬜ |

---

## Part 3: Known Limitations & Acceptable Data Characteristics

### Limitation 1: Price Sparsity

**Issue:** Not all items have prices available for all time periods.

**Reason:** M5 dataset reflects real retail: prices only recorded when item actively sold with promotional pricing.

**Impact:** int_sales_with_prices will have 40-60% NULL sell_prices; join logic handles gracefully.

**Mitigation:** Store-level average prices can be imputed if needed; currently acceptable.

**Acceptable:** ✓ YES

---

### Limitation 2: Zero Sales Days

**Issue:** 5-15% of Item × Store × Day combinations have zero sales (not sold that day at that location).

**Reason:** Normal retail behavior; not all SKUs sell every day everywhere.

**Impact:** Forecast model must handle zero-inflation; features should account for excess zeros.

**Mitigation:** Included in feature engineering and model architecture.

**Acceptable:** ✓ YES

---

### Limitation 3: No Post-Cutoff Actuals

**Issue:** M5 dataset ends 2016-06-19; no ground truth available for 28-day forecast validation.

**Reason:** Dataset published at cutoff; later actuals not available for direct backtesting.

**Impact:** Forecast evaluation uses cross-validation on historical forecast origins, not holdout set.

**Mitigation:** Backtesting implemented via rolling window from historical periods.

**Acceptable:** ✓ YES

---

### Limitation 4: Limited Event Data

**Issue:** Calendar has EVENT_NAME_1 and EVENT_NAME_2 but no structured holiday mapping.

**Reason:** M5 captures major US holidays (Thanksgiving, Christmas, etc.) but mapping may be incomplete.

**Impact:** May miss some localized or regional events; SNAP data more reliable for demand shifts.

**Mitigation:** Documentation; feature engineering can leverage SNAP indicator more heavily.

**Acceptable:** ✓ YES

---

## Part 4: Next Steps (Phase 5+)

### Upon Profiling Completion

After this data quality report is populated with actual results:

1. **Phase 5 — Data Engineering Hardening**
   - Review fact_daily_sales incremental load logic
   - Validate watermarking strategy
   - Test partition pruning effectiveness
   - Document load time and volumes

2. **Phase 6-10 — Analytical Build-Out**
   - Leverage cardinality insights to size aggregation tables
   - Use null/sparsity patterns to design imputation strategy
   - Reference coverage % when building forecasting features

3. **Phase 12 — Power BI Validation**
   - Confirm Power BI imports match warehouse row counts
   - Validate date filter excludes future forecast dates from reporting

---

## Appendix: How to Run Profiling

### Option 1: Execute SQL Script Directly

```powershell
# Connect to Snowflake via SnowSQL
snowsql -c <connection_name> -f sql/profile/00_comprehensive_data_profile.sql > data_quality_results.txt
```

### Option 2: Run Python Script

```powershell
# Install dependencies
pip install snowflake-connector-python

# Ensure .env configured with Snowflake credentials
python scripts/profile_data.py > data_quality_output.json
```

### Option 3: Execute in dbt (Recommended for CI/CD)

```bash
# Add profiling analysis as dbt operation
dbt run-operation profile_data
```

---

## References

- [DATA_CONTRACT.md](DATA_CONTRACT.md) — Baseline data assumptions
- [sql/profile/00_comprehensive_data_profile.sql](../sql/profile/00_comprehensive_data_profile.sql) — SQL check definitions
- [scripts/profile_data.py](../scripts/profile_data.py) — Python profiling wrapper
- M5 Dataset: https://www.kaggle.com/c/m5-forecasting-accuracy
