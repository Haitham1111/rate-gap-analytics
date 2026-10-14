"""Build the three report pages of rate-gap-dashboard.pbix (PBIR format).
Page 1 is the 11x17 landscape poster (1632 x 1056 px). Pages 2 and 3 are standard 16:9 pages.
Usage: python -I build_rg.py <source.pbix> <out.pbix> <theme.json>
"""
import json, sys, zipfile

SRC, OUT, THEME = sys.argv[1], sys.argv[2], sys.argv[3]
VIS = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.13.0/schema.json'
PAGE = 'https://developer.microsoft.com/json-schemas/fabric/item/report/definition/page/2.1.0/schema.json'
SURFACE, PAGE_BG, TEXT, MUTED, LINE = '#1E293B', '#0F172A', '#F8FAFC', '#94A3B8', '#334155'
TEAL, SKY, AMBER, ORANGE, RED, GREEN, INDIGO = '#14B8A6', '#38BDF8', '#F59E0B', '#F97316', '#EF4444', '#22C55E', '#818CF8'
P1, P2, P3 = 'd4f1a8c27e5b3096a1c4', 'e5a2b9d38f6c40a7b2d5', 'f6b3c0e49a7d51b8c3e6'

zin = zipfile.ZipFile(SRC)
files = {i.filename: zin.read(i.filename) for i in zin.infolist()}
order = [i.filename for i in zin.infolist()]
ctype = {i.filename: i.compress_type for i in zin.infolist()}


def add_part(p, data):
    if p not in files:
        order.append(p); ctype[p] = zipfile.ZIP_DEFLATED
    files[p] = data


def save(page, v):
    add_part(f'Report/definition/pages/{page}/visuals/{v["name"]}/visual.json', json.dumps(v, ensure_ascii=False).encode('utf-8'))


# ---- expression helpers (same shapes Power BI writes) ----
def lit(v):
    if isinstance(v, bool): s = 'true' if v else 'false'
    elif isinstance(v, (int, float)): s = f'{float(v)}D'
    else: s = "'" + v.replace("'", "''") + "'"
    return {'expr': {'Literal': {'Value': s}}}


def color(c): return {'solid': {'color': lit(c)}}
def measure(name): return {'Measure': {'Expression': {'SourceRef': {'Entity': '_Measures'}}, 'Property': name}}
def column(ent, prop): return {'Column': {'Expression': {'SourceRef': {'Entity': ent}}, 'Property': prop}}


def mproj(name, disp=None):
    p = {'field': measure(name), 'queryRef': f'_Measures.{name}', 'nativeQueryRef': name}
    if disp: p['displayName'] = disp
    return p


def cproj(ent, prop, disp=None, active=True):
    p = {'field': column(ent, prop), 'queryRef': f'{ent}.{prop}', 'nativeQueryRef': prop}
    if disp: p['displayName'] = disp
    if active: p['active'] = True
    return p


def meas_color(name, col): return {'properties': {'fill': color(col)}, 'selector': {'metadata': f'_Measures.{name}'}}


def cat_filter(name, ent, prop, values):
    vals = [[{'Literal': {'Value': (f'{v}L' if isinstance(v, int) else "'" + v + "'")}}] for v in values]
    return {'name': name, 'field': column(ent, prop), 'type': 'Categorical', 'filter': {'Version': 2,
            'From': [{'Name': 'd', 'Entity': ent, 'Type': 0}],
            'Where': [{'Condition': {'In': {'Expressions': [{'Column': {'Expression': {'SourceRef': {'Source': 'd'}}, 'Property': prop}}], 'Values': vals}}}]}}


def topn(ent, col, meas, n, name, direction=2):
    """Top N (direction 2, descending) or bottom N (direction 1, ascending) of a column by a measure."""
    return {'name': name, 'field': column(ent, col), 'type': 'TopN', 'filter': {'Version': 2, 'From': [
        {'Name': 'subquery', 'Expression': {'Subquery': {'Query': {'Version': 2,
            'From': [{'Name': 'f', 'Entity': ent, 'Type': 0}, {'Name': '_', 'Entity': '_Measures', 'Type': 0}],
            'Select': [{'Column': {'Expression': {'SourceRef': {'Source': 'f'}}, 'Property': col}, 'Name': 'field'}],
            'OrderBy': [{'Direction': direction, 'Expression': {'Measure': {'Expression': {'SourceRef': {'Source': '_'}}, 'Property': meas}}}],
            'Top': n}}}, 'Type': 2},
        {'Name': 'f', 'Entity': ent, 'Type': 0}],
        'Where': [{'Condition': {'In': {'Expressions': [{'Column': {'Expression': {'SourceRef': {'Source': 'f'}}, 'Property': col}}],
                                        'Table': {'SourceRef': {'Source': 'subquery'}}}}}]}}


def not_blank(name, meas):
    """Visual-level filter: measure is not blank. Keeps out-of-scope counties out of rankings."""
    return {'name': name, 'field': measure(meas), 'type': 'Advanced', 'filter': {'Version': 2,
            'From': [{'Name': 'm', 'Entity': '_Measures', 'Type': 0}],
            'Where': [{'Condition': {'Not': {'Expression': {'Comparison': {'ComparisonKind': 0,
                'Left': {'Measure': {'Expression': {'SourceRef': {'Source': 'm'}}, 'Property': meas}},
                'Right': {'Literal': {'Value': 'null'}}}}}}}]}}


def container(v, title=None, show_title=True, tsize=14):
    vco = v['visual'].setdefault('visualContainerObjects', {})
    vco['background'] = [{'properties': {'show': lit(True), 'color': color(SURFACE), 'transparency': lit(0)}}]
    vco['dropShadow'] = [{'properties': {'show': lit(True), 'preset': lit('BottomRight'), 'position': lit('Outer'),
                                         'color': color('#000000'), 'transparency': lit(40)}}]
    vco['border'] = [{'properties': {'show': lit(True), 'color': color(LINE), 'radius': lit(10)}}]
    vco['padding'] = [{'properties': {'top': lit(12), 'bottom': lit(12), 'left': lit(16), 'right': lit(16)}}]
    t = {'show': lit(show_title), 'fontColor': color(TEXT), 'fontFamily': lit('Segoe UI Semibold'), 'fontSize': lit(tsize)}
    if title: t['text'] = lit(title)
    vco['title'] = [{'properties': t}]
    vco['subTitle'] = [{'properties': {'show': lit(False)}}]
    return v


def base(name, vtype, rect, query=None, objects=None):
    x, y, w, h, z = rect if len(rect) == 5 else (*rect, 300)
    v = {'$schema': VIS, 'name': name, 'position': {'x': x, 'y': y, 'z': z, 'width': w, 'height': h, 'tabOrder': z},
         'visual': {'visualType': vtype, 'drillFilterOtherVisuals': True}}
    if query: v['visual']['query'] = query
    if objects: v['visual']['objects'] = objects
    return v


def run(text, size, bold=False, col=TEXT):
    st = {'fontFamily': 'Segoe UI', 'fontSize': f'{size}pt', 'color': col}
    if bold: st['fontWeight'] = 'bold'
    return {'value': text, 'textStyle': st}


def textbox(name, rect, paragraphs, card=False):
    v = base(name, 'textbox', rect, objects={'general': [{'properties': {'paragraphs': paragraphs}}]})
    if card:
        container(v, show_title=False)
    else:
        v['visual']['visualContainerObjects'] = {'background': [{'properties': {'show': lit(False)}}],
                                                 'dropShadow': [{'properties': {'show': lit(False)}}],
                                                 'border': [{'properties': {'show': lit(False)}}]}
    return v


def kpi(name, meas, title, x, y=124, col=TEXT, w=440, filters=None):
    v = base(name, 'cardVisual', (x, y, w, 170, 200),
             query={'queryState': {'Data': {'projections': [mproj(meas)]}}},
             objects={'value': [{'properties': {'fontSize': lit(35), 'fontColor': color(col), 'displayUnits': lit(1), 'labelDisplayUnits': lit(1),
                                                'fontFamily': lit('Segoe UI Semibold')}, 'selector': {'id': 'default'}}],
                      'label': [{'properties': {'show': lit(False)}, 'selector': {'id': 'default'}}]})
    if filters: v['filterConfig'] = {'filters': filters}
    return container(v, title)


def axes(cat_font=10, vmin=None, vmax=None, val_font=None, title_x=None, title_y=None):
    va = {'labelColor': color(MUTED), 'showAxisTitle': lit(bool(title_y)), 'gridlineShow': lit(True), 'gridlineColor': color(LINE)}
    if val_font: va['fontSize'] = lit(val_font)
    if vmin is not None: va['start'] = lit(vmin)
    if vmax is not None: va['end'] = lit(vmax)
    ca = {'labelColor': color('#CBD5E1'), 'fontSize': lit(cat_font), 'showAxisTitle': lit(bool(title_x))}
    if title_x: ca.update({'titleText': lit(title_x), 'titleColor': color(MUTED), 'titleFontSize': lit(cat_font)})
    if title_y: va.update({'titleText': lit(title_y), 'titleColor': color(MUTED), 'titleFontSize': lit(cat_font)})
    return {'categoryAxis': [{'properties': ca}], 'valueAxis': [{'properties': va}]}


def legend(show, pos='Top', fs=11):
    p = {'show': lit(show)}
    if show: p.update({'position': lit(pos), 'labelColor': color('#CBD5E1'), 'fontSize': lit(fs)})
    return {'legend': [{'properties': p}]}


def labels(fs=10, disp=None):
    p = {'show': lit(True), 'color': color(TEXT), 'fontSize': lit(fs)}
    if disp is not None: p['labelDisplayUnits'] = lit(disp)
    return {'labels': [{'properties': p}]}


def vis(name, vtype, rect, title, proj, objects, sort=None, filters=None, tsize=14):
    q = {'queryState': proj}
    if sort: q['sortDefinition'] = {'sort': [{'field': sort[0], 'direction': sort[1]}]}
    v = base(name, vtype, rect, query=q, objects=objects)
    if filters: v['filterConfig'] = {'filters': filters}
    return container(v, title, tsize=tsize)


def page_title(page, title, subtitle):
    save(page, textbox(f'pagetitle{page[:8]}', (40, 20, 1840, 84, 100),
                       [{'textRuns': [run(title, 24, bold=True)]}, {'textRuns': [run(subtitle, 12, col=MUTED)]}]))


# ================= THEME =================
theme = json.loads(open(THEME, encoding='utf-8-sig').read())
THEME_FILE = 'RateGapDark.json'
add_part(f'Report/StaticResources/RegisteredResources/{THEME_FILE}', json.dumps(theme, indent=2).encode('utf-8'))
rep = json.loads(files['Report/definition/report.json'])
rep['themeCollection']['customTheme'] = {'name': THEME_FILE, 'type': 'RegisteredResources',
                                         'reportVersionAtImport': rep['themeCollection']['baseTheme']['reportVersionAtImport']}
rep['resourcePackages'] = [r for r in rep['resourcePackages'] if r['name'] != 'RegisteredResources'] + [
    {'name': 'RegisteredResources', 'type': 'RegisteredResources', 'items': [{'name': THEME_FILE, 'path': THEME_FILE, 'type': 'CustomTheme'}]}]
files['Report/definition/report.json'] = json.dumps(rep).encode('utf-8')


def page_json(name, display, w=1920, h=1080):
    return {'$schema': PAGE, 'name': name, 'displayName': display, 'displayOption': 'FitToPage', 'height': h, 'width': w,
            'objects': {'background': [{'properties': {'color': color(PAGE_BG), 'transparency': lit(0)}}],
                        'outspace': [{'properties': {'color': color(PAGE_BG), 'transparency': lit(0)}}]}}


# drop the blank starter page(s) from the model-only file
for k in [k for k in files if k.startswith('Report/definition/pages/') and k != 'Report/definition/pages/pages.json']:
    files.pop(k); order.remove(k)
for p, n, w, h in ((P1, 'Poster 11x17', 1632, 1056), (P2, 'Counties and Contracts', 1920, 1080), (P3, 'Arizona vs National', 1920, 1080)):
    add_part(f'Report/definition/pages/{p}/page.json', json.dumps(page_json(p, n, w, h)).encode('utf-8'))
pages = json.loads(files['Report/definition/pages/pages.json'])
pages['pageOrder'] = [P1, P2, P3]; pages['activePageName'] = P1
files['Report/definition/pages/pages.json'] = json.dumps(pages).encode('utf-8')

YR = lambda y: cat_filter(f'yr{y}filter0001', 'DimYear', 'yr', [y])
NOTBLANK = 'Non-Med Share 2023 (5k+ Counties)'

# ================= PAGE 1: POSTER (1632 x 1056) =================
save(P1, textbox('posterheadline01', (40, 14, 1552, 190, 100), [
    {'textRuns': [run('THE RATE GAP  |  MEDICARE ADVANTAGE  |  2018-2023', 13, bold=True, col=AMBER)]},
    {'textRuns': [run('CMS raised county payment rates 28.9% from 2018 to 2023. The share of revenue not spent on care barely moved.', 28, bold=True)]},
    {'textRuns': [run('Non-medical share of revenue (1 - MLR), Medicare Advantage contracts: 9.16% in 2018, 9.22% in 2023, with a spike to 12.29% in 2020. County by county, payment growth and that share are unrelated. Not evidence of wrongdoing; MLR is not a profit measure.', 13, col=MUTED)]},
]))


def poster_card(name, x, big, big_col, small):
    save(P1, textbox(name, (x, 206, 500, 138, 150), [
        {'textRuns': [run(big, 34, bold=True, col=big_col)]},
        {'textRuns': [run(small, 13, col='#CBD5E1')]}], card=True))


poster_card('postercard000001', 40, 'r = 0.02', SKY,
            'Correlation across 709 counties between 2018-23 payment growth and the change in non-medical share.')
poster_card('postercard000002', 566, '2.1% to 13.3%', AMBER,
            'County non-medical share, 2023: Montgomery, MD (lowest) to Carter, TN (highest). Counties with 5,000+ MA members.')
poster_card('postercard000003', 1092, '-3.18 pp in 2021', TEAL,
            'Largest one-year move in the national share, in the year payment growth was lowest (3.55%).')

combo_proj = {'Category': {'projections': [cproj('DimYear', 'yr', 'Year')]},
              'Y': {'projections': [mproj('Payment Growth %', 'Payment growth (%)')]},
              'Y2': {'projections': [mproj('Non-Medical Change (pp)', 'Change in non-medical share (pp)')]}}
cobj = {'dataPoint': [meas_color('Payment Growth %', SKY), meas_color('Non-Medical Change (pp)', AMBER)],
        **labels(14), **axes(14, vmin=0, val_font=13), **legend(True, 'Top', 13)}
cobj['categoryAxis'][0]['properties']['axisType'] = lit('Categorical')
cobj['y2Axis'] = [{'properties': {'labelColor': color(MUTED), 'fontSize': lit(13), 'showAxisTitle': lit(False)}}]
save(P1, vis('postercombo00001', 'lineClusteredColumnComboChart', (40, 352, 760, 614, 300),
             'Each year: payment growth (columns, %) beside the change in non-medical share (line, pp)',
             combo_proj, cobj, sort=(column('DimYear', 'yr'), 'Ascending'),
             filters=[cat_filter('yr1923filter0001', 'DimYear', 'yr', [2019, 2020, 2021, 2022, 2023])], tsize=16))


def county_bars(name, rect, title, col, direction, fname):
    proj = {'Category': {'projections': [cproj('DimCounty', 'county_label', 'County')]},
            'Y': {'projections': [mproj(NOTBLANK, 'Non-medical share, 2023')]}}
    obj = {'dataPoint': [{'properties': {'fill': color(col)}}], **labels(11), **axes(11, vmin=0, val_font=11), **legend(False)}
    obj['categoryAxis'][0]['properties']['maxMarginFactor'] = lit(40)
    obj['categoryAxis'][0]['properties']['innerPadding'] = lit(6)
    obj['valueAxis'][0]['properties']['show'] = lit(False)
    sort_dir = 'Descending' if direction == 2 else 'Ascending'
    return vis(name, 'clusteredBarChart', rect, title, proj, obj, sort=(measure(NOTBLANK), sort_dir),
               filters=[not_blank(fname + 'nb', NOTBLANK), topn('DimCounty', 'county_label', NOTBLANK, 10, fname, direction)], tsize=16)


save(P1, county_bars('posterwidest0001', (826, 352, 766, 306, 300), 'Widest: 10 counties by non-medical share, 2023', AMBER, 2, 'topwidestfilter01'))
save(P1, county_bars('posternarrow0001', (826, 660, 766, 306, 300), 'Narrowest: 10 counties by non-medical share, 2023', SKY, 1, 'topnarrowfilter01'))

save(P1, textbox('posterfooter0001', (40, 976, 1552, 68, 100), [
    {'textRuns': [run('Sources: CMS Medicare Advantage ratebooks 2018-2023 (county monthly rate, Parts A&B, 0% bonus column); CMS MLR data release files, contract years 2018-2023 (Adjusted MLR; CY2024 not yet published); CMS Monthly Enrollment by Contract/Plan/State/County, December 2018-2023. '
                        '28.9% = enrollment-weighted, compounded. Non-medical share = 1 - MLR, weighted by December enrollment. Medicare Advantage contracts only (stand-alone Part D contracts excluded). County and contract level only. A gap is not proof of wrongdoing.', 10, col=MUTED)]},
    {'textRuns': [run('Haitham Saleh  |  github.com/Haitham1111/rate-gap-analytics', 10, bold=True, col='#CBD5E1')]}]))

# ================= PAGE 2: COUNTIES AND CONTRACTS =================
page_title(P2, 'Counties: payment growth does not line up with the non-medical share. Contracts: at most a weak pattern',
           'Medicare Advantage contracts only. Left: each dot is a county with 5,000+ MA members in 2018 and 2023. Right: 2023 contracts split into quartiles by non-medical share (NTILE). Contract level only; no providers.')
save(P2, kpi('kpiscope00000001', 'Counties In Scope', 'Counties with 5,000+ MA members in 2018 and 2023', 40, col=SKY, w=440))
save(P2, kpi('kpipub2023000001', 'Contracts Published', 'MA contracts with a published MLR, 2023', 503, col=TEAL, w=440, filters=[YR(2023)]))
save(P2, kpi('kpiover100000001', 'Contracts MLR Over 100%', 'MA contracts with MLR above 100%, 2023', 966, col=AMBER, w=440, filters=[YR(2023)]))
save(P2, kpi('kpiunder85000001', 'Contracts Under 85% MLR', 'MA contracts with MLR below 85%, 2023', 1429, col=RED, w=440, filters=[YR(2023)]))

sc_proj = {'Category': {'projections': [cproj('DimCounty', 'county_label', 'County')]},
           'X': {'projections': [mproj('County Payment Growth 2018-23 %', 'Payment growth 2018-23 (%)')]},
           'Y': {'projections': [mproj('County Non-Med Change 2018-23 (pp)', 'Change in non-medical share 2018-23 (pp)')]}}
sc_obj = {'dataPoint': [{'properties': {'fill': color(AMBER)}}],
          **axes(11, title_x='Payment growth, 2018 to 2023 (%)', title_y='Change in non-medical share, 2018 to 2023 (pp)'), **legend(False)}
sc_obj['categoryAxis'][0]['properties']['gridlineShow'] = lit(True)
sc_obj['categoryAxis'][0]['properties']['gridlineColor'] = color(LINE)
save(P2, vis('countyscatter0001', 'scatterChart', (40, 324, 1060, 716, 300), 'Each county: payment growth (x) vs change in non-medical share (y), 2018 to 2023 (r = 0.02)',
             sc_proj, sc_obj, filters=[not_blank('scatterxnb000001', 'County Payment Growth 2018-23 %')]))

q_proj = {'Category': {'projections': [cproj('FactContract', 'quartile', 'Quartile of non-medical share (1 = lowest)')]},
          'Y': {'projections': [mproj('Avg Contract Payment Growth %', 'Avg payment growth (%)')]},
          'Y2': {'projections': [mproj('Avg Contract Non-Med Change (pp)', 'Avg change in non-medical share (pp)')]}}
q_obj = {'dataPoint': [meas_color('Avg Contract Payment Growth %', SKY), meas_color('Avg Contract Non-Med Change (pp)', AMBER)],
         **labels(11), **axes(11, vmin=0), **legend(True, 'Top')}
q_obj['categoryAxis'][0]['properties']['axisType'] = lit('Categorical')
q_obj['y2Axis'] = [{'properties': {'labelColor': color(MUTED), 'showAxisTitle': lit(False)}}]
save(P2, vis('quartilecombo0001', 'lineClusteredColumnComboChart', (1130, 324, 750, 716, 300),
             '2023 contracts by quartile of non-medical share: payment growth (columns) beside change in share (line)',
             q_proj, q_obj, sort=(column('FactContract', 'quartile'), 'Ascending'), filters=[YR(2023)]))

# ================= PAGE 3: ARIZONA VS NATIONAL =================
page_title(P3, 'Arizona vs national: the Arizona non-medical share is above the national share in every year',
           'Medicare Advantage contracts only. Arizona = SSA state code 03. Non-medical share = 1 - MLR, weighted by December enrollment. Payment growth = year-over-year change in the county monthly rate.')
save(P3, kpi('kpiaz2023000000a', 'AZ Non-Medical Share', 'Arizona non-medical share, 2023', 40, col=AMBER, w=440, filters=[YR(2023)]))
save(P3, kpi('kpinat2023000000', 'National Non-Medical Share', 'National non-medical share, 2023', 503, col=TEAL, w=440, filters=[YR(2023)]))
save(P3, kpi('kpigap2023000000', 'AZ Minus National (pp)', 'Arizona minus national, 2023 (pp)', 966, col=SKY, w=440, filters=[YR(2023)]))
save(P3, kpi('kpiazpay2023000a', 'AZ Payment Growth %', 'Arizona payment growth, 2023', 1429, col=GREEN, w=440, filters=[YR(2023)]))

nm_proj = {'Category': {'projections': [cproj('DimYear', 'yr', 'Year')]},
           'Y': {'projections': [mproj('AZ Non-Medical Share', 'Arizona'), mproj('National Non-Medical Share', 'National')]}}
nm_obj = {'dataPoint': [meas_color('AZ Non-Medical Share', AMBER), meas_color('National Non-Medical Share', TEAL)],
          'lineStyles': [{'properties': {'strokeWidth': lit(3), 'showMarker': lit(True)}}],
          **labels(10), **axes(11, vmin=0.05), **legend(True, 'Top')}
nm_obj['categoryAxis'][0]['properties']['axisType'] = lit('Categorical')
save(P3, vis('aznmlinechart001', 'lineChart', (40, 324, 900, 340, 300), 'Non-medical share of revenue: Arizona vs national',
             nm_proj, nm_obj, sort=(column('DimYear', 'yr'), 'Ascending')))

pg_proj = {'Category': {'projections': [cproj('DimYear', 'yr', 'Year')]},
           'Y': {'projections': [mproj('AZ Payment Growth %', 'Arizona'), mproj('Payment Growth %', 'National')]}}
pg_obj = {'dataPoint': [meas_color('AZ Payment Growth %', AMBER), meas_color('Payment Growth %', TEAL)],
          **labels(10), **axes(11, vmin=0), **legend(True, 'Top')}
pg_obj['categoryAxis'][0]['properties']['axisType'] = lit('Categorical')
save(P3, vis('azpaycolumns0001', 'clusteredColumnChart', (40, 694, 900, 346, 300), 'Payment growth (%): Arizona vs national',
             pg_proj, pg_obj, sort=(column('DimYear', 'yr'), 'Ascending'),
             filters=[cat_filter('yr1923filter0003', 'DimYear', 'yr', [2019, 2020, 2021, 2022, 2023])]))

tb_proj = {'Values': {'projections': [cproj('DimCounty', 'county_name', 'County', active=False), mproj('Members'), mproj('Non-Medical Share', 'Non-medical share'),
                                      mproj('Payment Growth %', 'Payment growth (%)'), mproj('Non-Medical Change (pp)', 'Change (pp)')]}}
tb_obj = {'columnHeaders': [{'properties': {'fontColor': color(MUTED), 'backColor': color(PAGE_BG), 'fontSize': lit(12)}}],
          'values': [{'properties': {'fontColor': color(TEXT), 'fontSize': lit(12)}}]}
save(P3, vis('azcountytable0001', 'tableEx', (970, 324, 910, 716, 300), 'Arizona counties, 2023 (county level only)',
             tb_proj, tb_obj, sort=(measure('Non-Medical Share'), 'Descending'),
             filters=[YR(2023), cat_filter('azstatefilter0001', 'FactCounty', 'state_ssa', ['03'])]))

# ================= REPACK =================
files.pop('SecurityBindings', None)
if 'SecurityBindings' in order: order.remove('SecurityBindings')
ct = files['[Content_Types].xml'].decode('utf-8-sig').replace('<Override PartName="/SecurityBindings" ContentType="" />', '')
files['[Content_Types].xml'] = ('﻿' + ct).encode('utf-8')
with zipfile.ZipFile(OUT, 'w') as zout:
    for n in order:
        zout.writestr(zipfile.ZipInfo(n, date_time=(2026, 10, 13, 20, 0, 0)), files[n], compress_type=ctype[n])
print('wrote', OUT, len(order), 'parts')
