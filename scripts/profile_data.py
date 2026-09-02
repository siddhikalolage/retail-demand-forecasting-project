#!/usr/bin/env python3
# =============================================================================
# scripts/profile_data.py
# =============================================================================
# Phase 4 Data Profiling Script
# 
# Executes comprehensive data quality checks against the Snowflake warehouse.
# Generates a structured report with row counts, cardinality, anomalies.
#
# Usage:
#   python scripts/profile_data.py
#
# Requires:
#   - .env file with Snowflake credentials
#   - Snowflake Python connector
# =============================================================================

import os
import sys
from datetime import datetime
from typing import Dict, List, Any
import json

# Optional: Snowflake connector (install with: pip install snowflake-connector-python)
try:
    from snowflake.connector import connect as snowflake_connect
except ImportError:
    print("WARNING: snowflake-connector-python not installed.")
    print("Install with: pip install snowflake-connector-python")
    snowflake_connect = None


class DataProfiler:
    """Execute comprehensive data quality profiling against Snowflake."""
    
    def __init__(self):
        """Initialize profiler with environment credentials."""
        self.account = os.getenv('SNOWFLAKE_ACCOUNT')
        self.user = os.getenv('SNOWFLAKE_USER')
        self.password = os.getenv('SNOWFLAKE_PASSWORD')
        self.warehouse = os.getenv('SNOWFLAKE_WAREHOUSE')
        self.database = os.getenv('SNOWFLAKE_DATABASE', 'RETAIL_DB')
        self.schema = os.getenv('SNOWFLAKE_SCHEMA', 'RAW')
        
        self.connection = None
        self.results = []
        self.start_time = datetime.now()
        
    def connect(self) -> bool:
        """Establish Snowflake connection."""
        if not snowflake_connect:
            print("ERROR: Snowflake connector not available. Install snowflake-connector-python.")
            return False
            
        if not all([self.account, self.user, self.password]):
            print("ERROR: Missing Snowflake credentials in .env file.")
            print("Required: SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_PASSWORD")
            return False
        
        try:
            self.connection = snowflake_connect(
                account=self.account,
                user=self.user,
                password=self.password,
                warehouse=self.warehouse,
                database=self.database,
                schema=self.schema
            )
            print(f"✓ Connected to Snowflake: {self.account}")
            return True
        except Exception as e:
            print(f"✗ Snowflake connection failed: {str(e)}")
            return False
    
    def execute_query(self, query: str, query_name: str) -> List[Dict[str, Any]]:
        """Execute a query and return results as list of dicts."""
        if not self.connection:
            print(f"✗ Query '{query_name}' skipped (no connection)")
            return []
        
        try:
            cursor = self.connection.cursor()
            cursor.execute(query)
            columns = [desc[0] for desc in cursor.description]
            rows = cursor.fetchall()
            results = [dict(zip(columns, row)) for row in rows]
            print(f"✓ {query_name}: {len(results)} result(s)")
            return results
        except Exception as e:
            print(f"✗ Query '{query_name}' failed: {str(e)}")
            return []
    
    def profile_calendar(self) -> Dict[str, Any]:
        """Profile calendar dimension."""
        print("\n--- Calendar Dimension ---")
        
        checks = {}
        
        # Date range
        query = """
        SELECT MIN(DATE) as min_date, MAX(DATE) as max_date, COUNT(*) as total_days
        FROM RAW.CALENDAR
        """
        result = self.execute_query(query, "Calendar: Date Range")
        if result:
            checks['date_range'] = result[0]
        
        # Calendar attributes
        query = """
        SELECT 
            COUNT(DISTINCT WEEKDAY) as unique_weekdays,
            COUNT(DISTINCT MONTH) as unique_months,
            COUNT(DISTINCT YEAR) as unique_years,
            SUM(CASE WHEN EVENT_NAME_1 IS NOT NULL THEN 1 ELSE 0 END) as days_with_events
        FROM RAW.CALENDAR
        """
        result = self.execute_query(query, "Calendar: Attributes")
        if result:
            checks['attributes'] = result[0]
        
        return checks
    
    def profile_sales(self) -> Dict[str, Any]:
        """Profile sales fact table."""
        print("\n--- Sales Fact Table ---")
        
        checks = {}
        
        # Grain validation
        query = """
        SELECT 
            COUNT(*) as total_rows,
            COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || DATE)) as unique_keys
        FROM RAW.M5_SALES_TRAIN
        """
        result = self.execute_query(query, "Sales: Grain")
        if result:
            total = result[0]['TOTAL_ROWS']
            unique = result[0]['UNIQUE_KEYS']
            checks['grain'] = {
                'total_rows': total,
                'unique_keys': unique,
                'is_grain_valid': total == unique,
                'status': 'PASS - Item × Store × Day grain valid' if total == unique else 'FAIL - Duplicates detected'
            }
        
        # Value distribution
        query = """
        SELECT 
            MIN(SALES) as min_sales,
            MAX(SALES) as max_sales,
            AVG(SALES) as avg_sales,
            SUM(CASE WHEN SALES < 0 THEN 1 ELSE 0 END) as negative_count,
            SUM(CASE WHEN SALES = 0 THEN 1 ELSE 0 END) as zero_count,
            SUM(CASE WHEN SALES IS NULL THEN 1 ELSE 0 END) as null_count
        FROM RAW.M5_SALES_TRAIN
        """
        result = self.execute_query(query, "Sales: Value Distribution")
        if result:
            checks['value_distribution'] = result[0]
        
        # Dimension counts
        query = """
        SELECT 
            COUNT(DISTINCT ITEM_ID) as unique_items,
            COUNT(DISTINCT STORE_ID) as unique_stores,
            COUNT(DISTINCT DATE) as unique_dates
        FROM RAW.M5_SALES_TRAIN
        """
        result = self.execute_query(query, "Sales: Dimensions")
        if result:
            checks['dimensions'] = result[0]
        
        return checks
    
    def profile_prices(self) -> Dict[str, Any]:
        """Profile price dimension."""
        print("\n--- Price Data ---")
        
        checks = {}
        
        # Grain validation
        query = """
        SELECT 
            COUNT(*) as total_rows,
            COUNT(DISTINCT (STORE_ID || '|' || ITEM_ID || '|' || WM_YR_WK)) as unique_keys
        FROM RAW.SELL_PRICES
        """
        result = self.execute_query(query, "Prices: Grain")
        if result:
            total = result[0]['TOTAL_ROWS']
            unique = result[0]['UNIQUE_KEYS']
            checks['grain'] = {
                'total_rows': total,
                'unique_keys': unique,
                'is_grain_valid': total == unique,
                'status': 'PASS - Item × Store × Week grain valid' if total == unique else 'FAIL - Duplicates detected'
            }
        
        # Value distribution
        query = """
        SELECT 
            MIN(SELL_PRICE) as min_price,
            MAX(SELL_PRICE) as max_price,
            AVG(SELL_PRICE) as avg_price,
            SUM(CASE WHEN SELL_PRICE IS NULL THEN 1 ELSE 0 END) as null_count,
            SUM(CASE WHEN SELL_PRICE < 0 THEN 1 ELSE 0 END) as negative_count
        FROM RAW.SELL_PRICES
        """
        result = self.execute_query(query, "Prices: Value Distribution")
        if result:
            checks['value_distribution'] = result[0]
        
        return checks
    
    def profile_forecast(self) -> Dict[str, Any]:
        """Profile forecast fact table (warehouse layer)."""
        print("\n--- Forecast Fact Table ---")
        
        checks = {}
        
        # Grain validation
        query = """
        SELECT 
            COUNT(*) as total_rows,
            COUNT(DISTINCT ITEM_ID) as unique_items,
            COUNT(DISTINCT FORECAST_DATE) as unique_dates,
            MIN(FORECAST_DATE) as min_date,
            MAX(FORECAST_DATE) as max_date
        FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
        """
        result = self.execute_query(query, "Forecast: Grain & Date Range")
        if result:
            checks['grain'] = result[0]
        
        # Forecast value distribution
        query = """
        SELECT 
            MIN(FORECAST_VALUE) as min_forecast,
            MAX(FORECAST_VALUE) as max_forecast,
            AVG(FORECAST_VALUE) as avg_forecast,
            SUM(CASE WHEN FORECAST_VALUE IS NULL THEN 1 ELSE 0 END) as null_count
        FROM DEV.WAREHOUSE.FACT_FORECAST_DAILY
        """
        result = self.execute_query(query, "Forecast: Value Distribution")
        if result:
            checks['value_distribution'] = result[0]
        
        return checks
    
    def run_full_profile(self) -> Dict[str, Any]:
        """Execute comprehensive profiling suite."""
        print(f"\n{'='*60}")
        print(f"DATA PROFILING STARTED: {self.start_time.isoformat()}")
        print(f"{'='*60}")
        
        profile_data = {
            'timestamp': self.start_time.isoformat(),
            'connection': {
                'account': self.account,
                'warehouse': self.warehouse,
                'database': self.database,
                'schema': self.schema
            },
            'profiles': {}
        }
        
        if not self.connect():
            print("\nProfiling aborted: No database connection.")
            return profile_data
        
        # Execute profiling
        profile_data['profiles']['calendar'] = self.profile_calendar()
        profile_data['profiles']['sales'] = self.profile_sales()
        profile_data['profiles']['prices'] = self.profile_prices()
        profile_data['profiles']['forecast'] = self.profile_forecast()
        
        # Generate summary
        end_time = datetime.now()
        duration = (end_time - self.start_time).total_seconds()
        
        profile_data['duration_seconds'] = duration
        profile_data['timestamp_end'] = end_time.isoformat()
        
        print(f"\n{'='*60}")
        print(f"PROFILING COMPLETE in {duration:.1f}s")
        print(f"{'='*60}\n")
        
        return profile_data
    
    def export_json(self, output_path: str) -> bool:
        """Export profiling results as JSON."""
        try:
            with open(output_path, 'w') as f:
                json.dump(self.results, f, indent=2, default=str)
            print(f"✓ Results exported to: {output_path}")
            return True
        except Exception as e:
            print(f"✗ Export failed: {str(e)}")
            return False


def main():
    """Main entry point."""
    profiler = DataProfiler()
    profile_results = profiler.run_full_profile()
    
    # Print summary
    if profile_results.get('profiles'):
        print("\nPROFILE SUMMARY:")
        print(json.dumps(profile_results, indent=2, default=str))
    
    # TODO: Export to JSON and feed into DATA_QUALITY.md generation


if __name__ == '__main__':
    main()
