# Data-quality controls

The project works with long-format M5 source data and the `RETAIL_DB` dbt
warehouse. Use the runnable checks in `sql/profile/` and `sql/verify/` or the
read-only `scripts/profile_data.py` utility; this page states the contract they
enforce.

| Layer | Object | Required condition |
| --- | --- | --- |
| RAW | `CALENDAR` | `d` is unique and `date` converts to a valid date. |
| RAW | `SALES_TRAIN` | One row per `id` and `d`; units are non-null and non-negative. |
| RAW | `SELL_PRICES` | One row per `store_id`, `item_id`, and `wm_yr_wk`; price is non-negative. |
| WAREHOUSE | `DIM_CALENDAR` | `calendar_date` is unique. Future rows are allowed for the forecast horizon; freshness is evaluated only where `d` is populated. |
| WAREHOUSE | `FACT_DAILY_SALES` | Item-store-date grain, non-negative units and revenue, and reconciled source coverage. |
| WAREHOUSE | `FACT_FORECAST_DAILY` | Forecast interval lower bound never exceeds upper bound. |
| MARTS | `AGG_SALES_DAILY` | One row per `date_key`; units and revenue reconcile to `FACT_DAILY_SALES`. |
| MARTS | `MART_FORECAST_VS_ACTUAL` | One row per item, observation date, and series type. |

## Forecast boundary

`MART_FORECAST_VS_ACTUAL` joins historical actuals and future forecasts into a
common reporting shape. Future forecast rows intentionally have no observed
actual. Evaluate quality through the backtest/evaluation marts only where an
actual is available; do not calculate or present a future accuracy metric.

## Operational response

1. A failing dbt test blocks the affected model from being treated as trusted.
2. A profiling `ERROR` means the object or privilege must be fixed before the
   dashboard is refreshed.
3. A wide forecast interval is a planning-risk signal: increase review cadence
   or use a conservative reorder quantity; it is not evidence that the model
   has failed.
