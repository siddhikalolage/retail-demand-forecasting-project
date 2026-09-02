# WORKING_CONVENTIONS.md — Development Standards & Practices

This document codifies the architectural decisions, code style, and development practices used across the retail demand forecasting project.

---

## Code Style Standards

### SQL

- **All keywords in CAPITALS**: `SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, `ORDER BY`, `INSERT`, `UPDATE`, `DELETE`, `CREATE TABLE`, `ALTER`, `DROP`, etc.
- Applied consistently across all SQL dialects: Snowflake (primary), T-SQL (Azure SQL), and dbt SQL models
- Reason: Improves readability; makes keywords visually distinct from identifiers

**Example**:
```sql
SELECT
    customer_id,
    SUM(order_amount) AS total_revenue,
    COUNT(*) AS order_count
FROM fact_orders
WHERE order_date >= '2023-01-01'
GROUP BY customer_id
ORDER BY total_revenue DESC;
```

### Python

- Follow PEP 8 style guide
- Use type hints for function arguments and return types (Python 3.7+)
- Docstrings for all modules, classes, and functions (Google-style format)
- Use `ruff` for linting; F821 (undefined names) enforced in CI to catch stale variable references
- Use `pyright` for static type checking (configured via `pyrightconfig.json`)

**Example**:
```python
def calculate_revenue(units: int, price: float) -> float:
    """
    Calculate total revenue.
    
    Args:
        units: Number of units sold
        price: Price per unit in USD
    
    Returns:
        Total revenue as float
    """
    return units * price
```

### dbt

- Use snake_case for all model, macro, and variable names
- Prefix models by layer: `stg_` (staging), `int_` (intermediate), `dim_` / `fact_` (warehouse), `mart_` (mart)
- All dbt models are written in SQL; avoid Jinja unless required for logic parameterization
- Every model includes a `description` and column-level `description` in the YAML config
- Use dbt tests for data quality: nullness, uniqueness, primary keys, and relationships
- See `dbt/models/schema.yml` for complete model definitions and test logic

### YAML & Configuration

- Use 2-space indentation (not tabs)
- Quote strings with special characters or numbers; leave simple strings unquoted
- Use `true` / `false` for booleans (lowercase, not `True` / `False`)

---

## Git & Version Control

### Commit Hygiene

- Commit messages are concise and descriptive (50 characters max for subject line)
- Use imperative mood: "Add forecast validation", not "Added forecast validation"
- Reference related issues or decision records when applicable
- Example: `Add dbt test for fact_daily_sales nullness checks`

### Branch Strategy

- `main` branch is production-ready and stable (all CI checks passing)
- Feature branches are named by feature scope: `feature/forecast-evaluation`, `fix/airflow-schedule-none`
- All changes to `main` require a passing CI build and review before merge

### CI/CD Workflows

CI pipeline runs on all PRs and pushes to `main`:

1. **dbt parse** — catches Jinja errors, ref/source mismatches, and template syntax errors (no DB connection needed)
2. **sqlfluff lint** — SQL style validation (keywords, line length, formatting)
3. **ruff check** — Python linting with F821 enforced (undefined names)
4. **dbt test** — runs locally only (see rationale below); not in CI pipeline to conserve Snowflake credits

**Rationale for excluding `dbt test` from CI**: The M5 dataset is static (historical only, no live data ingestion). Running dbt tests on every PR would burn pay-as-you-go Snowflake credits (~$0.50–$2.00 per test run) without meaningful signal for a portfolio project. Developers run `dbt test` locally before pushing.

---

## Architectural Decisions

### Data Pipeline Layers

The project follows the **medallion** structure within a **Kimball star schema**:

1. **RAW** — Landing zone from Azure SQL extract (no transformations; COPY INTO from source)
2. **STAGING** — `stg_*` models; type casting, renaming, basic standardization; 1:1 mapping to RAW
3. **INTERMEDIATE** — `int_*` models; business logic, joins, aggregations
4. **WAREHOUSE** — `dim_*` and `fact_*` models; Kimball dimensions and facts conformed to a single business grain
5. **MARTS** — `mart_*` models; thin pre-aggregations and materialized views for BI consumption

**Why this design**:
- Clear separation of concerns enables parallel development and testing
- Staging models provide data contract (source schema changes isolated to staging layer)
- Warehouse layer enforces a single source of truth for all analytics
- Marts layer keeps dbt build time reasonable (pre-aggregation of high-cost joins)

### Forecasting Layer

- Cortex ML model trained on intermediate fact table (`int_forecast_input`)
- Forecast results conformed to warehouse schema (`fact_forecast_daily`)
- Forecast joined to actuals via dedicated mart (`mart_forecast_vs_actual`)
- Accuracy metrics (WAPE, bias, confidence intervals) calculated post-generation
- See `BUSINESS_INSIGHTS.md` for forecast KPIs and use cases

### Orchestration: Airflow Schedule

- Airflow DAG `schedule=None` (explicit trigger only, no auto-fire on unpause)
- Rationale: For a portfolio-demo project, manual control of each run is clearer than background automation. In production, would change to `schedule="@daily"` with `catchup=True`
- Discipline: NEVER pause a DAG mid-run; always "unpause → trigger → let complete → pause"

---

## Validation & Quality Assurance

### Data Validation Points

Every layer transition includes an explicit verification step:

1. **Post-Extract** — Row count, null percentages, date range, primary key uniqueness
2. **Post-dbt** — Row count, expected columns, schema evolution checks
3. **Post-Forecast** — Forecast generation success, row count vs. actuals, confidence interval bounds

### Testing Strategy

- **Unit tests** (SQL data tests): `dbt test` validates nullness, uniqueness, relationships
- **Integration tests**: Airflow DAG smoke tests across 2+ consecutive dates; verify end-to-end lineage
- **Schema validation**: dbt parse catches Jinja/ref/source errors at build time (no DB needed)
- **Lint checks**: ruff F821 catches undefined variables; sqlfluff catches SQL style drift

---

## Documentation Standards

Every project component should have accompanying documentation:

- **Code files**: Docstrings for functions, classes, modules (Google-style)
- **dbt models**: YAML descriptions at model and column level
- **Processes**: Layer-by-layer walkthroughs in `*_PIPELINE.md` files
- **Decisions**: Record rationale in `LEARNINGS.md` alongside the implementation
- **Glossary**: All business terms and technical jargon defined in `GLOSSARY.md`

---

## Security & Credentials

- **No credentials in code**: All secrets stored in `.env` file (ignored by git)
- **Template credentials in `.env.example`**: Provides reference for required variables
- **CI/CD secrets**: GitHub Actions uses `SNOWFLAKE_USER`, `SNOWFLAKE_PASSWORD`, etc. from repo secrets (never logged)
- **Local development**: `.env` file is gitignored; developers set their own credentials

---

## Performance & Cost Discipline

### Snowflake Cost Optimization

- **Use incremental models** for large fact tables (e.g., `fact_daily_sales` partitioned on `load_date`)
- **Cluster key on common join keys** (e.g., `item_id`, `store_id` on fact tables)
- **Avoid SELECT \*** ; always specify required columns
- **Run dbt test locally**, not in CI, to avoid burning credits on every push
- **Monitor spend**: Keep daily Snowflake bill <$5 for portfolio-scale workload

### Airflow Cost Optimization

- **Docker LocalExecutor** (not Kubernetes): Sufficient for single-developer portfolio scale
- **schedule=None**: No background processing; manual trigger only
- **No live refresh**: Power BI runs on Import mode (data baked into .pbix); no live Snowflake queries from dashboard

---

## Development Workflow

### Adding a New Model

1. Create `.sql` file in appropriate `dbt/models/` subdirectory (staging / intermediate / warehouse / marts)
2. Add YAML entry to `dbt/models/schema.yml` with model and column descriptions
3. Add dbt tests (nullness, uniqueness, relationships as appropriate)
4. Run `dbt parse` to validate syntax
5. Run `dbt test --models new_model` locally to verify logic
6. Commit with message: "Add `new_model` for [business purpose]"

### Adding a New Feature to Power BI

1. Add columns / measures to dbt marts if needed
2. Refresh Power BI data model (Ctrl+Shift+R in Power Query Editor)
3. Add visual to appropriate Power BI page
4. Verify measure logic in formula bar; cross-check against mart query
5. Test visual with slicers; ensure cross-page filters work
6. Document in `POWERBI_PIPELINE.md` §[relevant section]

---

## Decision Framework

When evaluating a technology choice or architecture decision:

- **Is it justified?** Does it solve a real problem, or is it gold-plating?
- **Will it scale to production?** Sustainable patterns from day 1; avoid refactoring later
- **Is it documented?** If it's not written down, it's tribal knowledge; write it down
- **Can the next person understand it?** Optimize for clarity and onboarding, not cleverness

---

## Rollout & Release Discipline

- **Feature parity**: All features complete and tested before merge to `main`
- **No partial deployments**: DAG, dbt models, and Power BI changes coordinated in a single release
- **Smoke testing**: Run DAG for 2+ consecutive dates before marking complete
- **Documentation**: README and LEARNINGS updated before final commit
- **Git tagging**: Tag stable releases (e.g., `v1.0`, `v1.1`) for portfolio narrative clarity

---

## Emergency / Rollback

If a DAG run fails:

1. Check Airflow UI for task-level error logs
2. Verify Snowflake table state (row count, schema)
3. Check dbt build log for model errors or SQL syntax issues
4. Retry the failing task from Airflow UI (if deterministic failure)
5. If unrecoverable, revert to previous commit and investigate root cause

If a Power BI measure is wrong:

1. Open Power BI Desktop; verify DAX formula in formula bar
2. Check mart query output in Snowflake directly
3. Refresh semantic model in Power BI (Ctrl+Shift+R)
4. Verify measure logic against POWERBI_PIPELINE.md documentation
5. If necessary, roll back .pbix from git history and re-apply changes

---

## Continuous Improvement

- Review `LEARNINGS.md` at end of each feature sprint; add new lessons learned
- Monthly: Scan CI logs for new error patterns; update documentation or add guards
- Quarterly: Review code metrics (dbt model count, query complexity, Snowflake cost); identify optimization opportunities
- Annually: Refresh decision log; document choices that are still valid vs. those that should evolve

