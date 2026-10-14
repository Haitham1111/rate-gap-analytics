"""
02_validate.py - recount the raw CMS files and compare them to the staged CSVs.

The raw files are counted a different way than 01_pull_cms.py stages them
(plain line counts and a raw sum), so a parsing mistake shows up as a mismatch.
Also writes source_counts.csv, which SQL query 08 loads and compares to the database.

Run after 01_pull_cms.py:  python 02_validate.py
Exit code 1 if any check fails.
"""
import csv
import glob
import os
import sys

import pandas as pd

ROOT = r"C:\Users\Public\rate_gap"
RAW = os.path.join(ROOT, "raw")
STAGE = os.path.join(ROOT, "stage")

results = []  # (check name, source value, staged value)
source_counts = []  # written to source_counts.csv for SQL query 08


def check(name, source, staged):
    results.append((name, source, staged))


def to_num(text):
    return float(str(text).replace(",", ""))


# 1. County rate: rows and sum of the 0% bonus rate, per year
rate = pd.read_csv(os.path.join(STAGE, "county_rate.csv"), dtype={"ssa_code": str})
for year in range(2018, 2024):
    path = glob.glob(os.path.join(RAW, f"ratebook{year}", "CSV", f"CountyRate{year}.csv"))[0]
    rows, total = 0, 0.0
    with open(path, newline="", encoding="latin-1") as f:
        for r in csv.reader(f):
            # A data row starts with a numeric SSA code and has a rate in column 6.
            if len(r) >= 7 and r[0].strip().isdigit():
                rows += 1
                total += to_num(r[5])
    s = rate[rate.year == year]
    check(f"county_rate {year} rows", rows, len(s))
    check(f"county_rate {year} sum of 0% rate", round(total, 2), round(s.rate_0.sum(), 2))
    source_counts.append({"source": "county_rate", "year": year, "row_count": rows, "value_sum": round(total, 2)})

# 2. MLR: rows and sum of Adjusted MLR, per year
mlr = pd.read_csv(os.path.join(STAGE, "mlr.csv"))
for year in range(2018, 2024):
    df = pd.read_excel(glob.glob(os.path.join(RAW, f"mlr_cy{year}", "*.xlsx"))[0])
    col = "Adjusted MLR" if "Adjusted MLR" in df.columns else "4.3 Adjusted MLR"
    s = mlr[mlr.year == year]
    source_sum = round(df[col].astype(float).sum(), 4)
    check(f"mlr {year} rows", len(df), len(s))
    check(f"mlr {year} sum of adjusted MLR", source_sum, round(s.adjusted_mlr.sum(), 4))
    source_counts.append({"source": "mlr", "year": year, "row_count": len(df), "value_sum": source_sum})

# 3. Enrollment: raw rows, suppressed rows and enrollment sum, per year
enr = pd.read_csv(os.path.join(STAGE, "enrollment_cc.csv"))
meta = pd.read_csv(os.path.join(STAGE, "enrollment_meta.csv")).set_index("year")
for year in range(2018, 2024):
    path = glob.glob(os.path.join(RAW, f"enroll{year}", "**", f"CPSC_Enrollment_Info_{year}_12.csv"), recursive=True)[0]
    rows, suppressed, total = 0, 0, 0
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        next(reader)  # header
        for r in reader:
            rows += 1
            if r[6].strip() == "*":
                suppressed += 1
            else:
                total += int(r[6])
    check(f"enrollment {year} raw rows", rows, int(meta.loc[year, "rows_total"]))
    check(f"enrollment {year} suppressed rows", suppressed, int(meta.loc[year, "rows_suppressed"]))
    check(f"enrollment {year} enrollment sum", total, int(enr[enr.year == year].enrollment.sum()))
    source_counts.append({"source": "enrollment", "year": year, "row_count": rows, "value_sum": total})

pd.DataFrame(source_counts).to_csv(os.path.join(STAGE, "source_counts.csv"), index=False)

# Report
failed = 0
for name, src, stg in results:
    ok = src == stg
    failed += 0 if ok else 1
    print(f"{'PASS' if ok else 'FAIL'}  {name:40s} source={src}  staged={stg}")
print(f"\n{len(results) - failed} PASS / {failed} FAIL of {len(results)} checks")
print("OVERALL:", "PASS" if failed == 0 else "FAIL")
sys.exit(1 if failed else 0)
