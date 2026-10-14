"""
04_validate_latest.py - recount the newest raw CMS files and compare them to the staged CSVs from 03_pull_cms_latest.py.
Plain line counts and raw sums, so a parsing mistake in the loader shows up as a mismatch.
Exit code 1 if any check fails.
"""
import csv
import glob
import os
import sys

import pandas as pd

ROOT = r"C:\Users\Public\rate_gap"
RAW = os.path.join(ROOT, "raw")
STAGE = os.path.join(ROOT, "stage_v2")
results = []


def check(name, source, staged):
    results.append((name, source, staged))


rate = pd.read_csv(os.path.join(STAGE, "county_rate_ext.csv"), dtype={"ssa_code": str})
for year in (2024, 2025, 2026, 2027):
    path = [p for p in glob.glob(os.path.join(RAW, f"{year}-ma-rate-book", "**", "*.csv"), recursive=True)
            if os.path.basename(p).lower() == f"countyrate{year}.csv"][0]
    rows, total = 0, 0.0
    with open(path, newline="", encoding="latin-1") as f:
        for r in csv.reader(f):
            if len(r) >= 7 and r[0].strip().isdigit():
                rows += 1
                total += float(r[5].replace(",", ""))
    s = rate[rate.year == year]
    check(f"county_rate {year} rows", rows, len(s))
    check(f"county_rate {year} sum of 0% rate", round(total, 2), round(s.rate_0.sum(), 2))

enr = pd.read_csv(os.path.join(STAGE, "enrollment_ext.csv"))
meta = pd.read_csv(os.path.join(STAGE, "enrollment_ext_meta.csv")).set_index("year")
for year, folder in ((2024, "monthly-enrollment-cpsc-december-2024"), (2025, "monthly-enrollment-cpsc-december-2025"),
                     (2026, "monthly-enrollment-cpsc-september-2026")):
    path = glob.glob(os.path.join(RAW, folder, "**", "CPSC_Enrollment_Info_*.csv"), recursive=True)[0]
    rows, suppressed, total = 0, 0, 0
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        next(reader)
        for r in reader:
            rows += 1
            if r[6].strip() == "*":
                suppressed += 1
            else:
                total += int(r[6])
    check(f"enrollment {year} raw rows", rows, int(meta.loc[year, "rows_total"]))
    check(f"enrollment {year} suppressed rows", suppressed, int(meta.loc[year, "rows_suppressed"]))
    check(f"enrollment {year} enrollment sum", total, int(enr[enr.year == year].enrollment.sum()))

failed = 0
for name, src, stg in results:
    ok = src == stg
    failed += 0 if ok else 1
    print(f"{'PASS' if ok else 'FAIL'}  {name:38s} source={src}  staged={stg}")
print(f"\n{len(results) - failed} PASS / {failed} FAIL of {len(results)} checks")
print("OVERALL:", "PASS" if failed == 0 else "FAIL")
sys.exit(1 if failed else 0)
