"""
01_pull_cms.py - download the public CMS files and stage clean CSVs.

Sources (all public, cms.gov):
  1. MA ratebooks 2018-2023   -> county monthly capitation rate (benchmark), Parts A&B
  2. MLR data release files   -> Adjusted MLR by contract, contract years 2018-2023
  3. Monthly Enrollment by CPSC, December 2018-2023 -> contract x county link

Output (C:\\Users\\Public\\rate_gap\\stage\\, so SQL Server BULK INSERT can read it):
  county_rate.csv    year, ssa_code, state_ssa, state_raw, county_name, rate_5, rate_35, rate_0, rate_esrd
  mlr.csv            year, contract_id, org_name, adjusted_mlr, remittance
  enrollment_cc.csv  year, contract_id, ssa_code, enrollment      (suppressed '*' rows dropped)
  enrollment_meta.csv year, rows_total, rows_suppressed, enrollment_sum

Run:  python 01_pull_cms.py
"""
import csv
import glob
import os
import zipfile
import urllib.request

import pandas as pd

ROOT = r"C:\Users\Public\rate_gap"
RAW = os.path.join(ROOT, "raw")
STAGE = os.path.join(ROOT, "stage")
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124 Safari/537.36"}
CMS = "https://www.cms.gov"
OLD = CMS + "/medicare/health-plans/medicareadvtgspecratestats/downloads/"

# name -> url. Exact file names were read from the CMS year pages on 2026-10-13.
FILES = {
    "ratebook2018.zip": OLD + "ratebook2018.zip",
    "ratebook2019.zip": OLD + "ratebook2019.zip",
    "ratebook2020.zip": OLD + "ratebook2020.zip",
    "ratebook2021.zip": CMS + "/files/zip/2021-ma-rate-book.zip",
    "ratebook2022.zip": CMS + "/files/zip/2022-ma-rate-book.zip",
    "ratebook2023.zip": CMS + "/files/zip/2023-ma-rate-book-zip.zip",
    "mlr_cy2018.zip": CMS + "/files/zip/cy-2018-mlr-data-release-file.zip",
    "mlr_cy2019.zip": CMS + "/files/zip/cy-2019-mlr-data-release-file.zip-0",
    "mlr_cy2020.zip": CMS + "/files/zip/cy-2020-mlr-data-release-file.zip-0",
    "mlr_cy2021.zip": CMS + "/files/zip/cy-2021-mlr-data-release-file.zip",
    "mlr_cy2022.zip": CMS + "/files/zip/cy-2022-mlr-data-release-file.zip",
    "mlr_cy2023.zip": CMS + "/files/zip/public-use-file-cy-2023-zip.zip",
}
for y in range(2019, 2024):
    FILES[f"enroll{y}.zip"] = f"{CMS}/files/zip/monthly-enrollment-cpsc-december-{y}.zip"
FILES["enroll2018.zip"] = "https://downloads.cms.gov/files/CPSC_Enrollment_2018_12.zip"  # older URL pattern


def download():
    """Download each zip once and extract it next to itself."""
    os.makedirs(RAW, exist_ok=True)
    for name, url in FILES.items():
        path = os.path.join(RAW, name)
        if not os.path.exists(path):
            print("downloading", name)
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req) as r, open(path, "wb") as f:
                f.write(r.read())
        folder = path[:-4]
        if not os.path.isdir(folder):
            with zipfile.ZipFile(path) as z:
                z.extractall(folder)


def to_number(text):
    """'1,073.16' -> 1073.16. Blank or text -> None."""
    try:
        return float(str(text).replace(",", "").strip())
    except ValueError:
        return None


def stage_county_rate():
    """One row per county per year. The CSV has 3-4 title/note lines before the header."""
    rows = []
    for year in range(2018, 2024):
        path = glob.glob(os.path.join(RAW, f"ratebook{year}", "CSV", f"CountyRate{year}.csv"))[0]
        with open(path, newline="", encoding="latin-1") as f:
            data = list(csv.reader(f))
        start = next(i for i, r in enumerate(data) if r and r[0].strip() == "Code")
        for r in data[start + 1:]:
            if len(r) < 7 or not r[0].strip().isdigit():
                continue
            rows.append({
                "year": year,
                "ssa_code": r[0].strip().zfill(5),
                "state_ssa": r[0].strip().zfill(5)[:2],
                "state_raw": r[1].strip(),  # abbreviation 2018-2020, full name 2021+
                "county_name": r[2].strip(),
                "rate_5": to_number(r[3]),
                "rate_35": to_number(r[4]),
                "rate_0": to_number(r[5]),
                "rate_esrd": to_number(r[6]),
            })
    return pd.DataFrame(rows)


def stage_mlr():
    """One row per contract per year. 2023 renamed the MLR column."""
    frames = []
    for year in range(2018, 2024):
        path = glob.glob(os.path.join(RAW, f"mlr_cy{year}", "*.xlsx"))[0]
        df = pd.read_excel(path)
        mlr_col = "Adjusted MLR" if "Adjusted MLR" in df.columns else "4.3 Adjusted MLR"
        # 2019-2022 call it "Remittance Amount"; 2023 calls it "5.5 Remittance amount due to CMS ..."
        remit_col = next((c for c in df.columns if "remittance amount" in str(c).lower()), None)
        out = pd.DataFrame({
            "year": year,
            "contract_id": df["Contract Number"].astype(str).str.strip(),
            "org_name": df["Organization Name"].astype(str).str.strip(),
            "adjusted_mlr": pd.to_numeric(df[mlr_col], errors="coerce"),
            "remittance": pd.to_numeric(df[remit_col], errors="coerce") if remit_col else None,
        })
        frames.append(out)
    return pd.concat(frames, ignore_index=True)


def stage_enrollment():
    """Sum plan-level enrollment to contract x county. '*' means 10 or fewer, so it is dropped."""
    frames, meta = [], []
    for year in range(2018, 2024):
        path = glob.glob(os.path.join(RAW, f"enroll{year}", "**", f"CPSC_Enrollment_Info_{year}_12.csv"), recursive=True)[0]
        df = pd.read_csv(path, dtype=str, usecols=["Contract Number", "Plan ID", "SSA State County Code", "Enrollment"])
        suppressed = int((df["Enrollment"].str.strip() == "*").sum())
        df["enrollment"] = pd.to_numeric(df["Enrollment"], errors="coerce")
        df = df.dropna(subset=["enrollment"])
        df["enrollment"] = df["enrollment"].astype(int)  # whole members, so SQL INT loads cleanly
        meta.append({"year": year, "rows_total": suppressed + len(df),
                     "rows_suppressed": suppressed, "enrollment_sum": int(df["enrollment"].sum())})
        g = (df.groupby(["Contract Number", "SSA State County Code"], as_index=False)["enrollment"].sum()
               .rename(columns={"Contract Number": "contract_id", "SSA State County Code": "ssa_code"}))
        g["ssa_code"] = g["ssa_code"].str.zfill(5)
        g.insert(0, "year", year)
        frames.append(g)
    return pd.concat(frames, ignore_index=True), pd.DataFrame(meta)


def main():
    download()
    os.makedirs(STAGE, exist_ok=True)
    rate = stage_county_rate()
    mlr = stage_mlr()
    enr, meta = stage_enrollment()
    rate.to_csv(os.path.join(STAGE, "county_rate.csv"), index=False)
    mlr.to_csv(os.path.join(STAGE, "mlr.csv"), index=False)
    enr.to_csv(os.path.join(STAGE, "enrollment_cc.csv"), index=False)
    meta.to_csv(os.path.join(STAGE, "enrollment_meta.csv"), index=False)
    print("county_rate rows:", len(rate))
    print("mlr rows:", len(mlr))
    print("enrollment_cc rows:", len(enr))
    print(meta.to_string(index=False))


if __name__ == "__main__":
    main()
