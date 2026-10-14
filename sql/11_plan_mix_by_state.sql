/* 11 - Plan mix by state: top 5 parent organizations, newest month (September 2026)
   Medicare Advantage plan types only. Parent organizations only (the parent listed by CMS on each contract);
   no provider names. Share = parent's MA enrollment in the state / all MA enrollment in the state.
   Result 1: one row per state and rank (1-5). Result 2: one row per state with the top-5 combined share. */
USE Rate_Gap;
SET NOCOUNT ON;

WITH org AS (
    SELECT state_ssa, parent_org, SUM(enrollment) AS members
    FROM dbo.v2_enroll_ma
    WHERE year = 2026
    GROUP BY state_ssa, parent_org
),
tot AS (
    SELECT state_ssa, SUM(members) AS state_members, COUNT(*) AS parent_orgs FROM org GROUP BY state_ssa
),
ranked AS (
    SELECT o.state_ssa, o.parent_org, o.members,
           ROW_NUMBER() OVER (PARTITION BY o.state_ssa ORDER BY o.members DESC, o.parent_org) AS org_rank
    FROM org AS o
)
SELECT s.state_name, r.org_rank, r.parent_org, r.members,
       CAST(r.members * 100.0 / t.state_members AS DECIMAL(5,1)) AS share_of_state_pct
FROM ranked AS r
JOIN tot AS t ON t.state_ssa = r.state_ssa
JOIN dbo.dim_state_licence AS s ON s.state_ssa = r.state_ssa
WHERE r.org_rank <= 5
ORDER BY s.state_name, r.org_rank;

-- Result 2: how concentrated is each state
WITH org AS (
    SELECT state_ssa, parent_org, SUM(enrollment) AS members
    FROM dbo.v2_enroll_ma WHERE year = 2026 GROUP BY state_ssa, parent_org
),
ranked AS (
    SELECT state_ssa, parent_org, members,
           SUM(members) OVER (PARTITION BY state_ssa) AS state_members,
           ROW_NUMBER() OVER (PARTITION BY state_ssa ORDER BY members DESC, parent_org) AS org_rank
    FROM org
)
SELECT s.state_name,
       MAX(r.state_members)                                                     AS ma_members,
       COUNT(*)                                                                 AS parent_orgs,
       CAST(SUM(CASE WHEN r.org_rank <= 5 THEN r.members END) * 100.0 / MAX(r.state_members) AS DECIMAL(5,1)) AS top5_share_pct,
       MAX(CASE WHEN r.org_rank = 1 THEN r.parent_org END)                      AS largest_parent,
       CAST(MAX(CASE WHEN r.org_rank = 1 THEN r.members END) * 100.0 / MAX(r.state_members) AS DECIMAL(5,1)) AS largest_share_pct
FROM ranked AS r
JOIN dbo.dim_state_licence AS s ON s.state_ssa = r.state_ssa
GROUP BY s.state_name
ORDER BY top5_share_pct DESC;
