-- mart_sales_by_category.sql
-- Sales analysis at Category × Department × Date grain.
-- Aggregates sales across stores for strategic category-level decision making.
--
-- Grain: One row per (calendar_date × category × department)
-- Row count: ~7 departments × 1,941 days = ~13,587 rows
--
-- Purposes:
--   Q1.1 — What are sales trends by category over time?
--   Q1.4 — Which department/category combinations are most valuable?
--   Q2.4 — What is SNAP's impact on demand? (food assistance indicator)

{{ config(
    materialized='table',
    schema='marts'
) }}

WITH sales_with_attributes AS (
    SELECT
        f.date_key,
        f.sale_date,
        d.item_key,
        d.item_id,
        d.category_name,
        d.department_name,
        f.units_sold,
        f.revenue_amount_usd,
        f.sell_price,
        c.snap_ca,
        c.snap_tx,
        c.snap_wi,
        c.event_name_1,
        c.event_name_2,
        c.weekday,
        c.week_of_year
    FROM {{ ref('fact_daily_sales') }} f
    JOIN {{ ref('dim_item') }} d ON f.item_key = d.item_key
    JOIN {{ ref('dim_calendar') }} c ON f.date_key = c.date_key
),

aggregated AS (
    SELECT
        date_key,
        sale_date,
        category_name,
        department_name,
        -- Sales metrics
        SUM(units_sold) AS total_units_sold,
        SUM(revenue_amount_usd) AS total_revenue_usd,
        COUNT(DISTINCT item_id) AS active_item_count,
        AVG(sell_price) AS avg_price,
        MAX(sell_price) AS max_price,
        MIN(sell_price) AS min_price,
        -- Derived metrics
        ROUND(SUM(revenue_amount_usd) / NULLIF(SUM(units_sold), 0), 2) AS avg_revenue_per_unit,
        -- Business context
        MAX(event_name_1) AS event_name,
        MAX(weekday) AS weekday,
        MAX(week_of_year) AS week_of_year,
        MAX(snap_ca) AS snap_ca,
        MAX(snap_tx) AS snap_tx,
        MAX(snap_wi) AS snap_wi
    FROM sales_with_attributes
    GROUP BY date_key, sale_date, category_name, department_name
)

SELECT * FROM aggregated
