/* 06 - Year-over-year trend, national
   Payment growth (%) and the change in non-medical share (pp) side by side, per year.
   payment_index compounds the weighted growth, 2018 = 100.
   Weighted = December enrollment in contracts with an MLR. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH n AS (
    SELECT year,
           SUM(CASE WHEN payment_growth_pct IS NOT NULL THEN enrollment * payment_growth_pct END)
             / NULLIF(SUM(CASE WHEN payment_growth_pct IS NOT NULL THEN enrollment END), 0) AS payment_growth_pct,
           SUM(enrollment * nonmed_share) / SUM(enrollment) * 100                           AS nonmed_pct
    FROM dbo.v_fact
    GROUP BY year
)
SELECT year,
       CAST(payment_growth_pct AS DECIMAL(5,2))                                  AS payment_growth_pct,
       CAST(nonmed_pct AS DECIMAL(5,2))                                          AS nonmed_share_pct,
       CAST(nonmed_pct - LAG(nonmed_pct) OVER (ORDER BY year) AS DECIMAL(5,2))   AS nonmed_change_pp,
       -- log trick: the running sum of LOG(1 + g) is the log of the compounded index
       CAST(ISNULL(EXP(SUM(LOG(1 + payment_growth_pct / 100.0))
                       OVER (ORDER BY year ROWS UNBOUNDED PRECEDING)), 1) * 100 AS DECIMAL(6,1)) AS payment_index_2018_100
FROM n
ORDER BY year;

-- Result 2: county by county, 2018 to 2023. Payment growth (%) beside the change in
-- non-medical share (pp), and the correlation between them (Pearson r, computed by hand).
-- Counties need 5,000+ members in both 2018 and 2023.
WITH c AS (
    SELECT (r23.rate_0 / r18.rate_0 - 1) * 100                    AS pay_pct,
           (y23.nonmed_share - y18.nonmed_share) * 100            AS nm_pp
    FROM dbo.v_county_year   AS y23
    JOIN dbo.v_county_year   AS y18 ON y18.ssa_code = y23.ssa_code AND y18.year = 2018
    JOIN dbo.stg_county_rate AS r23 ON r23.ssa_code = y23.ssa_code AND r23.year = 2023
    JOIN dbo.stg_county_rate AS r18 ON r18.ssa_code = y23.ssa_code AND r18.year = 2018
    WHERE y23.year = 2023 AND y23.enrollment >= 5000 AND y18.enrollment >= 5000
)
SELECT COUNT(*)                                   AS counties,
       CAST(AVG(pay_pct) AS DECIMAL(5,2))         AS avg_payment_growth_pct_18_23,
       CAST(MIN(pay_pct) AS DECIMAL(5,2))         AS min_payment_growth_pct,
       CAST(MAX(pay_pct) AS DECIMAL(5,2))         AS max_payment_growth_pct,
       CAST(AVG(nm_pp)   AS DECIMAL(5,2))         AS avg_nonmed_change_pp_18_23,
       CAST(MIN(nm_pp)   AS DECIMAL(5,2))         AS min_nonmed_change_pp,
       CAST(MAX(nm_pp)   AS DECIMAL(5,2))         AS max_nonmed_change_pp,
       CAST((COUNT(*) * SUM(pay_pct * nm_pp) - SUM(pay_pct) * SUM(nm_pp))
            / SQRT((COUNT(*) * SUM(pay_pct * pay_pct) - POWER(SUM(pay_pct), 2))
                 * (COUNT(*) * SUM(nm_pp * nm_pp)     - POWER(SUM(nm_pp), 2))) AS DECIMAL(5,3)) AS correlation_r
FROM c;
