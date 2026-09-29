-- Verification for MARTS.AGG_SALES_DAILY.
-- Run after `dbt build --select agg_sales_daily`.
-- The aggregate is keyed by DATE_KEY, so every check reconciles to the
-- corresponding grain in the current fact.

USE DATABASE RETAIL_DB;
USE WAREHOUSE WH_RETAIL;

-- 1. Full-table unit and revenue parity.
SELECT
    'units' AS measure,
    (SELECT SUM(total_units_sold) FROM MARTS.AGG_SALES_DAILY) AS aggregate_total,
    (SELECT SUM(units_sold) FROM WAREHOUSE.FACT_DAILY_SALES) AS fact_total
UNION ALL
SELECT
    'revenue',
    (SELECT SUM(total_revenue_usd) FROM MARTS.AGG_SALES_DAILY),
    (SELECT SUM(revenue_amount_usd) FROM WAREHOUSE.FACT_DAILY_SALES);

-- 2. One row per date key and coverage parity with the fact.
SELECT
    (SELECT COUNT(*) FROM MARTS.AGG_SALES_DAILY) AS aggregate_rows,
    (SELECT COUNT(DISTINCT date_key) FROM MARTS.AGG_SALES_DAILY) AS aggregate_distinct_dates,
    (SELECT COUNT(DISTINCT date_key) FROM WAREHOUSE.FACT_DAILY_SALES) AS fact_distinct_dates;

-- 3. Active-item and active-store parity for the most recent fact date.
WITH sample_date AS (
    SELECT MAX(date_key) AS date_key
    FROM WAREHOUSE.FACT_DAILY_SALES
),
aggregate_side AS (
    SELECT active_item_count, active_store_count
    FROM MARTS.AGG_SALES_DAILY
    WHERE date_key = (SELECT date_key FROM sample_date)
),
fact_side AS (
    SELECT
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id END) AS active_item_count,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END) AS active_store_count
    FROM WAREHOUSE.FACT_DAILY_SALES
    WHERE date_key = (SELECT date_key FROM sample_date)
)
SELECT
    aggregate_side.active_item_count AS aggregate_active_items,
    fact_side.active_item_count AS fact_active_items,
    aggregate_side.active_store_count AS aggregate_active_stores,
    fact_side.active_store_count AS fact_active_stores
FROM aggregate_side
CROSS JOIN fact_side;

-- 4. One-row health check. All columns should return PASS.
WITH checks AS (
    SELECT
        (SELECT SUM(total_units_sold) FROM MARTS.AGG_SALES_DAILY)
            = (SELECT SUM(units_sold) FROM WAREHOUSE.FACT_DAILY_SALES) AS units_parity,
        (SELECT SUM(total_revenue_usd) FROM MARTS.AGG_SALES_DAILY)
            = (SELECT SUM(revenue_amount_usd) FROM WAREHOUSE.FACT_DAILY_SALES) AS revenue_parity,
        (SELECT COUNT(*) FROM MARTS.AGG_SALES_DAILY)
            = (SELECT COUNT(DISTINCT date_key) FROM MARTS.AGG_SALES_DAILY) AS date_key_unique,
        (SELECT COUNT(*) FROM MARTS.AGG_SALES_DAILY)
            = (SELECT COUNT(DISTINCT date_key) FROM WAREHOUSE.FACT_DAILY_SALES) AS coverage_parity
)
SELECT
    IFF(units_parity, 'PASS', 'FAIL') AS units_parity,
    IFF(revenue_parity, 'PASS', 'FAIL') AS revenue_parity,
    IFF(date_key_unique, 'PASS', 'FAIL') AS date_key_unique,
    IFF(coverage_parity, 'PASS', 'FAIL') AS coverage_parity
FROM checks;
