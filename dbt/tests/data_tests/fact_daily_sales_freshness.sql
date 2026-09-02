-- dbt/tests/data_tests/fact_daily_sales_freshness.sql
-- 
-- Validates that fact table has data for most recent available date in calendar.
-- Fails if fact table lags calendar by more than 1 day.
--
-- Purpose: Catches if incremental loads have stalled or data hasn't been extracted.
--
-- Expected behavior:
--   - fact_daily_sales.max_date should equal or nearly equal calendar.max_date
--   - Allow 1 day lag (data extracted today for yesterday's business)
--   - Fail if lag > 1 day (suggests extraction/dbt load issue)

WITH fact_max_date AS (
    SELECT MAX(sale_date) AS max_fact_date FROM {{ ref('fact_daily_sales') }}
),
calendar_max_date AS (
    SELECT MAX(calendar_date) AS max_calendar_date FROM {{ ref('dim_calendar') }}
),
comparison AS (
    SELECT
        f.max_fact_date,
        c.max_calendar_date,
        DATEDIFF(DAY, f.max_fact_date, c.max_calendar_date) AS days_lag
    FROM fact_max_date f
    CROSS JOIN calendar_max_date c
)
SELECT
    max_fact_date,
    max_calendar_date,
    days_lag
FROM comparison
WHERE days_lag > 1  -- Fail if lag > 1 day (indicates stale data)
