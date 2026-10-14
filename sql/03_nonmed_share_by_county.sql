/* 03 - Non-medical share by county, 2023
   Non-medical share = 1 - MLR, enrollment-weighted across the contracts in the county.
   Each contract's MLR is a whole-contract figure, so a county value reflects the mix
   of contracts that serve it. Counties with under 1,000 members are left out. */
USE Rate_Gap;
SET NOCOUNT ON;

-- Result 1: how the 2023 county values are spread nationally
WITH cy AS (
    SELECT nonmed_share FROM dbo.v_county_year WHERE year = 2023 AND enrollment >= 1000
)
SELECT DISTINCT
       COUNT(*) OVER ()                                                              AS counties,
       CAST(PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY nonmed_share) OVER () * 100 AS DECIMAL(5,2)) AS p10_pct,
       CAST(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY nonmed_share) OVER () * 100 AS DECIMAL(5,2)) AS median_pct,
       CAST(PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY nonmed_share) OVER () * 100 AS DECIMAL(5,2)) AS p90_pct,
       CAST(MIN(nonmed_share) OVER () * 100 AS DECIMAL(5,2))                         AS min_pct,
       CAST(MAX(nonmed_share) OVER () * 100 AS DECIMAL(5,2))                         AS max_pct
FROM cy;

-- Result 2: Arizona counties, with payment growth beside the change in non-medical share
SELECT d.county_name,
       t.enrollment,
       t.contracts,
       CAST(t.nonmed_share      * 100 AS DECIMAL(5,2)) AS nonmed_share_pct_2023,
       CAST(t.payment_growth_pct      AS DECIMAL(5,2)) AS payment_growth_pct_2023,
       CAST(t.nonmed_change_pp        AS DECIMAL(5,2)) AS nonmed_change_pp_2023
FROM dbo.v_county_trend AS t
JOIN dbo.dim_county     AS d ON d.ssa_code = t.ssa_code
WHERE t.year = 2023 AND t.state_ssa = '03' AND t.enrollment >= 1000
ORDER BY t.nonmed_share DESC;
