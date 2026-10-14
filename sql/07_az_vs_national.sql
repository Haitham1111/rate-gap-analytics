/* 07 - Arizona vs national
   Arizona = SSA state code 03. Same weighting as query 06.
   The Arizona-minus-national column is in percentage points of non-medical share,
   which is the same unit on both sides. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH s AS (
    SELECT year,
           SUM(CASE WHEN state_ssa = '03' THEN enrollment END)                         AS az_members,
           SUM(CASE WHEN state_ssa = '03' AND payment_growth_pct IS NOT NULL THEN enrollment * payment_growth_pct END)
             / NULLIF(SUM(CASE WHEN state_ssa = '03' AND payment_growth_pct IS NOT NULL THEN enrollment END), 0) AS az_growth,
           SUM(CASE WHEN payment_growth_pct IS NOT NULL THEN enrollment * payment_growth_pct END)
             / NULLIF(SUM(CASE WHEN payment_growth_pct IS NOT NULL THEN enrollment END), 0)                     AS nat_growth,
           SUM(CASE WHEN state_ssa = '03' THEN enrollment * nonmed_share END)
             / SUM(CASE WHEN state_ssa = '03' THEN enrollment END) * 100               AS az_nonmed,
           SUM(enrollment * nonmed_share) / SUM(enrollment) * 100                      AS nat_nonmed
    FROM dbo.v_fact
    GROUP BY year
)
SELECT year,
       az_members,
       CAST(az_growth  AS DECIMAL(5,2)) AS az_payment_growth_pct,
       CAST(nat_growth AS DECIMAL(5,2)) AS nat_payment_growth_pct,
       CAST(az_nonmed  AS DECIMAL(5,2)) AS az_nonmed_share_pct,
       CAST(nat_nonmed AS DECIMAL(5,2)) AS nat_nonmed_share_pct,
       CAST(az_nonmed - nat_nonmed AS DECIMAL(5,2)) AS az_minus_nat_pp
FROM s
ORDER BY year;
