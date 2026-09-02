-- mart_forecast_backtest.sql
-- Rolling-origin historical backtest for a transparent demand baseline.
--
-- IMPORTANT:
-- This evaluates a historical benchmark, NOT the production Cortex model.
-- The production Cortex forecast is trained on the full available history and
-- does not have post-cutoff actuals in the M5 dataset.
--
-- Method:
--   1. Select historical forecast origins every 28 days.
--   2. At each origin, calculate average item demand over the previous
--      28 calendar days only.
--   3. Use that average as the forecast for horizons 1 through 28.
--   4. Compare each forecast with the observed future demand.
--
-- Grain: item_id x forecast_origin_date x horizon_day

{{ config(
    materialized='table'
) }}

WITH daily_item_sales AS (

    SELECT
        item_id,
        sale_date,
        SUM(units_sold) AS actual_units
    FROM {{ ref('fact_daily_sales') }}
    GROUP BY
        item_id,
        sale_date

),

date_bounds AS (

    SELECT
        MIN(sale_date) AS min_sale_date,
        MAX(sale_date) AS max_sale_date
    FROM daily_item_sales

),

forecast_origins AS (

    SELECT
        d.sale_date AS forecast_origin_date
    FROM (
        SELECT DISTINCT sale_date
        FROM daily_item_sales
    ) AS d
    CROSS JOIN date_bounds AS b
    WHERE d.sale_date >= DATEADD(DAY, 28, b.min_sale_date)
      AND d.sale_date <= DATEADD(DAY, -28, b.max_sale_date)
      AND MOD(
            DATEDIFF(DAY, b.min_sale_date, d.sale_date),
            28
          ) = 0

),

item_origin_baselines AS (

    SELECT
        o.forecast_origin_date,
        i.item_id,
        AVG(h.actual_units) AS baseline_forecast_units,
        COUNT(h.actual_units) AS history_days
    FROM forecast_origins AS o
    CROSS JOIN (
        SELECT DISTINCT item_id
        FROM daily_item_sales
    ) AS i
    JOIN daily_item_sales AS h
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
    JOIN daily_item_sales AS a
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
