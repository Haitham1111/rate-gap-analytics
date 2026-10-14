/* 12 - The five findings, each as a query a manager can run and challenge
   Scope: Medicare Advantage plan types only, 50 states + DC. Newest data for each source:
   ratebooks through 2027, enrollment through September 2026, MLR through contract year 2023 (CY2024 not published).
   Every query returns exactly the numbers quoted in reports/master-findings.md. */
USE Rate_Gap;
SET NOCOUNT ON;

/* ---------- Finding 1: the announced 2027 county benchmark change, and how far states differ ----------
   Shows : enrollment-weighted change in the county rate from the 2026 to the 2027 ratebook, nationally and by state.
   Not   : CMS's own national expected average payment change (+2.48%, +4.98% with risk score trend). This is the county rate file. */
WITH cur AS (
    SELECT ssa_code, SUM(enrollment) AS enr FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY ssa_code
),
nat AS (
    SELECT SUM(c.enr * g.payment_growth_pct) / SUM(c.enr) AS chg
    FROM cur AS c
    JOIN dbo.v2_rate_growth AS g ON g.ssa_code = c.ssa_code AND g.year = 2027 AND g.payment_growth_pct IS NOT NULL
)
SELECT CAST(nat.chg AS DECIMAL(6,2))                                                         AS national_2027_change_pct,
       (SELECT TOP 1 state_name FROM dbo.v2_state_scorecard ORDER BY chg_2027_pct DESC)      AS highest_state,
       (SELECT CAST(MAX(chg_2027_pct) AS DECIMAL(6,2)) FROM dbo.v2_state_scorecard)          AS highest_pct,
       (SELECT TOP 1 state_name FROM dbo.v2_state_scorecard ORDER BY chg_2027_pct ASC)       AS lowest_state,
       (SELECT CAST(MIN(chg_2027_pct) AS DECIMAL(6,2)) FROM dbo.v2_state_scorecard)          AS lowest_pct,
       (SELECT CAST(MAX(chg_2027_pct) AS DECIMAL(6,2)) - CAST(MIN(chg_2027_pct) AS DECIMAL(6,2)) FROM dbo.v2_state_scorecard) AS spread_pct_points,
       (SELECT COUNT(*) FROM dbo.v2_state_scorecard WHERE chg_2027_pct > nat.chg)            AS states_above_national
FROM nat;

/* ---------- Finding 2: the 2026 step-up in county rates ----------
   Shows : national enrollment-weighted county-rate growth for 2024, 2025 and 2026, and 2026 relative to the 2024-25 average.
   Not   : what plans were paid or what benefits changed. It is the county rate column (0% bonus) only. */
WITH yr AS (
    SELECT year,
           SUM(enrollment * payment_growth_pct) / SUM(CASE WHEN payment_growth_pct IS NOT NULL THEN enrollment END) AS g
    FROM dbo.v2_state_year WHERE year IN (2024, 2025, 2026) GROUP BY year
)
SELECT CAST(MAX(CASE WHEN year = 2024 THEN g END) AS DECIMAL(6,2)) AS growth_2024_pct,
       CAST(MAX(CASE WHEN year = 2025 THEN g END) AS DECIMAL(6,2)) AS growth_2025_pct,
       CAST(MAX(CASE WHEN year = 2026 THEN g END) AS DECIMAL(6,2)) AS growth_2026_pct,
       CAST(MAX(CASE WHEN year = 2026 THEN g END)
            / ((MAX(CASE WHEN year = 2024 THEN g END) + MAX(CASE WHEN year = 2025 THEN g END)) / 2) AS DECIMAL(6,2)) AS times_the_2024_25_average
FROM yr;

/* ---------- Finding 3: no state clearly leads ----------
   Shows : how many states rank in the top 10 on each of three market columns (MA enrollment, 3-year payment growth,
           2027 announced change). top10_count = 3 would mean a state leads on all three.
   Not   : which states are good for an agent. The columns are not combined, and non-medical share is not counted. */
SELECT top10_count,
       COUNT(*) AS states,
       STRING_AGG(state_name, ', ') WITHIN GROUP (ORDER BY state_name) AS state_list
FROM dbo.v2_state_scorecard
GROUP BY top10_count
ORDER BY top10_count DESC;

-- Finding 3, second number: share of national MA members (Sep 2026) in the 10 largest states
SELECT COUNT(*) AS states_counted,
       SUM(ma_members) AS ma_members_total,
       CAST(SUM(CASE WHEN rank_enrollment <= 10 THEN ma_members END) * 100.0 / SUM(ma_members) AS DECIMAL(5,1)) AS top10_states_share_pct
FROM dbo.v2_state_scorecard;

/* ---------- Finding 4: three parent organizations hold most of the market ----------
   Shows : share of national MA enrollment (Sep 2026) held by the three largest parent organizations, and in how many
           states the largest parent holds 30%, 40% or 50% of MA members.
   Not   : plan quality, prices or behavior. Parent is as CMS lists it on each contract; no providers are named. */
WITH o AS (
    SELECT parent_org, SUM(enrollment) AS m FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY parent_org
),
t AS (SELECT SUM(m) AS tot FROM o),
top3 AS (SELECT TOP 3 parent_org, m FROM o ORDER BY m DESC)
SELECT top3.parent_org, top3.m AS members,
       CAST(top3.m * 100.0 / t.tot AS DECIMAL(5,1)) AS share_of_national_pct,
       CAST(SUM(top3.m) OVER () * 100.0 / t.tot AS DECIMAL(5,1)) AS top3_combined_share_pct
FROM top3 CROSS JOIN t
ORDER BY top3.m DESC;

WITH o AS (
    SELECT state_ssa, parent_org, SUM(enrollment) AS m FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY state_ssa, parent_org
),
r AS (
    SELECT *, SUM(m) OVER (PARTITION BY state_ssa) AS st,
           ROW_NUMBER() OVER (PARTITION BY state_ssa ORDER BY m DESC, parent_org) AS rk
    FROM o
)
SELECT COUNT(*)                                                         AS areas,
       SUM(CASE WHEN m * 100.0 / st >= 30 THEN 1 ELSE 0 END)            AS largest_parent_30pct_or_more,
       SUM(CASE WHEN m * 100.0 / st >= 40 THEN 1 ELSE 0 END)            AS largest_parent_40pct_or_more,
       SUM(CASE WHEN m * 100.0 / st >= 50 THEN 1 ELSE 0 END)            AS largest_parent_50pct_or_more
FROM r WHERE rk = 1;

/* ---------- Finding 5: state non-medical share and payment growth are unrelated ----------
   Shows : across the 51 areas, the Pearson correlation between CY2023 non-medical share and 3-year payment growth,
           and the range of the share. Same result at county level in v1 (r = 0.02).
   Not   : a causal claim, and not proof of anything about any plan. MLR is a regulatory ratio, not a profit measure;
           a state value is a mix of the contracts that serve it; the MLR year (2023) is older than the payment data. */
SELECT COUNT(*) AS states,
       CAST((COUNT(*) * SUM(nonmed_share_cy2023_pct * pay_3yr_pct) - SUM(nonmed_share_cy2023_pct) * SUM(pay_3yr_pct))
            / SQRT((COUNT(*) * SUM(nonmed_share_cy2023_pct * nonmed_share_cy2023_pct) - POWER(SUM(nonmed_share_cy2023_pct), 2))
                 * (COUNT(*) * SUM(pay_3yr_pct * pay_3yr_pct) - POWER(SUM(pay_3yr_pct), 2))) AS DECIMAL(5,3)) AS correlation_r,
       (SELECT TOP 1 state_name FROM dbo.v2_state_scorecard ORDER BY nonmed_share_cy2023_pct DESC)  AS highest_state,
       (SELECT CAST(MAX(nonmed_share_cy2023_pct) AS DECIMAL(5,2)) FROM dbo.v2_state_scorecard)       AS highest_pct,
       (SELECT TOP 1 state_name FROM dbo.v2_state_scorecard ORDER BY nonmed_share_cy2023_pct ASC)   AS lowest_state,
       (SELECT CAST(MIN(nonmed_share_cy2023_pct) AS DECIMAL(5,2)) FROM dbo.v2_state_scorecard)       AS lowest_pct
FROM dbo.v2_state_scorecard;
