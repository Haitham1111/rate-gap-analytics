/* 08 - Reconciliation back to the source files
   Part A: database totals vs totals recounted from the raw CMS files (python\02_validate.py).
   Part B: where enrollment goes between the enrollment file and the fact view (MA scope). */
USE Rate_Gap;
SET NOCOUNT ON;

-- Part A: staged tables vs source
SELECT s.source, s.year,
       s.row_count                              AS source_rows,
       d.n                                      AS db_rows,
       CAST(s.value_sum AS DECIMAL(20,2))       AS source_total,
       CAST(d.total     AS DECIMAL(20,2))       AS db_total,
       CASE WHEN ABS(s.value_sum - d.total) < 0.01
             AND (d.n IS NULL OR s.row_count = d.n) THEN 'PASS' ELSE 'FAIL' END AS result
FROM dbo.stg_source_counts AS s
JOIN (
    SELECT 'county_rate' AS source, year, COUNT(*) AS n, SUM(rate_0)             AS total FROM dbo.stg_county_rate GROUP BY year
    UNION ALL
    SELECT 'mlr',                   year, COUNT(*),      SUM(adjusted_mlr)               FROM dbo.stg_mlr         GROUP BY year
    UNION ALL
    -- enrollment rows are not comparable (suppressed rows were dropped and plans summed), so compare members only
    SELECT 'enrollment',            year, NULL,          SUM(CAST(enrollment AS DECIMAL(20,4))) FROM dbo.stg_enrollment_cc GROUP BY year
) AS d ON d.source = s.source AND d.year = s.year
ORDER BY s.source, s.year;

-- Part B: enrollment funnel from the enrollment file to the fact view.
-- staged = non_ma + ma_no_mlr + no_rate + in_fact on every row.
--   non_ma     : contracts that are not Medicare Advantage (prefix other than H, R, E), mainly stand-alone Part D
--   ma_no_mlr  : MA contracts with no published MLR that year
--   no_rate    : MA contracts with an MLR, in a county that has no ratebook row (territories)
WITH f AS (
    SELECT e.year,
           SUM(e.enrollment)                                                                  AS staged_members,
           SUM(CASE WHEN LEFT(e.contract_id, 1) NOT IN ('H', 'R', 'E') THEN e.enrollment ELSE 0 END) AS non_ma_members,
           SUM(CASE WHEN LEFT(e.contract_id, 1) IN ('H', 'R', 'E') AND m.contract_id IS NULL
                    THEN e.enrollment ELSE 0 END)                                             AS ma_no_mlr_members,
           SUM(CASE WHEN m.contract_id IS NOT NULL AND r.ssa_code IS NULL
                    THEN e.enrollment ELSE 0 END)                                             AS no_rate_members
    FROM dbo.stg_enrollment_cc AS e
    LEFT JOIN dbo.v_contract_mlr  AS m ON m.contract_id = e.contract_id AND m.year = e.year
    LEFT JOIN dbo.stg_county_rate AS r ON r.ssa_code    = e.ssa_code    AND r.year = e.year
    GROUP BY e.year
),
v AS (SELECT year, SUM(enrollment) AS fact_members FROM dbo.v_fact GROUP BY year)
SELECT f.year, f.staged_members, f.non_ma_members, f.ma_no_mlr_members, f.no_rate_members, v.fact_members,
       CAST(v.fact_members * 100.0 / (f.staged_members - f.non_ma_members) AS DECIMAL(5,1)) AS pct_of_ma_members_in_fact,
       CASE WHEN f.staged_members = f.non_ma_members + f.ma_no_mlr_members + f.no_rate_members + v.fact_members
            THEN 'PASS' ELSE 'FAIL' END AS result
FROM f JOIN v ON v.year = f.year
ORDER BY f.year;
