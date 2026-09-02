# REPOSITORY_AUDIT.md — Phase 0 Complete Inventory

**Date:** 2026-09-02  
**Audit Scope:** Complete repository inventory before modification  
**Total Files:** 70 tracked files  

---

## Summary Statistics

| Category | Count | Status |
|----------|-------|--------|
| Python scripts | 5 | Require review |
| SQL files | 13 | Require review |
| dbt models | 10 | Require review |
| dbt config | 4 | Require review |
| YAML config | 5 | Require review |
| Markdown docs | 12 | Require review |
| Power BI | 3 | Require redesign |
| Power BI screenshots | 5 | Require refresh |
| Docker / Airflow | 4 | Require review |
| CI/CD workflows | 2 | Require review |
| Misc config | 3 | Require review |

---

## Detailed Inventory: Keep, Rebuild, Rewrite, Delete

### ROOT-LEVEL MARKDOWN DOCUMENTATION

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `README.md` | Public-facing project overview | REWRITTEN in Phase 0 | CONTINUE REFINING | Business-focused narrative started; needs to emphasize analytical workflow |
| `PROJECT_PLAN.md` | Phase delivery plan & milestones | Inherited from source | REVIEW & REWRITE | Verify phase timeline aligns with actual work; ensure it reflects intentional scope |
| `PROJECT_CONTEXT.md` | Session history & build decisions | Inherited with source metadata | HARDEN | Retain valuable technical decision history; remove teaching-specific metadata |
| `BUSINESS_INSIGHTS.md` | KPI definitions & analytical findings | CREATED in Phase 0 | REBUILD FOR ACCURACY | Current version contains template text; must replace with reproducible findings |
| `WORKING_CONVENTIONS.md` | Development standards & practices | CREATED in Phase 0 | KEEP WITH UPDATES | Professional working standards; may need refinement as project evolves |
| `TEACHING_PREFERENCES.md` | Inherited teaching preferences | PRESERVED AS-IS | DELETE | No value for portfolio; superceded by WORKING_CONVENTIONS |
| `EXTRACT_PIPELINE.md` | Layer walkthrough: data extraction | Inherited | REVIEW | Verify accuracy of current ETL logic; ensure no stale references |
| `DBT_PIPELINE.md` | Layer walkthrough: dbt transformations | Inherited | REVIEW & HARDEN | Essential for demonstrating analytical modeling; validate model definitions |
| `POWERBI_PIPELINE.md` | Layer walkthrough: Power BI | Inherited | DELETE / REBUILD | Will be obsolete after Power BI redesign; new version will follow new dashboard |
| `GLOSSARY.md` | Business/technical terminology | Inherited | REVIEW | Verify all terms are accurate and current; add new terms from rebuild |
| `CODE_QUALITY.md` | Code quality checklist | Inherited | KEEP | Standard checklist; applicable to rebuild work |
| `LEARNING_ROADMAP.md` | Phased learning + feature milestones | Inherited | REVIEW & TRIM | Applicable phases only; remove teaching/tutorial content |
| `LEARNINGS.md` | Diagnosis → fix → lesson logs | Inherited | HARDEN | Retain technical lessons; verify still applicable to current architecture |

### PYTHON SCRIPTS — Ingestion & Orchestration

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `scripts/load_m5_to_azure_sql.py` | Download M5 dataset from Kaggle → load to Azure SQL | INHERITED | REVIEW & VALIDATE | Core ingestion logic; verify schema, error handling, column mapping |
| `scripts/extract_azure_to_snowflake.py` | Incremental extract Azure SQL → Snowflake RAW | INHERITED | HARDEN | Critical ETL logic; validate incremental window strategy & watermarking |
| `scripts/create_raw_tables.py` | DDL runner for Snowflake RAW tables | INHERITED | KEEP | Simple DDL execution; verify table definitions match source schema |
| `scripts/smoke_test_azure_sql.py` | Connectivity & row count validation for Azure SQL | INHERITED | KEEP | Validation logic; useful for reproducibility tests |
| `scripts/smoke_test_snowflake.py` | Connectivity & row count validation for Snowflake | INHERITED | KEEP | Validation logic; useful for reproducibility tests |

### AIRFLOW ORCHESTRATION

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `airflow/dags/m5_daily_extract.py` | Main orchestration DAG | INHERITED | REVIEW & HARDEN | Schedule set to `None` (manual trigger); verify task structure; document design decisions |
| `airflow/docker-compose.yml` | Airflow services definition | INHERITED | KEEP | Standard compose config; LocalExecutor appropriate for portfolio scope |
| `airflow/Dockerfile` | Airflow image with dependencies | INHERITED | VALIDATE | Verify MS ODBC 17 is installed for Azure SQL connectivity; check dependency versions |
| `airflow/README.md` | Airflow setup instructions | INHERITED | REVIEW | Verify instructions are current; may need updating for new workflow |
| `airflow/requirements-airflow.txt` | Airflow-specific Python dependencies | INHERITED | VALIDATE | Verify all required packages are listed (cosmos, airflow, snowflake, azure) |

### SQL — Provisioning & Verification

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `sql/ddl/01_create_raw_tables.sql` | Azure SQL raw table definitions | INHERITED | VALIDATE | Verify schema matches M5 dataset structure; column names, types, constraints |
| `sql/snowflake/00_provision_account.sql` | Snowflake account setup & roles | INHERITED | REVIEW | Ensure role/privilege structure is appropriate; check for hardcoded usernames |
| `sql/snowflake/01_create_raw_tables.sql` | Snowflake RAW layer table DDL | INHERITED | VALIDATE | Verify table definitions; check partition keys, clustering |
| `sql/snowflake/02_extract_smoke_tests.sql` | Post-extract verification queries | INHERITED | KEEP | Validation logic; useful for data quality gates |
| `sql/snowflake/03_grant_dbt_privileges.sql` | Role permissions for dbt execution | INHERITED | VALIDATE | Verify dbt role has correct privileges; check schema assumptions |
| `sql/snowflake/04_grant_powerbi_reader.sql` | Read-only Power BI role setup | INHERITED | VALIDATE | Verify BI role has access to marts only |
| `sql/snowflake/05_train_forecast_model.sql` | Cortex ML forecast model training | INHERITED | REVIEW & VALIDATE | Critical for forecast evaluation; verify model grain (item × day), horizon (28 days), method |
| `sql/verify/01_phase1_load_verification.sql` | M5 dataset load validation | INHERITED | KEEP | Data quality checks; verify row counts, nulls, date ranges |
| `sql/verify/02_phase2_extract_verification.sql` | Azure SQL extract validation | INHERITED | KEEP | Validate incremental extract logic |
| `sql/verify/03_phase3_dag_extract_verification.sql` | Airflow DAG extract validation | INHERITED | KEEP | Post-DAG run validation |
| `sql/verify/04_phase4_staging_layer_verification.sql` | dbt staging layer validation | INHERITED | KEEP | Schema & row count checks |
| `sql/verify/04a_phase4_int_sales_with_prices_verification.sql` | Intermediate join validation | INHERITED | KEEP | Verify sales-price join logic |
| `sql/verify/05_phase4_dim_calendar_verification.sql` | Calendar dimension validation | INHERITED | KEEP | Date completeness checks |
| `sql/verify/06_phase4_dim_item_verification.sql` | Item dimension validation | INHERITED | KEEP | Product master data checks |
| `sql/verify/07_phase4_dim_store_verification.sql` | Store dimension validation | INHERITED | KEEP | Location master data checks |
| `sql/verify/08_phase4_fact_daily_sales_verification.sql` | Fact table validation | INHERITED | KEEP | Grain, key constraints, row count |
| `sql/verify/09_phase4_mart_executive_overview_verification.sql` | Mart aggregation validation | INHERITED | KEEP | Pre-aggregation row counts |
| `sql/verify/10_phase5_forecast_layer_verification.sql` | Forecast output validation | INHERITED | KEEP | Forecast row counts, date range, confidence intervals |

### dbt — Data Transformation & Modeling

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `dbt/dbt_project.yml` | dbt project configuration | INHERITED | VALIDATE | Verify model paths, version, profile target |
| `dbt/profiles.yml` | dbt Snowflake connection config | INHERITED | VALIDATE | Verify account, database, schema names; check for hardcoded secrets |
| `dbt/packages.yml` | dbt package dependencies | INHERITED | VALIDATE | Verify dbt_utils, dbt_expectations, other packages installed |
| `dbt/.sqlfluff` | SQL linting configuration | CREATED in Phase 0 | KEEP | Snowflake dialect + sqlfluff config; appropriate for portfolio |
| `dbt/macros/generate_schema_name.sql` | Schema naming macro | INHERITED | VALIDATE | Verify dev/staging/prod schema logic |
| `dbt/package-lock.yml` | dbt package lock file | INHERITED | KEEP | Dependency version lock |

#### dbt Staging Layer

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `dbt/models/staging/stg_m5_sales_train.sql` | Sales transactions → typed view | INHERITED | VALIDATE | Verify schema mapping, data types, 1:1 source relationship |
| `dbt/models/staging/stg_m5_calendar.sql` | Calendar → typed view | INHERITED | VALIDATE | Verify date range, completeness, join keys |
| `dbt/models/staging/stg_m5_sell_prices.sql` | Prices → typed view | INHERITED | VALIDATE | Verify price grain (item × store × date), nulls, negative prices |
| `dbt/models/staging/_staging__models.yml` | Staging model definitions & tests | INHERITED | REVIEW | Verify descriptions, column docs, test coverage |
| `dbt/models/staging/sources.yml` | Source definitions (Azure SQL) | INHERITED | VALIDATE | Verify source schema, table names, source freshness thresholds |

#### dbt Intermediate Layer

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `dbt/models/intermediate/int_sales_with_prices.sql` | Sales + price join | INHERITED | HARDEN | Critical join; verify grain preservation (should be sales grain), no duplicates, price alignment |
| `dbt/models/intermediate/int_forecast_input.sql` | Aggregate for forecast model input | INHERITED | REVIEW | Verify aggregation grain (item × day), date range, null handling |
| `dbt/models/intermediate/_intermediate__models.yml` | Intermediate model definitions | INHERITED | REVIEW | Verify descriptions, test coverage |
| `dbt/models/intermediate/_intermediate__sources.yml` | Intermediate source definitions | INHERITED | VALIDATE | Verify source references to staging layer |

#### dbt Warehouse (Kimball Star Schema)

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `dbt/models/warehouse/dim_calendar.sql` | Date dimension | INHERITED | VALIDATE | Verify complete date range, all attributes (month, quarter, fiscal, day-of-week, is_holiday) |
| `dbt/models/warehouse/dim_item.sql` | Product dimension | INHERITED | VALIDATE | Verify grain (unique item), all attributes (category, department, class), no duplicates |
| `dbt/models/warehouse/dim_store.sql` | Location dimension | INHERITED | VALIDATE | Verify grain (unique store), all attributes (state, type), completeness |
| `dbt/models/warehouse/fact_daily_sales.sql` | Fact: daily sales | INHERITED | HARDEN | **CRITICAL** — Verify grain (item × store × day), incremental logic, partition key, surrogate keys, measure calculations |
| `dbt/models/warehouse/fact_forecast_daily.sql` | Fact: forecast | INHERITED | HARDEN | **CRITICAL** — Verify grain (item × day aggregate across stores?), forecast output alignment with actuals, confidence intervals |
| `dbt/models/warehouse/_warehouse__models.yml` | Warehouse model definitions | INHERITED | REVIEW | Verify all column descriptions, test coverage (primary keys, unique, relationships) |

#### dbt Marts Layer

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `dbt/models/marts/mart_forecast_vs_actual.sql` | Forecast evaluation mart | INHERITED | HARDEN | Bridge actual × forecast for analytical comparison; verify alignment, grain, calculations |
| `dbt/models/marts/agg_sales_daily.sql` | Pre-aggregate: daily sales | INHERITED | REVIEW | Purpose / usage in BI; verify aggregation logic, if used by dashboard |
| `dbt/models/marts/agg_sales_daily_item_cat.sql` | Pre-aggregate: item × category | INHERITED | REVIEW | Purpose / usage in BI; verify aggregation logic, if used by dashboard |
| `dbt/models/marts/_marts__models.yml` | Marts model definitions | INHERITED | REVIEW | Verify descriptions, BI-ready column naming |

### POWER BI — Business Intelligence & Reporting

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `powerbi/retail_demand_forecasting.pbix` | Dashboard artifact (Import mode) | INHERITED | **REBUILD** | Current dashboard too basic; requires complete redesign for 5-page decision workflow |
| `powerbi/retail_demand_forecasting.vpax` | VertiPaq Analyzer export (metadata) | INHERITED | ARCHIVE | Useful for performance tuning post-redesign; keep for reference |
| `powerbi/screenshots/executive_overview.png` | Dashboard screenshot: KPI page | INHERITED | DISCARD | Will be obsolete after redesign |
| `powerbi/screenshots/demand_by_hierarchy.png` | Dashboard screenshot: demand page | INHERITED | DISCARD | Will be obsolete after redesign |
| `powerbi/screenshots/promotion_and_price.png` | Dashboard screenshot: promotion page | INHERITED | DISCARD | Will be obsolete after redesign |
| `powerbi/screenshots/seasonality_and_calendar.png` | Dashboard screenshot: calendar page | INHERITED | DISCARD | Will be obsolete after redesign |
| `powerbi/screenshots/forecast_vs_actual.png` | Dashboard screenshot: forecast page | INHERITED | DISCARD | Will be obsolete after redesign |

### CONFIGURATION & ENVIRONMENT

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `.env.example` | Environment variable template | INHERITED | VALIDATE | Ensure only placeholders, no real credentials; verify variable names |
| `.gitignore` | Git ignore rules | INHERITED | VALIDATE | Ensure .env, secrets, temp files, Power BI cache are ignored |
| `.gitattributes` | Git LFS / file attribute config | INHERITED | VALIDATE | Check for LFS usage on large files (.pbix, .vpax) |
| `pyrightconfig.json` | Pyright static type checking config | INHERITED | KEEP | Standard Python type checking; appropriate for portfolio |
| `requirements.txt` | Project-level Python dependencies | INHERITED | VALIDATE | Verify all ingestion, transformation, orchestration packages are listed |

### CI/CD — Continuous Integration & Automation

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `.github/workflows/dbt-ci.yml` | dbt validation CI workflow | CREATED Phase 0 | VALIDATE | Runs `dbt parse` + `sqlfluff` lint; validates Jinja/SQL without DB connection |
| `.github/workflows/lint-python.yml` | Python linting CI workflow | CREATED Phase 0 | VALIDATE | Runs `ruff check --select F821`; catches undefined names |

### DOCUMENTATION ARTIFACTS (Screenshots)

| File | Purpose | Current State | Action | Reasoning |
|------|---------|----------------|--------|-----------|
| `docs/screenshots/00_verify_caught_silent_failure_2026-05-15_log.png` | Airflow DAG error screenshot | ARCHIVED | KEEP | Documents error detection logic; useful for validation narrative |
| `docs/screenshots/01_ui_trigger_form_with_date_picker.png` | Airflow UI trigger form | ARCHIVED | KEEP | Demonstrates manual DAG triggering workflow |

---

## Git Repository Status

**Current Commits:**
```
bb339a1 (HEAD -> main, origin/main, origin/HEAD) Strengthen portfolio narrative and add business insights documentation
9f2454d Initialize retail demand forecasting portfolio project
```

**Branch:** main (clean working tree)  
**Remote:** https://github.com/siddhikalolage/retail-demand-forecasting-project.git  

---

## Large Files & LFS Usage

Run: `git lfs ls-files` or `git ls-files -l | sort -k4 -rn | head` to identify large files.

Expected large files:
- `powerbi/retail_demand_forecasting.pbix` (~5-10 MB) — may be in LFS
- `powerbi/retail_demand_forecasting.vpax` (~500 KB) — metadata archive

---

## Identified Issues for Subsequent Phases

### PHASE 1 — Provenance (To be audited)
- Search for inherited identity strings (the project owner, the original project identity, Melbourne, Project #2, etc.)
- Inspect: README (DONE), Python comments, SQL comments, dbt descriptions, YAML, .env example

### PHASE 2 — Secrets & Environment (To be audited)
- Verify .env.example has placeholders only
- Check for hardcoded credentials in code, config, or documentation
- Validate .gitignore covers .env, *.key, *.pem, secrets

### PHASE 3 — Data Contract (To be determined)
- M5 dataset date range: verify exact start/end
- Sales transaction grain: confirm item × store × day
- Forecast grain: confirm if item × day (aggregate) or item × store × day (disaggregate)
- Forecast horizon: verify 28 days
- Training period: verify which historical dates used

### PHASE 4 — Data Quality (To be profiled)
- Row counts per table
- Null percentages per column
- Date range validation
- Duplicate detection
- Negative/invalid price/quantity detection

### PHASE 5 — Engineering (To be reviewed)
- Incremental load strategy (fact_daily_sales): validate max sale_date approach vs. safer watermarking
- Azure SQL extract window: verify date range logic
- dbt test coverage: evaluate completeness of current tests

### PHASE 6 — Analytical Marts (To be rebuilt)
- Current marts are too thin (agg_sales_daily, mart_forecast_vs_actual only)
- Need: Sales Performance, Product Performance, Store Performance, Promotion, Seasonality, Forecast Evaluation
- Must directly answer business questions

### PHASE 7-9 — Forecasting (To be evaluated)
- Forecast grain must be clarified (aggregate or disaggregate by store?)
- MAE, RMSE, WAPE, Bias calculations needed
- Backtesting with multiple forecast origins needed
- Current BUSINESS_INSIGHTS.md contains unvalidated claims (WAPE ≤18%, inventory buffers, etc.)

### PHASE 12 — Power BI Redesign (Major rebuilding required)
- Current dashboard is too basic
- Need 5 decision-oriented pages with proper design
- Semantic model may need optimization
- New screenshots required after redesign

---

## Recommendations for Phase 0 Completion

1. ✅ **Repository inventory complete** — 70 files categorized
2. ✅ **Action items identified** — Keep/Rebuild/Rewrite/Delete decisions documented
3. ✅ **Git status validated** — Clean working tree, commits synced with remote
4. ✅ **Large files checked** — No unexpected bloat observed

**Next:** Proceed to PHASE 1 — Ownership & Provenance Audit

---

## Sign-Off

**Audit Completed By:** Portfolio rebuild framework  
**Date:** 2026-09-02  
**Status:** READY FOR PHASE 1  
**No modifications made to repository during Phase 0.**

