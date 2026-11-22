-- 06_delivery.sql — delivery performance: promised vs actual, late
-- rates by state / category / seller, and freight as % of order value.
-- late_days = delivered_customer_date − estimated_delivery_date in days
-- (positive = late). 8 delivered orders have no delivered timestamp and
-- are excluded from lateness math (see notes/cleaning_notes.md).

-- Q1: delivery KPIs overall (delivered orders with timestamps)
SELECT
    COUNT(*) FILTER (WHERE delivered_ts IS NOT NULL) AS delivered_with_dates,
    ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
    ROUND(MEDIAN(delivery_days), 1) AS median_delivery_days,
    ROUND(100.0 * COUNT(*) FILTER (WHERE late_days > 0) / COUNT(*) FILTER (WHERE late_days IS NOT NULL), 2) AS late_rate_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE late_days <= 0) / COUNT(*) FILTER (WHERE late_days IS NOT NULL), 2) AS on_time_or_early_pct,
    ROUND(AVG(late_days) FILTER (WHERE late_days > 0), 1) AS avg_days_late_when_late,
    MAX(late_days) AS max_days_late,
    ROUND(AVG(freight_pct), 2) AS avg_freight_pct_of_order_value
FROM order_level
WHERE is_delivered;

-- Q2: late-delivery rate by customer state (states with 500+ delivered orders)
SELECT
    customer_state,
    COUNT(*) AS delivered_orders,
    ROUND(100.0 * COUNT(*) FILTER (WHERE late_days > 0) / COUNT(*) FILTER (WHERE late_days IS NOT NULL), 2) AS late_rate_pct,
    ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
    ROUND(AVG(freight_pct), 2) AS avg_freight_pct
FROM order_level
WHERE is_delivered
GROUP BY customer_state
HAVING COUNT(*) >= 500
ORDER BY late_rate_pct DESC;

-- Q3: late-delivery rate by product category (categories with 500+ delivered orders)
SELECT
    COALESCE(c.category_en, 'Unknown / no category') AS category_en,
    COUNT(DISTINCT oi.order_id) AS delivered_orders,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN ol.late_days > 0 THEN oi.order_id END) / COUNT(DISTINCT oi.order_id), 2) AS late_rate_pct,
    ROUND(AVG(ol.delivery_days), 1) AS avg_delivery_days
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN categories c ON p.product_category_name = c.product_category_name
GROUP BY category_en
HAVING COUNT(DISTINCT oi.order_id) >= 500
ORDER BY late_rate_pct DESC;

-- Q4: freight as % of order value by price band (delivered orders)
SELECT
    price_band,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(order_total), 2) AS avg_order_value_brl,
    ROUND(AVG(freight_total), 2) AS avg_freight_brl,
    ROUND(AVG(freight_pct), 2) AS avg_freight_pct,
    ROUND(MEDIAN(freight_pct), 2) AS median_freight_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE freight_pct >= 50) / COUNT(*), 2) AS share_freight_ge_50pct
FROM order_level
WHERE is_delivered
GROUP BY price_band
ORDER BY MIN(order_total);

-- Q5: late-delivery rate by seller state (seller states with 500+ delivered order-seller pairs)
SELECT
    s.seller_state,
    COUNT(DISTINCT oi.order_id) AS delivered_orders,
    COUNT(DISTINCT oi.seller_id) AS sellers,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN ol.late_days > 0 THEN oi.order_id END) / COUNT(DISTINCT oi.order_id), 2) AS late_rate_pct,
    ROUND(AVG(ol.delivery_days), 1) AS avg_delivery_days
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN sellers s ON oi.seller_id = s.seller_id
GROUP BY s.seller_state
HAVING COUNT(DISTINCT oi.order_id) >= 500
ORDER BY late_rate_pct DESC;
