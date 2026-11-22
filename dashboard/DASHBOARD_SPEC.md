# Dashboard spec — Olist E-Commerce (Power BI / Tableau)

Static dashboard: `dashboard/index.html`. To rebuild it in Power BI or
Tableau, connect to the CSVs in `dashboard/` (all outputs of
`run_analysis.py`).

## Pages

### Page 1 — Overview
- **KPI cards:** 99,441 orders · 96,478 delivered (97.02%) · R$13,221,498
  delivered revenue · AOV R$137.04 (median R$86.57) · on-time rate 93.23%
  · average review 4.09/5 · freight R$2,198,276 (16.63% of revenue) ·
  repeat customers 3.12%.
- **Chart:** monthly revenue + delivered orders (`02_Q1.csv`, bars + line)
  — annotate Nov 2017: 7,289 orders / R$987,765 (Black Friday peak) and
  the 2018 plateau at 6,100–7,000 orders a month.
- **Table:** orders by status (`02_Q3.csv`) — delivered 97.02%, shipped
  1.11%, canceled 0.63%, unavailable 0.61%.

### Page 2 — Categories and geography
- **Chart:** revenue by top 10 categories (`03_Q1.csv`, horizontal bar) —
  annotate health & beauty R$1,233,132 (9.33%) and the top-5 share of
  39.83% (`03_Q2.csv`).
- **Chart:** AOV by category (`03_Q4.csv`) — musical instruments R$301.66
  and small appliances R$300.09 at the top; electronics R$61.60 and
  telephony R$75.70 at the bottom.
- **Table:** revenue/orders/AOV by customer state (`04_Q1.csv`) — SP
  38.33% of revenue, top 3 states 63.38% (`04_Q3.csv`); São Paulo city
  15,045 orders / R$1,859,557 (`04_Q2.csv`).

### Page 3 — Payments and delivery
- **Chart:** AOV by payment type (`05_Q2.csv`) — credit card R$142.95 vs
  boleto R$121.40, debit R$119.86, voucher R$85.91.
- **Chart:** installments vs AOV (`05_Q3.csv`) — paid in full R$82.27,
  7–12 installments R$299.57. Add a **slicer** for payment type; the
  installment chart is credit-card-only.
- **Chart:** late-delivery rate by state (`06_Q2.csv`) — Maranhão 17.43%,
  Ceará 13.76%, SP 4.49%; overall reference line 6.77%.
- **Chart:** freight % by price band (`06_Q4.csv`) — under R$50 mean
  56.98%, 44.96% of those orders pay freight ≥50% of value.

### Page 4 — Reviews, customers, sellers
- **Chart:** average review score by lateness bucket (`07_Q2.csv`) —
  on time 4.29, 1–3 days 3.29, 4–7 days 2.11, 8+ days 1.70; overall
  reference line 4.09. Add the late-vs-on-time gap table (`07_Q4.csv`):
  late 2.27 with 53.69% 1-star vs on time 4.29 with 6.58% 1-star.
- **Table:** average review score by category (`07_Q3.csv`) — worst is
  office furniture 3.51 (also the longest delivery time, 20.8 days).
- **Table:** repeat vs one-off buyers (`08_Q2.csv`) — repeat 5.75% of
  revenue, AOV R$124.67 vs R$137.88.
- **Table:** seller concentration (`08_Q3.csv`, `08_Q4.csv`) — top 10
  sellers 13.27%, top 100 45.52%; median seller revenue R$846.17.

## Filters (apply to all pages)
- Purchase month (Jan 2017–Aug 2018 is the meaningful range; 2016 has
  only 267 delivered orders and Nov 2016 has none).
- Customer state, product category (English), payment type.
- Delivery timing (on time / early vs late) for the review pages.

## Refresh
Re-run `python3 load.py`, `python3 run_analysis.py` and
`python3 notebooks/build_notebook.py` from the project root; the CSVs and
images refresh in place. The raw CSVs are git-ignored — download them
first (see README "How to reproduce").
