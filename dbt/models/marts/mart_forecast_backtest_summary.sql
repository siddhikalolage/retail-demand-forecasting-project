-- mart_forecast_backtest_summary.sql
-- Aggregated accuracy metrics for the rolling-origin historical benchmark.
--
-- IMPORTANT:
-- This summarizes the historical baseline in mart_forecast_backtest.
-- It does NOT measure the production Snowflake Cortex forecast.

{{ config(
    materialized='table'
) }}

WITH backtest AS (

    SELECT *
    FROM {{ ref('mart_forecast_backtest') }}

),

overall AS (

    SELECT
        'overall' AS aggregation_level,
        CAST(NULL AS INTEGER) AS horizon_day,

        COUNT(*) AS evaluated_observations,
        COUNT(DISTINCT forecast_origin_date) AS forecast_origins,
        COUNT(DISTINCT item_id) AS items_evaluated,

        AVG(absolute_error) AS mae,

        SQRT(
            AVG(squared_error)
        ) AS rmse,

        SUM(absolute_error)
            / NULLIF(SUM(actual_units), 0) AS wape,

        SUM(signed_error)
            / NULLIF(SUM(actual_units), 0) AS bias

    FROM backtest

),

by_horizon AS (

    SELECT
        'horizon' AS aggregation_level,
        horizon_day,

        COUNT(*) AS evaluated_observations,
        COUNT(DISTINCT forecast_origin_date) AS forecast_origins,
        COUNT(DISTINCT item_id) AS items_evaluated,

        AVG(absolute_error) AS mae,

        SQRT(
            AVG(squared_error)
        ) AS rmse,

        SUM(absolute_error)
            / NULLIF(SUM(actual_units), 0) AS wape,

        SUM(signed_error)
            / NULLIF(SUM(actual_units), 0) AS bias

    FROM backtest
    GROUP BY
        horizon_day

)

SELECT *
FROM overall

UNION ALL

SELECT *
FROM by_horizon