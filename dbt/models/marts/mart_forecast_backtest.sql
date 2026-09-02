-- mart_forecast_backtest.sql
-- Calendar-complete rolling-origin historical benchmark.
--
-- IMPORTANT:
-- This evaluates a transparent historical baseline, NOT the production
-- Snowflake Cortex forecast.
--
-- Method:
--   1. Build a complete item x calendar-day grid.
--   2. Treat missing sales rows as zero demand.
--   3. Select forecast origins every 28 days.
--   4. Calculate the previous 28 calendar days' average demand.
--   5. Forecast horizons 1 through 28.
--   6. Compare forecasts against the complete future demand series.
--
-- Grain: item_id x forecast_origin_date x horizon_day

{{ config(
    materialized='table'
) }}

WITH calendar AS (

    SELECT DISTINCT
        calendar_date AS sale_date
    FROM {{ ref('dim_calendar') }}

),

items AS (

    SELECT DISTINCT
        item_id
    FROM {{ ref('fact_daily_sales') }}

),

daily_sales AS (

    SELECT
        item_id,
        sale_date,
        SUM(units_sold) AS actual_units
    FROM {{ ref('fact_daily_sales') }}
    GROUP BY
        item_id,
        sale_date

),

item_calendar AS (

    SELECT
        i.item_id,
        c.sale_date
    FROM items AS i
    CROSS JOIN calendar AS c

),

complete_daily_sales AS (

    SELECT
        ic.item_id,
        ic.sale_date,
        COALESCE(ds.actual_units, 0) AS actual_units
    FROM item_calendar AS ic
    LEFT JOIN daily_sales AS ds
        ON ds.item_id = ic.item_id
       AND ds.sale_date = ic.sale_date

),

date_bounds AS (

    SELECT
        MIN(sale_date) AS min_sale_date,
        MAX(sale_date) AS max_sale_date
    FROM complete_daily_sales

),

forecast_origins AS (

    SELECT
        c.sale_date AS forecast_origin_date
    FROM calendar AS c
    CROSS JOIN date_bounds AS b
    WHERE c.sale_date >= DATEADD(DAY, 28, b.min_sale_date)
      AND c.sale_date <= DATEADD(DAY, -28, b.max_sale_date)
      AND MOD(
            DATEDIFF(DAY, b.min_sale_date, c.sale_date),
            28
          ) = 0

),

item_origin_baselines AS (

    SELECT
        o.forecast_origin_date,
        i.item_id,
        AVG(h.actual_units) AS baseline_forecast_units,
        COUNT(*) AS history_days
    FROM forecast_origins AS o
    CROSS JOIN items AS i
    JOIN complete_daily_sales AS h
        ON h.item_id = i.item_id
       AND h.sale_date >= DATEADD(DAY, -28, o.forecast_origin_date)
       AND h.sale_date < o.forecast_origin_date
    GROUP BY
        o.forecast_origin_date,
        i.item_id

),

backtest_observations AS (

    SELECT
        b.item_id,
        b.forecast_origin_date,
        DATEDIFF(
            DAY,
            b.forecast_origin_date,
            a.sale_date
        ) AS horizon_day,
        a.sale_date AS forecast_date,
        a.actual_units,
        b.baseline_forecast_units
    FROM item_origin_baselines AS b
    JOIN complete_daily_sales AS a
        ON a.item_id = b.item_id
       AND a.sale_date > b.forecast_origin_date
       AND a.sale_date <= DATEADD(DAY, 28, b.forecast_origin_date)
    WHERE b.history_days = 28

)

SELECT
    item_id,
    forecast_origin_date,
    horizon_day,
    forecast_date,
    actual_units,
    baseline_forecast_units,

    ABS(actual_units - baseline_forecast_units) AS absolute_error,

    POWER(
        actual_units - baseline_forecast_units,
        2
    ) AS squared_error,

    actual_units - baseline_forecast_units AS signed_error,

    CASE
        WHEN actual_units <> 0
        THEN ABS(actual_units - baseline_forecast_units) / actual_units
        ELSE NULL
    END AS absolute_percentage_error,

    CASE
        WHEN actual_units <> 0
        THEN (actual_units - baseline_forecast_units) / actual_units
        ELSE NULL
    END AS signed_percentage_error

FROM backtest_observations