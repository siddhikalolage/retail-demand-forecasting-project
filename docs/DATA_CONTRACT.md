# Analytical data contract

The warehouse database is `RETAIL_DB`. dbt is the authority for object shape;
the definitions in `dbt/models/` and their schema tests take precedence over
this concise reference.

## Sources

| Source | Grain | Business fields |
| --- | --- | --- |
| `RAW.CALENDAR` | M5 day (`d`) | `date`, fiscal week, calendar/event, and SNAP attributes. |
| `RAW.SALES_TRAIN` | item-store-M5 day | identifiers, `d`, and `sales` units. |
| `RAW.SELL_PRICES` | item-store-fiscal week | `sell_price`. |

## Conformed warehouse

| Object | Grain | Contract |
| --- | --- | --- |
| `WAREHOUSE.DIM_CALENDAR` | calendar date | `date_key`, `calendar_date`, M5 `d`, event, holiday, and SNAP fields. The dimension may include future dates with null `d` for forecast display. |
| `WAREHOUSE.DIM_ITEM` | item | `item_key`, item, department, and category hierarchy. |
| `WAREHOUSE.DIM_STORE` | store | `store_key`, store, and state. |
| `WAREHOUSE.FACT_DAILY_SALES` | item-store-sale date | `item_key`, `store_key`, `date_key`, `units_sold`, `sell_price`, `revenue_amount_usd`. |
| `WAREHOUSE.FACT_FORECAST_DAILY` | item-forecast date | keys plus `forecast_units`, `forecast_revenue_usd`, `forecast_units_lower_95`, and `forecast_units_upper_95`. |

## Reporting marts

| Object | Grain | Contract |
| --- | --- | --- |
| `MARTS.AGG_SALES_DAILY` | date key | Daily units, revenue, active item count, and active store count reconciled to the sales fact. |
| `MARTS.MART_FORECAST_VS_ACTUAL` | item-observation date-series type | Common shape for historical `actual` and future `forecast` rows, with units, revenue, and forecast interval fields. |
| Backtest/evaluation marts | item/date or aggregate evaluation grain | Used for forecast error metrics only for observations with known actuals. |

## Semantic-model rules

- Use the dimension-to-fact relationships in the PBIP model with single
  direction filtering.
- Build report measures from facts or the dedicated `_Measures` table so item,
  store, and date filters are honored.
- Treat forecast intervals as planning ranges. They are not observed error and
  must not be labelled as future accuracy.
