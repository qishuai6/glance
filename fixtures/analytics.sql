-- 门店销售日报 · 月度汇总（2026-09）
WITH daily AS (
    SELECT
        store_id,
        DATE(created_at)          AS day,
        SUM(amount)               AS revenue,
        COUNT(*)                  AS orders,
        COUNT(DISTINCT member_id) AS members
    FROM orders
    WHERE status = 'paid'
      AND created_at >= DATE '2026-09-01'
      AND created_at <  DATE '2026-10-01'
    GROUP BY store_id, DATE(created_at)
),
ranked AS (
    SELECT
        s.name  AS store_name,
        d.day,
        d.revenue / 100.0                  AS revenue_yuan,
        d.orders,
        ROUND(d.revenue / d.orders, 2)     AS avg_ticket,
        ROW_NUMBER() OVER (PARTITION BY s.id
                           ORDER BY d.revenue DESC) AS rk
    FROM daily d
    JOIN stores s ON s.id = d.store_id
)
SELECT store_name, day, revenue_yuan, orders, avg_ticket
FROM ranked
WHERE rk <= 3          -- 每店流水 Top3 的日子
ORDER BY store_name, day;
