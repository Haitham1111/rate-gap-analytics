/* 05 - Contract-level distribution, 2023, split into quartiles with NTILE
   Quartile 1 = lowest non-medical share, quartile 4 = highest.
   Contracts need 1,000+ matched members, a prior-year MLR and a payment growth value.
   Each contract's payment growth is the enrollment-weighted growth of the counties it serves. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH c AS (
    SELECT contract_id, enrollment, adjusted_mlr, nonmed_share,
           payment_growth_pct, nonmed_change_pp,
           NTILE(4) OVER (ORDER BY nonmed_share, contract_id) AS quartile   -- contract_id breaks ties so quartiles are repeatable
    FROM dbo.v_contract_year
    WHERE year = 2023
      AND enrollment >= 1000
      AND payment_growth_pct IS NOT NULL
      AND nonmed_change_pp   IS NOT NULL
)
SELECT quartile,
       COUNT(*)                                              AS contracts,
       CAST(MIN(nonmed_share) * 100 AS DECIMAL(6,2))         AS min_nonmed_pct,
       CAST(MAX(nonmed_share) * 100 AS DECIMAL(6,2))         AS max_nonmed_pct,
       CAST(AVG(payment_growth_pct) AS DECIMAL(5,2))         AS avg_payment_growth_pct,
       CAST(AVG(nonmed_change_pp)   AS DECIMAL(5,2))         AS avg_nonmed_change_pp,
       SUM(enrollment)                                       AS members
FROM c
GROUP BY quartile
ORDER BY quartile;
