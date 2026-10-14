/* 01 - County payment growth by year
   Question: how much did CMS raise the county per-member rate each year?
   Unit: payment growth % = (county rate this year / last year - 1) * 100.
   "Weighted" uses each county's December enrollment in contracts that have an MLR. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH g AS (
    SELECT r.year, r.ssa_code, r.payment_growth_pct,
           cy.enrollment,
           -- median needs a window function; every row in a year carries the same value
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.payment_growth_pct)
               OVER (PARTITION BY r.year) AS median_growth
    FROM dbo.v_county_rate_growth AS r
    LEFT JOIN dbo.v_county_year   AS cy ON cy.year = r.year AND cy.ssa_code = r.ssa_code
    WHERE r.year BETWEEN 2019 AND 2023
      AND r.payment_growth_pct IS NOT NULL
)
SELECT year,
       COUNT(*)                                                         AS counties,
       CAST(AVG(payment_growth_pct) AS DECIMAL(5,2))                    AS avg_county_growth_pct,
       CAST(MAX(median_growth)      AS DECIMAL(5,2))                    AS median_growth_pct,
       CAST(SUM(enrollment * payment_growth_pct) / NULLIF(SUM(enrollment), 0)
            AS DECIMAL(5,2))                                            AS weighted_growth_pct,
       CAST(MIN(payment_growth_pct) AS DECIMAL(5,2))                    AS min_growth_pct,
       CAST(MAX(payment_growth_pct) AS DECIMAL(5,2))                    AS max_growth_pct,
       SUM(CASE WHEN payment_growth_pct < 0 THEN 1 ELSE 0 END)          AS counties_with_cut
FROM g
GROUP BY year
ORDER BY year;
