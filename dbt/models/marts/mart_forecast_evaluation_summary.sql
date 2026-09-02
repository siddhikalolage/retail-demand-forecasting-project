-- mart_forecast_evaluation_summary.sql
-- Aggregated KPIs for the historical forecast benchmark.
--
-- These metrics evaluate the transparent trailing-average benchmark.
-- They must NOT be presented as production Cortex forecast accuracy.

{{ config(
    materialized='table'
) }}

WITH metrics AS (

    SELECT
        COUNT(*) AS evaluated_observations,

        AVG(absolute_error) AS mae,

        SQRT(AVG(squared_error)) AS rmse,

        CASE
            WHEN SUM(actual_units) <> 0
            THEN SUM(ABS(actual_units - baseline_forecast_units))
                 / SUM(actual_units)
            ELSE NULL
        END AS wape,

        CASE
            WHEN SUM(actual_units) <> 0
            THEN SUM(actual_units - baseline_forecast_units)
                 / SUM(actual_units)
            ELSE NULL
        END AS bias

    FROM {{ ref('mart_forecast_evaluation') }}

),

item_metrics AS (

    SELECT
        item_id,
        COUNT(*) AS evaluated_days,
        AVG(absolute_error) AS mae,
        SQRT(AVG(squared_error)) AS rmse,

        CASE
            WHEN SUM(actual_units) <> 0
            THEN SUM(ABS(actual_units - baseline_forecast_units))
                 / SUM(actual_units)
            ELSE NULL
        END AS wape,

        CASE
            WHEN SUM(actual_units) <> 0
            THEN SUM(actual_units - baseline_forecast_units)
                 / SUM(actual_units)
            ELSE NULL
        END AS bias

    FROM {{ ref('mart_forecast_evaluation') }}
    GROUP BY item_id

)

SELECT
    'overall' AS aggregation_level,
    CAST(NULL AS VARCHAR) AS item_id,
    evaluated_observations,
    mae,
    rmse,
    wape,
    bias
FROM metrics

UNION ALL

SELECT
    'item' AS aggregation_level,
    item_id,
    evaluated_days,
    mae,
    rmse,
    wape,
    bias
FROM item_metrics
