-- mart_sales_by_store.sql
-- Sales analysis at Store × Date grain.
-- Compares store-level performance for inventory, staffing, and regional decisions.
--
-- Grain: One row per (calendar_date × store)
-- Row count: ~10 stores × 1,941 days = ~19,410 rows
--
-- Purposes:
--   Q1.3 — Which stores drive the most volume?
--   Q1.3 — Store-to-store performance comparison (best/worst performers)
--   Enables Power BI regional dashboards and store benchmarking

{{ config(
    materialized='table',
    schema='marts'
) }}

WITH sales_with_store_attributes AS (
    SELECT
        f.date_key,
        f.sale_date,
        s.store_id,
        s.state_id,
        d.item_key,
        d.item_id,
        f.units_sold,
        f.revenue_amount_usd,
        f.sell_price,
        c.weekday,
        c.is_holiday,
        c.event_name_1
    FROM {{ ref('fact_daily_sales') }} f
    JOIN {{ ref('dim_store') }} s ON f.store_key = s.store_key
    JOIN {{ ref('dim_item') }} d ON f.item_key = d.item_key
    JOIN {{ ref('dim_calendar') }} c ON f.date_key = c.date_key
),

aggregated AS (
    SELECT
        date_key,
        sale_date,
        store_id,
        state_id,
        -- Sales metrics
        COUNT(DISTINCT item_id) AS active_item_count,
        SUM(units_sold) AS total_units_sold,
        SUM(revenue_amount_usd) AS total_revenue_usd,
        -- Derived metrics
        ROUND(SUM(revenue_amount_usd) / NULLIF(SUM(units_sold), 0), 2) AS avg_revenue_per_unit,
        AVG(sell_price) AS avg_price,
        -- Performance context
        MAX(weekday) AS weekday,
        MAX(is_holiday) AS is_holiday,
        MAX(event_name_1) AS event_name
    FROM sales_with_store_attributes
    GROUP BY date_key, sale_date, store_id, state_id
)

SELECT * FROM aggregated
