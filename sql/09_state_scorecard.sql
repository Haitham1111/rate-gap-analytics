/* 09 - State scorecard, newest year for each source
   One row per state (50 states + DC). Medicare Advantage plan types only.

   Newest data used for each column
     enrollment, counties, contracts : September 2026 (newest month CMS had published)
     payment growth, latest year     : 2026 county rate vs 2025 (ratebook), weighted by 2026 MA enrollment
     payment growth, 3-year          : 2026 county rate vs 2023, weighted by 2026 MA enrollment
     2027 announced benchmark change : 2027 county rate vs 2026 (ratebook), weighted by 2026 MA enrollment
     non-medical share               : contract year 2023, the newest MLR public file (CY2024 not published)
   Units: payment growth in %, non-medical share in %, its change in percentage points (pp). Never subtracted from each other.

   Ranking method (nothing is combined into one score; each column ranks on its own):
     rank_* = RANK() over the 51 areas, 1 = largest value.
     top10_count = how many of three market columns put the state in the top 10:
       MA enrollment, 3-year payment growth, 2027 announced benchmark change.
     No direction is assumed for non-medical share, so it is shown and ranked but not counted.
   licensed is NULL until the user fills dbo.dim_state_licence (the licensed-state list was not supplied). */
USE Rate_Gap;
SET NOCOUNT ON;

-- The calculation lives in dbo.v2_state_scorecard (sql/00b_setup_latest_data.sql); this query formats it.
SELECT state_name, licensed, ma_members, counties, contracts,
       CAST(enroll_growth_3yr_pct   AS DECIMAL(6,2)) AS enroll_growth_3yr_pct,
       CAST(pay_growth_2026_pct     AS DECIMAL(6,2)) AS pay_growth_2026_pct,
       CAST(pay_3yr_pct             AS DECIMAL(6,2)) AS pay_growth_3yr_pct,
       CAST(chg_2027_pct            AS DECIMAL(6,2)) AS announced_2027_change_pct,
       CAST(nonmed_share_cy2023_pct AS DECIMAL(6,2)) AS nonmed_share_cy2023_pct,
       CAST(nonmed_chg_1yr_pp       AS DECIMAL(6,2)) AS nonmed_chg_1yr_pp,
       CAST(nonmed_chg_3yr_pp       AS DECIMAL(6,2)) AS nonmed_chg_3yr_pp,
       rank_enrollment, rank_enroll_growth, rank_pay_2026, rank_pay_3yr, rank_chg_2027,
       rank_nonmed_share, rank_nonmed_chg_3yr, top10_count
FROM dbo.v2_state_scorecard
ORDER BY ma_members DESC;
