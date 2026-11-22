-- 05_payments.sql — payment mix, AOV by payment type, installments.
-- Payment rows are analysed at the payments-table level (Q1) because
-- 2,246 orders use more than one payment type — assigning such an order
-- to a single type would misstate the mix. AOV by type (Q2/Q3) uses
-- single-payment-type delivered orders only, so the AOV is clean.

-- Q1: payment mix — payment rows, distinct orders, payment value
SELECT
    payment_type,
    COUNT(*) AS payment_rows,
    COUNT(DISTINCT order_id) AS orders_using_type,
    ROUND(100.0 * COUNT(DISTINCT order_id) / (SELECT COUNT(*) FROM order_level), 2) AS share_of_all_orders_pct,
    ROUND(SUM(payment_value), 2) AS payment_value_brl,
    ROUND(100.0 * SUM(payment_value) / (SELECT SUM(payment_value) FROM payments), 2) AS share_of_payment_value_pct
FROM payments
GROUP BY payment_type
ORDER BY orders_using_type DESC;

-- Q2: AOV by payment type — single-payment-type delivered orders only
SELECT
    payment_type,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(MEDIAN(order_total), 2) AS median_order_value_brl,
    ROUND(AVG(max_installments), 2) AS avg_installments,
    ROUND(AVG(freight_pct), 2) AS avg_freight_pct
FROM order_level
WHERE is_delivered AND n_payment_types = 1
GROUP BY payment_type
ORDER BY aov_brl DESC;

-- Q3: installments vs AOV — credit-card-only delivered orders, by
-- installment bucket (max_installments on the order)
SELECT
    CASE
        WHEN max_installments = 1 THEN '1 (paid in full)'
        WHEN max_installments <= 3 THEN '2–3'
        WHEN max_installments <= 6 THEN '4–6'
        WHEN max_installments <= 12 THEN '7–12'
        ELSE '13+'
    END AS installment_bucket,
    COUNT(*) AS delivered_orders,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM order_level WHERE is_delivered AND n_payment_types = 1 AND payment_type = 'credit_card'), 2) AS share_pct,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(MEDIAN(order_total), 2) AS median_order_value_brl
FROM order_level
WHERE is_delivered AND n_payment_types = 1 AND payment_type = 'credit_card'
GROUP BY installment_bucket
ORDER BY MIN(max_installments);

-- Q4: orders using more than one payment type — how common, how big
SELECT
    (n_payment_types > 1) AS multi_payment_type,
    COUNT(*) AS delivered_orders,
    ROUND(AVG(order_total), 2) AS aov_brl,
    ROUND(AVG(n_payments), 2) AS avg_payment_rows
FROM order_level
WHERE is_delivered
GROUP BY multi_payment_type
ORDER BY multi_payment_type;
