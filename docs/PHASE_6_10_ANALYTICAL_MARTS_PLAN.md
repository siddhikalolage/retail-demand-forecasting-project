# PHASE_6_10_ANALYTICAL_MARTS_PLAN.md

## Phases 6-10: Analytical Marts & Forecasting Strategy

**Date Created:** 2026-09-02  
**Status:** Planning phase; implementation pending  
**Scope:** Build analytical layer with 6+ decision-oriented marts and complete forecast evaluation framework

---

## Part 1: Analytical Requirements & Mart Design

### Business Questions Driving Mart Design

#### Question Set 1: Demand Understanding
- Q1.1: What are sales trends by category over time?
- Q1.2: Which items are top performers? Bottom performers?
- Q1.3: Which stores drive the most volume?
- Q1.4: Are there seasonal patterns (daily, weekly, monthly, annual)?
- Q1.5: Which department/category combinations are most valuable?

#### Question Set 2: Price & Promotion Intelligence
- Q2.1: Do prices influence demand (observed correlation)?
- Q2.2: Which items benefit most from price reductions?
- Q2.3: Are there days/weeks with systematic price differences?
- Q2.4: What is SNAP's impact on demand? (food assistance program indicator)

#### Question Set 3: Forecast Accuracy & Reliability
- Q3.1: How accurate is the forecast overall? (WAPE, MAE, RMSE)
- Q3.2: Which categories forecast best? Which forecast worst?
- Q3.3: Are there systematic biases? (Over-forecast in holidays? Under-forecast in summer?)
- Q3.4: Which segments drive the most forecast error?
- Q3.5: Has forecast accuracy improved over time? (if backtesting multiple origins)

#### Question Set 4: Inventory & Promotion Opportunities
- Q4.1: What inventory buffers are implied by forecast confidence intervals?
- Q4.2: Which items have high forecast uncertainty?
- Q4.3: When should promotions be planned to maximize demand capture?

---

## Part 2: Proposed Mart Architecture

### Existing Marts (Already in Repository)

**MART 1: mart_forecast_vs_actual**
- Grain: Item × Date × Series Type (actual/forecast)
- Purpose: Power BI visualization of forecast vs. actual side-by-side
- Status: ✅ EXISTS

**MART 2: agg_sales_daily**
- Grain: Date (aggregate over all items × stores)
- Purpose: Daily trend reporting
- Status: ✅ EXISTS

**MART 3: agg_sales_daily_item_cat**
- Grain: Date × Category (aggregate over all stores, all items in category)
- Purpose: Category-level trend reporting
- Status: ✅ EXISTS

### Proposed New Marts (PHASE 6-10)

**MART 4: mart_sales_by_category** ← PHASE 6 HIGH PRIORITY
- Grain: Date × Category × Department
- Columns: units_sold, revenue_usd, avg_price, price_change_vs_prior_week, snap_ca/tx/wi, event_name
- Purpose: Answer Q1.1, Q1.4 (category trends, department performance)
- SQL Pattern:
```sql
WITH source AS (
    SELECT
        f.date_key, f.sale_date,
        d.category_name, d.department_name,
        f.units_sold, f.revenue_amount_usd, f.sell_price,
        c.snap_ca, c.snap_tx, c.snap_wi,
        c.event_name_1, c.event_name_2
    FROM fact_daily_sales f
    JOIN dim_item d ON f.item_key = d.item_key
    JOIN dim_calendar c ON f.date_key = c.date_key
    JOIN dim_store s ON f.store_key = s.store_key
)
SELECT
    date_key, sale_date,
    category_name, department_name,
    SUM(units_sold) as total_units,
    SUM(revenue_amount_usd) as total_revenue,
    AVG(sell_price) as avg_price,
    -- Price momentum: avg price this week vs prior week
    AVG(sell_price) - LAG(AVG(sell_price)) OVER (PARTITION BY category_name, department_name ORDER BY date_key) as price_change
FROM source
GROUP BY date_key, sale_date, category_name, department_name
```
- Estimated rows: ~7 departments × 365 days ≈ 2,500 rows

**MART 5: mart_sales_by_store** ← PHASE 6 HIGH PRIORITY
- Grain: Date × Store × State
- Columns: units_sold, revenue_usd, active_items, store_efficiency
- Purpose: Answer Q1.3 (store performance comparison)
- SQL Pattern:
```sql
SELECT
    f.date_key, f.sale_date,
    s.store_id, s.state_id,
    COUNT(DISTINCT f.item_id) as active_items,
    SUM(f.units_sold) as total_units,
    SUM(f.revenue_amount_usd) as total_revenue,
    ROUND(SUM(f.revenue_amount_usd) / NULLIF(SUM(f.units_sold), 0), 2) as avg_revenue_per_unit
FROM fact_daily_sales f
JOIN dim_store s ON f.store_key = s.store_key
GROUP BY f.date_key, f.sale_date, s.store_id, s.state_id
```
- Estimated rows: ~10 stores × 365 days ≈ 3,650 rows

**MART 6: mart_top_performers_by_category** ← PHASE 7
- Grain: Category × Department × Item × Time Period (weekly aggregates)
- Columns: rank, units_sold, revenue_usd, price, trend (vs prior week)
- Purpose: Answer Q1.2 (top/bottom items by category)
- SQL Pattern: WITH category_sales AS (...), ranked AS (SELECT ROW_NUMBER() OVER (PARTITION BY category ORDER BY revenue DESC))
- Estimated rows: ~3,000 items × 52 weeks = 156,000 rows (could be large; consider incremental)

**MART 7: mart_seasonality_calendar_effects** ← PHASE 7
- Grain: Day of Week, Week of Year, Holiday, SNAP Indicator
- Columns: avg_units_sold, avg_revenue_usd, day_name, is_holiday, holiday_name, snap_ca/tx/wi
- Purpose: Answer Q1.4, Q2.4 (seasonality, SNAP impact)
- SQL Pattern: Aggregate by DOW, WOY, holiday attributes; compute averages
- Estimated rows: ~14 (7 DOW × 2 SNAP patterns) × 53 weeks = 742 rows

**MART 8: mart_forecast_evaluation** ← PHASE 8 CRITICAL
- Grain: Category × Item × Forecast Date × Evaluation Window
- Columns: forecast_units, actual_units, error, abs_error, percentage_error, lower_ci_95, upper_ci_95
- Purpose: Answer Q3.1-Q3.4 (forecast accuracy, bias, confidence)
- SQL Pattern:
```sql
WITH forecast_actual_join AS (
    SELECT
        f.item_id, f.forecast_date,
        f.forecast_units, f.forecast_revenue_usd,
        f.forecast_units_lower_95, f.forecast_units_upper_95,
        a.units_sold as actual_units, a.revenue_amount_usd as actual_revenue,
        d.category_name
    FROM fact_forecast_daily f
    LEFT JOIN fact_daily_sales a ON f.item_id = a.item_id AND f.forecast_date = a.sale_date
    JOIN dim_item d ON f.item_id = d.item_id
)
SELECT
    item_id, forecast_date, category_name,
    forecast_units, actual_units,
    actual_units - forecast_units as error,
    ABS(actual_units - forecast_units) as abs_error,
    CASE WHEN actual_units > 0 
         THEN ABS(actual_units - forecast_units) / actual_units 
         ELSE NULL 
    END as percentage_error,
    lower_ci_95, upper_ci_95,
    CASE WHEN actual_units BETWEEN lower_ci_95 AND upper_ci_95 THEN 1 ELSE 0 END as in_ci_95
FROM forecast_actual_join
```
- Estimated rows: ~3,000 items × 28-day forecast horizon × backtest periods

**MART 9: mart_forecast_metrics_summary** ← PHASE 8 CRITICAL
- Grain: Category, Time Period (weekly), Forecast Metric Type
- Columns: MAE, RMSE, WAPE, Bias, CovPercent (% in CI)
- Purpose: Answer Q3.1-Q3.3 (accuracy by category, metric trends)
- SQL Pattern: Aggregate mart_forecast_evaluation by category; calculate metrics
- Estimated rows: ~3 categories × 4 weeks ≈ 12-100 rows (tiny)

**MART 10: mart_price_elasticity_signals** ← PHASE 9
- Grain: Category × Item × Week, with Price Buckets
- Columns: price_bucket, avg_units_sold, price_change_pct, demand_change_pct
- Purpose: Answer Q2.1-Q2.2 (price sensitivity)
- SQL Pattern: Segment by price quartile; compute demand change vs prior period
- Estimated rows: ~3,000 items × 4 price buckets × 52 weeks (large; consider sampling)

---

## Part 3: Forecast Evaluation Metrics Definitions

### Metric 1: MAE (Mean Absolute Error)
```
MAE = SUM(|actual_units - forecast_units|) / COUNT(forecasts)
Interpretation: Average absolute error in units
Range: [0, ∞); lower is better
Units: Same as forecast (units sold)
```

### Metric 2: RMSE (Root Mean Squared Error)
```
RMSE = SQRT(SUM((actual_units - forecast_units)²) / COUNT(forecasts))
Interpretation: Penalizes large errors more heavily than MAE
Range: [0, ∞); lower is better
Units: Same as forecast (units sold)
```

### Metric 3: WAPE (Weighted Absolute Percentage Error)
```
WAPE = SUM(|actual_units - forecast_units|) / SUM(|actual_units|)
Interpretation: Percentage error; normalized by actual volume
Range: [0, 1] or [0%, 100%]; lower is better
Units: Dimensionless (percent)
Benchmark: <18% is considered good for retail demand forecasting
Note: Handles zero actuals gracefully (excluded from denominator)
```

### Metric 4: Bias (Mean Directional Error)
```
Bias = SUM(actual_units - forecast_units) / COUNT(forecasts)
Interpretation: Systematic over/under forecast tendency
Range: (-∞, ∞); 0 is perfect; negative = over-forecast, positive = under-forecast
Units: Same as forecast (units sold)
Decision: If Bias consistently negative, forecast overestimates demand
```

### Metric 5: Coverage Percentage
```
Coverage = COUNT(actual BETWEEN lower_CI AND upper_CI) / COUNT(forecasts) * 100
Interpretation: % of actuals that fall within forecast confidence interval
Range: [0, 100]%; 95% CI should achieve ~95% coverage
Target: For 95% CI, expect 90-98% coverage in practice
Decision: If coverage too low, CI too narrow (under-confidence); if too high, CI too wide (over-confidence)
```

---

## Part 4: Backtesting Framework (IF DATA SUPPORTS)

### Current Challenge: M5 Dataset Limitation

**Issue:** M5 dataset ends 2016-06-19. No ground truth available for 28-day forecast validation.

**Impact:** Cannot test forecast directly against held-out 28-day window.

**Solution Options:**

#### Option A: Rolling Origin Backtesting (RECOMMENDED)
- Select multiple historical forecast origins (e.g., weeks 104, 105, 106 of training)
- For each origin, compute "forecast" as the ML model would
- Compare against actuals in [origin+1, origin+28]
- Repeat for 10+ origins
- Aggregate metrics across origins

**SQL Pattern:**
```sql
-- Pseudo-code for rolling origin backtesting
WITH forecast_origins AS (
    -- Select origin dates at regular intervals (e.g., every 4 weeks)
    -- For each origin, compute what forecast would have been at that time
    SELECT forecast_origin_date, forecast_date, item_id, forecast_value
    FROM computed_historical_forecasts  -- would need to be computed separately
),
actuals_for_evaluation AS (
    SELECT
        forecast_origin_date,
        forecast_date,
        item_id,
        SUM(units_sold) as actual_units
    FROM fact_daily_sales
    WHERE sale_date >= forecast_origin_date + INTERVAL '1 DAY'
    AND sale_date <= forecast_origin_date + INTERVAL '28 DAYS'
    GROUP BY forecast_origin_date, forecast_date, item_id
)
SELECT
    f.forecast_origin_date,
    f.item_id,
    f.forecast_value,
    a.actual_units,
    ABS(f.forecast_value - a.actual_units) as abs_error
FROM forecast_origins f
LEFT JOIN actuals_for_evaluation a
    ON f.forecast_origin_date = a.forecast_origin_date
    AND f.forecast_date = a.forecast_date
    AND f.item_id = a.item_id
```

**Advantages:**
- ✅ Uses only available historical data
- ✅ Simulates realistic deployment scenario (forecast today, evaluate 28 days later)
- ✅ Tests across multiple market conditions
- ✅ Defensible for portfolio (shows rigorous evaluation)

**Disadvantages:**
- ⚠️ Requires storing computed forecasts at historical origins (Python model retraining needed)
- ⚠️ Computationally expensive if many origins tested

#### Option B: Time Series Cross-Validation (ALTERNATIVE)
- Split data into 10+ training windows
- For each window, train model on historical data, forecast forward 28 days
- Test against subsequent actuals
- Aggregate metrics

**Status:** Recommend Option A if resources permit; Option B faster but less rigorous

---

## Part 5: BUSINESS_INSIGHTS.md Replacement Strategy

### Current State (Unvalidated Claims)
```markdown
## Accuracy & Performance
- Forecast WAPE: ≤18% (acceptable for retail)
- Category WAPE ranges: FOODS 12-15%, HOUSEHOLD 18-22%, HOBBIES 20-25%
- Confidence interval (95%) reduces bullwhip effect
```

### Problem with Current State
Per execution plan RULE 3: "NEVER INVENT BUSINESS INSIGHTS. Do not decide beforehand. Calculate first."

Current BUSINESS_INSIGHTS.md contains claims without source data calculations.

### Phase 8 Remediation Plan

**Step 1: Execute Forecast Evaluation Queries (Week 1)**
- Run mart_forecast_evaluation mart
- Calculate MAE, RMSE, WAPE, Bias for full dataset
- Segment by category, department, store
- Segment by time period (weeks, months)
- Document actual measured values

**Step 2: Identify Patterns & Drivers (Week 2)**
- Which categories have best accuracy? Worst?
- Does accuracy improve with more recent data?
- Are there seasonal effects (worse accuracy around holidays)?
- Do certain store locations forecast differently?
- What % of forecast intervals contain actuals?

**Step 3: Generate Findings Document (Week 2)**
- Create docs/FORECAST_EVALUATION.md
- Document methodology (queries used, date ranges, segments)
- Present calculated findings with source queries
- Acknowledge limitations (M5 dataset, model version, etc.)

**Step 4: Update BUSINESS_INSIGHTS.md (Week 3)**
- Replace unvalidated claims with calculated findings
- Add "Data Source" section citing specific queries
- Add caveats about M5 dataset nature (historical, no post-cutoff validation)
- Convert speculative insights to evidence-based statements

**Example Transformation:**

BEFORE (Speculative):
```
Forecast WAPE: ≤18% (assumed acceptable)
SNAP impact: +15% demand during SNAP windows (estimated)
Inventory buffer: 20-30% safety stock recommended (guideline)
```

AFTER (Calculated):
```
Forecast WAPE: 14.2% (calculated from mart_forecast_evaluation, 2016 data)
  - FOODS: 11.8% (highest accuracy)
  - HOUSEHOLD: 15.3%
  - HOBBIES: 18.9% (lowest accuracy)
  
SNAP impact: Observed +8.3% avg units on SNAP days vs non-SNAP days in CA (measured)
  - State variation: TX +5.2%, WI +3.1%
  - Not causal (observational only; documented in limitations)

Inventory buffer sizing: Based on 95% CI width
  - Avg buffer: 12-18% of forecast value
  - Recommended: 15-25% depending on risk tolerance
  - Data source: mart_forecast_metrics_summary
```
```

---

## Part 6: Implementation Roadmap (Phases 6-10)

### PHASE 6 — Foundation Marts (Week 1)
**Deliverables:**
- ✅ mart_sales_by_category (created)
- ✅ mart_sales_by_store (created)
- ✅ agg_sales_daily, agg_sales_daily_item_cat (validate existing)
- ✅ All marts pass dbt tests
- ✅ Docs/ANALYTICAL_LAYER.md documenting mart purposes

**Estimated Effort:** 4-5 hours
**Success Criteria:**
- All marts materialized and tests passing
- Power BI can import marts without errors
- Row counts align with expectations

---

### PHASE 7 — Performance & Seasonality Marts (Week 1-2)
**Deliverables:**
- ✅ mart_top_performers_by_category (created, possibly incremental)
- ✅ mart_seasonality_calendar_effects (created)
- ✅ docs/SEASONALITY_FINDINGS.md (calculated patterns)

**Estimated Effort:** 3-4 hours
**Success Criteria:**
- Seasonality patterns identified (DOW, WOY, holiday effects)
- Top/bottom items ranked by category
- Confidence intervals on seasonal estimates calculated

---

### PHASE 8 — Forecast Evaluation (Week 2-3) ⭐ CRITICAL
**Deliverables:**
- ✅ mart_forecast_evaluation (created)
- ✅ mart_forecast_metrics_summary (created)
- ✅ docs/FORECAST_EVALUATION.md (comprehensive methodology + findings)
- ✅ WAPE, MAE, RMSE, Bias calculated by category/segment
- ✅ Confidence interval coverage measured
- ✅ Backtesting framework (rolling origin) implemented if possible

**Estimated Effort:** 6-8 hours
**Success Criteria:**
- All forecast evaluation queries run without error
- Metrics calculated and match manual spot checks
- Backtesting (if implemented) covers 10+ forecast origins
- Findings documented with source queries

---

### PHASE 9 — Price Intelligence (Week 3)
**Deliverables:**
- ✅ mart_price_elasticity_signals (created)
- ✅ docs/PRICE_INTELLIGENCE.md

**Estimated Effort:** 2-3 hours
**Success Criteria:**
- Price/demand correlations calculated
- Segments identified (elastic vs. inelastic items)
- No causal claims (only "observed correlation" statements)

---

### PHASE 10 — Rebuild BUSINESS_INSIGHTS.md (Week 3-4)
**Deliverables:**
- ✅ BUSINESS_INSIGHTS.md rebuilt with calculated findings
- ✅ All claims traceable to specific queries/marts
- ✅ Limitations documented
- ✅ Data sources cited

**Estimated Effort:** 2-3 hours
**Success Criteria:**
- No unvalidated claims
- All numbers match calculated findings
- Interview-defensible analysis

---

## Part 7: Testing & Validation Strategy

### Mart Testing Checklist
- [ ] Row count matches expected grain (e.g., days × categories)
- [ ] No orphaned foreign keys
- [ ] No unexpected NULL values in key columns
- [ ] Date range aligns with source tables
- [ ] Aggregations reasonable (no negative values, no extreme outliers)

### Metric Validation Checklist
- [ ] MAE, RMSE comparable to WAPE (spot check)
- [ ] Bias sign makes sense (positive = under-forecast)
- [ ] Confidence interval coverage ≈ 95% for 95% CI
- [ ] Metrics stable across rolling windows (no sudden spikes)

### Query Verification Checklist
- [ ] Run all mart creation queries in Snowflake directly (bypass dbt)
- [ ] Verify row counts match dbt output
- [ ] Compare metrics across different aggregation levels
- [ ] Document any data quality issues discovered

---

## Part 8: Known Limitations & Caveats

### Limitation 1: M5 Dataset Boundaries
- Ends 2016-06-19; no ground truth for 28-day forecast validation
- Mitigation: Rolling origin backtesting on historical periods

### Limitation 2: No Causal Inference
- Price/demand correlations are observational, not causal
- Mitigation: Explicit documentation ("observed correlation"; avoid "price impact")

### Limitation 3: SNAP Data Availability
- Varies by state (CA, TX, WI only); limited geographic generalization
- Mitigation: Calculate by state separately; document scope

### Limitation 4: Forecast Model Static
- Cortex ML model trained once; not retrained during backtesting
- Mitigation: Document model version/training date; acknowledge stale model risk

---

## Success Metrics for Phases 6-10

| Criterion | Target | Status |
|---|---|---|
| Marts created | 6+ | ⬜ |
| All marts pass dbt tests | 100% | ⬜ |
| Forecast WAPE calculated | <25% acceptable range | ⬜ |
| Seasonality patterns identified | 3+ significant patterns | ⬜ |
| BUSINESS_INSIGHTS.md rebuilt | 100% validated claims | ⬜ |
| Interview-defensible | Yes | ⬜ |
| Power BI importable | All marts load | ⬜ |
| Documentation complete | FORECAST_EVALUATION.md + SEASONALITY_FINDINGS.md | ⬜ |

---

## References

- [DATA_CONTRACT.md](DATA_CONTRACT.md) — Grain specifications
- [DATA_ENGINEERING_DECISIONS.md](DATA_ENGINEERING_DECISIONS.md) — Incremental strategy
- dbt Documentation: https://docs.getdbt.com/docs/build/materializations
- Forecast Accuracy Metrics: https://en.wikipedia.org/wiki/Mean_absolute_percentage_error
