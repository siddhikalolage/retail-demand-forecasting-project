# Project file guide

This is the current project map. Legacy Power BI packages, redesign backups,
screenshots, and one-off inspection scripts were intentionally removed; the
PBIP source below is now the single dashboard source of truth.

| Area | Key files | Purpose |
| --- | --- | --- |
| Ingestion | `scripts/load_m5_to_azure_sql.py`, `scripts/extract_azure_to_snowflake.py` | Load M5 CSVs to Azure SQL then incrementally land them in Snowflake RAW. |
| Source schema | `sql/ddl/01_create_raw_tables.sql` | Creates the Azure SQL `raw` source tables. |
| Snowflake | `sql/snowflake/` | Provisions roles, warehouse, RAW tables, forecast workflow, and Power BI reader grants. |
| Transformations | `dbt/models/` | dbt staging, intermediate, warehouse dimensions/facts, and marts. |
| Quality | `dbt/tests/`, `sql/profile/`, `sql/verify/`, `scripts/profile_data.py` | Automated dbt tests plus read-only diagnostics and reconciliation packs. |
| Orchestration | `airflow/dags/m5_daily_extract.py` | Manual-trigger Airflow DAG for extract, dbt, and verification. |
| Dashboard | `powerbi/retail_demand_command_center/` | Editable Power BI command-center PBIP project. |
| Dashboard builder | `powerbi/build_command_center.ps1` | Recreates report JSON only; it does not connect to data sources. |
| Documentation | `README.md` | Setup, model boundary, dashboard purpose, and quality controls. |

## Power BI source layout

```text
powerbi/
  build_command_center.ps1
  retail_demand_command_center/
    retail_demand_command_center.pbip
    retail_demand_command_center.Report/
    retail_demand_command_center.SemanticModel/
      definition/expressions.tmdl
      definition/tables/
```

Open `retail_demand_command_center.pbip` in Power BI Desktop. Before the first
refresh, set the account, warehouse, role, and database expressions. Use the
least-privileged `POWERBI_READER` Snowflake role and never store credentials in
the PBIP files.
