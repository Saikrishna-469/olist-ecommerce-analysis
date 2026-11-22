-- 02_trend.sql — headline KPIs, growth trend, order-status mix.
-- Revenue = SUM(price) in order_items, delivered orders only (see
-- notes/cleaning_notes.md). The monthly series runs Sep 2016–Oct 2018;
-- Nov 2016 has zero orders in the raw data and Dec 2016 has one.

-- Q1: monthly trend — delivered orders, revenue, AOV, items per order
SELECT
    purchase_month,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(order_total), 2) AS revenue_brl,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(SUM(n_items) * 1.0 / COUNT(*), 2) AS items_per_order,
    ROUND(SUM(freight_total), 2) AS freight_brl
FROM order_level
WHERE is_delivered
GROUP BY purchase_month
ORDER BY purchase_month;

-- Q2: quarterly summary — delivered orders, revenue, AOV
SELECT
    DATE_TRUNC('quarter', purchase_month) AS quarter,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(order_total), 2) AS revenue_brl,
    ROUND(AVG(order_total), 2) AS aov_brl
FROM order_level
WHERE is_delivered
GROUP BY quarter
ORDER BY quarter;

-- Q3: orders by status — everything in the file, not just delivered
SELECT
    order_status,
    COUNT(*) AS n_orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_level), 2) AS share_pct,
    ROUND(SUM(order_total), 2) AS revenue_brl
FROM order_level
GROUP BY order_status
ORDER BY n_orders DESC;

-- Q4: headline KPIs across all delivered orders
SELECT
    COUNT(*) AS delivered_orders,
    (SELECT COUNT(*) FROM order_level) AS total_orders,
    ROUND(SUM(order_total), 2) AS revenue_brl,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(MEDIAN(order_total), 2) AS median_order_value_brl,
    ROUND(SUM(freight_total), 2) AS freight_brl,
    ROUND(100.0 * SUM(freight_total) / SUM(order_total), 2) AS freight_pct_of_revenue,
    ROUND(SUM(n_items) * 1.0 / COUNT(*), 2) AS items_per_order,
    MIN(purchase_ts) AS first_purchase,
    MAX(purchase_ts) AS last_purchase
FROM order_level
WHERE is_delivered;
