/* =====================================================================
   00_setup_database.sql  -  Rate_Gap
   Builds the database, loads the staged CMS CSVs, and creates the views
   every query (01-08) reads.

   Run:  sqlcmd -S .\SQLEXPRESS -C -i sql\00_setup_database.sql
   Needs: python\01_pull_cms.py and python\02_validate.py run first, so the
          CSVs exist in C:\Users\Public\rate_gap\stage\ (BULK INSERT cannot
          read from Downloads).

   Metric definitions (fixed):
     payment_growth_pct   = (county rate this year / county rate last year - 1) * 100
     MLR                  = CMS "Adjusted MLR", as published, by contract and year
     nonmed_share         = 1 - MLR
     nonmed_change_pp     = (nonmed_share this year - last year) * 100   (percentage points)
   Payment growth (%) and non-medical change (pp) are different units.
   They are shown side by side and never subtracted.
   ===================================================================== */

IF DB_ID('Rate_Gap') IS NULL CREATE DATABASE Rate_Gap;
GO
USE Rate_Gap;
GO

/* ---------- Drop in dependency order so the script can be re-run ---------- */
DROP VIEW  IF EXISTS dbo.v_contract_quartile;
DROP VIEW  IF EXISTS dbo.v_contract_year;
DROP VIEW  IF EXISTS dbo.v_county_trend;
DROP VIEW  IF EXISTS dbo.v_county_year;
DROP VIEW  IF EXISTS dbo.v_fact;
DROP VIEW  IF EXISTS dbo.v_contract_mlr;
DROP VIEW  IF EXISTS dbo.v_county_rate_growth;
DROP VIEW  IF EXISTS dbo.dim_county;
DROP VIEW  IF EXISTS dbo.dim_state;
DROP TABLE IF EXISTS dbo.stg_source_counts;
DROP TABLE IF EXISTS dbo.stg_enrollment_cc;
DROP TABLE IF EXISTS dbo.stg_mlr;
DROP TABLE IF EXISTS dbo.stg_county_rate;
GO

/* ---------- Staging tables (one per CSV) ---------- */
-- County monthly capitation rate, Parts A&B. rate_0 = the "0% Bonus" column,
-- used here as the base county benchmark. rate_5 / rate_35 are the bonus columns.
CREATE TABLE dbo.stg_county_rate (
    year        SMALLINT       NOT NULL,
    ssa_code    CHAR(5)        NOT NULL,   -- SSA state+county code (same code in the enrollment file)
    state_ssa   CHAR(2)        NOT NULL,   -- first 2 digits of ssa_code; '03' = Arizona
    state_raw   VARCHAR(40)    NULL,       -- abbreviation 2018-2020, full name 2021+
    county_name NVARCHAR(100)  NULL,
    rate_5      DECIMAL(10,2)  NULL,
    rate_35     DECIMAL(10,2)  NULL,
    rate_0      DECIMAL(10,2)  NULL,
    rate_esrd   DECIMAL(10,2)  NULL,
    CONSTRAINT pk_stg_county_rate PRIMARY KEY (year, ssa_code)
);

-- Adjusted MLR by contract and year, as CMS published it.
CREATE TABLE dbo.stg_mlr (
    year         SMALLINT       NOT NULL,
    contract_id  VARCHAR(10)    NOT NULL,
    org_name     NVARCHAR(200)  NULL,
    adjusted_mlr DECIMAL(8,4)   NOT NULL,
    remittance   DECIMAL(18,2)  NULL,
    CONSTRAINT pk_stg_mlr PRIMARY KEY (year, contract_id)
);

-- December enrollment summed from plan level to contract x county.
-- Cells CMS suppresses (10 or fewer members) are not in this table.
CREATE TABLE dbo.stg_enrollment_cc (
    year        SMALLINT     NOT NULL,
    contract_id VARCHAR(10)  NOT NULL,
    ssa_code    CHAR(5)      NOT NULL,
    enrollment  INT          NOT NULL,
    CONSTRAINT pk_stg_enrollment_cc PRIMARY KEY (year, contract_id, ssa_code)
);

-- Row counts and totals recounted from the raw CMS files by python\02_validate.py.
CREATE TABLE dbo.stg_source_counts (
    source     VARCHAR(20)    NOT NULL,
    year       SMALLINT       NOT NULL,
    row_count  BIGINT         NOT NULL,
    value_sum  DECIMAL(20,4)  NOT NULL,
    CONSTRAINT pk_stg_source_counts PRIMARY KEY (source, year)
);
GO

/* ---------- Load ---------- */
BULK INSERT dbo.stg_county_rate FROM 'C:\Users\Public\rate_gap\stage\county_rate.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, TABLOCK);
BULK INSERT dbo.stg_mlr FROM 'C:\Users\Public\rate_gap\stage\mlr.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', KEEPNULLS, TABLOCK);
BULK INSERT dbo.stg_enrollment_cc FROM 'C:\Users\Public\rate_gap\stage\enrollment_cc.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
BULK INSERT dbo.stg_source_counts FROM 'C:\Users\Public\rate_gap\stage\source_counts.csv'
    WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', TABLOCK);
GO

/* ---------- Dimensions ---------- */
-- State name per SSA state code, taken from the 2023 file (full names).
CREATE VIEW dbo.dim_state AS
SELECT state_ssa, MAX(state_raw) AS state_name
FROM dbo.stg_county_rate
WHERE year = 2023
GROUP BY state_ssa;
GO

-- One row per county, using the newest year the county appears in.
CREATE VIEW dbo.dim_county AS
SELECT x.ssa_code, x.state_ssa, s.state_name, x.county_name
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY ssa_code ORDER BY year DESC) AS rn
    FROM dbo.stg_county_rate
) AS x
LEFT JOIN dbo.dim_state AS s ON s.state_ssa = x.state_ssa
WHERE x.rn = 1;
GO

/* ---------- County payment growth ---------- */
-- payment_growth_pct is NULL when the county has no prior-year rate (2018, or a new county).
CREATE VIEW dbo.v_county_rate_growth AS
SELECT c.year, c.ssa_code, c.state_ssa, c.rate_0,
       p.rate_0 AS rate_0_prior,
       CASE WHEN p.rate_0 > 0 THEN (c.rate_0 / p.rate_0 - 1) * 100 END AS payment_growth_pct
FROM dbo.stg_county_rate AS c
LEFT JOIN dbo.stg_county_rate AS p
       ON p.ssa_code = c.ssa_code AND p.year = c.year - 1;
GO

/* ---------- Contract MLR and non-medical share ---------- */
-- MA contracts only (see WHERE below). nonmed_change_pp is NULL when the contract has no MLR in the prior year.
-- Negative non-medical share is possible: MLR above 1 means reported medical spending
-- exceeded premium revenue that year.
CREATE VIEW dbo.v_contract_mlr AS
SELECT m.year, m.contract_id, m.org_name, m.adjusted_mlr, m.remittance,
       1 - m.adjusted_mlr AS nonmed_share,
       CASE WHEN p.adjusted_mlr IS NOT NULL
            THEN ((1 - m.adjusted_mlr) - (1 - p.adjusted_mlr)) * 100 END AS nonmed_change_pp
FROM dbo.stg_mlr AS m
LEFT JOIN dbo.stg_mlr AS p
       ON p.contract_id = m.contract_id AND p.year = m.year - 1
-- Scope: Medicare Advantage contracts only. H = local MA, R = regional PPO, E = employer/direct MA.
-- Stand-alone Part D contracts (prefix S) are in the MLR files but are not paid from the MA county rate,
-- so they are left out. They made up 41-55% of the enrollment weights before this filter.
WHERE LEFT(m.contract_id, 1) IN ('H', 'R', 'E');
GO

/* ---------- Fact view: county x contract x year ----------
   Inner joins keep only rows that have all three: December enrollment in the county,
   an MLR for that contract-year, and a county rate for that year.
   Rows lost to each join are counted in query 08. */
CREATE VIEW dbo.v_fact AS
SELECT e.year, e.ssa_code, g.state_ssa, e.contract_id, m.org_name,
       e.enrollment,
       g.rate_0, g.payment_growth_pct,
       m.adjusted_mlr, m.nonmed_share, m.nonmed_change_pp
FROM dbo.stg_enrollment_cc  AS e
JOIN dbo.v_contract_mlr     AS m ON m.contract_id = e.contract_id AND m.year = e.year
JOIN dbo.v_county_rate_growth AS g ON g.ssa_code = e.ssa_code AND g.year = e.year;
GO

/* ---------- County x year ----------
   County non-medical share = enrollment-weighted average of the 1 - MLR of the
   contracts operating there. Each contract's MLR is a whole-contract figure and is
   applied to every county the contract serves. */
CREATE VIEW dbo.v_county_year AS
SELECT year, ssa_code, state_ssa,
       SUM(enrollment)                                        AS enrollment,
       COUNT(DISTINCT contract_id)                            AS contracts,
       MAX(rate_0)                                            AS rate_0,
       MAX(payment_growth_pct)                                AS payment_growth_pct,
       SUM(enrollment * adjusted_mlr) / SUM(enrollment)       AS mlr_weighted,
       SUM(enrollment * nonmed_share) / SUM(enrollment)       AS nonmed_share
FROM dbo.v_fact
GROUP BY year, ssa_code, state_ssa;
GO

-- Adds last year's value and the change in percentage points.
CREATE VIEW dbo.v_county_trend AS
SELECT *,
       LAG(nonmed_share) OVER (PARTITION BY ssa_code ORDER BY year) AS nonmed_share_prior,
       (nonmed_share - LAG(nonmed_share) OVER (PARTITION BY ssa_code ORDER BY year)) * 100
           AS nonmed_change_pp
FROM dbo.v_county_year;
GO

/* ---------- Contract x year ----------
   Payment growth for a contract = enrollment-weighted average of the payment growth
   of the counties it serves. */
CREATE VIEW dbo.v_contract_year AS
SELECT f.year, f.contract_id, MAX(f.org_name) AS org_name,
       SUM(f.enrollment)                      AS enrollment,
       COUNT(*)                               AS counties,
       MAX(f.adjusted_mlr)                    AS adjusted_mlr,
       MAX(f.nonmed_share)                    AS nonmed_share,
       MAX(f.nonmed_change_pp)                AS nonmed_change_pp,
       SUM(CASE WHEN f.payment_growth_pct IS NOT NULL THEN f.enrollment * f.payment_growth_pct END)
         / NULLIF(SUM(CASE WHEN f.payment_growth_pct IS NOT NULL THEN f.enrollment END), 0)
                                              AS payment_growth_pct
FROM dbo.v_fact AS f
GROUP BY f.year, f.contract_id;
GO

/* ---------- Contract quartiles (used by query 05 and the Power BI model) ----------
   Same scope as query 05: contracts with 1,000+ matched members, a prior-year MLR and a
   payment growth value. Quartile 1 = lowest non-medical share that year. */
CREATE VIEW dbo.v_contract_quartile AS
SELECT *, NTILE(4) OVER (PARTITION BY year ORDER BY nonmed_share, contract_id) AS quartile   -- contract_id breaks ties so quartiles are repeatable
FROM dbo.v_contract_year
WHERE enrollment >= 1000
  AND payment_growth_pct IS NOT NULL
  AND nonmed_change_pp   IS NOT NULL;
GO

/* ---------- Load check ---------- */
SELECT 'stg_county_rate'   AS tbl, COUNT(*) AS row_count FROM dbo.stg_county_rate UNION ALL
SELECT 'stg_mlr',                  COUNT(*) FROM dbo.stg_mlr UNION ALL
SELECT 'stg_enrollment_cc',        COUNT(*) FROM dbo.stg_enrollment_cc UNION ALL
SELECT 'stg_source_counts',        COUNT(*) FROM dbo.stg_source_counts UNION ALL
SELECT 'v_fact',                   COUNT(*) FROM dbo.v_fact UNION ALL
SELECT 'v_county_year',            COUNT(*) FROM dbo.v_county_year UNION ALL
SELECT 'v_contract_year',          COUNT(*) FROM dbo.v_contract_year;
GO
