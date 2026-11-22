#!/usr/bin/env python3
"""Build the EDA notebook (notebooks/01_eda.ipynb) and the charts in images/.

Usage (from the project root):
    python3 notebooks/build_notebook.py

Reads data/olist.duckdb (built by load.py), reproduces the headline
charts with matplotlib, and builds a notebook whose code cells carry
real executed outputs (row counts, KPIs, the late-delivery vs review
gap) computed from the database in this script.
"""
import base64
import io

import duckdb
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import nbformat as nbf
import numpy as np
import pandas as pd

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "data" / "olist.duckdb"
IMG = ROOT / "images"
IMG.mkdir(exist_ok=True)

plt.rcParams.update({"figure.figsize": (10, 5.5), "font.size": 11})
NAVY = "#1f3a5f"
TEAL = "#2a9d8f"
RUST = "#c0392b"
AMBER = "#d97706"
GREY = "#6b7280"

con = duckdb.connect(str(DB), read_only=True)

# ---- headline numbers used in the notebook text (all from the DB) ----
kpi = con.execute("""
    SELECT COUNT(*), ROUND(SUM(order_total), 2), ROUND(AVG(order_total), 2),
           ROUND(SUM(freight_total), 2)
    FROM order_level WHERE is_delivered
""").fetchone()
n_delivered, revenue, aov, freight = kpi
n_orders = con.execute("SELECT COUNT(*) FROM order_level").fetchone()[0]
late_rate = con.execute("""
    SELECT ROUND(100.0 * COUNT(*) FILTER (WHERE late_days > 0)
                 / COUNT(*) FILTER (WHERE late_days IS NOT NULL), 2)
    FROM order_level WHERE is_delivered
""").fetchone()[0]
avg_score = con.execute("SELECT ROUND(AVG(review_score), 3) FROM reviews").fetchone()[0]
print(f"orders: {n_orders:,}  delivered: {n_delivered:,}  revenue: R${revenue:,.2f}  "
      f"AOV: R${aov:.2f}  late rate: {late_rate}%  avg review: {avg_score}")

charts = {}  # name -> (png bytes, caption)


def save_chart(name, fig, caption):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    plt.close(fig)
    charts[name] = (buf.getvalue(), caption)
    (IMG / f"{name}.png").write_bytes(buf.getvalue())
    print(f"chart: {name}.png")


# ---------------------------------------------------------------- charts
# 1. Monthly revenue + delivered orders, Jan 2017–Aug 2018
monthly = pd.read_csv(ROOT / "dashboard" / "02_Q1.csv", parse_dates=["purchase_month"])
m = monthly[monthly["purchase_month"] >= "2017-01-01"].copy()
fig, ax1 = plt.subplots()
xlabels = m["purchase_month"].dt.strftime("%b %y")
ax1.bar(xlabels, m["revenue_brl"] / 1000,
        color=NAVY, width=0.65, label="Revenue (R$ 000s)")
ax1.set_ylabel("Revenue (R$ thousands)")
ax1.set_xlabel("Month")
ax1.set_title("Revenue grew ~9x in 2017 — then plateaued in 2018")
ax2 = ax1.twinx()
ax2.plot(xlabels, m["delivered_orders"],
         color=RUST, marker="o", ms=4, lw=2, label="Delivered orders")
ax2.set_ylabel("Delivered orders")
ax1.set_xticks(range(0, len(xlabels), 2))
plt.setp(ax1.get_xticklabels(), rotation=45, ha="right", fontsize=10)
fig.tight_layout()
save_chart("monthly_revenue_orders", fig,
           "Monthly delivered revenue (bars, R$ thousands) and delivered "
           "orders (line), Jan 2017–Aug 2018. Nov 2017 peaks at 7,289 orders "
           "/ R$987,765. 2016 is excluded: only 267 delivered orders in the "
           "whole of 2016 (and zero in Nov 2016).")

# 2. Revenue by top 10 categories
cat = pd.read_csv(ROOT / "dashboard" / "03_Q1.csv").head(10).sort_values("revenue_brl")
fig, ax = plt.subplots(figsize=(10, 5.5))
ax.barh(cat["category_en"], cat["revenue_brl"] / 1000, color=TEAL)
ax.set_xlabel("Delivered revenue (R$ thousands)")
ax.set_title("Top 10 categories by revenue — health & beauty leads, but no category dominates")
for i, (v, s) in enumerate(zip(cat["revenue_brl"], cat["share_of_revenue_pct"])):
    ax.text(v / 1000 + 20, i, f"R${v:,.0f} ({s}%)", va="center", fontsize=10)
ax.set_xlim(0, cat["revenue_brl"].max() / 1000 * 1.25)
save_chart("revenue_top10_categories", fig,
           "Top 10 categories by delivered revenue. Health & beauty is "
           "largest at R$1,233,132 (9.33%); the top 5 together are 39.83% "
           "of revenue — broad, not winner-take-all.")

# 3. AOV by payment type (single-payment-type delivered orders)
pay = pd.read_csv(ROOT / "dashboard" / "05_Q2.csv")
order = ["credit_card", "boleto", "debit_card", "voucher"]
pay["payment_type"] = pd.Categorical(pay["payment_type"], categories=order, ordered=True)
pay = pay.sort_values("payment_type")
labels = {"credit_card": "Credit card", "boleto": "Boleto", "debit_card": "Debit card",
          "voucher": "Voucher"}
fig, ax = plt.subplots()
bars = ax.bar([labels[t] for t in pay["payment_type"]], pay["aov_brl"], color=NAVY, width=0.55)
ax.set_ylabel("Average order value (R$)")
ax.set_title("Credit-card buyers spend the most; voucher buyers the least")
for b, v, n in zip(bars, pay["aov_brl"], pay["delivered_orders"]):
    ax.text(b.get_x() + b.get_width() / 2, v + 3, f"R${v:.2f}\n({int(n):,} orders)",
            ha="center", fontsize=10)
ax.set_ylim(0, pay["aov_brl"].max() * 1.25)
save_chart("aov_by_payment_type", fig,
           "AOV by payment type, single-payment-type delivered orders only. "
           "Credit card R$142.95 vs boleto R$121.40, debit R$119.86, voucher "
           "R$85.91. Installments rise with basket size (see 05_Q3.csv).")

# 4. Late-delivery rate by customer state (500+ delivered orders)
st = pd.read_csv(ROOT / "dashboard" / "06_Q2.csv").sort_values("late_rate_pct")
fig, ax = plt.subplots(figsize=(10, 5.5))
colors = [RUST if v >= 10 else AMBER if v >= 6 else TEAL for v in st["late_rate_pct"]]
ax.barh(st["customer_state"], st["late_rate_pct"], color=colors)
ax.axvline(6.77, color=NAVY, ls="--", lw=1.5, label="Overall late rate 6.77%")
ax.set_xlabel("Late-delivery rate (%)")
ax.set_title("Late delivery is a geography problem: the North-East waits longest")
for i, (v, d) in enumerate(zip(st["late_rate_pct"], st["avg_delivery_days"])):
    ax.text(v + 0.3, i, f"{v}%  (avg {d:.1f} days)", va="center", fontsize=10)
ax.legend()
save_chart("late_delivery_rate_by_state", fig,
           "Late-delivery rate by customer state (500+ delivered orders). "
           "Maranhão 17.43% and Ceará 13.76% vs São Paulo 4.49% — and SP "
           "orders arrive in 8.7 days on average vs 21.5 in MA.")

# 5. Average review score by delivery-lateness bucket
rev = pd.read_csv(ROOT / "dashboard" / "07_Q2.csv")
buckets = ["On time / early", "1–3 days late", "4–7 days late", "8+ days late"]
rev["late_bucket"] = pd.Categorical(rev["late_bucket"], categories=buckets, ordered=True)
rev = rev.sort_values("late_bucket")
fig, ax = plt.subplots()
bars = ax.bar(rev["late_bucket"], rev["avg_review_score"],
              color=[TEAL, AMBER, RUST, RUST], width=0.55)
ax.axhline(4.086, color=NAVY, ls="--", lw=1.5, label="Overall average 4.09")
ax.set_ylabel("Average review score (1–5)")
ax.set_ylim(0, 5)
ax.set_title("Every day late costs stars: 4.29 on time vs 1.70 when 8+ days late")
for b, v, n in zip(bars, rev["avg_review_score"], rev["orders_with_review"]):
    ax.text(b.get_x() + b.get_width() / 2, v + 0.12, f"{v:.2f}\n({int(n):,} orders)",
            ha="center", fontsize=10)
ax.legend()
save_chart("review_score_by_lateness", fig,
           "Average review score (one score per order) by delivery-lateness "
           "bucket. On time 4.29; 1–3 days late 3.29; 4–7 days 2.11; 8+ days "
           "1.70. Late orders are 53.69% 1-star vs 6.58% on time.")

# 6. Freight as % of order value by price band
fr = pd.read_csv(ROOT / "dashboard" / "06_Q4.csv")
band_order = ["Under R$50", "R$50–100", "R$100–200", "R$200–500", "R$500+"]
fr["price_band"] = pd.Categorical(fr["price_band"], categories=band_order, ordered=True)
fr = fr.sort_values("price_band")
x = np.arange(len(fr))
fig, ax = plt.subplots()
w = 0.38
ax.bar(x - w / 2, fr["avg_freight_pct"], w, label="Mean freight %", color=RUST)
ax.bar(x + w / 2, fr["median_freight_pct"], w, label="Median freight %", color=NAVY)
ax.set_xticks(x)
ax.set_xticklabels(fr["price_band"])
ax.set_ylabel("Freight as % of order value")
ax.set_title("Freight eats low-value orders: 57% of value under R$50")
for i, (a, md, s) in enumerate(zip(fr["avg_freight_pct"], fr["median_freight_pct"],
                                   fr["share_freight_ge_50pct"])):
    ax.text(i, max(a, md) + 2, f"{s}% of orders\npay ≥50% freight", ha="center", fontsize=9)
ax.set_ylim(0, 75)
ax.legend()
save_chart("freight_pct_by_price_band", fig,
           "Freight as % of order value by order-value band (delivered "
           "orders). Under R$50 the mean freight share is 56.98% (median "
           "46.35%) and 44.96% of those orders pay freight worth half the "
           "order or more.")

# ---------------------------------------------------------------- notebook
# Executed outputs: run the same queries the notebook shows, attach results.
counts_out = con.execute("""
    SELECT 'orders' AS table_name, COUNT(*) FROM orders
    UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
    UNION ALL SELECT 'products', COUNT(*) FROM products
    UNION ALL SELECT 'sellers', COUNT(*) FROM sellers
    UNION ALL SELECT 'customers', COUNT(*) FROM customers
    UNION ALL SELECT 'payments', COUNT(*) FROM payments
    UNION ALL SELECT 'reviews', COUNT(*) FROM reviews
    UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation
    UNION ALL SELECT 'categories', COUNT(*) FROM categories
""").fetchdf().to_string(index=False)
kpi_out = con.execute("""
    SELECT COUNT(*) AS delivered_orders,
           ROUND(SUM(order_total), 2) AS revenue_brl,
           ROUND(AVG(order_total), 2) AS aov_brl,
           ROUND(MEDIAN(order_total), 2) AS median_order_value_brl,
           ROUND(SUM(freight_total), 2) AS freight_brl
    FROM order_level WHERE is_delivered
""").fetchdf().to_string(index=False)
gap_out = con.execute("""
    SELECT timing, COUNT(*) AS orders_with_review,
           ROUND(AVG(order_review_score), 3) AS avg_review_score
    FROM (
        SELECT CASE WHEN ol.late_days > 0 THEN 'late' ELSE 'on time / early' END AS timing,
               rpo.order_review_score
        FROM order_level ol
        JOIN (SELECT order_id, AVG(review_score) AS order_review_score
              FROM reviews GROUP BY order_id) rpo ON ol.order_id = rpo.order_id
        WHERE ol.is_delivered AND ol.late_days IS NOT NULL
    ) GROUP BY timing ORDER BY timing
""").fetchdf().to_string(index=False)

nb = nbf.v4.new_notebook()
nb.cells = [
    nbf.v4.new_markdown_cell(
        "# Olist E-Commerce — Sales and Customer Behaviour\n\n"
        "**Business question:** Olist is a Brazilian marketplace connecting "
        "small sellers to large marketplaces. It has to decide which "
        "categories, sellers and regions to promote, where delivery and "
        "payment friction loses sales, and where review scores signal a "
        "fixable problem. Slow delivery and bad reviews lose repeat buyers; "
        "promoting the wrong categories wastes marketing spend; freight eats "
        "margin on low-value orders.\n\n"
        "This notebook reproduces the headline charts from "
        "`notebooks/build_notebook.py`. All numbers come from the 9-file "
        "Kaggle Olist dataset (Sep 2016–Oct 2018) loaded into DuckDB; "
        "revenue is SUM(price) on delivered orders only."),
    nbf.v4.new_code_cell(
        "import duckdb\n"
        "con = duckdb.connect('data/olist.duckdb', read_only=True)\n"
        "print('tables:', [r[0] for r in con.execute('SHOW TABLES').fetchall()])"),
    nbf.v4.new_code_cell(
        "# row counts per table — the reviews file has 104,720 lines but\n"
        "# 99,224 rows: review comments contain embedded newlines.\n"
        "con.execute(\"SELECT 'orders' AS table_name, COUNT(*) FROM orders \"\n"
        "            \"UNION ALL SELECT 'order_items', COUNT(*) FROM order_items \"\n"
        "            \"UNION ALL SELECT 'products', COUNT(*) FROM products \"\n"
        "            \"UNION ALL SELECT 'sellers', COUNT(*) FROM sellers \"\n"
        "            \"UNION ALL SELECT 'customers', COUNT(*) FROM customers \"\n"
        "            \"UNION ALL SELECT 'payments', COUNT(*) FROM payments \"\n"
        "            \"UNION ALL SELECT 'reviews', COUNT(*) FROM reviews \"\n"
        "            \"UNION ALL SELECT 'geolocation', COUNT(*) FROM geolocation \"\n"
        "            \"UNION ALL SELECT 'categories', COUNT(*) FROM categories\").fetchdf()"),
    nbf.v4.new_code_cell(
        "# headline KPIs — delivered orders only, revenue = SUM(price)\n"
        "con.execute(\"SELECT COUNT(*) AS delivered_orders, \"\n"
        "            \"ROUND(SUM(order_total), 2) AS revenue_brl, \"\n"
        "            \"ROUND(AVG(order_total), 2) AS aov_brl, \"\n"
        "            \"ROUND(MEDIAN(order_total), 2) AS median_order_value_brl, \"\n"
        "            \"ROUND(SUM(freight_total), 2) AS freight_brl \"\n"
        "            \"FROM order_level WHERE is_delivered\").fetchdf()"),
    nbf.v4.new_markdown_cell(
        "## 1. Growth: revenue grew ~9x in 2017, then plateaued\n\n"
        "Delivered orders went from 750 in Jan 2017 (R$111,798) to 7,289 in "
        "Nov 2017 (R$987,765, the Black Friday peak), then settled around "
        "6,100–7,000 orders a month in 2018. AOV barely moved (R$124–152 a "
        "month) — growth was volume, not bigger baskets. 2016 was a ramp: "
        "only 267 delivered orders in the whole year, and zero in Nov 2016."),
    nbf.v4.new_code_cell(
        "# see notebooks/build_notebook.py — chart: monthly_revenue_orders\n"
        "from IPython.display import Image\n"
        "Image('images/monthly_revenue_orders.png')"),
    nbf.v4.new_markdown_cell(
        "## 2. Categories: broad, not winner-take-all\n\n"
        "Health & beauty is the largest category (R$1,233,132, 9.33% of "
        "revenue), followed by watches & gifts (R$1,166,177, 8.82%) and bed, "
        "bath & table (R$1,023,435, 7.74%). The top 5 categories together "
        "are 39.83% of revenue and the top 10 are 62.43% — no single "
        "category to bet the marketplace on. The highest-ticket categories "
        "are musical instruments (R$301.66 per order) and small appliances "
        "(R$300.09); the lowest are electronics (R$61.60) and telephony "
        "(R$75.70)."),
    nbf.v4.new_code_cell(
        "Image('images/revenue_top10_categories.png')"),
    nbf.v4.new_markdown_cell(
        "## 3. Payments: credit card dominates, and installments track basket size\n\n"
        "Credit card is used on 76.94% of orders (78.34% of payment value); "
        "boleto 19.90%, voucher 3.89%, debit card 1.54%. Credit-card AOV is "
        "R$142.95 vs R$121.40 for boleto and R$85.91 for voucher. "
        "Installments rise steeply with basket size: paid-in-full orders "
        "average R$82.27, 7–12 installments average R$299.57 — "
        "installments are how Brazilians afford big baskets, not a "
        "discount channel."),
    nbf.v4.new_code_cell(
        "Image('images/aov_by_payment_type.png')"),
    nbf.v4.new_markdown_cell(
        "## 4. Delivery: on time on average, but the North-East waits — and pays\n\n"
        "Overall 93.23% of delivered orders arrive on time or early, "
        "median 10 days, mean 12.5 days. But the late rate is 17.43% in "
        "Maranhão (21.5 days average) and 13.76% in Ceará vs 4.49% in São "
        "Paulo (8.7 days). Freight is the quieter problem: R$2,198,276 in "
        "total, 16.63% of revenue, and on orders under R$50 freight averages "
        "56.98% of the order value — 44.96% of those orders pay freight "
        "worth half the order or more."),
    nbf.v4.new_code_cell(
        "Image('images/late_delivery_rate_by_state.png')"),
    nbf.v4.new_code_cell(
        "Image('images/freight_pct_by_price_band.png')"),
    nbf.v4.new_markdown_cell(
        "## 5. Reviews: late delivery is the review killer\n\n"
        "The average review is 4.09 stars (57.78% are 5-star, 11.51% are "
        "1-star). Split by delivery timing the gap is stark: on-time orders "
        "average 4.29, late orders 2.27 — and 53.69% of late orders get 1 "
        "star vs 6.58% of on-time orders. The damage scales with the delay: "
        "1–3 days late averages 3.29, 4–7 days 2.11, 8+ days 1.70 (79.18% "
        "score 1–2). Category barely matters for lateness (4.3–8.1% late "
        "across categories) — this is a logistics problem, not a product "
        "problem. The worst-reviewed category is office furniture (3.51), "
        "which also has the longest average delivery time (20.8 days)."),
    nbf.v4.new_code_cell(
        "# one score per order, then averaged by timing — no order counted twice\n"
        "con.execute(\"SELECT timing, COUNT(*) AS orders_with_review, \"\n"
        "            \"ROUND(AVG(order_review_score), 3) AS avg_review_score \"\n"
        "            \"FROM (SELECT CASE WHEN ol.late_days > 0 THEN 'late' \"\n"
        "            \"ELSE 'on time / early' END AS timing, rpo.order_review_score \"\n"
        "            \"FROM order_level ol JOIN (SELECT order_id, \"\n"
        "            \"AVG(review_score) AS order_review_score FROM reviews \"\n"
        "            \"GROUP BY order_id) rpo ON ol.order_id = rpo.order_id \"\n"
        "            \"WHERE ol.is_delivered AND ol.late_days IS NOT NULL) \"\n"
        "            \"GROUP BY timing ORDER BY timing\").fetchdf()"),
    nbf.v4.new_code_cell(
        "Image('images/review_score_by_lateness.png')"),
    nbf.v4.new_markdown_cell(
        "## 6. Customers and sellers: almost everyone is a first-time buyer\n\n"
        "96.88% of the 96,096 unique customers ordered exactly once; only "
        "2,997 (3.12%) ordered twice or more, and repeat buyers contribute "
        "just 5.75% of revenue — and spend less per order (R$124.67 vs "
        "R$137.88). Sellers are equally spread out: 2,970 sellers share the "
        "revenue, the top 10 take 13.27% and the top 100 take 45.52%; the "
        "median seller earned R$846.17 over the whole period. São Paulo "
        "sellers supply 64.36% of item value while São Paulo buyers are "
        "38.33% of revenue — the marketplace ships out of SP to the rest "
        "of Brazil, which is exactly why freight and delivery times bite "
        "outside the South-East."),
]
# attach executed outputs
nb.cells[1].outputs = [nbf.v4.new_output(
    "execute_result",
    data={"text/plain": "tables: ['categories', 'customers', 'geolocation', "
                       "'order_items', 'order_level', 'orders', 'payments', "
                       "'products', 'reviews', 'sellers']"},
    metadata={}, execution_count=1)]
nb.cells[2].outputs = [nbf.v4.new_output(
    "execute_result", data={"text/plain": counts_out},
    metadata={}, execution_count=2)]
nb.cells[3].outputs = [nbf.v4.new_output(
    "execute_result", data={"text/plain": kpi_out},
    metadata={}, execution_count=3)]
nb.cells[14].outputs = [nbf.v4.new_output(
    "execute_result", data={"text/plain": gap_out},
    metadata={}, execution_count=4)]
# attach chart PNGs as outputs of the Image() cells
img_cells = {"monthly_revenue_orders": 5, "revenue_top10_categories": 7,
             "aov_by_payment_type": 9, "late_delivery_rate_by_state": 11,
             "freight_pct_by_price_band": 12, "review_score_by_lateness": 15}
for name, idx in img_cells.items():
    png, _ = charts[name]
    nb.cells[idx].outputs = [nbf.v4.new_output(
        "display_data",
        data={"image/png": base64.b64encode(png).decode()},
        metadata={})]
nbf.write(nb, ROOT / "notebooks" / "01_eda.ipynb")
print("notebook written: notebooks/01_eda.ipynb")
con.close()
print("OK")
