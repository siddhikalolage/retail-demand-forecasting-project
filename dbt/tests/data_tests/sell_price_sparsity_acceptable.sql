-- dbt/tests/data_tests/sell_price_sparsity_acceptable.sql
-- 
-- Validates that price null percentage is within acceptable bounds (25-75%).
-- Fails if null_percent falls outside expected range.
--
-- Purpose: Catches anomalies in price data availability.
-- 
-- Expected behavior:
--   - M5 dataset has sparse pricing (not all items priced every week)
--   - Typically 40-60% NULL prices (accepted retail pattern)
--   - Fail if < 25% null (suggests corruption) or > 75% null (data loss)
--
-- Known limitation: This check validates the entire fact table.
-- If needed, can be segmented by category or time period.

WITH price_stats AS (
    SELECT
        COUNT(*) AS total_rows,
        SUM(CASE WHEN sell_price IS NULL THEN 1 ELSE 0 END) AS null_prices,
        ROUND(100.0 * SUM(CASE WHEN sell_price IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS null_percent
    FROM {{ ref('fact_daily_sales') }}
)
SELECT
    total_rows,
    null_prices,
    null_percent
FROM price_stats
WHERE null_percent NOT BETWEEN 25 AND 75  -- Fail if outside 25-75% range
