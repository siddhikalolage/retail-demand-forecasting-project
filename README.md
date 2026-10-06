# Retail Demand Forecasting

An end-to-end retail demand-planning project: Azure SQL source data is loaded
into Snowflake RAW, transformed with dbt into a Kimball-style warehouse and
decision marts, forecast with Snowflake Cortex, and explored through a
five-page Power BI command center.

## What it answers

- Where are revenue and unit demand concentrated, growing, or softening?
- Are price, event, weekday/weekend, or SNAP signals associated with the shift?
- Which future forecasts need conservative replenishment because their 95%
  planning interval is wide?
- What operational action should be reviewed next?

## Architecture

```text
M5 CSVs -> Azure SQL raw -> Snowflake RAW -> dbt STAGING / INTERMEDIATE
       -> WAREHOUSE facts and dimensions -> MARTS -> Power BI command center
                                             -> Snowflake Cortex forecast
```

## Power BI command center

The canonical, editable report source is
[`powerbi/retail_demand_command_center/retail_demand_command_center.pbip`](powerbi/retail_demand_command_center/retail_demand_command_center.pbip).
It replaces the legacy PBIX/PBIP copies and is intentionally source-controlled
as a PBIP project rather than a large binary export.

The five report pages are:

1. Executive Pulse - headline revenue, units, selling price, trend, and forecast risk.
2. Demand Intelligence - category, department, and store concentration plus demand signals.
3. Price & Calendar Drivers - price movement, events, weekday/weekend, and SNAP context.
4. Forecast Control Tower - future demand, 95% planning range, item watchlist, and action trigger.
5. Action & Risk Center - concise operating actions and validation guardrails.

The report separates historical actuals from future forecasts. A future forecast
does not have an observed actual yet; forecast quality must be evaluated through
the historical backtest marts, not by claiming that a future prediction has
already been validated.

### Open and refresh the report

1. Build the dbt models, including `fact_daily_sales`, `fact_forecast_daily`, and `mart_forecast_vs_actual`.
2. In Power BI Desktop, open the PBIP file above.
3. In the semantic model, set the four expressions in `definition/expressions.tmdl` for your Snowflake account, warehouse, role, and database. The default role is `POWERBI_READER`; no account endpoint or credentials are committed.
4. Refresh and confirm that the Snowflake reader role has the grants in `sql/snowflake/04_grant_powerbi_reader.sql`.

For the row-count smoke test, relationship checks, measure catalog, and the
manual five-page design plan, see
[`powerbi/POWERBI_MANUAL_BUILD_GUIDE.md`](powerbi/POWERBI_MANUAL_BUILD_GUIDE.md).
The corresponding Snowflake validation script is
[`sql/snowflake/06_powerbi_smoke_test.sql`](sql/snowflake/06_powerbi_smoke_test.sql).

To regenerate the report-definition JSON from the documented layout, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\powerbi\build_command_center.ps1
```

This does not connect to Snowflake or write data; it only recreates the report
definition from the source layout.

## Local setup

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
dbt deps --project-dir dbt
dbt build --project-dir dbt --profiles-dir dbt
python scripts\profile_data.py --output logs\data_profile.json
```

Create a local `.env` from `.env.example` before using Azure SQL, Snowflake, or
the profiling script. Secrets and Power BI local cache files are ignored.

## Quality controls

- dbt source, schema, grain, reconciliation, and freshness tests.
- Read-only profiling in `scripts/profile_data.py` and `sql/profile/` using the
  current `RETAIL_DB` table names.
- Re-runnable mart verification in `sql/verify/09_phase4_agg_sales_daily_verification.sql`.
- Forecast intervals used as operational uncertainty ranges, not as future
  accuracy claims.

## Project map

| Path | Purpose |
| --- | --- |
| `scripts/` | Azure/Snowflake load, smoke-test, and profile utilities. |
| `sql/` | Provisioning, source DDL, profile packs, and verification queries. |
| `dbt/` | Transformations, tests, and model documentation. |
| `airflow/` | Local manual-trigger Airflow orchestration. |
| `powerbi/` | The PBIP command center and its reproducible report builder. |
