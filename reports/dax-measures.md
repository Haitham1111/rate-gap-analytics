# DAX measures

20 measures in the `_Measures` table of `powerbi/rate-gap-dashboard.pbix`. Definitions live in [`powerbi/build/measures.txt`](../powerbi/build/measures.txt) and are loaded into the model by `build_model.ps1`.

Scope: Medicare Advantage contracts only (contract prefix H, R, E). Stand-alone Part D contracts are excluded in SQL before the data reaches Power BI.

## Model

| Table | Source | Rows |
|---|---|---|
| `FactCounty` | `dbo.v_county_trend`: one row per county per year with weighted MLR, non-medical share and payment growth | 18,618 |
| `DimCounty` | `dbo.dim_county` plus a `county_label` column | 3,246 |
| `FactMLR` | `dbo.v_contract_mlr`: every published MA contract-year MLR | 2,932 |
| `FactContract` | `dbo.v_contract_quartile`: MA contracts with 1,000+ matched members, NTILE(4) by year | 2,097 |
| `DimYear` | calculated, 2018 to 2023 | 6 |

Relationships (many to one, single direction): `FactCounty[year]`, `FactMLR[year]`, `FactContract[year]` to `DimYear[yr]`; `FactCounty[ssa_code]` to `DimCounty[ssa_code]`.

## Units

- **Payment growth** is a percent (5.87 means 5.87%) and is formatted with a literal `%`.
- **Non-medical share** is a ratio (0.0922) formatted as a percent.
- **Change in non-medical share** is in percentage points (pp).
- Payment growth (%) and the change in non-medical share (pp) are shown side by side. No measure subtracts one from the other.

## How the BLANK() traps were tested

In DAX, `BLANK() < 3` is TRUE, and `x - BLANK()` returns `x`. Every comparison in these measures first checks `NOT ISBLANK(...)`, and every difference returns BLANK when either side is BLANK.

`powerbi/build/blanktests.ps1` evaluates each measure under edge-case contexts against the open model. Raw output: [`dax-blank-tests-output.txt`](dax-blank-tests-output.txt).

| Test | Context | Result |
|---|---|---|
| T1 | First year, 2018 | Change and growth measures BLANK; index 100; share 9.16% |
| T2 | A year with no data (2016) | All yearly measures BLANK, none 0 |
| T3 | Kimble, TX (300 members in 2023) | Scope measures BLANK; share still computed |
| T4 | Kandiyohi, MN (4,857 members in 2023, just under 5,000) | Scope measures BLANK |
| T5 | Aleutians East, AK (no MA enrollment) | Every measure BLANK |
| T5c | Petroleum, MT (47 member-years in total) | Never in scope; change BLANK |
| T6 | Arizona, 2019 | AZ and national measures return values |
| T7 | 2023, all 20 measures | Values below; match SQL |
| T8 | Two years selected (2021, 2022) | Change and index use the latest year |
| T9 | Maricopa, AZ, 2023 | County measures return values |

**Defect found and fixed during testing:** `Non-Medical Change (pp)` first compared the share in the current context (a blend of all selected years) with the prior year. With several years selected the change was wrong. It now takes the latest year in context for both sides.

**Scope defect found and fixed during QA:** the first build included stand-alone Part D contracts (prefix S) in the weights. They are 41% to 55% of enrollment-weighted members and are not paid from the MA county rate. Every number, visual and screenshot in this project was regenerated after the fix (see `methodology-and-limits.md`).

Source columns that are BLANK by design: `FactCounty[nonmed_change_pp]` 3,169 rows (2018 and counties new to a year), `FactCounty[payment_growth_pct]` 3,033 rows. `FactMLR` and `FactContract` have none.

## Measures

### Volume

#### Members

Members in contracts that have a published MLR, December enrollment. Sums county rows, so several years selected add up member-years.

- Format: `#,0`
- BLANK behavior: SUM of enrollment. BLANK when the filter leaves no rows (a year or county with no data).
- Value in 2023 context (test T7): `31419801`

```dax
SUM ( FactCounty[enrollment] )
```

#### Contracts Published

Distinct contracts with a published Adjusted MLR in the selected year(s).

- Format: `#,0`
- BLANK behavior: DISTINCTCOUNT of MA contracts with a published MLR. BLANK when none are in context.
- Value in 2023 context (test T7): `593`

```dax
DISTINCTCOUNT ( FactMLR[contract_id] )
```

### Payment

#### Payment Growth %

Enrollment-weighted year-over-year growth in the county monthly rate (0% bonus column). Value is already in percent. Counties with no prior-year rate are left out of numerator and denominator.

- Format: `0.00"%"`
- BLANK behavior: BLANK for 2018 (no prior-year rate) and for any context with no weighted base. Counties with no prior-year rate are excluded from both numerator and denominator, so a missing rate is never read as 0%.
- Value in 2023 context (test T7): `5.3798`

```dax
VAR _num = SUMX ( FactCounty, IF ( NOT ISBLANK ( FactCounty[payment_growth_pct] ), FactCounty[enrollment] * FactCounty[payment_growth_pct] ) )
VAR _den = SUMX ( FactCounty, IF ( NOT ISBLANK ( FactCounty[payment_growth_pct] ), FactCounty[enrollment] ) )
RETURN DIVIDE ( _num, _den )
```

#### Payment Index (2018=100)

Compounded weighted payment growth, first year in DimYear = 100. BLANK if any year in the chain has no growth value, so a gap is never treated as 0%.

- Format: `0.0`
- BLANK behavior: 100 in the base year. BLANK outside DimYear, and BLANK if any year in the chain has no growth value, so a gap is never compounded as 0%.
- Value in 2023 context (test T7): `128.8931`

```dax
VAR _base = CALCULATE ( MIN ( DimYear[yr] ), ALL ( DimYear ) )
VAR _y = MAX ( DimYear[yr] )
VAR _yrs = FILTER ( ALL ( DimYear[yr] ), DimYear[yr] > _base && DimYear[yr] <= _y )
VAR _missing = COUNTROWS ( FILTER ( _yrs, ISBLANK ( [Payment Growth %] ) ) )
RETURN
    IF ( _y = _base, 100,
        IF ( _missing = 0, PRODUCTX ( _yrs, 1 + [Payment Growth %] / 100 ) * 100 ) )
```

### MLR

#### Weighted MLR

Enrollment-weighted Adjusted MLR, as CMS published it by contract. Not a profit measure.

- Format: `0.0%`
- BLANK behavior: BLANK when there are no members in context.
- Value in 2023 context (test T7): `0.9078`

```dax
DIVIDE ( SUMX ( FactCounty, FactCounty[enrollment] * FactCounty[mlr_weighted] ), SUM ( FactCounty[enrollment] ) )
```

#### Non-Medical Share

1 minus MLR, enrollment-weighted. Can be negative for a contract whose MLR is above 100%.

- Format: `0.00%`
- BLANK behavior: BLANK when there are no members in context. Negative when MLR is above 100%.
- Value in 2023 context (test T7): `0.0922`

```dax
DIVIDE ( SUMX ( FactCounty, FactCounty[enrollment] * FactCounty[nonmed_share] ), SUM ( FactCounty[enrollment] ) )
```

#### Non-Medical Change (pp)

Change in Non-Medical Share versus the prior year, in percentage points, for the latest year in context. BLANK when either year is missing (never the share itself).

- Format: `+0.00;-0.00;0.00`
- BLANK behavior: BLANK for 2018 and whenever either year is missing. It never returns the share itself (x - BLANK = x is the trap). Pinned to the latest year in context, so several years selected return the change for that latest year.
- Value in 2023 context (test T7): `-1.0941`

```dax
VAR _y = MAX ( DimYear[yr] )
VAR _now = CALCULATE ( [Non-Medical Share], DimYear[yr] = _y )
VAR _prev = CALCULATE ( [Non-Medical Share], DimYear[yr] = _y - 1 )
RETURN IF ( ISBLANK ( _now ) || ISBLANK ( _prev ), BLANK (), ( _now - _prev ) * 100 )
```

### County

#### County In Scope

1 when the county has 5,000+ members in both 2018 and 2023, otherwise BLANK. Blank member counts count as out of scope.

- Format: `0`
- BLANK behavior: BLANK when members are BLANK or under 5,000 in 2018 or 2023. A blank member count is treated as out of scope, not as small.
- Value in 2023 context (test T7): `1`

```dax
VAR _m23 = CALCULATE ( [Members], DimYear[yr] = 2023 )
VAR _m18 = CALCULATE ( [Members], DimYear[yr] = 2018 )
RETURN IF ( NOT ISBLANK ( _m23 ) && NOT ISBLANK ( _m18 ) && _m23 >= 5000 && _m18 >= 5000, 1 )
```

#### Counties In Scope

Number of counties with 5,000+ members in both 2018 and 2023.

- Format: `#,0`
- BLANK behavior: Sum of County In Scope over counties.
- Value in 2023 context (test T7): `709`

```dax
SUMX ( VALUES ( DimCounty[ssa_code] ), [County In Scope] )
```

#### County Payment Growth 2018-23 %

Cumulative rise in the county rate from 2018 to 2023, in percent. BLANK outside the 5,000-member scope.

- Format: `0.0"%"`
- BLANK behavior: BLANK outside scope or when either rate is BLANK. Ignores the year filter by design (fixed 2018 to 2023 window). Meant for one county at a time; at a total it is the ratio of summed county rates, not an average.
- Value in 2023 context (test T7): `35.3583`

```dax
VAR _r23 = CALCULATE ( SUM ( FactCounty[rate_0] ), DimYear[yr] = 2023 )
VAR _r18 = CALCULATE ( SUM ( FactCounty[rate_0] ), DimYear[yr] = 2018 )
RETURN IF ( [County In Scope] = 1 && NOT ISBLANK ( _r23 ) && NOT ISBLANK ( _r18 ) && _r18 > 0, ( DIVIDE ( _r23, _r18 ) - 1 ) * 100 )
```

#### County Non-Med Change 2018-23 (pp)

Change in the county Non-Medical Share from 2018 to 2023, in percentage points. BLANK outside the 5,000-member scope.

- Format: `+0.00;-0.00;0.00`
- BLANK behavior: BLANK outside scope or when either year is BLANK. Ignores the year filter by design.
- Value in 2023 context (test T7): `0.0576`

```dax
VAR _n23 = CALCULATE ( [Non-Medical Share], DimYear[yr] = 2023 )
VAR _n18 = CALCULATE ( [Non-Medical Share], DimYear[yr] = 2018 )
RETURN IF ( [County In Scope] = 1 && NOT ISBLANK ( _n23 ) && NOT ISBLANK ( _n18 ), ( _n23 - _n18 ) * 100 )
```

#### Non-Med Share 2023 (5k+ Counties)

2023 Non-Medical Share for counties in scope. Used to rank the widest and narrowest counties. BLANK outside scope so small counties never rank.

- Format: `0.00%`
- BLANK behavior: BLANK outside scope, so small counties cannot enter a ranking. The Top N visuals also filter this measure to is-not-blank.
- Value in 2023 context (test T7): `0.0922`

```dax
IF ( [County In Scope] = 1, CALCULATE ( [Non-Medical Share], DimYear[yr] = 2023 ) )
```

### Arizona

#### AZ Non-Medical Share

Non-Medical Share for Arizona (SSA state code 03).

- Format: `0.00%`
- BLANK behavior: BLANK when Arizona has no data in context.
- Value in 2023 context (test T7): `0.1043`

```dax
CALCULATE ( [Non-Medical Share], FactCounty[state_ssa] = "03" )
```

#### National Non-Medical Share

Non-Medical Share for all counties, ignoring any county or state filter.

- Format: `0.00%`
- BLANK behavior: Ignores county and state filters. BLANK when there is no data in the year context.
- Value in 2023 context (test T7): `0.0922`

```dax
CALCULATE ( [Non-Medical Share], REMOVEFILTERS ( DimCounty ), REMOVEFILTERS ( FactCounty[state_ssa] ) )
```

#### AZ Minus National (pp)

Arizona Non-Medical Share minus national, in percentage points. Same unit on both sides.

- Format: `+0.00;-0.00;0.00`
- BLANK behavior: BLANK if either side is BLANK.
- Value in 2023 context (test T7): `1.2029`

```dax
VAR _az = [AZ Non-Medical Share]
VAR _nat = [National Non-Medical Share]
RETURN IF ( ISBLANK ( _az ) || ISBLANK ( _nat ), BLANK (), ( _az - _nat ) * 100 )
```

#### AZ Payment Growth %

Enrollment-weighted payment growth for Arizona counties.

- Format: `0.00"%"`
- BLANK behavior: BLANK for 2018 and when Arizona has no data.
- Value in 2023 context (test T7): `5.9646`

```dax
CALCULATE ( [Payment Growth %], FactCounty[state_ssa] = "03" )
```

### Contracts

#### Contracts MLR Over 100%

Contract-years whose Adjusted MLR is above 100%. A blank MLR is never counted.

- Format: `#,0`
- BLANK behavior: A BLANK MLR is never counted. BLANK (not 0) when no rows are in context.
- Value in 2023 context (test T7): `87`

```dax
COUNTROWS ( FILTER ( FactMLR, NOT ISBLANK ( FactMLR[adjusted_mlr] ) && FactMLR[adjusted_mlr] > 1 ) )
```

#### Contracts Under 85% MLR

Contract-years whose Adjusted MLR is below 85%, the level that triggers a remittance. A blank MLR is never counted (BLANK is less than 0.85 in DAX).

- Format: `#,0`
- BLANK behavior: A BLANK MLR is never counted. This guards the trap: in DAX, BLANK < 0.85 is TRUE. BLANK (not 0) when no rows are in context.
- Value in 2023 context (test T7): `22`

```dax
COUNTROWS ( FILTER ( FactMLR, NOT ISBLANK ( FactMLR[adjusted_mlr] ) && FactMLR[adjusted_mlr] < 0.85 ) )
```

#### Avg Contract Payment Growth %

Simple average over contracts of each contract's enrollment-weighted county payment growth. Contracts need 1,000+ members, a prior-year MLR and a growth value.

- Format: `0.00"%"`
- BLANK behavior: AVERAGE ignores BLANK values.
- Value in 2023 context (test T7): `5.347`

```dax
AVERAGE ( FactContract[payment_growth_pct] )
```

#### Avg Contract Non-Med Change (pp)

Simple average over contracts of the year-over-year change in non-medical share, in percentage points.

- Format: `+0.00;-0.00;0.00`
- BLANK behavior: AVERAGE ignores BLANK values.
- Value in 2023 context (test T7): `-0.5532`

```dax
AVERAGE ( FactContract[nonmed_change_pp] )
```
