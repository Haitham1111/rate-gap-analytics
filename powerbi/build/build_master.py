"""Build the three pages of rate-gap-master-40-state.pbix (PBIR format) on top of the master model.
Reuses the helper functions in build_report.py (v1), so v1 and master look the same.
Page 1: 11x17 landscape summary (1632 x 1056 px). Pages 2 and 3: 16:9.
Usage: python -I build_master.py <master_model.pbix> <out.pbix> <theme.json>
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, 'build_report.py'), encoding='utf-8').read()
_THEME = '# ================= THEME ================='
_DROP = '# drop the blank starter page(s)'
_YR = 'YR = lambda y:'
_REPACK = '# ================= REPACK ================='
# 1) helpers and the zip loader, 2) theme + page_json, 3) repack. Page content below is new.
exec(compile(_src.split(_THEME)[0], 'build_report_helpers', 'exec'))
exec(compile(_THEME + _src.split(_THEME)[1].split(_DROP)[0], 'build_report_theme', 'exec'))

def series_color(ent, prop, val, col):
    """Fill colour for one value of a series column (used by the outlook line chart)."""
    return {'properties': {'fill': color(col)}, 'selector': {'data': [{'scopeId': {'Comparison': {
        'ComparisonKind': 0, 'Left': column(ent, prop), 'Right': lit(val)['expr']}}}]}}


PM1, PM2, PM3 = 'a7c1e5b93d204f68a1b7', 'b8d2f6c04e315a79b2c8', 'c9e3a7d15f426b8ac3d9'
# drop starter pages, register the three master pages
for k in [k for k in files if k.startswith('Report/definition/pages/') and k != 'Report/definition/pages/pages.json']:
    files.pop(k); order.remove(k)
for p, n, w, h in ((PM1, 'Master summary 11x17', 1632, 1056), (PM2, 'State scorecard', 1920, 1080), (PM3, 'Outlook 2027', 1920, 1080)):
    add_part(f'Report/definition/pages/{p}/page.json', json.dumps(page_json(p, n, w, h)).encode('utf-8'))
pages = json.loads(files['Report/definition/pages/pages.json'])
pages['pageOrder'] = [PM1, PM2, PM3]; pages['activePageName'] = PM1
files['Report/definition/pages/pages.json'] = json.dumps(pages).encode('utf-8')

# ================= PAGE 1: ONE-PAGE SUMMARY (1632 x 1056) =================
save(PM1, textbox('mastheadline0001', (40, 14, 1552, 190, 100), [
    {'textRuns': [run('THE RATE GAP  |  MASTER SUMMARY  |  50 STATES + DC  |  MEDICARE ADVANTAGE', 13, bold=True, col=AMBER)]},
    {'textRuns': [run('No state leads on every measure. The announced 2027 county benchmark change runs from 3.21% in Indiana to 9.36% in Alaska.', 28, bold=True)]},
    {'textRuns': [run('Enrollment-weighted county rate change, ratebook 2027 vs 2026: 5.26% nationally. CMS states an expected average payment change of +2.48% (+4.98% with risk score trend) in its April 6, 2026 rate announcement. Rankings are by each column separately; this is not a recommendation and no licensing filter is applied.', 13, col=MUTED)]},
]))


def master_card(name, x, big, big_col, small):
    save(PM1, textbox(name, (x, 206, 500, 138, 150), [
        {'textRuns': [run(big, 34, bold=True, col=big_col)]},
        {'textRuns': [run(small, 13, col='#CBD5E1')]}], card=True))


master_card('mastercard000001', 40, '5.26%', SKY, 'National 2027 county benchmark change. 26 of 51 areas are above it.')
master_card('mastercard000002', 566, '0 of 51', AMBER, 'States in the top 10 on all three market columns. California, Florida, New York and Utah reach two.')
master_card('mastercard000003', 1092, '58.7%', TEAL, 'of MA members are with 3 parent organizations: UnitedHealth 26.5%, Humana 20.4%, CVS 11.8%.')


def rank_bar(name, rect, title, meas, disp, col, n, fname):
    proj = {'Category': {'projections': [cproj('DimState', 'state_name', 'State')]},
            'Y': {'projections': [mproj(meas, disp)]}}
    obj = {'dataPoint': [{'properties': {'fill': color(col)}}], **labels(11), **axes(11, vmin=0, val_font=11), **legend(False)}
    obj['categoryAxis'][0]['properties']['maxMarginFactor'] = lit(40)
    obj['categoryAxis'][0]['properties']['innerPadding'] = lit(6)
    obj['valueAxis'][0]['properties']['show'] = lit(False)
    return vis(name, 'clusteredBarChart', rect, title, proj, obj, sort=(measure(meas), 'Descending'),
               filters=[topn('DimState', 'state_name', meas, n, fname)], tsize=16)


save(PM1, rank_bar('masterbarchg00001', (40, 352, 760, 614, 300), 'Announced 2027 county benchmark change (%), top 15 states',
                   'State Announced 2027 Change %', '2027 change (%)', SKY, 15, 'topchgfilter00001'))
save(PM1, rank_bar('masterbarsize0001', (826, 352, 766, 614, 300), 'Largest Medicare Advantage markets, members in September 2026, top 10 states',
                   'State MA Members', 'MA members', AMBER, 10, 'topsizefilter0001'))
save(PM1, textbox('masterfooter00001', (40, 976, 1552, 68, 100), [
    {'textRuns': [run('Sources (CMS, pulled 2026-10-13): MA ratebooks 2023-2027 (county rate, 0% bonus column); Monthly Enrollment by Contract/Plan/State/County, December 2023-2025 and September 2026; MLR public use file, contract year 2023 (CY2024 not published). '
                        'MA plan types only (Local/Regional CCP, PFFS, MSA); PACE, cost and stand-alone Part D excluded. 3-year growth = 2026 vs 2023 rate. A ranking or projection is not proof of wrongdoing. Licensed-state list not supplied: all 50 states + DC shown.', 10, col=MUTED)]},
    {'textRuns': [run('Haitham Saleh  |  github.com/Haitham1111/rate-gap-analytics', 10, bold=True, col='#CBD5E1')]}]))

# ================= PAGE 2: STATE SCORECARD =================
page_title(PM2, 'State scorecard: 50 states + DC, newest data for each source',
           'MA members, counties and contracts: September 2026. Payment growth: county rate, weighted by members. Non-medical share: contract year 2023 (newest MLR file). Ranks: 1 = largest. Columns are not combined into one score.')
sl = base('stateslicer0000001', 'slicer', (40, 124, 560, 74, 150),
          query={'queryState': {'Values': {'projections': [cproj('DimState', 'state_name')]}}},
          objects={'data': [{'properties': {'mode': lit('Dropdown')}}],
                   'header': [{'properties': {'show': lit(True), 'fontColor': color(MUTED), 'text': lit('State')}}],
                   'items': [{'properties': {'fontColor': color(TEXT), 'background': color(SURFACE), 'textSize': lit(11)}}]})
save(PM2, container(sl, show_title=False))
lic = base('licslicer00000001', 'slicer', (620, 124, 420, 74, 150),
           query={'queryState': {'Values': {'projections': [cproj('DimState', 'licensed_text')]}}},
           objects={'data': [{'properties': {'mode': lit('Dropdown')}}],
                    'header': [{'properties': {'show': lit(True), 'fontColor': color(MUTED), 'text': lit('Licensed (not set yet)')}}],
                    'items': [{'properties': {'fontColor': color(TEXT), 'background': color(SURFACE), 'textSize': lit(11)}}]})
save(PM2, container(lic, show_title=False))
save(PM2, textbox('rankmethod0000001', (1060, 124, 820, 74, 150), [
    {'textRuns': [run('Ranking method: ', 11, bold=True, col=AMBER),
                  run('each rank column orders the 51 areas on that column alone. Top-10 count = how many of enrollment, 3-year payment growth and 2027 announced change put a state in the top 10. If no state has 3, no state clearly leads.', 11, col='#CBD5E1')]}], card=True))

sc_cols = [('state_name', 'State', None), ('ma_members', 'Members', None), ('counties', 'Counties', None), ('contracts', 'Contracts', None),
           ('enroll_growth_3yr_pct', 'Member growth 3y %', None), ('pay_growth_2026_pct', 'Pay growth 2026 %', None),
           ('pay_3yr_pct', 'Pay growth 3y %', None), ('chg_2027_pct', '2027 announced %', None),
           ('nonmed_share_cy2023_pct', 'Non-med CY2023 %', None), ('nonmed_chg_3yr_pp', 'Non-med chg 3y pp', None),
           ('rank_enrollment', 'Rk members', None), ('rank_pay_3yr', 'Rk pay 3y', None), ('rank_chg_2027', 'Rk 2027', None),
           ('rank_nonmed_share', 'Rk non-med', None), ('top10_count', 'Top-10', None)]
tb2 = {'Values': {'projections': [cproj('FactScorecard', c, d, active=False) for c, d, _ in sc_cols] + [cproj('DimState', 'licensed_text', 'Licensed', active=False)]}}
tb2_obj = {'columnHeaders': [{'properties': {'fontColor': color(MUTED), 'backColor': color(PAGE_BG), 'fontSize': lit(10)}}],
           'values': [{'properties': {'fontColor': color(TEXT), 'fontSize': lit(10)}}]}
save(PM2, vis('scorecardtable0001', 'tableEx', (40, 214, 1840, 826, 300), 'Scorecard (sorted by members; scroll for all 51 areas)', tb2, tb2_obj,
              sort=(column('FactScorecard', 'ma_members'), 'Descending')))

# ================= PAGE 3: OUTLOOK 2027 =================
page_title(PM3, 'Outlook 2027: actual trend beside the projection',
           'Actual = published county rates 2024-2026. Announced = ratebook 2027 vs 2026 (published). Trend projection = mean of the 2024-2026 growth rates carried forward: a projection, not published data and not a forecast of any plan.')
sl3 = base('stateslicer0000003', 'slicer', (40, 124, 560, 74, 150),
           query={'queryState': {'Values': {'projections': [cproj('DimState', 'state_name')]}}},
           objects={'data': [{'properties': {'mode': lit('Dropdown')}}],
                    'header': [{'properties': {'show': lit(True), 'fontColor': color(MUTED), 'text': lit('State (blank = all states, member-weighted)')}}],
                    'items': [{'properties': {'fontColor': color(TEXT), 'background': color(SURFACE), 'textSize': lit(11)}}]})
save(PM3, container(sl3, show_title=False))
save(PM3, kpi('kpiann2027000001', 'State Announced 2027 Change %', 'Announced 2027 change, selection', 620, col=SKY, w=320))
ol_proj = {'Category': {'projections': [cproj('FactOutlookLong', 'year', 'Year')]},
           'Series': {'projections': [cproj('FactOutlookLong', 'series', 'Series')]},
           'Y': {'projections': [mproj('Outlook Value %', 'Payment growth (%)')]}}
ol_obj = {'dataPoint': [series_color('FactOutlookLong', 'series', 'Actual', AMBER), series_color('FactOutlookLong', 'series', 'Announced benchmark change', SKY),
                        series_color('FactOutlookLong', 'series', 'Trend projection', GREEN)],
          'lineStyles': [{'properties': {'strokeWidth': lit(3), 'showMarker': lit(True)}}],
          **labels(12), **axes(12, vmin=0), **legend(True, 'Top', 12)}
ol_obj['categoryAxis'][0]['properties']['axisType'] = lit('Categorical')
save(PM3, vis('outlookline000001', 'lineChart', (40, 304, 900, 470, 300),
              'Payment growth (%): actual 2024-2026, announced 2027, and the trend projection for 2027',
              ol_proj, ol_obj, sort=(column('FactOutlookLong', 'year'), 'Ascending')))
save(PM3, textbox('projmethod0000001', (40, 794, 900, 246, 150), [
    {'textRuns': [run('Projection method', 16, bold=True, col=AMBER)]},
    {'textRuns': [run('Trend projection (payment): the mean of the three annual growth rates 2024, 2025 and 2026, carried forward as the 2027 value. It is shown only to compare with the announced figure.', 12, col='#CBD5E1')]},
    {'textRuns': [run('Non-medical share (table, right): projection = mean of contract years 2021-2023, range = lowest to highest of those years. MLR for 2024 onward is not published, and payment growth is not used because v1 found no county-level link (r = 0.02).', 12, col='#CBD5E1')]},
    {'textRuns': [run('Announced 2027 change is the county rate file, not the CMS expected average payment change (+2.48%; +4.98% with risk score trend). A projection is not proof of anything about any plan.', 12, col=MUTED)]}], card=True))
ol_cols = [('state_name', 'State'), ('actual_2024_pct', '2024 %'), ('actual_2025_pct', '2025 %'), ('actual_2026_pct', '2026 %'),
           ('announced_2027_pct', '2027 announced %'), ('projection_trend_2027_pct', '2027 trend proj. %'),
           ('announced_minus_trend_pct_points', 'Ann. minus trend pts'), ('nonmed_cy2023_pct', 'Non-med CY23 %'),
           ('nonmed_projection_mean_pct', 'Non-med proj. mean %'), ('nonmed_projection_low_pct', 'low'), ('nonmed_projection_high_pct', 'high')]
tb3 = {'Values': {'projections': [cproj('FactOutlook', c, d, active=False) for c, d in ol_cols]}}
save(PM3, vis('outlooktable00001', 'tableEx', (960, 124, 920, 916, 300), 'Outlook by state (sorted by announced 2027 change)', tb3, tb2_obj,
              sort=(column('FactOutlook', 'announced_2027_pct'), 'Descending')))

exec(compile(_REPACK + _src.split(_REPACK)[1], 'build_report_repack', 'exec'))
