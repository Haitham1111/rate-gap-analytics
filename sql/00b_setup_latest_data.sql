/* =====================================================================
   00b_setup_latest_data.sql  -  Rate_Gap, master extension
   Adds the newest CMS releases beside the v1 data. Nothing in v1 is changed.

   Run AFTER 00_setup_database.sql:
     sqlcmd -S .\SQLEXPRESS -C -i sql\00b_setup_latest_data.sql
   Needs python\03_pull_cms_latest.py run first (CSVs in C:\Users\Public\rate_gap\stage_v2\).

   New data
     county rates 2024-2027   (ratebooks; 2027 is the newest CMS had published)
     enrollment   Dec 2024, Dec 2025, Sep 2026 (newest month published)
     contract type and parent organization for Dec 2023, Dec 2024, Dec 2025, Sep 2026
   MLR: contract year 2023 is still the newest public file (CY2024 not published), so MLR stays in v1.

   Scope rules
     Payment and enrollment views: Medicare Advantage plan types only (Local CCP, Regional CCP, PFFS, MSA)
       with contract prefix H, R or E. PACE, cost plans and stand-alone Part D are excluded.
     50 states + DC only (territories are left out).
   Same metric definitions as v1: payment growth in %, non-medical share = 1 - MLR, change in pp.
   ===================================================================== */

USE Rate_Gap;
GO

DROP VIEW  IF EXISTS dbo.v2_state_outlook_long;
DROP VIEW  IF EXISTS dbo.v2_state_outlook;
DROP VIEW  IF EXISTS dbo.v2_state_scorecard;
DROP VIEW  IF EXISTS dbo.v2_state_year;
DROP VIEW  IF EXISTS dbo.v2_enroll_ma;
DROP VIEW  IF EXISTS dbo.v2_ma_contract;
DROP VIEW  IF EXISTS dbo.v2_rate_growth;
DROP VIEW  IF EXISTS dbo.v2_rate_all;
DROP TABLE IF EXISTS dbo.stg_source_counts_ext;
DROP TABLE IF EXISTS dbo.stg_contract_info;
DROP TABLE IF EXISTS dbo.stg_enroll_ext;
DROP TABLE IF EXISTS dbo.stg_rate_ext;
GO

/* ---------- Staging tables ---------- */
CREATE TABLE dbo.stg_rate_ext (
    year        SMALLINT       NOT NULL,
    ssa_code    CHAR(5)        NOT NULL,
    state_ssa   CHAR(2)        NOT NULL,
    state_raw   VARCHAR(40)    NULL,
    county_name NVARCHAR(100)  NULL,
    rate_5      DECIMAL(10,2)  NULL,
    rate_35     DECIMAL(10,2)  NULL,
    rate_0      DECIMAL(10,2)  NULL,
    rate_esrd   DECIMAL(10,2)  NULL,
    CONSTRAINT pk_stg_rate_ext PRIMARY KEY (year, ssa_code)
);

-- Contract x county enrollment. period is the month the file covers (2026-09 is the newest month).
CREATE TABLE dbo.stg_enroll_ext (
    year        SMALLINT     NOT NULL,
    period      CHAR(7)      NOT NULL,
    contract_id VARCHAR(10)  NOT NULL,
    ssa_code    CHAR(5)      NOT NULL,
    enrollment  INT          NOT NULL,
    CONSTRAINT pk_stg_enroll_ext PRIMARY KEY (year, contract_id, ssa_code)
);

-- Contract type and parent organization as CMS lists them in each month's contract file.
CREATE TABLE dbo.stg_contract_info (
    period      CHAR(7)        NOT NULL,
    contract_id VARCHAR(10)    NOT NULL,
    parent_org  NVARCHAR(200)  NULL,
    org_type    VARCHAR(60)    NULL,
    CONSTRAINT pk_stg_contract_info PRIMARY KEY (period, contract_id)
);

CREATE TABLE dbo.stg_source_counts_ext (
    source     VARCHAR(20)    NOT NULL,
    year       SMALLINT       NOT NULL,
    row_count  BIGINT         NOT NULL,
    value_sum  DECIMAL(20,4)  NOT NULL,
    CONSTRAINT pk_stg_source_counts_ext PRIMARY KEY (source, year)
);
GO

/* ---------- Load ---------- */
BULK INSERT dbo.stg_rate_ext FROM 'C:\Users\Public\rate_gap\stage_v2\county_rate_ext.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, TABLOCK);
BULK INSERT dbo.stg_enroll_ext FROM 'C:\Users\Public\rate_gap\stage_v2\enrollment_ext.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.stg_contract_info FROM 'C:\Users\Public\rate_gap\stage_v2\contract_parent.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, TABLOCK);
BULK INSERT dbo.stg_source_counts_ext FROM 'C:\Users\Public\rate_gap\stage_v2\source_counts_ext.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

/* ---------- States and the licensing column ----------
   50 states + DC. "licensed" is NULL for every state: the licensed-state list was not supplied,
   so the column is left for the user to fill in (UPDATE dbo.dim_state_licence SET licensed = 1 WHERE ...).
   The table is created once and is not dropped when this script is re-run. */
IF OBJECT_ID('dbo.dim_state_licence') IS NULL
BEGIN
    CREATE TABLE dbo.dim_state_licence (
        state_ssa  CHAR(2)      NOT NULL PRIMARY KEY,   -- first 2 digits of the SSA county code
        state_name VARCHAR(40)  NOT NULL,
        licensed   BIT          NULL
    );
    INSERT dbo.dim_state_licence (state_ssa, state_name)
    SELECT DISTINCT state_ssa, state_raw
    FROM dbo.stg_rate_ext
    WHERE year = 2027
      AND state_raw NOT IN ('GU', 'NORTHERN MARIANA ISLANDS', 'PUERTO RICO', 'VIRGIN ISLANDS');
END
GO

/* ---------- County rates, 2018-2027 ---------- */
CREATE VIEW dbo.v2_rate_all AS
SELECT year, ssa_code, state_ssa, county_name, rate_0 FROM dbo.stg_county_rate      -- 2018-2023 (v1)
UNION ALL
SELECT year, ssa_code, state_ssa, county_name, rate_0 FROM dbo.stg_rate_ext;        -- 2024-2027
GO

-- payment_growth_pct is NULL when the county has no prior-year rate. In this data the NULLs that matter come from
-- enrollment county codes that have no row in that year's ratebook at all (Connecticut 07120, 07140; Arizona 03101).
CREATE VIEW dbo.v2_rate_growth AS
SELECT c.year, c.ssa_code, c.state_ssa, c.rate_0,
       p.rate_0 AS rate_0_prior,
       CASE WHEN p.rate_0 > 0 THEN (c.rate_0 / p.rate_0 - 1) * 100 END AS payment_growth_pct
FROM dbo.v2_rate_all AS c
LEFT JOIN dbo.v2_rate_all AS p ON p.ssa_code = c.ssa_code AND p.year = c.year - 1;
GO

/* ---------- MA contracts by month ---------- */
CREATE VIEW dbo.v2_ma_contract AS
SELECT CAST(LEFT(period, 4) AS SMALLINT) AS year, period, contract_id, parent_org, org_type
FROM dbo.stg_contract_info
WHERE org_type IN ('Local CCP', 'Regional CCP', 'PFFS', 'MSA')
  AND LEFT(contract_id, 1) IN ('H', 'R', 'E');
GO

/* ---------- MA enrollment, contract x county x year, 2023-2026, 50 states + DC ----------
   2023 = December 2023 (v1 staging), 2024 and 2025 = December, 2026 = September (newest month). */
CREATE VIEW dbo.v2_enroll_ma AS
SELECT e.year, e.ssa_code, s.state_ssa, e.contract_id, c.parent_org, e.enrollment
FROM (SELECT year, contract_id, ssa_code, enrollment FROM dbo.stg_enrollment_cc WHERE year = 2023
      UNION ALL
      SELECT year, contract_id, ssa_code, enrollment FROM dbo.stg_enroll_ext) AS e
JOIN dbo.v2_ma_contract     AS c ON c.year = e.year AND c.contract_id = e.contract_id
JOIN dbo.dim_state_licence  AS s ON s.state_ssa = LEFT(e.ssa_code, 2);
GO

/* ---------- State x year: enrollment, counties, contracts, weighted payment growth ----------
   Payment growth is the enrollment-weighted average of county payment growth (weights = that year's
   MA enrollment). Counties with no prior-year rate are left out of numerator and denominator. */
CREATE VIEW dbo.v2_state_year AS
SELECT e.year, e.state_ssa,
       SUM(e.enrollment)                                         AS enrollment,
       COUNT(DISTINCT e.ssa_code)                                AS counties,
       COUNT(DISTINCT e.contract_id)                             AS contracts,
       SUM(CASE WHEN g.payment_growth_pct IS NOT NULL THEN e.enrollment * g.payment_growth_pct END)
         / NULLIF(SUM(CASE WHEN g.payment_growth_pct IS NOT NULL THEN e.enrollment END), 0)  AS payment_growth_pct
FROM dbo.v2_enroll_ma AS e
LEFT JOIN dbo.v2_rate_growth AS g ON g.ssa_code = e.ssa_code AND g.year = e.year
GROUP BY e.year, e.state_ssa;
GO

/* ---------- State scorecard (newest data for each source; ranking method is in sql/09_state_scorecard.sql) ---------- */
CREATE VIEW dbo.v2_state_scorecard AS
WITH cur AS (   -- MA enrollment by state x county, newest month
    SELECT state_ssa, ssa_code, SUM(enrollment) AS enr
    FROM dbo.v2_enroll_ma
    WHERE year = 2026
    GROUP BY state_ssa, ssa_code
),
cum AS (        -- county rate changes, weighted by the newest enrollment
    SELECT c.state_ssa,
           SUM(CASE WHEN r23.rate_0 > 0 AND r26.rate_0 > 0 THEN c.enr * (r26.rate_0 / r23.rate_0 - 1) * 100 END)
             / NULLIF(SUM(CASE WHEN r23.rate_0 > 0 AND r26.rate_0 > 0 THEN c.enr END), 0)   AS pay_3yr_pct,
           SUM(CASE WHEN g27.payment_growth_pct IS NOT NULL THEN c.enr * g27.payment_growth_pct END)
             / NULLIF(SUM(CASE WHEN g27.payment_growth_pct IS NOT NULL THEN c.enr END), 0)  AS chg_2027_pct
    FROM cur AS c
    LEFT JOIN dbo.v2_rate_all    AS r23 ON r23.ssa_code = c.ssa_code AND r23.year = 2023
    LEFT JOIN dbo.v2_rate_all    AS r26 ON r26.ssa_code = c.ssa_code AND r26.year = 2026
    LEFT JOIN dbo.v2_rate_growth AS g27 ON g27.ssa_code = c.ssa_code AND g27.year = 2027
    GROUP BY c.state_ssa
),
nm AS (         -- non-medical share by state, enrollment-weighted (v1 fact, MLR contracts)
    SELECT y.state_ssa, y.year, SUM(y.enrollment * y.nonmed_share) / SUM(y.enrollment) * 100 AS nm_pct
    FROM dbo.v_county_year AS y
    JOIN dbo.dim_state_licence AS s ON s.state_ssa = y.state_ssa
    WHERE y.year IN (2020, 2022, 2023)
    GROUP BY y.state_ssa, y.year
),
base AS (
    SELECT s.state_name, s.licensed,
           y26.enrollment                                              AS ma_members,
           y26.counties, y26.contracts,
           (y26.enrollment * 1.0 / y23.enrollment - 1) * 100           AS enroll_growth_3yr_pct,
           y26.payment_growth_pct                                      AS pay_growth_2026_pct,
           cum.pay_3yr_pct, cum.chg_2027_pct,
           n23.nm_pct                                                  AS nonmed_share_cy2023_pct,
           n23.nm_pct - n22.nm_pct                                     AS nonmed_chg_1yr_pp,
           n23.nm_pct - n20.nm_pct                                     AS nonmed_chg_3yr_pp
    FROM dbo.dim_state_licence AS s
    JOIN dbo.v2_state_year AS y26 ON y26.state_ssa = s.state_ssa AND y26.year = 2026
    JOIN dbo.v2_state_year AS y23 ON y23.state_ssa = s.state_ssa AND y23.year = 2023
    JOIN cum                    ON cum.state_ssa = s.state_ssa
    JOIN nm AS n23              ON n23.state_ssa = s.state_ssa AND n23.year = 2023
    JOIN nm AS n22              ON n22.state_ssa = s.state_ssa AND n22.year = 2022
    JOIN nm AS n20              ON n20.state_ssa = s.state_ssa AND n20.year = 2020
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY ma_members DESC)               AS rank_enrollment,
           RANK() OVER (ORDER BY enroll_growth_3yr_pct DESC)    AS rank_enroll_growth,
           RANK() OVER (ORDER BY pay_growth_2026_pct DESC)      AS rank_pay_2026,
           RANK() OVER (ORDER BY pay_3yr_pct DESC)              AS rank_pay_3yr,
           RANK() OVER (ORDER BY chg_2027_pct DESC)             AS rank_chg_2027,
           RANK() OVER (ORDER BY nonmed_share_cy2023_pct DESC)  AS rank_nonmed_share,
           RANK() OVER (ORDER BY nonmed_chg_3yr_pp DESC)        AS rank_nonmed_chg_3yr
    FROM base
)
SELECT *,
       (CASE WHEN rank_enrollment <= 10 THEN 1 ELSE 0 END
      + CASE WHEN rank_pay_3yr    <= 10 THEN 1 ELSE 0 END
      + CASE WHEN rank_chg_2027   <= 10 THEN 1 ELSE 0 END) AS top10_count
FROM ranked;
GO

/* ---------- State outlook for 2027 (actual trend, announced change, labeled projections; see sql/10_state_outlook_2027.sql) ---------- */
CREATE VIEW dbo.v2_state_outlook AS
WITH cur AS (
    SELECT state_ssa, ssa_code, SUM(enrollment) AS enr
    FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY state_ssa, ssa_code
),
a27 AS (
    SELECT c.state_ssa,
           SUM(c.enr * g.payment_growth_pct) / SUM(c.enr) AS chg_2027
    FROM cur AS c
    JOIN dbo.v2_rate_growth AS g ON g.ssa_code = c.ssa_code AND g.year = 2027 AND g.payment_growth_pct IS NOT NULL
    GROUP BY c.state_ssa
),
pay AS (
    SELECT state_ssa,
           MAX(CASE WHEN year = 2024 THEN payment_growth_pct END) AS g24,
           MAX(CASE WHEN year = 2025 THEN payment_growth_pct END) AS g25,
           MAX(CASE WHEN year = 2026 THEN payment_growth_pct END) AS g26
    FROM dbo.v2_state_year GROUP BY state_ssa
),
nm AS (
    SELECT y.state_ssa,
           MAX(CASE WHEN y.year = 2021 THEN y.s END) AS n21,
           MAX(CASE WHEN y.year = 2022 THEN y.s END) AS n22,
           MAX(CASE WHEN y.year = 2023 THEN y.s END) AS n23
    FROM (SELECT state_ssa, year, SUM(enrollment * nonmed_share) / SUM(enrollment) * 100 AS s
          FROM dbo.v_county_year WHERE year IN (2021, 2022, 2023) GROUP BY state_ssa, year) AS y
    GROUP BY y.state_ssa
)
SELECT s.state_name, s.licensed,
       p.g24 AS actual_2024_pct, p.g25 AS actual_2025_pct, p.g26 AS actual_2026_pct,
       (p.g24 + p.g25 + p.g26) / 3                  AS trailing_3yr_mean_pct,
       a.chg_2027                                   AS announced_2027_pct,
       (p.g24 + p.g25 + p.g26) / 3                  AS projection_trend_2027_pct,
       a.chg_2027 - (p.g24 + p.g25 + p.g26) / 3     AS announced_minus_trend_pct_points,
       RANK() OVER (ORDER BY a.chg_2027 DESC)       AS rank_announced_2027,
       n.n21 AS nonmed_cy2021_pct, n.n22 AS nonmed_cy2022_pct, n.n23 AS nonmed_cy2023_pct,
       (n.n21 + n.n22 + n.n23) / 3                  AS nonmed_projection_mean_pct,
       (SELECT MIN(v) FROM (VALUES (n.n21), (n.n22), (n.n23)) AS t(v)) AS nonmed_projection_low_pct,
       (SELECT MAX(v) FROM (VALUES (n.n21), (n.n22), (n.n23)) AS t(v)) AS nonmed_projection_high_pct,
       (SELECT enrollment FROM dbo.v2_state_year y WHERE y.state_ssa = s.state_ssa AND y.year = 2026) AS ma_members_sep2026
FROM dbo.dim_state_licence AS s
JOIN pay AS p ON p.state_ssa = s.state_ssa
JOIN a27 AS a ON a.state_ssa = s.state_ssa
JOIN nm  AS n ON n.state_ssa = s.state_ssa;
GO

-- Long form for charts: one row per state, year and series.
-- Weight = that year's MA members for the Actual rows (same weights as query 10's national line), and Sep 2026 MA members
-- for the 2027 rows (no 2027 enrollment exists yet).
CREATE VIEW dbo.v2_state_outlook_long AS
SELECT s.state_name, y.year, 'Actual' AS series, y.payment_growth_pct AS value_pct, y.enrollment AS weight
FROM dbo.v2_state_year AS y
JOIN dbo.dim_state_licence AS s ON s.state_ssa = y.state_ssa
WHERE y.year IN (2024, 2025, 2026)
UNION ALL SELECT state_name, 2027, 'Announced benchmark change', announced_2027_pct, ma_members_sep2026 FROM dbo.v2_state_outlook
UNION ALL SELECT state_name, 2027, 'Trend projection', projection_trend_2027_pct, ma_members_sep2026 FROM dbo.v2_state_outlook;
GO

/* ---------- Load check ---------- */
SELECT 'stg_rate_ext' AS tbl, COUNT(*) AS row_count FROM dbo.stg_rate_ext UNION ALL
SELECT 'stg_enroll_ext',      COUNT(*) FROM dbo.stg_enroll_ext UNION ALL
SELECT 'stg_contract_info',   COUNT(*) FROM dbo.stg_contract_info UNION ALL
SELECT 'stg_source_counts_ext', COUNT(*) FROM dbo.stg_source_counts_ext UNION ALL
SELECT 'dim_state_licence',   COUNT(*) FROM dbo.dim_state_licence UNION ALL
SELECT 'v2_enroll_ma',        COUNT(*) FROM dbo.v2_enroll_ma UNION ALL
SELECT 'v2_state_year',       COUNT(*) FROM dbo.v2_state_year;
GO
