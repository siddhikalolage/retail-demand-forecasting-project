# Retail Demand Command Center: data, DAX and manual design guide

The editable report is [`retail_demand_command_center.pbip`](retail_demand_command_center/retail_demand_command_center.pbip). The semantic model already contains the Snowflake partitions and the measures in [`_Measures.tmdl`](retail_demand_command_center/retail_demand_command_center.SemanticModel/definition/tables/_Measures.tmdl). This guide is for validating the data first and then rebuilding or refining the page design manually.

## 1. Load the data in the correct order

Power BI does not carry a cached copy of an Import model in the PBIP source files. It must authenticate to Snowflake and refresh the partitions.

1. Build the warehouse and marts with dbt, including `fact_daily_sales`, `fact_forecast_daily`, and `mart_forecast_vs_actual`.
2. Run [`04_grant_powerbi_reader.sql`](../sql/snowflake/04_grant_powerbi_reader.sql) as `ACCOUNTADMIN` once. It grants the least-privilege reader role used by the model.
3. Run [`06_powerbi_smoke_test.sql`](../sql/snowflake/06_powerbi_smoke_test.sql) as `POWERBI_READER`. The five row counts must be non-zero, the mart must show both `actual` and `forecast`, and all relationship/interval failure counts must be zero.
4. Open the PBIP and go to **Transform data > Data source settings**. Sign in to the Snowflake server with an account that has the `POWERBI_READER` role. Do not commit the password or token.
5. In the semantic model, verify these four expressions in `definition/expressions.tmdl`:

   | Expression | Current value |
   | --- | --- |
   | `PBI_Snowflake_Account` | `tq94402.ap-southeast-2.snowflakecomputing.com` |
   | `PBI_Snowflake_Warehouse` | `WH_RETAIL` |
   | `PBI_Snowflake_Role` | `POWERBI_READER` |
   | `PBI_Snowflake_Database` | `RETAIL_DB` |

6. Select **Refresh**. In Data view, confirm that `FACT_DAILY_SALES` and `MART_FORECAST_VS_ACTUAL` contain rows. If they are blank, fix the Snowflake authentication/grants or upstream dbt build first; changing colors or visuals cannot create rows.

## 2. Model relationships and forecast limitation

Keep these active, single-direction dimension-to-fact relationships:

| Dimension | Fact/mart | Key |
| --- | --- | --- |
| `DIM_CALENDAR` | `FACT_DAILY_SALES` | `DATE_KEY` |
| `DIM_ITEM` | `FACT_DAILY_SALES` | `ITEM_KEY` |
| `DIM_STORE` | `FACT_DAILY_SALES` | `STORE_KEY` |
| `DIM_CALENDAR` | `MART_FORECAST_VS_ACTUAL` | `DATE_KEY` |
| `DIM_ITEM` | `MART_FORECAST_VS_ACTUAL` | `ITEM_KEY` |

`MART_FORECAST_VS_ACTUAL` is an item-by-day forecast aggregated across all stores. It intentionally has no `STORE_KEY`. Therefore, do not apply a store slicer to forecast visuals and do not describe a forecast as store-specific. Label the forecast page **item-level / all stores** unless the forecast pipeline is retrained at store-item grain.

Use `DIM_CALENDAR[CALENDAR_DATE]` as the date field and mark `DIM_CALENDAR` as the date table. The calendar includes future dates so forecast rows can be sliced by date.

## 3. Measures that are ready to use

The model contains 29 measures. The main groups are:

- Commercial KPIs: `Total Revenue`, `Total Units`, `Avg Selling Price`, `Active Stores`, `Active Items`.
- Trend: `Revenue Prior Year`, `Revenue Growth %`, `Revenue 30D Average`, `Units 30D Average`, `Units vs 30D Average %`, `Revenue Share %`.
- Drivers: `Price Prior Year`, `Price Change %`, `Holiday Revenue Share %`, `SNAP Revenue Share %`.
- Forecast: `Actual Units`, `Forecast Units`, `Forecast Revenue`, `Forecast Lower 95`, `Forecast Upper 95`, `Forecast Coverage Days`, `Forecast Start Date`, `Forecast End Date`, `Forecast Interval Width %`.
- Decision layer: `Forecast Risk Status`, `Demand Signal`, `Pricing Signal`, `Recommended Action`, `Model Coverage Status`.

The rolling averages are anchored to the latest actual sale in the current item/store context, not to the future maximum calendar date. Forecast series filters use `KEEPFILTERS`, and the SNAP measure uses valid `DIM_CALENDAR[SNAP Day Type]` syntax.

## 4. Manual page design

Use a consistent dark navy canvas, white cards, one teal accent for positive movement, amber for monitoring and red only for risk. Keep a 12-column grid, align all cards to the same baseline, and limit each page to one primary chart plus supporting cards/tables.

### Page 1 — Executive Pulse

- KPI cards: `Total Revenue`, `Revenue Growth %`, `Total Units`, `Avg Selling Price`, `Forecast Risk Status`.
- Line chart: `DIM_CALENDAR[CALENDAR_DATE]` with `Total Revenue` and `Revenue 30D Average`.
- Bar chart: `DIM_ITEM[CAT_ID]` with `Total Revenue`, sorted descending.
- Narrative card: `Demand Signal`, `Recommended Action`, `Model Coverage Status`.
- Slicers: date, category, state. Use a tooltip showing `Revenue Share %` and `Units vs 30D Average %`.

### Page 2 — Demand Intelligence

- Matrix rows: `DIM_ITEM[CAT_ID]`, `DIM_ITEM[DEPT_ID]`, `DIM_ITEM[ITEM_ID]`.
- Values: `Total Units`, `Units 30D Average`, `Units vs 30D Average %`, `Total Revenue`, `Revenue Share %`, `Demand Signal`.
- Add a ranked bar for the top 10 items by `Units vs 30D Average %`.
- Conditional format the percentage column: green above 10%, amber from -10% to 10%, red below -10%.
- Insight: accelerating demand means protect availability; softening demand means investigate price, events and local stock before reordering.

### Page 3 — Price & Calendar Drivers

- Cards: `Price Change %`, `Holiday Revenue Share %`, `SNAP Revenue Share %`, `Units vs 30D Average %`.
- Clustered column: `DIM_CALENDAR[Day Type]` by `Total Units` and `Avg Selling Price`.
- Column chart: `DIM_CALENDAR[MONTH_NAME]` by `Total Revenue`, sorted by `MONTH`.
- Matrix: event name/type with `Total Revenue`, `Total Units`, and `Revenue Share %`.
- Highlight `Pricing Signal`; do not claim causation. A price-demand warning is a review trigger, not proof that price caused the change.

### Page 4 — Forecast Control Tower

- Use `MART_FORECAST_VS_ACTUAL[OBSERVATION_DATE]` on the axis and `SERIES_TYPE` as the legend.
- Plot `Actual Units` and `Forecast Units`. Add `Forecast Lower 95` and `Forecast Upper 95` as the planning band.
- Cards: `Forecast Units`, `Forecast Revenue`, `Forecast Interval Width %`, `Forecast Coverage Days`, `Forecast Start Date`, `Forecast End Date`.
- Watchlist table: `DIM_ITEM[ITEM_ID]`, `Forecast Units`, `Forecast Interval Width %`, `Forecast Risk Status`, `Recommended Action`.
- Add a visible subtitle: **Forecast is item-level across all stores; intervals are planning ranges, not observed accuracy.**

### Page 5 — Action & Risk Center

- Cards: `Forecast Risk Status`, `Model Coverage Status`, `Demand Signal`, `Pricing Signal`.
- Matrix rows: item and category; values: `Demand Signal`, `Pricing Signal`, `Forecast Interval Width %`, `Recommended Action`.
- Conditional formatting: red = high uncertainty or demand softening, amber = monitor, teal = planning-ready/accelerating.
- Add a small “decision rules” text box:
  - High uncertainty → use a conservative reorder quantity and review inputs.
  - Demand accelerating → prioritize replenishment.
  - Demand softening → check price, events and availability.
  - Price increase + demand decline → test a targeted adjustment and monitor margin.

## 5. Final validation before publishing

1. Clear all slicers and confirm the executive cards show values.
2. Select one category and one state; confirm historical visuals change.
3. Select a future date; historical cards may be blank, while forecast visuals should retain forecast values.
4. Confirm no forecast visual is filtered by `DIM_STORE`.
5. Refresh again and record the refresh time in the report subtitle.
6. Treat `No forecast in current selection`, `No historical baseline`, and `Historical view - no forecast available` as intentional data-quality statuses, not as zero values.
