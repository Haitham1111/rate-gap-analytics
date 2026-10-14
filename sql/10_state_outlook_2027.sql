/* 10 - State outlook for 2027: actual trend beside the projection

   ACTUAL (published data)
     payment growth 2024, 2025, 2026  : county rate vs prior year, weighted by that year's MA enrollment
     announced 2027 benchmark change  : CMS 2027 ratebook county rates vs 2026, weighted by Sep 2026 MA enrollment
                                        (this is the county rate file, not CMS's national expected average payment change;
                                         CMS states an expected average change of +2.48%, +4.98% with risk score trend, fact sheet 2026-04-06)
     non-medical share CY2021-CY2023  : v1 MLR fact (CY2023 is the newest MLR file; CY2024 is not published)

   PROJECTION (labeled, not published data)
     Method 1, payment: trend_projection_2027 = mean of the three annual growth rates 2024-2026 carried forward.
       It is shown only to compare with the announced figure. announced_minus_trend is two percent figures
       subtracted from each other (same unit).
     Method 2, non-medical share: projection = mean of CY2021-CY2023 shares, range = min to max of those years.
       Payment growth is not used: v1 found no county-level relationship (r = 0.02), so tying the projection to payment
       would be unsupported. A projection is not a forecast of any plan's behavior and not evidence of wrongdoing. */
USE Rate_Gap;
SET NOCOUNT ON;

-- The calculation lives in dbo.v2_state_outlook (sql/00b_setup_latest_data.sql); this query formats it.
SELECT state_name, licensed,
       CAST(actual_2024_pct AS DECIMAL(6,2))               AS actual_2024_pct,
       CAST(actual_2025_pct AS DECIMAL(6,2))               AS actual_2025_pct,
       CAST(actual_2026_pct AS DECIMAL(6,2))               AS actual_2026_pct,
       CAST(trailing_3yr_mean_pct AS DECIMAL(6,2))         AS trailing_3yr_mean_pct,
       CAST(announced_2027_pct AS DECIMAL(6,2))            AS announced_2027_pct,
       CAST(projection_trend_2027_pct AS DECIMAL(6,2))     AS projection_trend_2027_pct,
       CAST(announced_2027_pct AS DECIMAL(6,2)) - CAST(projection_trend_2027_pct AS DECIMAL(6,2)) AS announced_minus_trend_pct_points,
       rank_announced_2027,
       CAST(nonmed_cy2021_pct AS DECIMAL(6,2))             AS nonmed_cy2021_pct,
       CAST(nonmed_cy2022_pct AS DECIMAL(6,2))             AS nonmed_cy2022_pct,
       CAST(nonmed_cy2023_pct AS DECIMAL(6,2))             AS nonmed_cy2023_pct,
       CAST(nonmed_projection_mean_pct AS DECIMAL(6,2))    AS nonmed_projection_mean_pct,
       CAST(nonmed_projection_low_pct AS DECIMAL(6,2))     AS nonmed_projection_low_pct,
       CAST(nonmed_projection_high_pct AS DECIMAL(6,2))    AS nonmed_projection_high_pct
FROM dbo.v2_state_outlook
ORDER BY announced_2027_pct DESC;

-- National line (all 50 states + DC, enrollment-weighted)
WITH cur AS (
    SELECT ssa_code, SUM(enrollment) AS enr FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY ssa_code
),
yr AS (
    SELECT year,
           SUM(enrollment * payment_growth_pct) / SUM(enrollment) AS g
    FROM dbo.v2_state_year WHERE year IN (2024, 2025, 2026) GROUP BY year
)
SELECT CAST((SELECT g FROM yr WHERE year = 2024) AS DECIMAL(6,2)) AS actual_2024_pct,
       CAST((SELECT g FROM yr WHERE year = 2025) AS DECIMAL(6,2)) AS actual_2025_pct,
       CAST((SELECT g FROM yr WHERE year = 2026) AS DECIMAL(6,2)) AS actual_2026_pct,
       CAST((SELECT AVG(g) FROM yr) AS DECIMAL(6,2))              AS trailing_3yr_mean_pct,
       CAST((SELECT SUM(c.enr * g.payment_growth_pct) / SUM(c.enr)
             FROM cur AS c
             JOIN dbo.v2_rate_growth AS g ON g.ssa_code = c.ssa_code AND g.year = 2027
                                         AND g.payment_growth_pct IS NOT NULL) AS DECIMAL(6,2)) AS announced_2027_pct;
