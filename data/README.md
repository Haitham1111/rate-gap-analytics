# Data

All data is public CMS data, pulled 2026-10-13 by [`python/01_pull_cms.py`](../python/01_pull_cms.py). Raw downloads (about 450 MB) are not committed; they land in `C:\Users\Public\rate_gap\raw\`. The cleaned CSVs the SQL scripts load are in [`stage/`](stage/).

## Sources

### 1. County payment rate (ratebooks)

Source page: [Ratebooks and Supporting Data](https://www.cms.gov/medicare/payment/medicare-advantage-rates-statistics/ratebooks-supporting-data)

| Year | File | Inside |
|---|---|---|
| 2018 | `ratebook2018.zip` | `CSV/CountyRate2018.csv` |
| 2019 | `ratebook2019.zip` | `CSV/CountyRate2019.csv` |
| 2020 | `ratebook2020.zip` | `CSV/CountyRate2020.csv` |
| 2021 | `2021-ma-rate-book.zip` | `CSV/CountyRate2021.csv` |
| 2022 | `2022-ma-rate-book.zip` | `CSV/CountyRate2022.csv` |
| 2023 | `2023-ma-rate-book-zip.zip` | `CSV/CountyRate2023.csv` |

Columns: `Code` (SSA state-county), `State`, `County name`, `Parts A&B 5% Bonus Rate`, `Parts A&B 3.5% Bonus Rate`, `Parts A&B 0% Bonus Rate`, `Parts A&B ESRD Rate`. Monthly per-member capitation rate in dollars. Each file has 3,245 or 3,246 county rows.

Newest year on CMS: 2027. Used: 2018 to 2023, to match the MLR years. The `0% Bonus` column is used as the base county benchmark.

### 2. Medical Loss Ratio

Source page: [Medical Loss Ratio](https://www.cms.gov/medicare/health-drug-plans/medical-loss-ratio)

| Contract year | File |
|---|---|
| 2018 | `cy-2018-mlr-data-release-file.zip` |
| 2019 | `cy-2019-mlr-data-release-file.zip-0` |
| 2020 | `cy-2020-mlr-data-release-file.zip-0` |
| 2021 | `cy-2021-mlr-data-release-file.zip` |
| 2022 | `cy-2022-mlr-data-release-file.zip` |
| 2023 | `public-use-file-cy-2023-zip.zip` |

Columns used: `Contract Number`, `Contract Year`, `Organization Name`, `Adjusted MLR` (2023: `4.3 Adjusted MLR`), `Remittance Amount` (2023: `5.5 Remittance amount due to CMS for CY 2023 experience`). Rows: 423, 453, 508, 564, 615 and 635 (all contract types; 2,932 are MA contracts).

Newest year available: contract year 2023. No contract year 2024 file was listed on 2026-10-13.

### 3. Contract x county enrollment

Source page: [Monthly Enrollment by Contract/Plan/State/County](https://www.cms.gov/data-research/statistics-trends-and-reports/medicare-advantagepart-d-contract-and-enrollment-data/monthly-enrollment-contract/plan/state/county)

| Month | File |
|---|---|
| December 2018 | `CPSC_Enrollment_2018_12.zip` (downloads.cms.gov) |
| December 2019 to 2023 | `monthly-enrollment-cpsc-december-YYYY.zip` |

Columns: `Contract Number`, `Plan ID`, `SSA State County Code`, `FIPS State County Code`, `State`, `County`, `Enrollment` (`*` = 10 or fewer, suppressed). 2.3 to 3.7 million plan-county rows per month; about 95% are suppressed `*` cells.

### 4. Newest releases (master extension, pulled 2026-10-13)

| Data | File | Newest |
|---|---|---|
| County rates 2024 to 2027 | `2024-ma-rate-book.zip`, `2025-ma-rate-book.zip`, `2026-ma-rate-book.zip`, `2027-ma-rate-book.zip` (each has `CSV/CountyRate<year>.csv`) | 2027 |
| Enrollment | `monthly-enrollment-cpsc-december-2024.zip`, `monthly-enrollment-cpsc-december-2025.zip`, `monthly-enrollment-cpsc-september-2026.zip` | September 2026 |
| Contract type, parent organization | `CPSC_Contract_Info_*.csv` inside the enrollment zips (December 2023, 2024, 2025, September 2026) | September 2026 |

MLR is unchanged: contract year 2023 is still the newest public file. Staged by `python/03_pull_cms_latest.py` into `C:\Users\Public\rate_gap\stage_v2\` (12,987 rate rows, 225,610 contract x county enrollment rows, 4,034 contract rows); `python/04_validate_latest.py` recounts them. The `stage_v2` CSVs are not committed (the enrollment file is 6.7 MB and is re-created by the script).

## Staged files (`stage/`)

| File | Rows | Columns |
|---|---|---|
| `county_rate.csv` | 19,472 | `year, ssa_code, state_ssa, state_raw, county_name, rate_5, rate_35, rate_0, rate_esrd` |
| `mlr.csv` | 3,198 | `year, contract_id, org_name, adjusted_mlr, remittance` |
| `enrollment_cc.csv` | 425,613 | `year, contract_id, ssa_code, enrollment` (plans summed; suppressed cells dropped) |
| `enrollment_meta.csv` | 6 | `year, rows_total, rows_suppressed, enrollment_sum` |
| `source_counts.csv` | 18 | `source, year, row_count, value_sum` (recounted from raw files by `02_validate.py`) |

No personal data. Contract and county identifiers only.
