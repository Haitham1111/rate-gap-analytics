/* 04 - Ten counties with the widest and narrowest non-medical share, 2023
   Widest = highest non-medical share. Narrowest = lowest.
   Counties with under 5,000 members in 2018 or 2023 are left out so small counties
   do not dominate. Payment growth (%) and the change in non-medical share (pp) are
   shown side by side, 2018 to 2023. They are different units and are not subtracted. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH c AS (
    SELECT d.state_name, d.county_name,
           y23.enrollment, y23.contracts,
           y23.nonmed_share * 100                                AS nonmed_pct_2023,
           (y23.nonmed_share - y18.nonmed_share) * 100           AS nonmed_change_pp_18_23,
           (r23.rate_0 / r18.rate_0 - 1) * 100                   AS payment_growth_pct_18_23
    FROM dbo.v_county_year    AS y23
    JOIN dbo.v_county_year    AS y18 ON y18.ssa_code = y23.ssa_code AND y18.year = 2018
    JOIN dbo.stg_county_rate  AS r23 ON r23.ssa_code = y23.ssa_code AND r23.year = 2023
    JOIN dbo.stg_county_rate  AS r18 ON r18.ssa_code = y23.ssa_code AND r18.year = 2018
    JOIN dbo.dim_county       AS d   ON d.ssa_code   = y23.ssa_code
    WHERE y23.year = 2023 AND y23.enrollment >= 5000 AND y18.enrollment >= 5000
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (ORDER BY nonmed_pct_2023 DESC) AS rk_widest,
           ROW_NUMBER() OVER (ORDER BY nonmed_pct_2023 ASC)  AS rk_narrowest
    FROM c
)
SELECT grp, rk, state_name, county_name, enrollment, contracts,
       nonmed_share_pct_2023, payment_growth_pct_18_23, nonmed_change_pp_18_23
FROM (
    SELECT 'Widest' AS grp, 0 AS grp_order, rk_widest AS rk, state_name, county_name, enrollment, contracts,
           CAST(nonmed_pct_2023 AS DECIMAL(5,2))          AS nonmed_share_pct_2023,
           CAST(payment_growth_pct_18_23 AS DECIMAL(5,1)) AS payment_growth_pct_18_23,
           CAST(nonmed_change_pp_18_23 AS DECIMAL(5,2))   AS nonmed_change_pp_18_23
    FROM ranked WHERE rk_widest <= 10
    UNION ALL
    SELECT 'Narrowest', 1, rk_narrowest, state_name, county_name, enrollment, contracts,
           CAST(nonmed_pct_2023 AS DECIMAL(5,2)),
           CAST(payment_growth_pct_18_23 AS DECIMAL(5,1)),
           CAST(nonmed_change_pp_18_23 AS DECIMAL(5,2))
    FROM ranked WHERE rk_narrowest <= 10
) AS u
ORDER BY grp_order, rk;
