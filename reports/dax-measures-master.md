# DAX measures: master extension (state view)

Nine more measures in the same `_Measures` table, display folder `7 Master`, used only by `powerbi/rate-gap-master-40-state.pbix`. The v1 measures ([`dax-measures.md`](dax-measures.md)) are unchanged and still in the model. Definitions are in [`powerbi/build/measures_master.txt`](../powerbi/build/measures_master.txt) and are loaded by `powerbi/build/build_master_model.ps1`.

## Model additions

| Table | Source | Rows |
|---|---|---|
| `FactScorecard` | `dbo.v2_state_scorecard`, one row per state with values and ranks | 51 |
| `FactOutlook` | `dbo.v2_state_outlook`, actual trend, announced 2027 change, projections | 51 |
| `FactOutlookLong` | `dbo.v2_state_outlook_long`, one row per state, year and series, with a weight | 255 |
| `DimState` | `dbo.dim_state_licence` plus `licensed_text` (Yes, No or Not set) | 51 |

Each fact relates many-to-one to `DimState[state_name]`.

## Measures

| Measure | Format | What it does | BLANK behavior |
|---|---|---|---|
| State MA Members | `#,0` | Sum of September 2026 MA members | BLANK when no state is in context |
| States Counted | `#,0` | Distinct states in context | BLANK when none |
| State Announced 2027 Change % | `0.00"%"` | 2027 county rate vs 2026, weighted by members | Rows with a BLANK change are left out of numerator and denominator |
| State 3-Year Payment Growth % | `0.00"%"` | 2026 county rate vs 2023, weighted by members | Same |
| State 2026 Payment Growth % | `0.00"%"` | 2026 vs 2025, weighted by members | Same |
| State Non-Medical Share CY2023 | `0.00"%"` | 1 - MLR for contract year 2023, weighted by members | Same |
| State Top 10 Count | `0` | How many of three market columns put the state in the top 10 | BLANK unless exactly one state is in context, so a total never shows a made-up count |
| Top 10 States Share of MA Members | `0.0"%"` | Members in the 10 largest states over all members | Ignores any state filter by design |
| Outlook Value % | `0.00"%"` | Payment growth for the chart series (Actual 2024-2026, Announced 2027, Trend projection), weighted | BLANK when the series has no rows. Always read with a series split; the blend of all series is not a meaningful number |

Units: payment growth is a percent (5.26 means 5.26%). Non-medical share is shown in percent. Nothing subtracts payment growth from non-medical share.

## BLANK tests

`powerbi/build/blanktests_master.ps1` runs every measure through edge-case contexts. Raw output: [`dax-blank-tests-master-output.txt`](dax-blank-tests-master-output.txt).

| Test | Context | Result |
|---|---|---|
| M1 | All 51 areas | Members 34,871,342; Top 10 Count BLANK |
| M2 | No state in context | Every state measure BLANK, none 0 (except Top 10 States Share, which ignores filters by design and still returns 56.7) |
| M3 | Arizona | 802,893 members; announced 2027 change 4.61; Top 10 Count 1 |
| M4 | Wyoming | 18,243 members; announced 7.42 |
| M5 | District of Columbia | 33,636 members; Top 10 Count 0 |
| M6 | Outlook series with no rows (Actual 2027) | BLANK |
| M7 | Two states selected (Arizona, Texas) | Members summed; Top 10 Count BLANK |

## Values that tie to SQL

Members 34,871,342; announced 2027 change 5.26%; 2026 payment growth 8.69%; top-10 states share 56.7%; trend projection 4.48%. These match `sql/12_five_findings.sql` and `sql/10_state_outlook_2027.sql`. Note on the trend projection: SQL computes the national 4.48 as the mean of the three national yearly rates (4.4801); the DAX measure returns the member-weighted mean of the state trend values (4.4774). The two definitions differ slightly and both round to 4.48.
