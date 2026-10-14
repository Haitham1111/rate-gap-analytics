"""Generate reports/dax-measures.md from powerbi/build/measures.txt and the recorded BLANK-test output.
Run from anywhere:  python make_dax_doc.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))

defs, cur = [], None
for line in open(os.path.join(HERE, 'measures.txt'), encoding='utf-8').read().splitlines():
    if line.startswith('### '):
        p = line[4:].split('|')
        cur = {'name': p[0].strip(), 'fmt': p[1].strip(), 'folder': p[2].strip(), 'desc': p[3].strip(), 'dax': []}
        defs.append(cur)
    elif cur:
        cur['dax'].append(line)

out = open(os.path.join(ROOT, 'reports', 'dax-blank-tests-output.txt'), encoding='utf-8').read()
t7 = out.split('### T7')[1].split('### T8')[0]
val = {m.group(1).strip(): m.group(2).strip() for m in re.finditer(r'^\s{2}(.+?) = (.+)$', t7, re.M)}

blank = {
    'Members': 'SUM of enrollment. BLANK when the filter leaves no rows (a year or county with no data).',
    'Contracts Published': 'DISTINCTCOUNT of MA contracts with a published MLR. BLANK when none are in context.',
    'Payment Growth %': 'BLANK for 2018 (no prior-year rate) and for any context with no weighted base. Counties with no prior-year rate are excluded from both numerator and denominator, so a missing rate is never read as 0%.',
    'Payment Index (2018=100)': '100 in the base year. BLANK outside DimYear, and BLANK if any year in the chain has no growth value, so a gap is never compounded as 0%.',
    'Weighted MLR': 'BLANK when there are no members in context.',
    'Non-Medical Share': 'BLANK when there are no members in context. Negative when MLR is above 100%.',
    'Non-Medical Change (pp)': 'BLANK for 2018 and whenever either year is missing. It never returns the share itself (x - BLANK = x is the trap). Pinned to the latest year in context, so several years selected return the change for that latest year.',
    'County In Scope': 'BLANK when members are BLANK or under 5,000 in 2018 or 2023. A blank member count is treated as out of scope, not as small.',
    'Counties In Scope': 'Sum of County In Scope over counties.',
    'County Payment Growth 2018-23 %': 'BLANK outside scope or when either rate is BLANK. Ignores the year filter by design (fixed 2018 to 2023 window). Meant for one county at a time; at a total it is the ratio of summed county rates, not an average.',
    'County Non-Med Change 2018-23 (pp)': 'BLANK outside scope or when either year is BLANK. Ignores the year filter by design.',
    'Non-Med Share 2023 (5k+ Counties)': 'BLANK outside scope, so small counties cannot enter a ranking. The Top N visuals also filter this measure to is-not-blank.',
    'AZ Non-Medical Share': 'BLANK when Arizona has no data in context.',
    'National Non-Medical Share': 'Ignores county and state filters. BLANK when there is no data in the year context.',
    'AZ Minus National (pp)': 'BLANK if either side is BLANK.',
    'AZ Payment Growth %': 'BLANK for 2018 and when Arizona has no data.',
    'Contracts MLR Over 100%': 'A BLANK MLR is never counted. BLANK (not 0) when no rows are in context.',
    'Contracts Under 85% MLR': 'A BLANK MLR is never counted. This guards the trap: in DAX, BLANK < 0.85 is TRUE. BLANK (not 0) when no rows are in context.',
    'Avg Contract Payment Growth %': 'AVERAGE ignores BLANK values.',
    'Avg Contract Non-Med Change (pp)': 'AVERAGE ignores BLANK values.',
}
assert set(blank) == set(d['name'] for d in defs), set(blank) ^ set(d['name'] for d in defs)

md = [
    '# DAX measures', '',
    '20 measures in the `_Measures` table of `powerbi/rate-gap-dashboard.pbix`. Definitions live in [`powerbi/build/measures.txt`](../powerbi/build/measures.txt) and are loaded into the model by `build_model.ps1`.', '',
    'Scope: Medicare Advantage contracts only (contract prefix H, R, E). Stand-alone Part D contracts are excluded in SQL before the data reaches Power BI.', '',
    '## Model', '',
    '| Table | Source | Rows |', '|---|---|---|',
    '| `FactCounty` | `dbo.v_county_trend`: one row per county per year with weighted MLR, non-medical share and payment growth | 18,618 |',
    '| `DimCounty` | `dbo.dim_county` plus a `county_label` column | 3,246 |',
    '| `FactMLR` | `dbo.v_contract_mlr`: every published MA contract-year MLR | 2,932 |',
    '| `FactContract` | `dbo.v_contract_quartile`: MA contracts with 1,000+ matched members, NTILE(4) by year | 2,097 |',
    '| `DimYear` | calculated, 2018 to 2023 | 6 |', '',
    'Relationships (many to one, single direction): `FactCounty[year]`, `FactMLR[year]`, `FactContract[year]` to `DimYear[yr]`; `FactCounty[ssa_code]` to `DimCounty[ssa_code]`.', '',
    '## Units', '',
    '- **Payment growth** is a percent (5.87 means 5.87%) and is formatted with a literal `%`.',
    '- **Non-medical share** is a ratio (0.0922) formatted as a percent.',
    '- **Change in non-medical share** is in percentage points (pp).',
    '- Payment growth (%) and the change in non-medical share (pp) are shown side by side. No measure subtracts one from the other.', '',
    '## How the BLANK() traps were tested', '',
    'In DAX, `BLANK() < 3` is TRUE, and `x - BLANK()` returns `x`. Every comparison in these measures first checks `NOT ISBLANK(...)`, and every difference returns BLANK when either side is BLANK.', '',
    '`powerbi/build/blanktests.ps1` evaluates each measure under edge-case contexts against the open model. Raw output: [`dax-blank-tests-output.txt`](dax-blank-tests-output.txt).', '',
    '| Test | Context | Result |', '|---|---|---|',
    '| T1 | First year, 2018 | Change and growth measures BLANK; index 100; share 9.16% |',
    '| T2 | A year with no data (2016) | All yearly measures BLANK, none 0 |',
    '| T3 | Kimble, TX (300 members in 2023) | Scope measures BLANK; share still computed |',
    '| T4 | Kandiyohi, MN (4,857 members in 2023, just under 5,000) | Scope measures BLANK |',
    '| T5 | Aleutians East, AK (no MA enrollment) | Every measure BLANK |',
    '| T5c | Petroleum, MT (47 member-years in total) | Never in scope; change BLANK |',
    '| T6 | Arizona, 2019 | AZ and national measures return values |',
    '| T7 | 2023, all 20 measures | Values below; match SQL |',
    '| T8 | Two years selected (2021, 2022) | Change and index use the latest year |',
    '| T9 | Maricopa, AZ, 2023 | County measures return values |', '',
    '**Defect found and fixed during testing:** `Non-Medical Change (pp)` first compared the share in the current context (a blend of all selected years) with the prior year. With several years selected the change was wrong. It now takes the latest year in context for both sides.', '',
    '**Scope defect found and fixed during QA:** the first build included stand-alone Part D contracts (prefix S) in the weights. They are 41% to 55% of enrollment-weighted members and are not paid from the MA county rate. Every number, visual and screenshot in this project was regenerated after the fix (see `methodology-and-limits.md`).', '',
    'Source columns that are BLANK by design: `FactCounty[nonmed_change_pp]` 3,169 rows (2018 and counties new to a year), `FactCounty[payment_growth_pct]` 3,033 rows. `FactMLR` and `FactContract` have none.', '',
    '## Measures', '',
]
folders = []
for d in defs:
    if d['folder'] not in folders:
        folders.append(d['folder'])
for f in folders:
    md += ['### ' + f[2:], '']
    for d in [x for x in defs if x['folder'] == f]:
        md += ['#### ' + d['name'], '', d['desc'], '',
               '- Format: `' + d['fmt'] + '`',
               '- BLANK behavior: ' + blank[d['name']],
               '- Value in 2023 context (test T7): `' + val.get(d['name'], '') + '`', '',
               '```dax'] + d['dax'] + ['```', '']
open(os.path.join(ROOT, 'reports', 'dax-measures.md'), 'w', encoding='utf-8').write('\n'.join(md))
print('measures', len(defs), 'lines', len(md))
print(val)
