# Cleaning notes — Olist E-Commerce (Sales and Customer Behaviour)

## Source
- Kaggle dataset "Brazilian E-Commerce Public Dataset by Olist"
  (`olistbr/brazilian-ecommerce`), 9 CSVs, downloaded 2026-11-21 from
  the public Kaggle endpoint
  (`https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce`,
  44,717,580-byte zip, HTTP 200, no Kaggle account needed). The zip is
  kept at `hidden_files/build-olist-ecommerce-analysis/olist.zip` next to
  this build; the extracted CSVs are in `data/raw/` (git-ignored).
- The data are ~100,000 orders placed Sep 2016–Oct 2018 on Olist, a
  Brazilian marketplace connecting small sellers to large marketplaces.
  Currency is Brazilian real (R$).

## Decisions (each one affects the numbers — documented, not hidden)

1. **Revenue = SUM(price) in order_items, delivered orders only.**
   `payment_value` is NOT revenue: it includes freight, is split across
   installments, and covers orders that were never delivered (canceled /
   unavailable orders still have payment rows). Delivered revenue is
   R$13,221,498.11; total payment_value across all payment rows is
   R$16,008,872.12. The choice is stated in the README and in
   `sql/01_load.sql`.
2. **Delivered-only for revenue / delivery / review analysis.**
   96,478 of 99,441 orders (97.02%) are delivered. The rest are counted
   separately, not silently dropped: shipped 1,107 (1.11%), canceled 625
   (0.63%), unavailable 609 (0.61%), invoiced 314, processing 301,
   created 5, approved 2 (`02_Q3.csv`). Non-delivered orders still have
   item revenue in the file (e.g. shipped orders R$150,727.44) — that
   money is excluded from every headline number.
3. **One row per order (`order_level`), aggregated before joining.**
   One order can have multiple items (up to 21), multiple payments
   (up to 29 rows) and multiple sellers. Items and payments are
   aggregated to order level first, then joined — revenue is never
   double-counted. Category and seller analyses are item-level by
   design and are labelled as such; category "orders" means orders
   containing that category, and categories' revenues sum to total
   delivered revenue only at the item level.
4. **Payment mix is analysed at the payment-row level.**
   2,246 orders use more than one payment type, so assigning such an
   order to a single type would misstate the mix. `05_Q1.csv` counts
   distinct orders per type (an order can appear under two types);
   AOV by type (`05_Q2.csv`, `05_Q3.csv`) uses single-payment-type
   delivered orders only. One order (the first order in the file,
   2016-09-04, R$134.97) has no payment row at all.
5. **Reviews are averaged to one score per order before any averaging.**
   `review_id` is NOT unique in the raw file: 814 review_ids appear
   more than once, each time attached to a different order with the
   same score and creation date (a dataset artifact). 547 orders have
   more than one review row (543 have 2, 4 have 3). Every review
   analysis first averages to one row per order
   (`review_per_order` CTE in `sql/07_reviews.sql`), so no order is
   double-counted. The raw distribution in `07_Q1.csv` is the only
   query that counts review rows (99,224).
6. **Review comment text is not analysed.** 58,256 of 99,224 reviews
   (58.7%) have no comment message; the comments that exist are
   Portuguese. Scores (1–5, 0 nulls) are complete and are the whole
   review analysis.
7. **Category names are translated via the translation table.**
   Raw category names are Portuguese; the English names come from
   `product_category_name_translation.csv` (71 rows). 610 products
   (1.9%) have no category and 24 order items reference a category
   with no translation — both appear as "Unknown / no category"
   (1,412 delivered orders, R$175,967.21).
8. **Timestamps are parsed as TIMESTAMP; lateness is in whole days.**
   `late_days` = delivered_customer_date − estimated_delivery_date
   (DATE_DIFF in days; positive = late). 8 delivered orders have no
   delivered timestamp and are excluded from lateness math (96,470 of
   96,478 delivered orders have dates). The longest late delivery is
   188 days.
9. **A "customer" is `customer_unique_id`, not `customer_id`.**
   A person can have several `customer_id` rows (99,441) mapping to
   96,096 unique ids. Repeat-customer analysis uses the unique id;
   using `customer_id` would understate repeat buying.
10. **Freight % is per order, then averaged.** `freight_pct` =
    100 × freight_total / order_total on each delivered order; the
    "average freight %" figures are means of that per-order ratio,
    not total freight / total revenue (which is 16.63% overall). The
    two differ because small orders carry proportionally more freight.

## QA results (from `load.py`)
- orders 99,441; order_items 112,650; products 32,951; sellers 3,095;
  customers 99,441; payments 103,886; reviews 99,224; geolocation
  1,000,163; categories (translation) 71
- Purchase range: 2016-09-04 21:15:19 to 2018-10-17 17:30:18 (delivered
  orders only to 2018-08-29; 20 orders bought Sep–Oct 2018 were still
  in transit)
- Delivered 96,478; delivered revenue R$13,221,498.11; freight
  R$2,198,275.64
- Orders with no items: 775 (164 canceled, 603 unavailable, 5 created,
  2 invoiced, 1 shipped) — these are the orders that never got an item
  row; they contribute R$0 to revenue
- Orders with no payment: 1; orders with multiple payment types: 2,246
- Duplicate review_ids: 814 (same id, different order — see decision 5)
- Null review scores: 0; nulls in key order fields: 0
- Reviews file: 104,720 lines but 99,224 rows — review comments
  contain embedded newlines, which DuckDB's CSV reader handles; the
  row count (not the line count) is the real one
- Geolocation file: 1,000,163 lines, 1,000,163 rows (no embedded
  newlines there)

## Known quirks
- **Nov 2016 has zero orders and Dec 2016 has one.** The monthly
  series jumps Sep 2016 (4 orders) → Oct 2016 (324) → Dec 2016 (1) →
  Jan 2017 (800). 2016 is a launch ramp, not a baseline; trend charts
  start Jan 2017.
- **Lateness is measured against Olist's own estimate.** If estimates
  were padded in some states, the late rate understates the customer
  experience there. The absolute delivery time is the check: 21.5
  days average in Maranhão vs 8.7 in São Paulo.
- **The translation file has a UTF-8 BOM** on its header
  (`﻿product_category_name`). DuckDB's CSV reader handles it; the
  column loads cleanly as `product_category_name`.
- **Geolocation is not joined in this analysis.** It maps zip-code
  prefixes to lat/lng for 1,000,163 rows and is loaded for
  completeness, but state/city from the customers and sellers tables
  answer the geography questions without it. A distance-based
  freight analysis would be the natural next step.
- **No seller cost or margin data.** Freight here is the freight
  charged on the order, not Olist's logistics cost, and there is no
  product cost — recommendations are about revenue and customer
  experience, not profit.
