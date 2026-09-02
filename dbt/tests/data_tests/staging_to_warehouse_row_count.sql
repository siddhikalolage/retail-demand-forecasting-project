-- dbt/tests/data_tests/staging_to_warehouse_row_count.sql
-- 
-- Validates that staging and warehouse row counts align (within acceptable variance).
-- Fails if warehouse coverage < 95% of staging.
--
-- Purpose: Catches data loss during transformation from staging to warehouse.
--
-- Expected behavior:
--   - Staging and warehouse should have nearly identical row counts
--   - Allow 5% variance for data quality filtering (if any is applied)
--   - Fail if variance > 5% (indicates missing data)

WITH staging_count AS (
    SELECT COUNT(*) AS rows FROM {{ ref('stg_m5_sales_train') }}
),
warehouse_count AS (
    SELECT COUNT(*) AS rows FROM {{ ref('fact_daily_sales') }}
),
comparison AS (
    SELECT
        s.rows AS staging_rows,
        w.rows AS warehouse_rows,
        ROUND(100.0 * w.rows / NULLIF(s.rows, 0), 2) AS coverage_percent
    FROM staging_count s
    CROSS JOIN warehouse_count w
)
SELECT
    staging_rows,
    warehouse_rows,
    coverage_percent
FROM comparison
WHERE coverage_percent < 95.0  -- Fail if < 95% coverage
