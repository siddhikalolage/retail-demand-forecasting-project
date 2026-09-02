-- dbt/tests/data_tests/mart_sales_by_store_grain.sql
--
-- Validates that mart_sales_by_store is at correct grain
-- with no duplicate (date_key, store_id) combinations.
--
-- Grain: One row per store Ã— date

SELECT
    date_key,
    store_id,
    COUNT(*) AS row_count
FROM {{ ref('mart_sales_by_store') }}
GROUP BY date_key, store_id
HAVING COUNT(*) > 1  -- Fail if duplicates exist
