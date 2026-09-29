-- Read-only quality profile for the current RETAIL_DB pipeline.
-- Run each query independently in Snowsight after the Azure extraction and dbt build.
-- The checks deliberately use the long-format RAW.SALES_TRAIN source and
-- conformed WAREHOUSE/MARTS objects; no obsolete DEV schema or pivoted source
-- table names are referenced.

USE DATABASE RETAIL_DB;
USE WAREHOUSE WH_RETAIL;

-- 1. Raw calendar: valid date conversion and unique M5 day keys.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT d) AS distinct_day_keys,
    MIN(TRY_TO_DATE(date)) AS first_date,
    MAX(TRY_TO_DATE(date)) AS last_date,
    COUNT_IF(TRY_TO_DATE(date) IS NULL) AS invalid_date_count
FROM RAW.CALENDAR;

-- 2. Raw sales: expected series x day grain and unit validity.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT id || '|' || d) AS distinct_series_day_keys,
    COUNT_IF(sales < 0) AS negative_unit_rows,
    COUNT_IF(sales IS NULL) AS null_unit_rows,
    COUNT(DISTINCT item_id) AS item_count,
    COUNT(DISTINCT store_id) AS store_count
FROM RAW.SALES_TRAIN;

-- 3. Raw prices: weekly item-store uniqueness and valid non-negative prices.
SELECT
    COUNT(*) AS row_count,
    COUNT(DISTINCT store_id || '|' || item_id || '|' || wm_yr_wk) AS distinct_price_keys,
    COUNT_IF(sell_price < 0) AS negative_price_rows,
    COUNT_IF(sell_price IS NULL) AS null_price_rows,
    MIN(sell_price) AS minimum_price,
    MAX(sell_price) AS maximum_price
FROM RAW.SELL_PRICES;

-- 4. Conformed daily fact: sales coverage, totals and price sparsity.
SELECT
    COUNT(*) AS row_count,
    MIN(sale_date) AS first_sale_date,
    MAX(sale_date) AS last_sale_date,
    SUM(units_sold) AS total_units,
    SUM(revenue_amount_usd) AS total_revenue_usd,
    COUNT_IF(sell_price IS NULL) AS missing_price_rows
FROM WAREHOUSE.FACT_DAILY_SALES;

-- 5. Forecast facts: forecast horizon and interval validity.
SELECT
    COUNT(*) AS row_count,
    MIN(forecast_date) AS first_forecast_date,
    MAX(forecast_date) AS last_forecast_date,
    COUNT(DISTINCT item_id) AS item_count,
    COUNT_IF(forecast_units < 0) AS negative_forecast_rows,
    COUNT_IF(forecast_units_lower_95 > forecast_units_upper_95) AS invalid_interval_rows
FROM WAREHOUSE.FACT_FORECAST_DAILY;

-- 6. Actual-vs-forecast reporting mart: grain by series type.
SELECT
    series_type,
    COUNT(*) AS row_count,
    COUNT(DISTINCT item_id || '|' || observation_date) AS distinct_item_date_keys,
    MIN(observation_date) AS first_observation_date,
    MAX(observation_date) AS last_observation_date
FROM MARTS.MART_FORECAST_VS_ACTUAL
GROUP BY series_type
ORDER BY series_type;
