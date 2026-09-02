# Retail Demand Forecasting — Business Insights

## Purpose

This document translates the retail demand forecasting pipeline into business-facing
observations, analytical questions, and decision-support opportunities.

All claims in this document follow an evidence-first rule:

- Metrics are reported only when they can be reproduced from the project data and SQL.
- Forecast accuracy is not claimed unless an evaluation run produces the metric.
- Production Cortex forecast accuracy is explicitly separated from historical benchmark evaluation.
- Recommendations are labelled as recommendations rather than presented as measured outcomes.

---

## 1. Executive Summary

The project combines retail sales analytics, dimensional modelling, demand forecasting,
and BI reporting into a single decision-support workflow.

The analytical architecture supports five major business questions:

1. What products and categories generate demand and revenue?
2. How does demand vary across stores and time?
3. How do price and calendar effects relate to sales?
4. What does the demand forecast imply for upcoming inventory requirements?
5. How reliable is the forecasting process when evaluated against historical observations?

The current warehouse and analytical marts provide the foundation for answering these
questions at item, category, store, and daily levels.

---

## 2. Analytical Grain

### Actual sales

The primary sales fact is:

**Item × Store × Day**

`fact_daily_sales` contains the conformed sales grain used by downstream analytical models.

### Forecast

The production forecast is:

**Item × Day**

Forecast demand is aggregated across stores before entering the Snowflake Cortex forecasting
layer. This is an intentional modelling decision designed to reduce the number of forecast
series and focus the production forecast on item-level demand.

### Forecast vs Actual

`mart_forecast_vs_actual` exposes:

**Item × Observation Date × Series Type**

where `series_type` is either:

- `actual`
- `forecast`

This structure allows Power BI to compare historical demand with future forecast demand.

---

## 3. Category Demand Analysis

`mart_sales_by_category` provides daily analytical aggregation at:

**Date × Category × Department**

The mart supports analysis of:

- Units sold
- Revenue
- Active item count
- Average selling price
- Revenue per unit
- Calendar effects
- Events and holidays

### Business questions

Management can use this layer to investigate:

- Which categories consistently generate the highest demand?
- Which categories experience the strongest seasonal changes?
- Are revenue changes caused by units, price, or both?
- Which departments require closer inventory monitoring?

### Evidence status

Category-level numerical findings should be generated directly from the mart after a
successful Snowflake/dbt execution.

No fixed revenue-share or category forecast-accuracy percentages are asserted here without
a reproducible query result.

---

## 4. Store Performance Analysis

`mart_sales_by_store` provides:

**Store × Date**

with measures including:

- Units sold
- Revenue
- Average selling price
- Active item count
- State
- Weekday
- Holiday/event context

### Business questions

This supports:

- Store demand ranking
- Store-level demand variability
- Identification of consistently high-volume locations
- Comparison of demand patterns between states
- Investigation of holiday/event effects
- Store-specific inventory planning

A future extension could add store-level demand segmentation based on historical volume
and volatility.

---

## 5. Seasonality and Calendar Intelligence

The retail dataset contains calendar attributes that can be used to investigate:

- Weekday/weekend effects
- Holidays
- Events
- SNAP-related calendar indicators
- Weekly and monthly demand patterns

These variables should be treated as explanatory dimensions unless an analysis demonstrates
a statistically or operationally meaningful relationship.

### Important distinction

A calendar indicator being present in the dataset does not automatically establish that it
causes a specific percentage of revenue or demand.

Therefore this project does not claim a fixed SNAP revenue contribution or fixed weekend
uplift without a reproducible aggregation.

---

## 6. Price and Demand Analysis

The analytical layer includes selling-price information alongside units and revenue.

This enables questions such as:

- Do higher prices coincide with lower unit demand?
- Which categories have the greatest price variation?
- Which items show stable demand despite price changes?
- Are revenue increases driven by volume or price?

### Important limitation

The M5 dataset does not provide complete causal experimental information.

Therefore observed price-demand relationships should be described as **associations**, not
as causal price elasticity estimates, unless a dedicated statistical analysis is performed.

---

## 7. Forecasting Strategy

The production forecasting layer uses:

**Snowflake Cortex ML FORECAST**

The configured production process:

- Uses item-level daily demand
- Aggregates demand across stores
- Forecasts a 28-day horizon
- Provides forecast lower and upper bounds
- Uses the Cortex `method='best'` configuration
- Enables Cortex's internal evaluation with `evaluate=TRUE`

The production forecast is treated as the authoritative forecasting artifact.

### Production forecast revenue

Forecast revenue is derived from:

**Forecast Units × Recent Historical Average Selling Price**

Therefore this field represents:

**Estimated Forecast Revenue**

It must not be interpreted as actual future revenue or as a modelled price forecast.

---

## 8. Forecast Evaluation

The project now contains a separate historical evaluation framework.

### Historical benchmark

`mart_forecast_evaluation` evaluates a transparent:

**28-day trailing-average baseline**

at:

**Item × Evaluation Date**

The evaluation framework calculates:

- Absolute error
- Squared error
- Signed error
- Absolute percentage error
- Signed percentage error

`mart_forecast_evaluation_summary` aggregates the benchmark into:

- MAE
- RMSE
- WAPE
- Bias

### Why this is separate from production forecasting

The public M5 dataset does not contain actual observations for the production forecast horizon.

Consequently, production future forecast accuracy cannot currently be calculated against
actual future demand.

The historical benchmark provides a reproducible evaluation framework without pretending
that unavailable future actuals exist.

### What is intentionally not claimed

This project does **not** currently claim:

- A specific production WAPE
- A specific production MAE
- A specific production RMSE
- Category-level production accuracy percentages
- Item-level production accuracy percentages
- Forecast accuracy thresholds such as `<12%` or `>20%`

Those values should only be published after a reproducible evaluation run.

---

## 9. Forecast Bias

Forecast bias should be interpreted as:

**Actual Demand − Forecast Demand**

Positive values indicate under-forecasting.

Negative values indicate over-forecasting.

Bias should be monitored by:

- Time period
- Category
- Item
- Demand volume segment

Persistent bias can indicate systematic under- or over-estimation and may justify
investigation of seasonality, promotions, price changes, stock-outs, or model configuration.

No fixed safety-stock percentage is prescribed by this project because an appropriate buffer
requires service-level targets, lead times, demand variability, and operational constraints.

---

## 10. Inventory Decision Framework

The forecasting layer should be treated as a **decision-support signal**, not an automatic
replenishment command.

A practical decision workflow is:

**Historical Demand → Forecast → Uncertainty → Inventory Constraints → Management Decision**

Relevant considerations include:

- Forecast level
- Forecast uncertainty
- Recent demand trend
- Lead time
- Current inventory
- Service-level target
- Supplier constraints
- Promotions/events
- Stock-out history

The current dataset does not contain all of these operational variables, so the project does
not prescribe an exact replenishment quantity.

---

## 11. Recommended BI Decision Views

The analytical marts support a management-oriented Power BI structure.

### Page 1 — Executive Command Center

Focus:

- Total demand
- Revenue
- Active products
- Store performance
- Category contribution
- Key demand movements

### Page 2 — Demand Intelligence

Focus:

- Daily demand trend
- Category and department hierarchy
- Top/bottom products
- Demand concentration
- Store comparisons

### Page 3 — Price & Calendar Intelligence

Focus:

- Units vs selling price
- Calendar effects
- Events
- SNAP-related patterns
- Category price differences

### Page 4 — Store & Seasonality Intelligence

Focus:

- Store ranking
- State comparison
- Weekday/weekend patterns
- Holiday/event demand
- Store-level volatility

### Page 5 — Forecast Control Tower

Focus:

- Forecast units
- Estimated forecast revenue
- Forecast uncertainty
- Forecast vs actual history
- Historical benchmark accuracy
- Bias monitoring

---

## 12. Management Decision Framework

The intended analytical narrative is:

### Observation

What changed?

### Explanation

Which product, category, store, price, or calendar dimension explains the movement?

### Forecast

What does the forecasting layer indicate about upcoming demand?

### Decision

What operational action should management consider?

This prevents the dashboard from becoming a collection of charts without business context.

---

## 13. Known Data and Modelling Limitations

The project should be interpreted with the following limitations:

1. The production forecast is item-level rather than item-store-level.
2. M5 does not provide actuals for the production forecast horizon.
3. Forecast revenue uses recent historical price rather than a future price forecast.
4. The dataset does not contain complete cost/margin information.
5. Observational price-demand relationships should not automatically be treated as causal.
6. External variables such as weather are not currently incorporated.
7. Inventory position and supplier lead-time data are not available in the base dataset.
8. Historical benchmark metrics and production forecast metrics must remain clearly separated.

---

## 14. Future Analytical Extensions

Potential extensions include:

1. Historical rolling-origin backtesting of multiple forecast origins.
2. Forecast accuracy monitoring by category and demand-volume segment.
3. Forecast coverage analysis for prediction intervals.
4. Store-level forecasting where sufficient operational value exists.
5. Integration of promotion and price signals.
6. Integration of inventory and lead-time data.
7. Margin and profitability analysis after cost data becomes available.
8. Forecast monitoring in Power BI.
9. Automated data-quality and forecast-health alerts.

These are future enhancements, not capabilities claimed as already implemented.

---

## 15. Evidence Policy

This repository follows a simple rule:

> **If a number cannot be reproduced from the project's data, SQL, or executed model output,
> it should not be presented as a measured business result.**

This applies particularly to:

- Forecast accuracy
- Revenue percentages
- Demand uplift
- Price elasticity
- Safety-stock percentages
- Category-level performance
- Store-level performance

This evidence-first approach keeps the project analytically defensible and makes dashboard
recommendations traceable to the underlying data model.

---

## Conclusion

The project demonstrates an end-to-end retail analytics workflow connecting:

**Retail Data → Data Engineering → dbt Transformation → Analytical Marts → Forecasting →
Evaluation → BI Decision Support**

The objective is not simply to produce a forecast.

The objective is to create a defensible analytical system in which business users can move
from observed demand, to explanation, to forecast, to an informed operational decision.
