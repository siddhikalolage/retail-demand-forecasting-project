# DATA_ENGINEERING_HARDENING.md

## Phase 5: Data Engineering Hardening & Reliability Assessment

**Document Version:** 1.0  
**Date Created:** 2026-09-02  
**Status:** Architecture review complete; recommendations proposed; implementation pending

---

## Executive Summary

This document audits the current data engineering approach and proposes hardening recommendations to improve reliability, completeness, and maintainability. Key findings:

1. **Current Incremental Strategy:** Reasonable baseline using timestamp-based watermarking on `sale_date`
2. **Primary Risk:** Late-arriving or corrected data may be missed in incremental runs
3. **Recommended Hardening:** Rolling window reprocessing + reconciliation checks
4. **Overall Assessment:** Solid for a portfolio project; would require enhancement for production

---

## Part 1: Current Architecture Review

### Component 1.1 — Extract Layer (Azure SQL → Snowflake RAW)

**Current Design:**
- Location: `scripts/extract_azure_to_snowflake.py`
- Pattern: Date-partitioned extraction (one logical date per Airflow run)
- Strategy: Daily extraction simulates freshness; in backfill mode processes historical dates
- Execution: Airflow DAG `m5_daily_extract` with manual trigger (schedule=None)

**Key Features:**
```
- Extract window: Single day (context['ds'] logical date)
- Three tables extracted: CALENDAR, SALES_TRAIN, SELL_PRICES
- Connection: Azure SQL ← → Snowflake RAW schema
- Error handling: Retry logic for Azure SQL cold-start (40613/40197 errors)
- Validation: verify_one_day task confirms row counts post-extract
```

**Assessment:** ✅ **SOLID**

- Manual scheduling is appropriate for portfolio demo (no auto-fire on unpause)
- Date-partitioned extraction clearly demarcates responsibilities
- Airflow verification catches most extract failures
- Error handling addresses known Azure SQL transient issues

**Recommendation:** KEEP AS-IS

---

### Component 1.2 — Staging Layer (RAW → STAGING)

**Current Design:**
```sql
-- stg_m5_sales_train.sql example
WITH source AS (
    SELECT * FROM {{ source('m5', 'SALES_TRAIN') }}
),
calendar AS (
    SELECT d, calendar_date FROM {{ ref('stg_m5_calendar') }}
),
joined AS (
    SELECT
        s.id, s.item_id, s.dept_id, s.cat_id, s.store_id, s.state_id, s.d,
        c.calendar_date AS sale_date,
        s.sales AS units_sold
    FROM source AS s
    LEFT JOIN calendar AS c ON s.d = c.d
)
SELECT * FROM joined
```

**Materialization:** VIEW (not table)

**Assessment:** ⚠️ **CAUTION — ASYMMETRY RISK**

**Issue:** Staging models are views (ephemeral computation), not materialized tables. This means:
1. Each downstream reference re-computes the join
2. No staging table row count to validate against source
3. dbt DAG run time couples staging logic to warehouse model execution
4. Harder to debug data issues (can't query staging schema directly for intermediate state)

**Recommendation:** UPGRADE staging models to VIEWS → TABLES

**Rationale:**
- Views are memory-efficient but create coupling
- Materializing staging as tables enables:
  - Direct Snowflake queries for debugging
  - Explicit validation of 1:1 source→staging transformation
  - Parallelization (warehouse models don't depend on real-time staging computation)
  - Staging layer included in dbt test suite (currently implicit)

**Proposed Change:**
```sql
{{ config(
    materialized='table',
    schema='staging'
) }}

-- Same logic as before
WITH source AS (
    SELECT * FROM {{ source('m5', 'SALES_TRAIN') }}
),
...
```

**Expected Impact:**
- Incremental warehouse build: ~5s faster (less re-computation)
- Debugging: Direct queries into STAGING schema
- Testing: Staging row counts validated explicitly
- Maintenance: Clearer data lineage in dbt DAG visualization

---

### Component 1.3 — Intermediate Layer (STAGING → INTERMEDIATE)

**Current Design:**
```sql
-- int_sales_with_prices.sql
WITH sales AS (
    SELECT * FROM {{ ref('stg_m5_sales_train') }}
),
prices AS (
    SELECT * FROM {{ ref('stg_m5_sell_prices') }}
),
calendar AS (
    SELECT d, wm_yr_wk FROM {{ ref('stg_m5_calendar') }}
),
sales_with_week AS (
    SELECT sales.*, calendar.wm_yr_wk
    FROM sales
    LEFT JOIN calendar ON sales.d = calendar.d
),
joined AS (
    SELECT ... prices ... revenue_amount_usd
    FROM sales_with_week
    LEFT JOIN prices ON (store, item, week match)
)
SELECT * FROM joined
```

**Materialization:** TABLE (incremental) — assumes upstream (staging) is complete

**Assessment:** ⚠️ **INHERITS STAGING RISK**

Because staging is a view, intermediate layer's incremental strategy assumes complete data every run. If staging has gaps or inconsistencies, they propagate downstream.

**Recommendation:** Address staging materialization first (above); then intermediate model is solid

---

### Component 1.4 — Warehouse Layer: fact_daily_sales Incremental Strategy

**Current Design:**
```sql
{{ config(
    materialized='incremental',
    unique_key='sale_key',
    cluster_by=['sale_date'],
    on_schema_change='fail'
) }}

WITH source AS (
    SELECT ... FROM {{ ref('int_sales_with_prices') }}
    
    {% if is_incremental() %}
        WHERE sale_date > (
            SELECT COALESCE(MAX(sale_date), '1900-01-01')
            FROM {{ this }}
        )
    {% endif %}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(...) }} AS sale_key,
        ... other columns ...
    FROM source
)

SELECT * FROM final
```

**Strategy:** Timestamp-based watermarking on `sale_date` column

**How It Works:**

1. **First run (full load):** No `is_incremental()` block → entire dataset inserted
2. **Subsequent runs (incremental):** Only rows with `sale_date > MAX(sale_date)` in table merged in
3. **Merge behavior:** dbt + Snowflake handles INSERT (new dates) and UPDATE (corrected quantities for existing dates)

**Assessment:** ⚠️ **GOOD BUT INCOMPLETE**

**Strengths:**
- ✅ Reduces dbt run time (processes ~1 day vs. ~58M rows)
- ✅ Appropriate clustering on `sale_date` improves query performance
- ✅ Unique key properly enforced (dbt merge includes update logic)
- ✅ `on_schema_change='fail'` prevents silent corruption from schema drift

**Weaknesses:**
- ⚠️ **Late-arriving data risk:** If a sale from 2 days ago is uploaded today, the watermark already passed it
- ⚠️ **Corrected records risk:** If Azure SQL updates a past record (e.g., "customer returned item"), the update won't be captured (only checks date, not update timestamp)
- ⚠️ **No reconciliation:** No daily check that incremental row count matches expected new records from extract

**Real-World Scenario Where This Fails:**
```
Day 1 (2016-06-15 data):
  - Extract: 150 items × 10 stores = 1,500 new rows
  - dbt fact: 1,500 new rows inserted → MAX(sale_date) = 2016-06-15

Day 2 (2016-06-16 data):
  - Extract: 1,500 new rows for 2016-06-16
  - But ALSO: A prior store corrected yesterday's inventory (quantity change for 1 item)
  - Azure SQL updated SALES_TRAIN[sale_date=2016-06-15, item=X, store=Y] quantity from 42 → 41
  - dbt staging pulls from RAW.SALES_TRAIN which now has quantity=41
  - dbt fact incremental filter: WHERE sale_date > '2016-06-15' → misses the corrected 2016-06-15 row
  - Result: fact_daily_sales has outdated quantity for item X, store Y on 2016-06-15
```

---

## Part 2: Recommended Hardening Strategies

### Strategy A: Rolling Window Reprocessing (RECOMMENDED for this project)

**Concept:** Always reprocess the last N days, even in incremental runs, to catch late-arriving and corrected records.

**Implementation:**
```sql
{{ config(
    materialized='incremental',
    unique_key='sale_key',
    cluster_by=['sale_date'],
    on_schema_change='fail'
) }}

WITH source AS (
    SELECT ... FROM {{ ref('int_sales_with_prices') }}
    
    {% if is_incremental() %}
        -- Reprocess last 7 days in addition to new data
        WHERE sale_date > (
            SELECT COALESCE(DATEADD(DAY, -7, MAX(sale_date)), '1900-01-01')
            FROM {{ this }}
        )
    {% endif %}
),
final AS (
    SELECT {{ dbt_utils.generate_surrogate_key(...) }} AS sale_key, ...
    FROM source
)

SELECT * FROM final
```

**Pros:**
- ✅ Catches late arrivals and corrected records within 7-day window
- ✅ Minimal performance impact (reprocess ~10,500 rows vs. 58M rows = 99.98% savings vs. full rebuild)
- ✅ Simple to implement (one-line change)
- ✅ No schema changes needed
- ✅ Works with existing dbt merge logic

**Cons:**
- ⚠️ Deletes and re-inserts 7 days of data on every run (more I/O than append-only)
- ⚠️ Assumes late data arrives within 7 days (must document assumption)
- ⚠️ Doesn't prevent issues older than 7 days

**Window Size Rationale:**
- M5 dataset: Portfolio project, not real-time pipeline
- Recommended: 7-day window (balances catch window vs. re-computation cost)
- Could be tuned to `DATEADD(DAY, -3, MAX(sale_date))` if performance critical

**Recommendation:** ✅ **IMPLEMENT THIS** for Phase 5

---

### Strategy B: Add `_EXTRACT_TS` Updated Timestamp Column

**Concept:** Track when each record was last loaded/updated; increment logic becomes smarter.

**Current Limitation:** Staging models have no updated_timestamp, only date columns.

**Enhancement:**
```sql
-- In staging model: stg_m5_sales_train.sql
WITH source AS (
    SELECT *,
           CURRENT_TIMESTAMP() AS _EXTRACT_TS  -- Add load timestamp
    FROM {{ source('m5', 'SALES_TRAIN') }}
)
```

**Then in warehouse:**
```sql
{% if is_incremental() %}
    WHERE _EXTRACT_TS > (
        SELECT COALESCE(MAX(_EXTRACT_TS), '1900-01-01')
        FROM {{ this }}
    )
{% endif %}
```

**Pros:**
- ✅ Precise tracking of when records were updated
- ✅ Enables true "extract once" append-only pattern (vs. re-processing)
- ✅ Better for high-frequency pipelines

**Cons:**
- ⚠️ Requires schema changes to staging models
- ⚠️ Adds complexity (timestamp transformation, timezone assumptions)
- ⚠️ Requires coordination with extract script (Python script must set `_EXTRACT_TS`)
- ⚠️ Not necessary for portfolio project (M5 data is static historical)

**Recommendation:** ⏭️ **DEFER TO LATER PHASE** (not critical for portfolio)

---

### Strategy C: Reconciliation Checks (dbt Test)

**Concept:** Add a dbt test that validates incremental row counts vs. extraction expectations.

**Implementation:**
Create `dbt/tests/data_tests/fact_daily_sales_incremental_check.sql`:

```sql
-- Validates that fact_daily_sales incremental load captured expected row count
-- based on extract verification data (tracked in WAREHOUSE.EXTRACT_LOG)
-- 
-- This test is informational and will be skipped if EXTRACT_LOG doesn't exist.
-- Can be run after dbt build to audit data completeness.

SELECT
    'FACT_DAILY_SALES_INCREMENTAL_CHECK' AS test_name,
    COALESCE(COUNT(*), 0) AS actual_fact_rows,
    COALESCE(MAX(extract_expected_rows), 0) AS expected_from_extract,
    CASE
        WHEN COUNT(*) >= MAX(extract_expected_rows) * 0.95 -- Allow 5% variance
        THEN 'PASS'
        ELSE 'WARNING: Low row count variance'
    END AS status
FROM WAREHOUSE.FACT_DAILY_SALES f
LEFT JOIN WAREHOUSE.EXTRACT_LOG e ON f.sale_date = e.extraction_date
WHERE f.sale_date = CURRENT_DATE() - INTERVAL '1 DAY'
    OR f.sale_date = (SELECT MAX(sale_date) FROM WAREHOUSE.FACT_DAILY_SALES)
GROUP BY 1
HAVING actual_fact_rows < expected_from_extract * 0.95 -- Fail only if variance > 5%
```

**Pros:**
- ✅ Automated check catches data loss
- ✅ Integrated into dbt workflow
- ✅ Can alert on variance > threshold

**Cons:**
- ⚠️ Requires EXTRACT_LOG table (meta-tracking)
- ⚠️ Adds complexity
- ⚠️ Only works if extract script tracks expected row counts

**Recommendation:** 🔶 **OPTIONAL** (implement after rolling window is working)

---

## Part 3: dbt Test Coverage Assessment

### Current Test Suite

**Dimension Tests (dim_calendar, dim_item, dim_store):**
- ✅ Surrogate key uniqueness (unique_key)
- ✅ Natural key uniqueness
- ✅ Non-null constraints on critical columns
- ✅ NOT NULL on foreign keys (in fact table)
- ✅ SNAP indicator tests with date filters

**Fact Table Tests (fact_daily_sales):**
- ✅ Unique combination of (item_id, store_id, sale_date) — grain validation
- ✅ Surrogate key uniqueness (sale_key)
- ✅ Foreign key relationships to all three dimensions
- ✅ Range checks on units_sold (≥ 0)
- ✅ NOT NULL on critical columns
- ❌ NOT NULL on optional columns (sell_price correctly nullable)

**Forecast Fact Tests (fact_forecast_daily):**
- ✅ Unique combination of (item_id, forecast_date) — grain validation
- ⚠️ Relationships test SKIPPED on date_key (forecast dates aren't in calendar)

**Missing Test Categories:**
- ⚠️ Row count consistency between layers (staging → intermediate → warehouse)
- ⚠️ Price sparsity validation (% nulls acceptable)
- ⚠️ Freshness check (do facts have data for most recent date in calendar?)

### Assessment: ⚠️ **GOOD BUT INCOMPLETE**

**Strengths:**
- ✅ Grain is well-defined and tested
- ✅ Foreign key integrity enforced
- ✅ Critical business constraints validated (non-negative sales, etc.)

**Gaps:**
- ⚠️ No cross-model consistency tests
- ⚠️ No data freshness test (e.g., "fact table should have yesterday's data")
- ⚠️ No price availability test (acceptable null % in sell_price)

### Recommended Test Additions

**Test 1: Row Count Consistency**
```sql
-- dbt/tests/data_tests/staging_to_warehouse_row_count.sql
-- Validates that staging and warehouse row counts align (within acceptable variance)

WITH staging_count AS (
    SELECT COUNT(*) AS rows FROM STAGING.STG_M5_SALES_TRAIN
),
warehouse_count AS (
    SELECT COUNT(*) AS rows FROM WAREHOUSE.FACT_DAILY_SALES
)
SELECT
    s.rows AS staging_rows,
    w.rows AS warehouse_rows,
    ROUND(100.0 * w.rows / s.rows, 2) AS coverage_percent
FROM staging_count s
CROSS JOIN warehouse_count w
WHERE ROUND(100.0 * w.rows / s.rows, 2) < 95.0  -- Fail if < 95% coverage
```

**Test 2: Data Freshness**
```sql
-- dbt/tests/data_tests/fact_daily_sales_freshness.sql
-- Validates that fact table has data for most recent available date in calendar

SELECT
    f.max_fact_date,
    c.max_calendar_date,
    DATEDIFF(DAY, f.max_fact_date, c.max_calendar_date) AS days_lag
FROM (SELECT MAX(sale_date) AS max_fact_date FROM WAREHOUSE.FACT_DAILY_SALES) f
CROSS JOIN (SELECT MAX(calendar_date) AS max_calendar_date FROM WAREHOUSE.DIM_CALENDAR) c
WHERE DATEDIFF(DAY, f.max_fact_date, c.max_calendar_date) > 1  -- Fail if > 1 day lag
```

**Test 3: Price Sparsity Validation**
```sql
-- dbt/tests/data_tests/sell_price_sparsity_acceptable.sql
-- Validates that price null % is within acceptable bounds (30-70%)

WITH price_stats AS (
    SELECT
        COUNT(*) AS total_rows,
        SUM(CASE WHEN sell_price IS NULL THEN 1 ELSE 0 END) AS null_prices,
        ROUND(100.0 * SUM(CASE WHEN sell_price IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent
    FROM WAREHOUSE.FACT_DAILY_SALES
)
SELECT * FROM price_stats
WHERE null_percent NOT BETWEEN 25 AND 75  -- Fail if outside 25-75% null range
```

**Recommendation:** ✅ **ADD THESE 3 TESTS** to dbt/tests/data_tests/

---

## Part 4: Airflow DAG Verification Assessment

### Current Verification Strategy

**Verification Points:**
1. ✅ `verify_one_day` — Confirms RAW tables received expected rows
2. ✅ `verify_dbt_one_day` — Confirms STAGING/INTERMEDIATE/WAREHOUSE updated
3. ⚠️ No explicit reconciliation between extract and warehouse counts

### Assessment: ✅ **SOLID BUT COULD STRENGTHEN**

**Strengths:**
- ✅ Two independent verification tasks (doesn't rely on extract/dbt reporting)
- ✅ Queries Snowflake directly for source-of-truth validation
- ✅ Failures surface as red squares in Airflow Grid (easy to see)
- ✅ Batched SQL queries (efficient single round-trip)

**Weaknesses:**
- ⚠️ Verification only checks for `> 0` rows, not exact counts
- ⚠️ No comparison of extract vs. warehouse row counts
- ⚠️ No alert if warehouse row count differs from extract by > 5%

### Recommended Enhancement

**Add Reconciliation Task:**
```python
@task(task_id="reconcile_extract_vs_warehouse")
def reconcile_extract_vs_warehouse(**context) -> str:
    """Validate that extract row counts match warehouse incremental adds.
    
    Checks:
      1. RAW table row count for run_date
      2. WAREHOUSE.FACT_DAILY_SALES new row count for same run_date
      3. Fail if warehouse count < extract count * 0.95 (allow 5% variance)
    """
    run_date: str = context["ds"]
    log = logging.getLogger("airflow.task")
    
    import extract_azure_to_snowflake as extractor
    
    sql = """
    WITH extract_counts AS (
        SELECT
            COUNT(*) as raw_rows
        FROM RAW.M5_SALES_TRAIN
        WHERE sale_date = %s
    ),
    warehouse_counts AS (
        SELECT
            COUNT(*) as fact_rows
        FROM WAREHOUSE.FACT_DAILY_SALES
        WHERE sale_date = %s
    )
    SELECT
        e.raw_rows,
        w.fact_rows,
        CASE WHEN w.fact_rows >= e.raw_rows * 0.95 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM extract_counts e
    CROSS JOIN warehouse_counts w
    """
    
    conn = extractor.connect_snowflake()
    try:
        cur = conn.cursor()
        cur.execute(sql, (run_date, run_date))
        raw_rows, fact_rows, status = cur.fetchone()
    finally:
        conn.close()
    
    log.info(f"Reconciliation for {run_date}: extract={raw_rows}, warehouse={fact_rows}, status={status}")
    
    if status != 'PASS':
        raise RuntimeError(f"Reconciliation failed: extract {raw_rows} rows but warehouse only {fact_rows}")
    
    return f"reconciliation passed: {raw_rows} rows"
```

**Placement in DAG:**
```
extract_one_day → verify_one_day → [dbt_models] → verify_dbt_one_day → reconcile_extract_vs_warehouse
                                                                      ↓
                                                         [success/failure flag]
```

**Recommendation:** 🔶 **OPTIONAL** (implement after rolling window works)

---

## Part 5: Azure SQL Extract Strategy Assessment

### Current Extract Pattern

**Location:** `scripts/extract_azure_to_snowflake.py`

**Key Design:**
- Extracts single day per run (date-partitioned)
- Uses `dbt_d_code` → `calendar_date` mapping
- Loads into RAW schema (landing zone)
- No updates to Azure SQL (read-only)
- Error handling: Retry on Azure cold-start (40613/40197)

### Assessment: ✅ **GOOD**

**Strengths:**
- ✅ Read-only prevents accidental updates
- ✅ Date-partitioned extraction is clear and debuggable
- ✅ Error handling reasonable for cloud databases
- ✅ Staging models layer handles transformation

**Potential Enhancements:**
- ⚠️ Could add checksums to detect corruption mid-transfer
- ⚠️ Could log row counts to WAREHOUSE.EXTRACT_LOG for reconciliation
- ⚠️ Could validate no negative values in source (early data quality check)

**Recommendation:** ✅ **KEEP AS-IS** (enhancements non-critical for portfolio)

---

## Part 6: Implementation Plan for Phase 5

### Task 5.1 — Materialize Staging Models to TABLES ✅ **HIGH PRIORITY**

**Work:**
1. Modify `dbt/models/staging/stg_m5_*.sql` files
2. Change from VIEW to TABLE materialization
3. Add dbt/tests/data_tests/staging_row_count_check.sql
4. Run dbt test to validate new materialization
5. Commit changes

**Expected Outcome:**
- Staging models physically persisted in Snowflake
- Direct Snowflake queries now possible for debugging
- Staging layer included in dbt lineage

**Time Estimate:** 30 minutes

---

### Task 5.2 — Implement Rolling Window Reprocessing ✅ **HIGH PRIORITY**

**Work:**
1. Modify `dbt/models/warehouse/fact_daily_sales.sql`
2. Change incremental filter to: `WHERE sale_date > DATEADD(DAY, -7, (SELECT MAX(...)))`
3. Document assumption: "Late data expected within 7 days"
4. Run full dbt build; validate no regressions
5. Commit changes

**Expected Outcome:**
- fact_daily_sales now catches late arrivals and corrections within 7 days
- Incremental performance impact minimal (~0.1% increase per run)

**Time Estimate:** 15 minutes

---

### Task 5.3 — Add Three Recommended dbt Tests 🔶 **MEDIUM PRIORITY**

**Work:**
1. Create `dbt/tests/data_tests/staging_to_warehouse_row_count.sql`
2. Create `dbt/tests/data_tests/fact_daily_sales_freshness.sql`
3. Create `dbt/tests/data_tests/sell_price_sparsity_acceptable.sql`
4. Run dbt test to validate new tests
5. Document expected results in DATA_QUALITY.md
6. Commit changes

**Expected Outcome:**
- Automated checks for data consistency, freshness, sparsity
- Tests fail fast if data quality issues occur

**Time Estimate:** 20 minutes

---

### Task 5.4 — Document Phase 5 Decisions 📝 **REQUIRED**

**Work:**
1. Create `docs/DATA_ENGINEERING_DECISIONS.md`
2. Document rolling window strategy and rationale
3. Document staging materialization decision
4. Document test strategy
5. Link from README.md

**Expected Outcome:**
- Clear rationale for engineering choices
- Interview-defensible decisions documented

**Time Estimate:** 15 minutes

---

## Part 7: Summary & Recommendations

### Overall Assessment

| Component | Current State | Risk Level | Recommendation |
|---|---|---|---|
| Extract Layer | Strong | LOW | Keep as-is |
| Staging Layer | Views (not materialized) | MEDIUM | Upgrade to TABLES |
| Intermediate Layer | Incremental TABLE | LOW (after staging fix) | Keep as-is |
| Warehouse: fact_daily_sales | Timestamp watermark | HIGH | Add 7-day rolling window |
| dbt Tests | Comprehensive but gaps | MEDIUM | Add 3 recommended tests |
| Airflow Verification | Good but basic | MEDIUM | Optional: add reconciliation |

### Implementation Priority

**MUST DO (Phase 5):**
1. ✅ Task 5.1 — Materialize staging models
2. ✅ Task 5.2 — Implement rolling window
3. ✅ Task 5.4 — Document decisions

**SHOULD DO (Phase 5 or 6):**
4. 🔶 Task 5.3 — Add 3 dbt tests

**NICE TO HAVE (Future):**
5. ⏭️ Add EXTRACT_LOG meta-tracking
6. ⏭️ Add Airflow reconciliation task
7. ⏭️ Add checksums to extract

### Estimated Effort

- Total implementation time: ~1.5 hours
- Testing/validation: ~30 minutes
- Documentation: ~30 minutes
- **Total Phase 5: ~2.5 hours**

---

## References

- [DATA_CONTRACT.md](DATA_CONTRACT.md) — Data grain specifications
- [DATA_QUALITY.md](DATA_QUALITY.md) — Quality checks framework
- dbt Incremental Models: https://docs.getdbt.com/docs/build/incremental-models
- Snowflake Incremental Merge: https://docs.snowflake.com/en/sql-reference/sql/merge
