-- mart_forecast_evaluation.sql
-- Historical holdout evaluation framework for the retail demand forecast.
--
-- IMPORTANT:
-- This is NOT production forecast accuracy.
-- The production Cortex model is trained on the full historical dataset.
-- M5 does not contain actuals for the production forecast horizon.
--
-- This mart evaluates a simple, reproducible historical baseline:
-- forecast = average daily units over the previous 28 calendar days.
--
-- Grain: item × evaluation_date
--
-- Metrics:
--   MAE  = mean absolute error
--   RMSE = root mean squared error
--   WAPE = weighted absolute percentage error
--   Bias = signed error / actual demand
--
-- The baseline is intentionally transparent and does not replace or retrain
-- the production Cortex model.

{{ config(
    materialized='table'
) }}

WITH daily_item_sales AS (

    SELECT
        item_id,
        sale_date,
        SUM(units_sold) AS actual_units
    FROM {{ ref('fact_daily_sales') }}
    GROUP BY item_id, sale_date

),

evaluation_dates AS (

    SELECT
        item_id,
        sale_date AS evaluation_date,
        actual_units
    FROM daily_item_sales

),

historical_window AS (

    SELECT
        e.item_id,
        e.evaluation_date,
        e.actual_units,
        AVG(h.actual_units) AS baseline_forecast_units
    FROM evaluation_dates AS e
    JOIN daily_item_sales AS h
        ON e.item_id = h.item_id
       AND h.sale_date >= DATEADD(DAY, -28, e.evaluation_date)
       AND h.sale_date < e.evaluation_date
    GROUP BY
        e.item_id,
        e.evaluation_date,
        e.actual_units

)

SELECT
    item_id,
    evaluation_date,
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

FROM historical_window
WHERE baseline_forecast_units IS NOT NULL
