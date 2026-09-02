-- dbt/tests/data_tests/mart_sales_by_category_grain.sql
--
-- Validates that mart_sales_by_category is at correct grain
-- with no duplicate (date_key, category_name, department_name) combinations.
--
-- Grain: One row per date Ã— category Ã— department

SELECT
    date_key,
    category_name,
    department_name,
    COUNT(*) AS row_count
FROM {{ ref('mart_sales_by_category') }}
GROUP BY date_key, category_name, department_name
HAVING COUNT(*) > 1  -- Fail if duplicates exist
