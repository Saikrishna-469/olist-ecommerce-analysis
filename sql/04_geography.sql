-- 04_geography.sql — where demand concentrates: customer state and city.
-- Delivered orders only; revenue = SUM(price).

-- Q1: revenue, orders and AOV by customer state
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_level WHERE is_delivered), 2) AS share_of_orders_pct,
    ROUND(SUM(order_total), 2) AS revenue_brl,
    ROUND(100.0 * SUM(order_total) / (SELECT SUM(order_total) FROM order_level WHERE is_delivered), 2) AS share_of_revenue_pct,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(AVG(freight_pct), 2) AS avg_freight_pct
FROM order_level
WHERE is_delivered
GROUP BY customer_state
ORDER BY revenue_brl DESC;

-- Q2: top 15 cities by delivered revenue
SELECT
    customer_city,
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(SUM(order_total), 2) AS revenue_brl,
    ROUND(AVG(order_total), 2) AS aov_brl
FROM order_level
WHERE is_delivered
GROUP BY customer_city, customer_state
ORDER BY revenue_brl DESC
LIMIT 15;

-- Q3: concentration — revenue share of São Paulo state vs the rest,
-- and of the top 3 states
SELECT
    ROUND(100.0 * SUM(CASE WHEN customer_state = 'SP' THEN order_total ELSE 0 END) / SUM(order_total), 2) AS sp_share_pct,
    ROUND(100.0 * SUM(CASE WHEN customer_state IN ('SP', 'RJ', 'MG') THEN order_total ELSE 0 END) / SUM(order_total), 2) AS top3_states_share_pct,
    COUNT(DISTINCT customer_state) AS n_states
FROM order_level
WHERE is_delivered;
