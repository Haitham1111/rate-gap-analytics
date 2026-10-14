# Methodology and limits

## Question

When CMS raises its per-member payment to Medicare Advantage (MA) plans, how does the share of premium-plus-payment revenue spent on medical care (the medical loss ratio, MLR) change, and which counties and contracts show the largest non-medical share? Did it grow or shrink year over year?

## Metric definitions

Fixed for this project.

| Metric | Definition | Unit |
|---|---|---|
| Payment growth | (county monthly rate this year / county monthly rate last year - 1) x 100 | percent |
| MLR | CMS "Adjusted MLR" by contract and year, as published | ratio |
| Non-medical share | 1 - MLR | ratio, shown as percent |
| Change in non-medical share | non-medical share this year minus last year, x 100 | percentage points (pp) |

Payment growth (%) and the change in non-medical share (pp) are different units. They are shown side by side, per county and per contract. They are never subtracted from each other.

## Headline comparison

Per year (national), per county (2018 to 2023) and per contract (2023 quartiles), the project reports payment growth next to the change in non-medical share, plus the Pearson correlation between them across counties (r = 0.02 across 709 counties). Queries 05 and 06 compute these; the poster and the two supporting pages display them.

## How the numbers are built

1. **County payment** comes from the county rate file in each ratebook (Parts A&B). The `0% Bonus` column is used as the base county benchmark. Reading that column as the benchmark is an assumption; the `5%` and `3.5%` bonus columns are staged but not used.
2. **MLR** comes from the CMS MLR data release files. 2018 to 2022 are small files (`Adjusted MLR`, remittance); 2023 is the full public use file (`4.3 Adjusted MLR`).
3. **Link between the two** is the December contract x county enrollment file. Plan-level rows are summed to contract x county. The SSA state-county code joins enrollment to the ratebook.
4. **Fact view** `v_fact` is county x contract x year with enrollment, county rate, payment growth, MLR and non-medical share. It keeps only rows that have all three: enrollment, an MLR for that contract-year, and a rate for that county-year.
5. **County non-medical share** is the enrollment-weighted average of 1 - MLR across the MA contracts in the county. **Contract payment growth** is the enrollment-weighted payment growth of the counties the contract serves.
6. **Scope** is Medicare Advantage contracts (contract IDs starting H, R or E). Stand-alone Part D contracts (S) are in the MLR files but are not paid from the MA county rate, so they are excluded.

### Scope defect found during QA

The first build included Part D contracts. They were 41% to 55% of the enrollment weights (24.9 million of 45.4 million members in 2018) and pulled the headline share to 8.00% in 2018 and 7.78% in 2023. With MA contracts only it is 9.16% and 9.22%. The county in-scope count went from 1,475 to 709 and r from 0.052 to 0.024, and the Arizona comparison reversed (Arizona is above national every year, not below in 2023). Everything in this repository was regenerated after the fix.

## Data vintage and missing years

- County rate: ratebooks 2018 to 2023. CMS lists ratebooks through 2027, but there is no matching MLR for 2024 onward.
- MLR: contract years 2018 to 2023. The CMS page listed no public use file for contract year 2024 on 2026-10-13. CMS's schedule has CY2024 reports due 2025-12-05.
- Enrollment: December of each year, 2018 to 2023.
- 2018 has no prior-year data in this project, so payment growth and every year-over-year change start in 2019.
- Pulled on 2026-10-13. Exact files are listed in [`data/README.md`](../data/README.md).

## Limits

**Level of analysis.** County and contract level only. No individual provider is named, listed or analyzed. Organization names appear only in the staged MLR file as CMS published them and are not shown in any visual.

**A gap is not proof of wrongdoing.** A wide non-medical share in a county can reflect which contracts operate there, plan design, supplemental benefits, risk-adjustment timing, plan size or a one-year utilization swing. The data cannot separate these.

**MLR is reported under its own CMS rules and is not a profit measure.** The numerator and denominator follow CMS definitions, with credibility adjustments, and some costs count as medical that are not clinical care. A low MLR is not margin. An MLR above 100% means reported medical spending exceeded revenue that year; 87 of 593 MA contracts report one in 2023.

**County values are contract-mix values.** An MLR belongs to a whole contract. Applying it to every county of the contract means two counties differ only because different contracts serve them.

**Scope and weights.**
- Employer group plans are inside their contracts and are not separated. Their payment is not set by the county benchmark.
- Enrollment cells of 10 or fewer are suppressed by CMS and dropped, so weights slightly understate small plan-county cells. The size of that understatement is not known.
- The fact view covers 95.2% to 97.3% of MA enrollment in the file; the rest is MA enrollment in contracts with no published MLR that year, or, for about 2,100 member-years in total, in counties with no ratebook row (query 08).
- The in-scope county group (5,000+ MA members in both 2018 and 2023) is 709 mostly larger counties, not all counties.

**Interpretation.** The year-over-year swings (a rise to 12.29% in 2020, a fall to 9.11% in 2021) coincide with the pandemic years. Linking them to utilization is an interpretation, not something this data shows. At national level, 2021 had both the lowest payment growth and the biggest drop in share; with five yearly points that co-movement is not tested. The no-relationship result (r = 0.02) is for counties only; contracts show at most a weak pattern.

## Master extension: newest data, by state (added 2026-10-13)

v1 above covers 2018 to 2023 and is unchanged. The master extension adds the newest CMS releases and a state view. Findings are in [`master-findings.md`](master-findings.md).

### New sources and release dates

| Source | File | Newest | Release date |
|---|---|---|---|
| MA county ratebooks | `2024-ma-rate-book.zip`, `2025-ma-rate-book.zip`, `2026-ma-rate-book.zip`, `2027-ma-rate-book.zip` | 2027 | Page shows no date; the final CY2027 rate announcement is dated 2026-04-06 |
| Enrollment by contract/plan/state/county | `monthly-enrollment-cpsc-december-2024.zip`, `...-december-2025.zip`, `monthly-enrollment-cpsc-september-2026.zip` | September 2026 | Monthly; day not shown |
| Contract type and parent organization | `CPSC_Contract_Info` inside the same enrollment zips | September 2026 | Same |
| MLR | `public-use-file-cy-2023-zip.zip` (v1) | Contract year 2023 | Not stated by CMS |

- **CY2027 rate announcement:** published 2026-04-06. CMS states a +2.48% expected average payment change (+4.98% with risk score trend). The state figures in this project are county rate file changes and are a different measure.
- **MLR for contract year 2024:** no public use file was listed on 2026-10-13 and five file-name patterns returned not found. Non-medical share therefore stays at contract year 2023 while payment and enrollment run to 2026 and 2027. That gap in years is a limit of every state row.
- Staging for the new files is in `C:\Users\Public\rate_gap\stage_v2\`; `python/04_validate_latest.py` recounts them (17 of 17 checks pass).

### Definitions that differ from v1

- **Scope for payment and enrollment** is Medicare Advantage plan types as CMS labels them (Local CCP, Regional CCP, PFFS, MSA) with contract prefix H, R or E. PACE and cost plans have an H prefix but are not paid from the county benchmark, so they are excluded here. v1 used the contracts that publish an MLR.
- **State payment growth** is the enrollment-weighted average of county payment growth, weights = that year's MA enrollment (December for 2023-2025, September for 2026). **3-year growth** is the 2026 county rate against 2023, weighted by September 2026 enrollment. **2027 announced change** is the 2027 county rate against 2026, weighted by September 2026 enrollment.
- **State non-medical share** is the v1 enrollment-weighted share by state for contract year 2023 (Dec 2023 weights).
- **Ranks:** 1 = largest, each column ranked alone, nothing combined into one score. `top10_count` counts how many of enrollment, 3-year payment growth and 2027 announced change put a state in the top 10.

### Projection method

- **Payment, 2027 trend projection:** mean of the 2024, 2025 and 2026 growth rates carried forward, shown only beside the announced 2027 figure.
- **Non-medical share:** mean of contract years 2021 to 2023, with the lowest-to-highest range of those years.
- Projections are not published data, not forecasts of any plan, and not evidence of wrongdoing. Payment growth is not used to project non-medical share because no relationship was found (r = 0.02 by county, r = 0.032 by state).

### Licensing caveat

The licensed-state list was not supplied, so the scorecard covers all 50 states + DC and `dbo.dim_state_licence.licensed` is NULL until filled in. Nothing here says a state is available to any agent. Licensing, commission, competition and member needs are not in the data.

### Added limits

- The county rate column used is the 0% bonus column read as the base benchmark (assumption, as in v1).
- Enrollment rows whose county code has no row in that year's ratebook are left out of payment growth. These are Connecticut codes 07120 and 07140 (December 2025 enrollment only; the ratebooks keep Connecticut's eight older county codes) and Arizona code 03101. That is 11 rows (1,177 members) in December 2024, 39 rows (3,468 members) in December 2025 and 1 row (25 members, under 0.001%) in September 2026, so the 3-year growth and the 2027 change leave out one county with 25 members. Checked by the QA pass on 2026-10-13.
- Suppressed enrollment cells (10 or fewer) are dropped, as in v1.
- Parent organization is the parent CMS lists on each contract for September 2026; it is not a statement about plan quality or behavior.

## Known and assumed

| Known (computed or read from the files) | Assumed |
|---|---|
| Row counts and totals tie to the raw files (42 Python checks, query 08) | The 0% bonus column is the base county benchmark |
| Every README and poster number matches the database | An MLR applies equally to every county of its contract |
| Part D contracts are excluded by contract prefix | Contract prefixes H, R, E identify MA contracts |
| MLR above 100% appears in the published data | Suppressed cells are small relative to the totals |
