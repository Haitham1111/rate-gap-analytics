/* 02 - Medical loss ratio by year
   Question: what share of revenue did MA contracts report spending on medical care?
   MLR = CMS "Adjusted MLR", as published. Non-medical share = 1 - MLR.
   MLR above 100% means reported medical spending exceeded premium revenue that year.
   A contract below 85% owes CMS a remittance (the MA minimum MLR rule).
   Scope: Medicare Advantage contracts only (prefix H, R, E). Stand-alone Part D contracts are excluded. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH c AS (   -- all published MA contracts, one row per contract-year
    SELECT year, adjusted_mlr,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY adjusted_mlr) OVER (PARTITION BY year) AS median_mlr
    FROM dbo.v_contract_mlr
),
w AS (        -- enrollment-weighted MLR across county rows we can place
    SELECT year, SUM(enrollment * adjusted_mlr) / SUM(enrollment) AS weighted_mlr
    FROM dbo.v_fact
    GROUP BY year
)
SELECT c.year,
       COUNT(*)                                                   AS contracts,
       CAST(AVG(c.adjusted_mlr)  * 100 AS DECIMAL(5,1))           AS avg_mlr_pct,
       CAST(MAX(c.median_mlr)    * 100 AS DECIMAL(5,1))           AS median_mlr_pct,
       CAST(MAX(w.weighted_mlr)  * 100 AS DECIMAL(5,1))           AS weighted_mlr_pct,
       SUM(CASE WHEN c.adjusted_mlr > 1    THEN 1 ELSE 0 END)     AS contracts_mlr_over_100,
       SUM(CASE WHEN c.adjusted_mlr < 0.85 THEN 1 ELSE 0 END)     AS contracts_under_85
FROM c
JOIN w ON w.year = c.year
GROUP BY c.year
ORDER BY c.year;
