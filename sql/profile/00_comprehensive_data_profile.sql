-- =============================================================================
-- sql/profile/00_comprehensive_data_profile.sql
-- =============================================================================
-- Phase 4 Data Profiling Queries
-- Validates all assumptions in docs/DATA_CONTRACT.md
-- 
-- Execute this against Snowflake RETAIL_DB.RAW schema
-- Results feed into docs/DATA_QUALITY.md
-- =============================================================================

-- ====== DIMENSION: CALENDARS ======
-- Validate calendar completeness and date range

SELECT 'Calendar Dimension' AS check_category,
       'Date Range' AS check_name,
       TO_VARCHAR(MIN(DATE)) AS result_min_date,
       TO_VARCHAR(MAX(DATE)) AS result_max_date,
       COUNT(*) AS total_days,
       COUNT(DISTINCT DATE) AS unique_days
FROM RAW.CALENDAR
;

-- Check for date gaps
WITH date_range AS (
    SELECT 
        MIN(DATE) AS min_date,
        MAX(DATE) AS max_date,
        DATEDIFF(DAY, min_date, max_date) + 1 AS expected_days
    FROM RAW.CALENDAR
)
SELECT 'Calendar Dimension' AS check_category,
       'Date Continuity' AS check_name,
       expected_days AS expected_day_count,
       (SELECT COUNT(*) FROM RAW.CALENDAR) AS actual_day_count,
       CASE 
           WHEN expected_days = (SELECT COUNT(*) FROM RAW.CALENDAR) 
           THEN 'PASS - No gaps'
           ELSE 'FAIL - Gaps detected'
       END AS status
FROM date_range
;

-- Calendar attributes validation
SELECT 'Calendar Dimension' AS check_category,
       'Attributes' AS check_name,
       COUNT(DISTINCT WEEKDAY) AS unique_weekdays,
       COUNT(DISTINCT MONTH) AS unique_months,
       COUNT(DISTINCT YEAR) AS unique_years,
       COUNT(DISTINCT WM_YR_WK) AS unique_walmart_weeks,
       SUM(CASE WHEN EVENT_NAME_1 IS NOT NULL THEN 1 ELSE 0 END) AS days_with_event_1,
       SUM(CASE WHEN EVENT_NAME_2 IS NOT NULL THEN 1 ELSE 0 END) AS days_with_event_2
FROM RAW.CALENDAR
;

-- ====== DIMENSION: ITEMS (PRODUCTS) ======

SELECT 'Item Dimension' AS check_category,
       'Item Counts' AS check_name,
       COUNT(DISTINCT ITEM_ID) AS unique_items,
       MIN(ITEM_ID) AS min_item_id,
       MAX(ITEM_ID) AS max_item_id,
       COUNT(*) AS total_rows
FROM RAW.M5_SALES_TRAIN
;

-- ====== DIMENSION: STORES ======

SELECT 'Store Dimension' AS check_category,
       'Store Counts' AS check_name,
       COUNT(DISTINCT STORE_ID) AS unique_stores,
       MIN(STORE_ID) AS min_store_id,
       MAX(STORE_ID) AS max_store_id,
       COUNT(*) AS total_rows
FROM RAW.M5_SALES_TRAIN
;

-- ====== FACT: SALES TRANSACTIONS ======
-- Validate grain, cardinality, and value distributions

SELECT 'Sales Fact' AS check_category,
       'Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) AS unique_keys,
       CASE 
           WHEN COUNT(*) = COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE))
           THEN 'PASS - Grain is Item × Store × Day'
           ELSE 'FAIL - Duplicates detected'
       END AS status
FROM RAW.M5_SALES_TRAIN
;

-- Sales value distribution
SELECT 'Sales Fact' AS check_category,
       'Sales Values' AS check_name,
       MIN(SALES) AS min_sales,
       MAX(SALES) AS max_sales,
       AVG(SALES) AS avg_sales,
       STDDEV(SALES) AS stddev_sales,
       SUM(CASE WHEN SALES < 0 THEN 1 ELSE 0 END) AS negative_sales_count,
       SUM(CASE WHEN SALES = 0 THEN 1 ELSE 0 END) AS zero_sales_count,
       SUM(CASE WHEN SALES IS NULL THEN 1 ELSE 0 END) AS null_sales_count
FROM RAW.M5_SALES_TRAIN
;

-- Sales date range
SELECT 'Sales Fact' AS check_category,
       'Date Range' AS check_name,
       TO_VARCHAR(MIN(DATE)) AS min_date,
       TO_VARCHAR(MAX(DATE)) AS max_date,
       COUNT(DISTINCT DATE) AS unique_dates,
       DATEDIFF(DAY, MIN(DATE), MAX(DATE)) + 1 AS expected_date_span
FROM RAW.M5_SALES_TRAIN
;

-- Sales completeness (store × item × date coverage)
WITH expected_combos AS (
    SELECT COUNT(DISTINCT STORE_ID) * COUNT(DISTINCT ITEM_ID) * COUNT(DISTINCT DATE) AS total_possible_combos
    FROM RAW.M5_SALES_TRAIN
)
SELECT 'Sales Fact' AS check_category,
       'Completeness' AS check_name,
       (SELECT total_possible_combos FROM expected_combos) AS expected_rows,
       COUNT(*) AS actual_rows,
       ROUND(100.0 * COUNT(*) / (SELECT total_possible_combos FROM expected_combos), 2) AS coverage_percent
FROM RAW.M5_SALES_TRAIN
;

-- ====== DIMENSION: PRICES ======
-- Validate price data grain and coverage

SELECT 'Price Data' AS check_category,
       'Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || WM_YR_WK)) AS unique_keys,
       CASE 
           WHEN COUNT(*) = COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || WM_YR_WK))
           THEN 'PASS - Grain is Item × Store × Week'
           ELSE 'FAIL - Duplicates detected'
       END AS status
FROM RAW.SELL_PRICES
;

-- Price value distribution
SELECT 'Price Data' AS check_category,
       'Price Values' AS check_name,
       COUNT(*) AS total_rows,
       SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) AS null_prices,
       MIN(SELL_PRICE) AS min_price,
       MAX(SELL_PRICE) AS max_price,
       AVG(SELL_PRICE) AS avg_price,
       SUM(CASE WHEN SELL_PRICE < 0 THEN 1 ELSE 0 END) AS negative_price_count,
       SUM(CASE WHEN SELL_PRICE = 0 THEN 1 ELSE 0 END) AS zero_price_count
FROM RAW.SELL_PRICES
;

-- Price coverage (what % of item × store × week combos have prices)
WITH max_combos AS (
    SELECT 
        COUNT(DISTINCT STORE_ID) AS store_count,
        COUNT(DISTINCT ITEM_ID) AS item_count,
        COUNT(DISTINCT WM_YR_WK) AS week_count
    FROM RAW.SELL_PRICES
)
SELECT 'Price Data' AS check_category,
       'Coverage' AS check_name,
       (SELECT store_count * item_count * week_count FROM max_combos) AS max_possible_rows,
       COUNT(*) AS actual_rows,
       ROUND(100.0 * COUNT(*) / (SELECT store_count * item_count * week_count FROM max_combos), 2) AS coverage_percent
FROM RAW.SELL_PRICES
;

-- ====== DATA QUALITY: ANOMALIES ======

SELECT 'Data Quality' AS check_category,
       'Negative or Zero Sales' AS check_name,
       COUNT(*) AS anomaly_count,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM RAW.M5_SALES_TRAIN), 2) AS percent_of_total
FROM RAW.M5_SALES_TRAIN
WHERE SALES <= 0
;

SELECT 'Data Quality' AS check_category,
       'NULL Sales Values' AS check_name,
       COUNT(*) AS anomaly_count,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM RAW.M5_SALES_TRAIN), 2) AS percent_of_total
FROM RAW.M5_SALES_TRAIN
WHERE SALES IS NULL
;

SELECT 'Data Quality' AS check_category,
       'NULL Price Values' AS check_name,
       COUNT(*) AS anomaly_count,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM RAW.SELL_PRICES), 2) AS percent_of_total
FROM RAW.SELL_PRICES
WHERE SELL_PRICE IS NULL
;

-- ====== STAGING LAYER VALIDATION ======
-- These queries validate the transformation at the staging layer

SELECT 'Staging Layer' AS check_category,
       'stg_m5_sales_train' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) AS unique_keys,
       SUM(CASE WHEN SALES IS NULL THEN 1 ELSE 0 END) AS null_count
FROM DEV.STAGING.STG_M5_SALES_TRAIN
;

SELECT 'Staging Layer' AS check_category,
       'stg_m5_calendar' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT DATE) AS unique_dates
FROM DEV.STAGING.STG_M5_CALENDAR
;

SELECT 'Staging Layer' AS check_category,
       'stg_m5_sell_prices' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || WM_YR_WK)) AS unique_keys,
       SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) AS null_prices
FROM DEV.STAGING.STG_M5_SELL_PRICES
;

-- ====== INTERMEDIATE LAYER VALIDATION ======

SELECT 'Intermediate Layer' AS check_category,
       'int_sales_with_prices' AS check_name,
       COUNT(*) AS row_count,
       SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) AS null_prices,
       MIN(DATE) AS min_date,
       MAX(DATE) AS max_date
FROM DEV.INTERMEDIATE.INT_SALES_WITH_PRICES
;

SELECT 'Intermediate Layer' AS check_category,
       'int_forecast_input Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT ITEM_ID) AS unique_items,
       COUNT(DISTINCT DATE) AS unique_dates,
       (SELECT COUNT(DISTINCT ITEM_ID) FROM DEV.INTERMEDIATE.INT_FORECAST_INPUT) * 
       (SELECT COUNT(DISTINCT DATE) FROM DEV.INTERMEDIATE.INT_FORECAST_INPUT) AS expected_dense_rows
FROM DEV.INTERMEDIATE.INT_FORECAST_INPUT
;

SELECT 'Intermediate Layer' AS check_category,
       'int_forecast_input Values' AS check_name,
       MIN(AGGREGATE_SALES) AS min_agg_sales,
       MAX(AGGREGATE_SALES) AS max_agg_sales,
       AVG(AGGREGATE_SALES) AS avg_agg_sales,
       SUM(CASE WHEN AGGREGATE_SALES < 0 THEN 1 ELSE 0 END) AS negative_count,
       SUM(CASE WHEN AGGREGATE_SALES IS NULL THEN 1 ELSE 0 END) AS null_count
FROM DEV.INTERMEDIATE.INT_FORECAST_INPUT
;

-- ====== WAREHOUSE LAYER VALIDATION ======

SELECT 'Warehouse Layer' AS check_category,
       'dim_calendar' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT DATE_ID) AS unique_keys,
       MIN(DATE) AS min_date,
       MAX(DATE) AS max_date
FROM DEV.WAREHOUSE.DIM_CALENDAR
;

SELECT 'Warehouse Layer' AS check_category,
       'dim_item' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT ITEM_ID) AS unique_items,
       COUNT(DISTINCT CATEGORY) AS unique_categories,
       COUNT(DISTINCT DEPARTMENT) AS unique_departments
FROM DEV.WAREHOUSE.DIM_ITEM
;

SELECT 'Warehouse Layer' AS check_category,
       'dim_store' AS check_name,
       COUNT(*) AS row_count,
       COUNT(DISTINCT STORE_ID) AS unique_stores
FROM DEV.WAREHOUSE.DIM_STORE
;

SELECT 'Warehouse Layer' AS check_category,
       'fact_daily_sales Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) AS unique_keys,
       CASE 
           WHEN COUNT(*) = COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE))
           THEN 'PASS - Grain preserved'
           ELSE 'FAIL - Grain corrupted'
       END AS status
FROM DEV.WAREHOUSE.FACT_DAILY_SALES
;

SELECT 'Warehouse Layer' AS check_category,
       'fact_daily_sales Values' AS check_name,
       MIN(SALES_UNITS) AS min_units,
       MAX(SALES_UNITS) AS max_units,
       AVG(SALES_UNITS) AS avg_units,
       SUM(CASE WHEN SALES_UNITS < 0 THEN 1 ELSE 0 END) AS negative_count,
       SUM(CASE WHEN SALES_UNITS IS NULL THEN 1 ELSE 0 END) AS null_count
FROM DEV.WAREHOUSE.FACT_DAILY_SALES
;

SELECT 'Warehouse Layer' AS check_category,
       'fact_forecast_daily Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT ITEM_ID) AS unique_items,
       COUNT(DISTINCT FORECAST_DATE) AS unique_dates,
       MIN(FORECAST_DATE) AS min_date,
       MAX(FORECAST_DATE) AS max_date
FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
;

SELECT 'Warehouse Layer' AS check_category,
       'fact_forecast_daily Values' AS check_name,
       MIN(FORECAST_VALUE) AS min_forecast,
       MAX(FORECAST_VALUE) AS max_forecast,
       AVG(FORECAST_VALUE) AS avg_forecast,
       SUM(CASE WHEN FORECAST_VALUE < 0 THEN 1 ELSE 0 END) AS negative_count,
       SUM(CASE WHEN FORECAST_VALUE IS NULL THEN 1 ELSE 0 END) AS null_count,
       SUM(CASE WHEN LOWER_BOUND_95 IS NULL THEN 1 ELSE 0 END) AS null_lower_ci,
       SUM(CASE WHEN UPPER_BOUND_95 IS NULL THEN 1 ELSE 0 END) AS null_upper_ci
FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
;

-- ====== MART LAYER VALIDATION ======

SELECT 'Mart Layer' AS check_category,
       'mart_forecast_vs_actual Grain' AS check_name,
       COUNT(*) AS total_rows,
       COUNT(DISTINCT ITEM_ID) AS unique_items,
       COUNT(DISTINCT FORECAST_DATE) AS unique_dates,
       SUM(CASE WHEN ACTUAL_UNITS IS NULL THEN 1 ELSE 0 END) AS null_actual,
       SUM(CASE WHEN FORECAST_VALUE IS NULL THEN 1 ELSE 0 END) AS null_forecast
FROM DEV.MARTS.MART_FORECAST_VS_ACTUAL
;

-- ====== CROSS-LAYER INTEGRITY ======

SELECT 'Integrity Check' AS check_category,
       'Date Alignment' AS check_name,
       'CALENDAR' AS table_name,
       COUNT(DISTINCT DATE) AS unique_dates,
       MIN(DATE) AS min_date,
       MAX(DATE) AS max_date
FROM DEV.STAGING.STG_M5_CALENDAR

UNION ALL

SELECT 'Integrity Check',
       'Date Alignment',
       'SALES',
       COUNT(DISTINCT DATE),
       MIN(DATE),
       MAX(DATE)
FROM DEV.WAREHOUSE.FACT_DAILY_SALES

UNION ALL

SELECT 'Integrity Check',
       'Date Alignment',
       'FORECAST',
       COUNT(DISTINCT FORECAST_DATE),
       MIN(FORECAST_DATE),
       MAX(FORECAST_DATE)
FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
;

-- ====== END OF PROFILING QUERIES ======
