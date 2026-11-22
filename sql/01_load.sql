-- 01_load.sql — load the Kaggle Olist Brazilian E-Commerce dataset into DuckDB.
--
-- Source: Kaggle "Brazilian E-Commerce Public Dataset by Olist"
-- (olistbr/brazilian-ecommerce), 9 CSVs, downloaded 2026-11-21 from the
-- public Kaggle endpoint https://www.kaggle.com/api/v1/datasets/download/
-- olistbr/brazilian-ecommerce (44.7 MB zip). ~100,000 orders, Sep 2016–
-- Aug 2018, across multiple marketplaces in Brazil.
--
-- Revenue convention (see notes/cleaning_notes.md): revenue = SUM(price)
-- in order_items. payment_value is NOT used as revenue — it includes
-- freight and is split across installments. One order can have multiple
-- items / payments / sellers, so order-level aggregates are built once
-- here (order_level) and every analysis reads from that table.
--
-- Derived columns on order_level:
--   is_delivered   order_status = 'delivered'. Revenue and delivery
--                  analysis use delivered orders only; other statuses are
--                  counted separately in sql/02_trend.sql Q3.
--   order_total    SUM(price) of the order's items (revenue).
--   freight_total  SUM(freight_value) of the order's items.
--   freight_pct    100 * freight_total / order_total.
--   n_items        number of line items; n_sellers distinct sellers.
--   delivery_days  days from purchase to delivery at the customer.
--   late_days      days delivered AFTER the estimated date (negative =
--                  early, positive = late). NULL when not delivered.
--   late_bucket    'On time / early', '1–3 days late', '4–7 days late',
--                  '8+ days late' (delivered orders only).
--   price_band     order-value bands used in the freight analysis.

CREATE OR REPLACE TABLE orders AS
SELECT
    order_id,
    customer_id,
    order_status,
    CAST(order_purchase_timestamp AS TIMESTAMP) AS purchase_ts,
    CAST(order_approved_at AS TIMESTAMP) AS approved_ts,
    CAST(order_delivered_carrier_date AS TIMESTAMP) AS carrier_ts,
    CAST(order_delivered_customer_date AS TIMESTAMP) AS delivered_ts,
    CAST(order_estimated_delivery_date AS TIMESTAMP) AS estimated_ts
FROM read_csv('data/raw/olist_orders_dataset.csv', header = true);

CREATE OR REPLACE TABLE order_items AS
SELECT
    order_id,
    CAST(order_item_id AS INTEGER) AS order_item_id,
    product_id,
    seller_id,
    CAST(shipping_limit_date AS TIMESTAMP) AS shipping_limit_ts,
    CAST(price AS DOUBLE) AS price,
    CAST(freight_value AS DOUBLE) AS freight_value
FROM read_csv('data/raw/olist_order_items_dataset.csv', header = true);

CREATE OR REPLACE TABLE products AS
SELECT
    product_id,
    product_category_name,
    CAST(product_name_lenght AS INTEGER) AS product_name_lenght,
    CAST(product_description_lenght AS INTEGER) AS product_description_lenght,
    CAST(product_photos_qty AS INTEGER) AS product_photos_qty,
    CAST(product_weight_g AS INTEGER) AS product_weight_g,
    CAST(product_length_cm AS INTEGER) AS product_length_cm,
    CAST(product_height_cm AS INTEGER) AS product_height_cm,
    CAST(product_width_cm AS INTEGER) AS product_width_cm
FROM read_csv('data/raw/olist_products_dataset.csv', header = true);

CREATE OR REPLACE TABLE sellers AS
SELECT
    seller_id,
    CAST(seller_zip_code_prefix AS INTEGER) AS seller_zip_code_prefix,
    seller_city,
    seller_state
FROM read_csv('data/raw/olist_sellers_dataset.csv', header = true);

CREATE OR REPLACE TABLE customers AS
SELECT
    customer_id,
    customer_unique_id,
    CAST(customer_zip_code_prefix AS INTEGER) AS customer_zip_code_prefix,
    customer_city,
    customer_state
FROM read_csv('data/raw/olist_customers_dataset.csv', header = true);

CREATE OR REPLACE TABLE payments AS
SELECT
    order_id,
    CAST(payment_sequential AS INTEGER) AS payment_sequential,
    payment_type,
    CAST(payment_installments AS INTEGER) AS payment_installments,
    CAST(payment_value AS DOUBLE) AS payment_value
FROM read_csv('data/raw/olist_order_payments_dataset.csv', header = true);

CREATE OR REPLACE TABLE reviews AS
SELECT
    review_id,
    order_id,
    CAST(review_score AS INTEGER) AS review_score,
    review_comment_title,
    review_comment_message,
    CAST(review_creation_date AS TIMESTAMP) AS review_creation_ts,
    CAST(review_answer_timestamp AS TIMESTAMP) AS review_answer_ts
FROM read_csv('data/raw/olist_order_reviews_dataset.csv', header = true);

CREATE OR REPLACE TABLE geolocation AS
SELECT
    CAST(geolocation_zip_code_prefix AS INTEGER) AS geolocation_zip_code_prefix,
    CAST(geolocation_lat AS DOUBLE) AS geolocation_lat,
    CAST(geolocation_lng AS DOUBLE) AS geolocation_lng,
    geolocation_city,
    geolocation_state
FROM read_csv('data/raw/olist_geolocation_dataset.csv', header = true);

CREATE OR REPLACE TABLE categories AS
SELECT
    product_category_name,
    product_category_name_english AS category_en
FROM read_csv('data/raw/product_category_name_translation.csv', header = true);

-- Order-level aggregates: one row per order, the base table for revenue,
-- delivery, payment and review analysis. Items and payments are aggregated
-- BEFORE joining so revenue is never double-counted.
CREATE OR REPLACE TABLE order_level AS
WITH items_agg AS (
    SELECT
        order_id,
        SUM(price) AS order_total,
        SUM(freight_value) AS freight_total,
        COUNT(*) AS n_items,
        COUNT(DISTINCT seller_id) AS n_sellers,
        COUNT(DISTINCT product_id) AS n_products
    FROM order_items
    GROUP BY order_id
),
payments_agg AS (
    SELECT
        order_id,
        SUM(payment_value) AS payment_total,
        COUNT(*) AS n_payments,
        MAX(payment_type) AS payment_type,  -- first payment type; multi-type orders flagged below
        COUNT(DISTINCT payment_type) AS n_payment_types,
        MAX(payment_installments) AS max_installments
    FROM payments
    GROUP BY order_id
)
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.purchase_ts,
    DATE_TRUNC('month', o.purchase_ts) AS purchase_month,
    o.approved_ts,
    o.carrier_ts,
    o.delivered_ts,
    o.estimated_ts,
    (o.order_status = 'delivered') AS is_delivered,
    COALESCE(ia.order_total, 0) AS order_total,
    COALESCE(ia.freight_total, 0) AS freight_total,
    CASE WHEN COALESCE(ia.order_total, 0) > 0
         THEN 100.0 * ia.freight_total / ia.order_total END AS freight_pct,
    COALESCE(ia.n_items, 0) AS n_items,
    COALESCE(ia.n_sellers, 0) AS n_sellers,
    COALESCE(ia.n_products, 0) AS n_products,
    pa.payment_total,
    pa.n_payments,
    pa.payment_type,
    pa.n_payment_types,
    pa.max_installments,
    CASE WHEN o.delivered_ts IS NOT NULL AND o.purchase_ts IS NOT NULL
         THEN DATE_DIFF('day', o.purchase_ts, o.delivered_ts) END AS delivery_days,
    CASE WHEN o.delivered_ts IS NOT NULL AND o.estimated_ts IS NOT NULL
         THEN DATE_DIFF('day', o.estimated_ts, o.delivered_ts) END AS late_days,
    CASE
        WHEN o.order_status <> 'delivered' OR o.delivered_ts IS NULL THEN NULL
        WHEN DATE_DIFF('day', o.estimated_ts, o.delivered_ts) <= 0 THEN 'On time / early'
        WHEN DATE_DIFF('day', o.estimated_ts, o.delivered_ts) <= 3 THEN '1–3 days late'
        WHEN DATE_DIFF('day', o.estimated_ts, o.delivered_ts) <= 7 THEN '4–7 days late'
        ELSE '8+ days late'
    END AS late_bucket,
    CASE
        WHEN COALESCE(ia.order_total, 0) < 50 THEN 'Under R$50'
        WHEN ia.order_total < 100 THEN 'R$50–100'
        WHEN ia.order_total < 200 THEN 'R$100–200'
        WHEN ia.order_total < 500 THEN 'R$200–500'
        ELSE 'R$500+'
    END AS price_band
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN items_agg ia ON o.order_id = ia.order_id
LEFT JOIN payments_agg pa ON o.order_id = pa.order_id;
