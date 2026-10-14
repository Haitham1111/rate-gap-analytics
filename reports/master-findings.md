# Master findings: Medicare Advantage by state, newest data

Added on top of the v1 project (2018-2023). v1 files are unchanged. Scope: Medicare Advantage plan types only (Local CCP, Regional CCP, PFFS, MSA; contract prefix H, R or E), 50 states + DC. Stand-alone Part D, PACE and cost plans are excluded.

Metric definitions are the v1 definitions: payment growth in %, non-medical share = 1 - MLR in percentage points. Payment growth and non-medical share are never subtracted from each other.

## Source register (checked on 2026-10-13)

| Source | File | Newest year | Release date | In staging |
|---|---|---|---|---|
| MA county ratebook | `2027-ma-rate-book.zip` (also 2024, 2025, 2026 ratebooks) | 2027 | CMS page shows no date. The final CY2027 rate announcement is dated 2026-04-06 | Yes (`stage_v2`) |
| CY2027 Rate Announcement | [CMS fact sheet](https://www.cms.gov/newsroom/fact-sheets/2027-medicare-advantage-part-d-rate-announcement) | CY2027, final | 2026-04-06 | Not a data file; figures quoted below |
| Parts C & D bid memo | `july-28-2026-parts-c-d-announcement.pdf` | CY2027 | 2026-07-28 | Not used (Part D bid amounts, regional PPO benchmarks) |
| Medical loss ratio | `public-use-file-cy-2023-zip.zip` | Contract year 2023 | Not stated by CMS | Yes (v1) |
| MLR, contract year 2024 | No public use file listed. Filing instructions released 2025-05-30 | Not published | n/a | n/a |
| Enrollment by contract/plan/state/county | `monthly-enrollment-cpsc-september-2026.zip` (also December 2024 and December 2025; December 2023 from v1) | September 2026 | Monthly; CMS page shows no day | Yes (`stage_v2`) |

- **CY2027 rate announcement: published.** CMS states an expected average change in MA payments of +2.48% (over $13 billion), +4.98% including the estimated risk score trend. This is a national payment figure from CMS. The state numbers below are changes in the county rate file and are a different measure.
- **MLR for newer contract years: not published.** Checked the CMS MLR page and five file-name patterns for a contract year 2024 public use file (all returned not found). The newest is contract year 2023, so non-medical share is as of 2023 while payment and enrollment run to 2026 and 2027. Release dates for the MLR files are not stated by CMS: not verified.
- 2026-09 is the newest enrollment month on the CMS page. All figures called "2026 members" use September 2026.

## Ranking method and the "good states" question

No state is chosen here. Each rank column orders the 51 areas on that column alone (1 = largest). `top10_count` counts how many of three market columns (MA members, 3-year payment growth, 2027 announced change) put a state in the top 10. No direction is assumed for non-medical share, so it is ranked but not counted. **No state clearly leads** (Finding 3).

## Finding 1: the 2027 county benchmark change runs from 3.21% to 9.36% by state

SQL: [`sql/12_five_findings.sql`](../sql/12_five_findings.sql), Finding 1.

| national_2027_change_pct | highest_state | highest_pct | lowest_state | lowest_pct | spread_pct_points | states_above_national |
|---|---|---|---|---|---|---|
| 5.26 | ALASKA | 9.36 | INDIANA | 3.21 | 6.15 | 26 |

Highest six: Alaska 9.36, Colorado 8.38, Utah 8.05, Wyoming 7.42, Idaho 7.37, Nebraska 7.36. Lowest six: Indiana 3.21, Kansas 3.54, Michigan 3.57, Oklahoma 3.66, Hawaii 3.66, Connecticut 3.90 ([`sql/09_state_scorecard.sql`](../sql/09_state_scorecard.sql)).

- **Shows:** the enrollment-weighted change in the county rate from the 2026 to the 2027 ratebook, nationally and by state.
- **Does NOT show:** what plans will actually be paid or CMS's expected average payment change (+2.48%; +4.98% with risk score trend). It does not show benefits, premiums or any plan's behavior.

## Finding 2: county rates rose 8.69% in 2026, 3.66 times the 2024-25 average

SQL: [`sql/12_five_findings.sql`](../sql/12_five_findings.sql), Finding 2.

| growth_2024_pct | growth_2025_pct | growth_2026_pct | times_the_2024_25_average |
|---|---|---|---|
| 2.32 | 2.43 | 8.69 | 3.66 |

For 2027 the announced figure is 5.26% and the trend projection (mean of 2024-2026) is 4.48% ([`sql/10_state_outlook_2027.sql`](../sql/10_state_outlook_2027.sql), national line). The trend projection is a projection, not published data.

- **Shows:** national enrollment-weighted growth of the county rate column (0% bonus) for each year.
- **Does NOT show:** payments to plans, risk-score changes or benefit changes. Reading the 0% bonus column as the base benchmark is an assumption.

## Finding 3: no state clearly leads

SQL: [`sql/12_five_findings.sql`](../sql/12_five_findings.sql), Finding 3.

| top10_count | states | state_list |
|---|---|---|
| 3 | 0 | none |
| 2 | 4 | California, Florida, New York, Utah |
| 1 | 22 | Alaska, Arizona, Colorado, Georgia, Idaho, Illinois, Indiana, Iowa, Louisiana, Maine, Michigan, Montana, Nebraska, Nevada, New Mexico, North Carolina, Ohio, Oklahoma, Pennsylvania, Texas, Washington, Wyoming |
| 0 | 25 | all other states and DC |

The 10 largest states by members hold 56.7% of the 34,871,342 MA members (September 2026).

Arizona detail from [`sql/09_state_scorecard.sql`](../sql/09_state_scorecard.sql): 802,893 members (rank 12), 3-year payment growth 19.15% (rank 1), 2027 announced change 4.61% (rank 41).

- **Shows:** that the market-size and payment columns point to different states.
- **Does NOT show:** which states are good for an agent. Licensing, competition, commission, plan mix and member needs are not in the data. The licensed-state list was not supplied, so no licensing filter is applied.

## Finding 4: three parent organizations hold 58.7% of MA members

SQL: [`sql/12_five_findings.sql`](../sql/12_five_findings.sql), Finding 4; detail by state in [`sql/11_plan_mix_by_state.sql`](../sql/11_plan_mix_by_state.sql).

| parent_org | members | share_of_national_pct | top3_combined_share_pct |
|---|---|---|---|
| UnitedHealth Group, Inc. | 9,240,027 | 26.5 | 58.7 |
| Humana Inc. | 7,107,782 | 20.4 | 58.7 |
| CVS Health Corporation | 4,111,217 | 11.8 | 58.7 |

In 42 of 51 areas the largest parent organization holds 30% or more of the state's MA members, in 24 areas 40% or more, and in 5 areas 50% or more.

- **Shows:** enrollment concentration by parent organization, as CMS lists the parent on each contract in September 2026.
- **Does NOT show:** plan quality, prices, benefits or behavior. Parent organizations only; no provider is named or listed.

## Finding 5: state non-medical share and payment growth are unrelated (r = 0.032)

SQL: [`sql/12_five_findings.sql`](../sql/12_five_findings.sql), Finding 5.

| states | correlation_r | highest_state | highest_pct | lowest_state | lowest_pct |
|---|---|---|---|---|---|
| 51 | 0.032 | TENNESSEE | 12.17 | NORTH DAKOTA | 2.24 |

This matches v1 at county level (r = 0.02 across 709 counties).

- **Shows:** across 51 areas, contract year 2023 non-medical share and 2023-2026 payment growth do not move together.
- **Does NOT show:** a cause, or anything about any plan. MLR is a regulatory ratio, not a profit measure. A state value is a mix of the contracts that serve it. The MLR year (2023) is older than the payment data.

## Projection method

Every projection is labeled. See [`sql/10_state_outlook_2027.sql`](../sql/10_state_outlook_2027.sql).

- **Payment, 2027 trend projection:** the mean of the three annual growth rates 2024, 2025 and 2026, carried forward. Shown beside the announced 2027 change to compare. It is not a forecast.
- **Non-medical share:** projection = mean of contract years 2021 to 2023, range = lowest to highest of those years. Payment growth is not used because there is no relationship to build on (Finding 5).
- A projection is not evidence of wrongdoing and not a prediction of any plan's behavior.

## Licensing

The licensed-state list was not supplied (the placeholder was blank). All 50 states + DC are built. `dbo.dim_state_licence` has a `licensed` column set to NULL for every state; fill it with `UPDATE dbo.dim_state_licence SET licensed = 1 WHERE state_name IN (...)` and refresh the Power BI file. The Power BI file keeps the name `rate-gap-master-40-state.pbix` as requested, and its scorecard has a Licensed filter that reads "Not set" until then.
