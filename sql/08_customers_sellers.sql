-- 08_customers_sellers.sql — repeat customers and seller concentration.
-- A "customer" is customer_unique_id (a person can have several
-- customer_id rows). Revenue is delivered-order SUM(price) only.

-- Q1: repeat customers — order counts per unique customer
SELECT
    order_count,
    COUNT(*) AS customers,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_unique_id) FROM order_level), 2) AS share_of_customers_pct
FROM (
    SELECT customer_unique_id, COUNT(*) AS order_count
    FROM order_level
    GROUP BY customer_unique_id
)
GROUP BY order_count
ORDER BY order_count;

-- Q2: AOV of repeat vs one-off buyers (delivered orders)
WITH cust_orders AS (
    SELECT customer_unique_id, COUNT(*) AS order_count
    FROM order_level
    GROUP BY customer_unique_id
)
SELECT
    CASE WHEN co.order_count > 1 THEN 'Repeat (2+ orders)' ELSE 'One-off (1 order)' END AS buyer_type,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(ol.order_total), 2) AS revenue_brl,
    ROUND(100.0 * SUM(ol.order_total) / (SELECT SUM(order_total) FROM order_level WHERE is_delivered), 2) AS share_of_revenue_pct,
    ROUND(AVG(ol.order_total), 2) AS aov_brl
FROM order_level ol
JOIN cust_orders co ON ol.customer_unique_id = co.customer_unique_id
WHERE ol.is_delivered
GROUP BY buyer_type
ORDER BY buyer_type;

-- Q3: seller concentration — revenue share of the top sellers
WITH seller_rev AS (
    SELECT
        oi.seller_id,
        COUNT(DISTINCT oi.order_id) AS orders,
        SUM(oi.price) AS revenue_brl
    FROM order_items oi
    JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
    GROUP BY oi.seller_id
),
ranked AS (
    SELECT seller_id, orders, revenue_brl,
           ROW_NUMBER() OVER (ORDER BY revenue_brl DESC) AS rnk,
           SUM(revenue_brl) OVER () AS total_revenue
    FROM seller_rev
)
SELECT
    (SELECT COUNT(*) FROM seller_rev) AS n_sellers,
    ROUND(100.0 * (SELECT SUM(revenue_brl) FROM ranked WHERE rnk <= 10) / MAX(total_revenue), 2) AS top10_sellers_share_pct,
    ROUND(100.0 * (SELECT SUM(revenue_brl) FROM ranked WHERE rnk <= 100) / MAX(total_revenue), 2) AS top100_sellers_share_pct,
    ROUND(100.0 * (SELECT COUNT(*) FROM ranked WHERE orders = 1) / (SELECT COUNT(*) FROM seller_rev), 2) AS share_sellers_with_1_order_pct,
    ROUND((SELECT MEDIAN(revenue_brl) FROM seller_rev), 2) AS median_seller_revenue_brl,
    ROUND((SELECT MAX(revenue_brl) FROM seller_rev), 2) AS max_seller_revenue_brl
FROM ranked;

-- Q4: top 10 sellers by delivered revenue
SELECT
    oi.seller_id,
    s.seller_state,
    s.seller_city,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(SUM(oi.price), 2) AS revenue_brl,
    ROUND(100.0 * SUM(oi.price) / (SELECT SUM(order_total) FROM order_level WHERE is_delivered), 2) AS share_of_revenue_pct
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN sellers s ON oi.seller_id = s.seller_id
GROUP BY oi.seller_id, s.seller_state, s.seller_city
ORDER BY revenue_brl DESC
LIMIT 10;

-- Q5: seller state vs customer state — same-state share of delivered
-- order value (item level; an order with sellers in two states counts
-- once per seller state, noted in cleaning notes)
WITH item_states AS (
    SELECT
        oi.order_id,
        s.seller_state,
        ol.customer_state,
        oi.price
    FROM order_items oi
    JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
    JOIN sellers s ON oi.seller_id = s.seller_id
)
SELECT
    ROUND(100.0 * SUM(CASE WHEN seller_state = customer_state THEN price ELSE 0 END) / SUM(price), 2) AS same_state_share_of_item_value_pct,
    ROUND(100.0 * SUM(CASE WHEN seller_state = 'SP' THEN price ELSE 0 END) / SUM(price), 2) AS sp_seller_share_pct,
    COUNT(DISTINCT seller_state) AS n_seller_states
FROM item_states;

-- Q6: seller states vs customer states — top seller states by item value
SELECT
    s.seller_state,
    COUNT(DISTINCT oi.seller_id) AS sellers,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(SUM(oi.price), 2) AS revenue_brl,
    ROUND(100.0 * SUM(oi.price) / (SELECT SUM(order_total) FROM order_level WHERE is_delivered), 2) AS share_of_revenue_pct
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN sellers s ON oi.seller_id = s.seller_id
GROUP BY s.seller_state
ORDER BY revenue_brl DESC;
