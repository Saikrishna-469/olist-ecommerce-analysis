#!/usr/bin/env python3
"""Run the SQL analysis (sql/02–08) and save dashboard CSVs.

Usage (from the project root):
    python3 run_analysis.py

Reads data/olist.duckdb (built by load.py), prints every query in
sql/02_trend.sql … sql/08_customers_sellers.sql, and writes the result
of each query to dashboard/<nn>_<name>.csv.
"""
import re
import duckdb
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "olist.duckdb"
DASH = ROOT / "dashboard"
DASH.mkdir(exist_ok=True)

con = duckdb.connect(str(DB), read_only=True)


def split_queries(sql_text):
    """Split a .sql file into (name, sql) pairs on '-- Qn:' comment headers."""
    parts = re.split(r"-- (Q\d+):[^\n]*\n", sql_text)
    # parts: [preamble, 'Q1', sql1, 'Q2', sql2, ...]
    out = []
    for i in range(1, len(parts) - 1, 2):
        out.append((parts[i], parts[i + 1]))
    return out


for fname in ["02_trend.sql", "03_category.sql", "04_geography.sql",
              "05_payments.sql", "06_delivery.sql", "07_reviews.sql",
              "08_customers_sellers.sql"]:
    sql_text = (ROOT / "sql" / fname).read_text()
    prefix = fname[:2]
    for qname, qsql in split_queries(sql_text):
        df = con.execute(qsql).fetchdf()
        print(f"\n=== {fname} {qname} ===")
        print(df.to_string(index=False))
        out = DASH / f"{prefix}_{qname}.csv"
        df.to_csv(out, index=False)
        print(f"saved {out.name} ({len(df)} rows)")

con.close()
print("\nOK")
