"""
03_pull_cms_latest.py - extend the v1 data with the newest CMS releases (added beside v1, nothing replaced).

Pulled on the day it runs; the register of what CMS had published is in reports/master-findings.md and
reports/methodology-and-limits.md.

  1. MA ratebooks 2024, 2025, 2026, 2027   -> county monthly rate (CountyRate<year>.csv)
  2. Monthly Enrollment by CPSC            -> December 2024, December 2025 and the newest month (September 2026)
  3. Contract info from the newest month   -> contract -> parent organization (parent organizations only, no providers)

Output (C:\\Users\\Public\\rate_gap\\stage_v2\\):
  county_rate_ext.csv   year, ssa_code, state_ssa, state_raw, county_name, rate_5, rate_35, rate_0, rate_esrd
  enrollment_ext.csv    year, period, contract_id, ssa_code, enrollment   (suppressed '*' rows dropped)
  enrollment_ext_meta.csv  year, period, rows_total, rows_suppressed, enrollment_sum
  contract_parent.csv   period, contract_id, parent_org, org_type   (Dec 2023, Dec 2024, Dec 2025, Sep 2026)
  source_counts_ext.csv source, year, row_count, value_sum   (recounted from the raw files)

Run:  python 03_pull_cms_latest.py
"""
import csv
import glob
import os
import urllib.request
import zipfile

import pandas as pd

ROOT = r"C:\Users\Public\rate_gap"
RAW = os.path.join(ROOT, "raw")
STAGE = os.path.join(ROOT, "stage_v2")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124 Safari/537.36"}
CMS = "https://www.cms.gov/files/zip/"

# (year, zip name). File names read from the CMS year pages.
RATEBOOKS = [(2024, "2024-ma-rate-book.zip"), (2025, "2025-ma-rate-book.zip"),
             (2026, "2026-ma-rate-book.zip"), (2027, "2027-ma-rate-book.zip")]
# (year, period label, zip name). The newest month CMS had published was 2026-09.
ENROLLMENT = [(2024, "2024-12", "monthly-enrollment-cpsc-december-2024.zip"),
              (2025, "2025-12", "monthly-enrollment-cpsc-december-2025.zip"),
              (2026, "2026-09", "monthly-enrollment-cpsc-september-2026.zip")]


def fetch(name):
    """Download a zip once and extract it next to itself. Returns the extracted folder."""
    os.makedirs(RAW, exist_ok=True)
    path = os.path.join(RAW, name)
    if not os.path.exists(path):
        print("downloading", name)
        with urllib.request.urlopen(urllib.request.Request(CMS + name, headers=UA)) as r, open(path, "wb") as f:
            f.write(r.read())
    folder = path[:-4]
    if not os.path.isdir(folder):
        with zipfile.ZipFile(path) as z:
            z.extractall(folder)
    return folder


def to_number(text):
    try:
        return float(str(text).replace(",", "").strip())
    except ValueError:
        return None


def stage_rates():
    rows, counts = [], []
    for year, name in RATEBOOKS:
        folder = fetch(name)
        path = [p for p in glob.glob(os.path.join(folder, "**", "*.csv"), recursive=True)
                if os.path.basename(p).lower() == f"countyrate{year}.csv"][0]
        with open(path, newline="", encoding="latin-1") as f:
            data = list(csv.reader(f))
        start = next(i for i, r in enumerate(data) if r and r[0].strip() == "Code")
        n, total = 0, 0.0
        for r in data[start + 1:]:
            if len(r) < 7 or not r[0].strip().isdigit():
                continue
            code = r[0].strip().zfill(5)
            rows.append({"year": year, "ssa_code": code, "state_ssa": code[:2], "state_raw": r[1].strip(),
                         "county_name": r[2].strip(), "rate_5": to_number(r[3]), "rate_35": to_number(r[4]),
                         "rate_0": to_number(r[5]), "rate_esrd": to_number(r[6])})
            n += 1
            total += to_number(r[5])
        counts.append({"source": "county_rate", "year": year, "row_count": n, "value_sum": round(total, 2)})
    return pd.DataFrame(rows), counts


def contract_info(folder, period):
    """Contract -> parent organization and organization type for one month (parent organizations only)."""
    info = glob.glob(os.path.join(folder, "**", "CPSC_Contract_Info_*.csv"), recursive=True)[0]
    ci = pd.read_csv(info, dtype=str, encoding="latin-1")
    ci = ci.rename(columns={"Contract ID": "contract_id", "Parent Organization": "parent_org",
                            "Organization Type": "org_type"})
    ci = ci.dropna(subset=["contract_id"]).drop_duplicates("contract_id")[["contract_id", "parent_org", "org_type"]]
    ci.insert(0, "period", period)
    return ci


def stage_enrollment():
    frames, meta, counts, parents = [], [], [], []
    for year, period, name in ENROLLMENT:
        folder = fetch(name)
        enr = glob.glob(os.path.join(folder, "**", "CPSC_Enrollment_Info_*.csv"), recursive=True)[0]
        df = pd.read_csv(enr, dtype=str, usecols=["Contract Number", "Plan ID", "SSA State County Code", "Enrollment"])
        suppressed = int((df["Enrollment"].str.strip() == "*").sum())
        df["enrollment"] = pd.to_numeric(df["Enrollment"], errors="coerce")
        df = df.dropna(subset=["enrollment"])
        df["enrollment"] = df["enrollment"].astype(int)
        meta.append({"year": year, "period": period, "rows_total": suppressed + len(df),
                     "rows_suppressed": suppressed, "enrollment_sum": int(df["enrollment"].sum())})
        counts.append({"source": "enrollment", "year": year, "row_count": suppressed + len(df),
                       "value_sum": int(df["enrollment"].sum())})
        g = (df.groupby(["Contract Number", "SSA State County Code"], as_index=False)["enrollment"].sum()
               .rename(columns={"Contract Number": "contract_id", "SSA State County Code": "ssa_code"}))
        g["ssa_code"] = g["ssa_code"].str.zfill(5)
        g.insert(0, "period", period)
        g.insert(0, "year", year)
        frames.append(g)
        parents.append(contract_info(folder, period))
    v1 = os.path.join(RAW, "enroll2023")   # December 2023 was downloaded by 01_pull_cms.py
    if os.path.isdir(v1):
        parents.append(contract_info(v1, "2023-12"))
    return pd.concat(frames, ignore_index=True), pd.DataFrame(meta), counts, pd.concat(parents)


def main():
    os.makedirs(STAGE, exist_ok=True)
    rate, c1 = stage_rates()
    enr, meta, c2, parent = stage_enrollment()
    rate.to_csv(os.path.join(STAGE, "county_rate_ext.csv"), index=False)
    enr.to_csv(os.path.join(STAGE, "enrollment_ext.csv"), index=False)
    meta.to_csv(os.path.join(STAGE, "enrollment_ext_meta.csv"), index=False)
    parent.to_csv(os.path.join(STAGE, "contract_parent.csv"), index=False)
    pd.DataFrame(c1 + c2).to_csv(os.path.join(STAGE, "source_counts_ext.csv"), index=False)
    print("county_rate_ext rows:", len(rate))
    print("enrollment_ext rows:", len(enr))
    print("contract_parent rows:", len(parent))
    print(meta.to_string(index=False))


if __name__ == "__main__":
    main()
