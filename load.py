#!/usr/bin/env python3
"""Load the Kaggle Olist Brazilian E-Commerce CSVs into DuckDB and run QA.

Usage (from the project root):
    python3 load.py

Reads sql/01_load.sql, builds data/olist.duckdb, then prints a QA
summary. The raw CSVs live in data/raw/ (git-ignored); the .duckdb file
is also git-ignored — re-run this script to rebuild it.
"""
import duckdb
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DB = ROOT / "data" / "olist.duckdb"
SQL = ROOT / "sql" / "01_load.sql"

con = duckdb.connect(str(DB))
con.execute(SQL.read_text())
print("Loaded tables:", [r[0] for r in con.execute("SHOW TABLES").fetchall()])

qa = {
    "orders": "SELECT COUNT(*) FROM orders",
    "order_items": "SELECT COUNT(*) FROM order_items",
    "products": "SELECT COUNT(*) FROM products",
    "sellers": "SELECT COUNT(*) FROM sellers",
    "customers": "SELECT COUNT(*) FROM customers",
    "payments": "SELECT COUNT(*) FROM payments",
    "reviews": "SELECT COUNT(*) FROM reviews",
    "geolocation": "SELECT COUNT(*) FROM geolocation",
    "categories (translation)": "SELECT COUNT(*) FROM categories",
    "order_level rows": "SELECT COUNT(*) FROM order_level",
    "orders by status": "SELECT order_status, COUNT(*) FROM orders GROUP BY 1 ORDER BY 2 DESC",
    "purchase date range": "SELECT MIN(purchase_ts), MAX(purchase_ts) FROM orders",
    "delivered orders": "SELECT COUNT(*) FROM order_level WHERE is_delivered",
    "delivered revenue (R$, sum of price)":
        "SELECT ROUND(SUM(order_total), 2) FROM order_level WHERE is_delivered",
    "orders with no items": "SELECT COUNT(*) FROM order_level WHERE n_items = 0",
    "orders with no payment": "SELECT COUNT(*) FROM order_level WHERE n_payments IS NULL",
    "orders with multiple payment types":
        "SELECT COUNT(*) FROM order_level WHERE n_payment_types > 1",
    "distinct review orders": "SELECT COUNT(DISTINCT order_id) FROM reviews",
    "duplicate review_ids": "SELECT COUNT(*) - COUNT(DISTINCT review_id) FROM reviews",
    "nulls in key order fields":
        "SELECT COUNT(*) FROM orders WHERE order_id IS NULL OR customer_id IS NULL OR order_status IS NULL",
    "null review scores": "SELECT COUNT(*) FROM reviews WHERE review_score IS NULL",
    "missing review comment message":
        "SELECT COUNT(*) FROM reviews WHERE review_comment_message IS NULL OR TRIM(review_comment_message) = ''",
}
for label, q in qa.items():
    print(f"- {label}: {con.execute(q).fetchall()}")
con.close()
print("OK")
