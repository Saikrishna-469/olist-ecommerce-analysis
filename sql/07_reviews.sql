-- 07_reviews.sql — review scores: overall, by delivery lateness, by
-- category. 547 orders have more than one review row and review_id is
-- reused across orders in the raw file, so scores are first averaged to
-- ONE row per order (review_per_order) and every bucket/category average
-- is an average of order-level scores — no order is double-counted.
-- Review comment text is not analysed: 58,256 of 99,224 reviews (58.7%)
-- have no comment message.

-- Q1: review score distribution and average (all 99,224 review rows)
SELECT
    review_score,
    COUNT(*) AS n_reviews,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM reviews), 2) AS share_pct
FROM reviews
GROUP BY review_score
ORDER BY review_score;

-- Q2: average review score by delivery-lateness bucket (delivered orders with a review)
WITH review_per_order AS (
    SELECT order_id, AVG(review_score) AS order_review_score
    FROM reviews
    GROUP BY order_id
)
SELECT
    ol.late_bucket,
    COUNT(*) AS orders_with_review,
    ROUND(AVG(rpo.order_review_score), 3) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE rpo.order_review_score <= 2) / COUNT(*), 2) AS share_score_1_2_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE rpo.order_review_score >= 4) / COUNT(*), 2) AS share_score_4_5_pct
FROM order_level ol
JOIN review_per_order rpo ON ol.order_id = rpo.order_id
WHERE ol.is_delivered AND ol.late_bucket IS NOT NULL
GROUP BY ol.late_bucket
ORDER BY MIN(ol.late_days);

-- Q3: average review score by product category (top 15 by orders with reviews)
WITH review_per_order AS (
    SELECT order_id, AVG(review_score) AS order_review_score
    FROM reviews
    GROUP BY order_id
)
SELECT
    COALESCE(c.category_en, 'Unknown / no category') AS category_en,
    COUNT(DISTINCT oi.order_id) AS orders_with_review,
    ROUND(AVG(rpo.order_review_score), 3) AS avg_review_score,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN rpo.order_review_score <= 2 THEN oi.order_id END) / COUNT(DISTINCT oi.order_id), 2) AS share_score_1_2_pct
FROM order_items oi
JOIN order_level ol ON oi.order_id = ol.order_id AND ol.is_delivered
JOIN review_per_order rpo ON oi.order_id = rpo.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN categories c ON p.product_category_name = c.product_category_name
GROUP BY category_en
HAVING COUNT(DISTINCT oi.order_id) >= 500
ORDER BY avg_review_score ASC;

-- Q4: the late-vs-on-time review gap, quantified in one row
WITH review_per_order AS (
    SELECT order_id, AVG(review_score) AS order_review_score
    FROM reviews
    GROUP BY order_id
),
bucketed AS (
    SELECT
        CASE WHEN ol.late_days > 0 THEN 'late' ELSE 'on time / early' END AS timing,
        rpo.order_review_score
    FROM order_level ol
    JOIN review_per_order rpo ON ol.order_id = rpo.order_id
    WHERE ol.is_delivered AND ol.late_days IS NOT NULL
)
SELECT
    timing,
    COUNT(*) AS orders_with_review,
    ROUND(AVG(order_review_score), 3) AS avg_review_score,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_review_score = 1) / COUNT(*), 2) AS share_1_star_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_review_score = 5) / COUNT(*), 2) AS share_5_star_pct
FROM bucketed
GROUP BY timing
ORDER BY timing;
