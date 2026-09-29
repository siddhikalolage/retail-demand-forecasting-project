#!/usr/bin/env python3
"""Profile the current RETAIL_DB raw and warehouse tables in Snowflake.

Usage:
    python scripts/profile_data.py --output logs/data_profile.json

The script is read-only. It loads local ``.env`` settings, but credentials are
never written to the report. Required settings are SNOWFLAKE_ACCOUNT,
SNOWFLAKE_USER and SNOWFLAKE_PASSWORD; warehouse, database, schema and role
use the project defaults when omitted.
"""

from __future__ import annotations

import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

try:
    from snowflake.connector import connect as snowflake_connect
except ImportError:  # Gives a useful message on development machines.
    snowflake_connect = None


class DataProfiler:
    """Run named, read-only data-quality queries and return structured output."""

    def __init__(self) -> None:
        load_dotenv()
        self.account = os.getenv("SNOWFLAKE_ACCOUNT")
        self.user = os.getenv("SNOWFLAKE_USER")
        self.password = os.getenv("SNOWFLAKE_PASSWORD")
        self.warehouse = os.getenv("SNOWFLAKE_WAREHOUSE", "WH_RETAIL")
        self.database = os.getenv("SNOWFLAKE_DATABASE", "RETAIL_DB")
        self.schema = os.getenv("SNOWFLAKE_SCHEMA", "RAW")
        self.role = os.getenv("SNOWFLAKE_ROLE")
        self.connection: Any | None = None
        self.results: dict[str, Any] = {}

    def connect(self) -> None:
        """Open the Snowflake session or raise a precise configuration error."""
        if snowflake_connect is None:
            raise RuntimeError(
                "snowflake-connector-python is not installed. Run `pip install -r requirements.txt`."
            )
        missing = [
            key
            for key, value in {
                "SNOWFLAKE_ACCOUNT": self.account,
                "SNOWFLAKE_USER": self.user,
                "SNOWFLAKE_PASSWORD": self.password,
            }.items()
            if not value
        ]
        if missing:
            raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

        options = {
            "account": self.account,
            "user": self.user,
            "password": self.password,
            "warehouse": self.warehouse,
            "database": self.database,
            "schema": self.schema,
        }
        if self.role:
            options["role"] = self.role
        self.connection = snowflake_connect(**options)

    def query(self, name: str, sql: str) -> dict[str, Any]:
        """Execute one check and retain either its rows or an actionable error."""
        assert self.connection is not None
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(sql)
                columns = [column[0].lower() for column in cursor.description]
                rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
            return {"status": "PASS", "rows": rows}
        except Exception as error:  # Continue so one unavailable mart does not hide others.
            return {"status": "ERROR", "error": str(error)}

    def run_full_profile(self) -> dict[str, Any]:
        """Profile the actual table names and columns used by the dbt project."""
        started = datetime.now(timezone.utc)
        self.connect()
        db = self.database
        checks = {
            "raw_calendar_coverage": f"""
                SELECT MIN(TRY_TO_DATE(date)) AS first_date,
                       MAX(TRY_TO_DATE(date)) AS last_date,
                       COUNT(*) AS row_count,
                       COUNT_IF(TRY_TO_DATE(date) IS NULL) AS invalid_date_count,
                       COUNT(DISTINCT d) AS distinct_day_keys
                FROM {db}.RAW.CALENDAR
            """,
            "raw_sales_grain_and_values": f"""
                SELECT COUNT(*) AS row_count,
                       COUNT(DISTINCT id || '|' || d) AS distinct_series_day_keys,
                       COUNT_IF(sales < 0) AS negative_unit_rows,
                       COUNT_IF(sales IS NULL) AS null_unit_rows,
                       COUNT(DISTINCT item_id) AS item_count,
                       COUNT(DISTINCT store_id) AS store_count
                FROM {db}.RAW.SALES_TRAIN
            """,
            "raw_price_grain_and_values": f"""
                SELECT COUNT(*) AS row_count,
                       COUNT(DISTINCT store_id || '|' || item_id || '|' || wm_yr_wk) AS distinct_price_keys,
                       COUNT_IF(sell_price < 0) AS negative_price_rows,
                       COUNT_IF(sell_price IS NULL) AS null_price_rows,
                       MIN(sell_price) AS minimum_price,
                       MAX(sell_price) AS maximum_price
                FROM {db}.RAW.SELL_PRICES
            """,
            "daily_sales_reconciliation": f"""
                SELECT COUNT(*) AS row_count,
                       MIN(sale_date) AS first_sale_date,
                       MAX(sale_date) AS last_sale_date,
                       SUM(units_sold) AS total_units,
                       SUM(revenue_amount_usd) AS total_revenue_usd,
                       COUNT_IF(sell_price IS NULL) AS missing_price_rows
                FROM {db}.WAREHOUSE.FACT_DAILY_SALES
            """,
            "forecast_coverage": f"""
                SELECT COUNT(*) AS row_count,
                       MIN(forecast_date) AS first_forecast_date,
                       MAX(forecast_date) AS last_forecast_date,
                       COUNT(DISTINCT item_id) AS item_count,
                       COUNT_IF(forecast_units < 0) AS negative_forecast_rows,
                       COUNT_IF(forecast_units_lower_95 > forecast_units_upper_95) AS invalid_interval_rows
                FROM {db}.WAREHOUSE.FACT_FORECAST_DAILY
            """,
            "actual_forecast_mart_grain": f"""
                SELECT series_type,
                       COUNT(*) AS row_count,
                       COUNT(DISTINCT item_id || '|' || observation_date) AS distinct_item_date_keys,
                       MIN(observation_date) AS first_observation_date,
                       MAX(observation_date) AS last_observation_date
                FROM {db}.MARTS.MART_FORECAST_VS_ACTUAL
                GROUP BY series_type
                ORDER BY series_type
            """,
        }
        profiles = {name: self.query(name, sql) for name, sql in checks.items()}
        finished = datetime.now(timezone.utc)
        self.results = {
            "generated_at_utc": finished.isoformat(),
            "duration_seconds": round((finished - started).total_seconds(), 2),
            "connection": {
                "account": self.account,
                "warehouse": self.warehouse,
                "database": self.database,
                "schema": self.schema,
                "role": self.role,
            },
            "profiles": profiles,
        }
        return self.results

    def close(self) -> None:
        if self.connection is not None:
            self.connection.close()
            self.connection = None

    def export_json(self, output_path: Path) -> None:
        """Write the last profile run, creating only the requested output path."""
        if not self.results:
            raise RuntimeError("No profile results are available; call run_full_profile first.")
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(self.results, indent=2, default=str), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Profile RETAIL_DB quality and coverage.")
    parser.add_argument("--output", type=Path, help="Optional JSON output path.")
    args = parser.parse_args()

    profiler = DataProfiler()
    try:
        report = profiler.run_full_profile()
        print(json.dumps(report, indent=2, default=str))
        if args.output:
            profiler.export_json(args.output)
            print(f"Profile written to {args.output}")
        return 0
    except RuntimeError as error:
        print(f"Profile failed: {error}")
        return 1
    finally:
        profiler.close()


if __name__ == "__main__":
    raise SystemExit(main())
