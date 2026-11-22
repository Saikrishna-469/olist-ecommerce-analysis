-- 03_category.sql — revenue, orders and AOV by product category.
-- Item-level: SUM(price) per category, delivered orders only. An order
-- with items in several categories contributes to each of them; category
-- revenue therefore sums to total delivered revenue. Category names are
-- the English translation (categories table); 610 products have no
-- category and appear as 'Unknown / no category'.

-- Q1: revenue, orders and AOV by category (English), top 15 by revenue
SELECT
    COALESCE(c.category_en, 'Unknown / no category') AS category_en,
    COUNT(DISTINCT oi.order_id) AS orders,
    COUNT(*) AS items,
    ROUND(SUM(oi.price), 2) AS revenue_brl,
    ROUND(100.0 * SUM(oi.price) / (SELECT SUM(order_total) FROM order_level WHERE is_delivered), 2) AS share_of_revenue_pct,
    ROUND(SUM(oi.price) / COUNT(DISTINCT oi.order_id), 2) AS revenue_per_order_brl,
    ROUND(AVG(oi.price), 2) AS avg_item_price_brl
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN categories c ON p.product_category_name = c.product_category_name
GROUP BY category_en
ORDER BY revenue_brl DESC
LIMIT 15;

-- Q2: concentration — revenue share of the top 5 and top 10 categories
WITH cat_rev AS (
    SELECT
        COALESCE(c.category_en, 'Unknown / no category') AS category_en,
        SUM(oi.price) AS revenue_brl
    FROM order_items oi
    JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
    JOIN products p ON oi.product_id = p.product_id
    LEFT JOIN categories c ON p.product_category_name = c.product_category_name
    GROUP BY category_en
),
ranked AS (
    SELECT category_en, revenue_brl,
           ROW_NUMBER() OVER (ORDER BY revenue_brl DESC) AS rnk,
           SUM(revenue_brl) OVER () AS total_revenue
    FROM cat_rev
)
SELECT
    (SELECT COUNT(*) FROM cat_rev) AS n_categories,
    ROUND(100.0 * (SELECT SUM(revenue_brl) FROM ranked WHERE rnk <= 5) / MAX(total_revenue), 2) AS top5_share_pct,
    ROUND(100.0 * (SELECT SUM(revenue_brl) FROM ranked WHERE rnk <= 10) / MAX(total_revenue), 2) AS top10_share_pct,
    ROUND(100.0 * (SELECT SUM(revenue_brl) FROM ranked WHERE rnk <= 3) / MAX(total_revenue), 2) AS top3_share_pct
FROM ranked;

-- Q3: bottom 10 categories by revenue (delivered orders)
SELECT
    COALESCE(c.category_en, 'Unknown / no category') AS category_en,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(SUM(oi.price), 2) AS revenue_brl,
    ROUND(SUM(oi.price) / COUNT(DISTINCT oi.order_id), 2) AS revenue_per_order_brl
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN categories c ON p.product_category_name = c.product_category_name
GROUP BY category_en
ORDER BY revenue_brl ASC
LIMIT 10;

-- Q4: highest and lowest AOV categories (min 500 orders) — what a
-- high-ticket category looks like vs a low-ticket one
SELECT
    COALESCE(c.category_en, 'Unknown / no category') AS category_en,
    COUNT(DISTINCT oi.order_id) AS orders,
    ROUND(SUM(oi.price), 2) AS revenue_brl,
    ROUND(SUM(oi.price) / COUNT(DISTINCT oi.order_id), 2) AS revenue_per_order_brl,
    ROUND(AVG(oi.price), 2) AS avg_item_price_brl
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN categories c ON p.product_category_name = c.product_category_name
GROUP BY category_en
HAVING COUNT(DISTINCT oi.order_id) >= 500
ORDER BY revenue_per_order_brl DESC;
