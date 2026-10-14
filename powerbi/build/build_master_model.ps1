# build_master_model.ps1 <port> [step]  - add the master (state scorecard) tables, relationships and measures
# to the open Power BI model, beside the v1 tables. Steps: tables | model (default both, refresh in Desktop between them).
param($port, $step = 'all')
$bin = 'C:\Program Files\WindowsApps\Microsoft.MicrosoftPowerBIDesktop_2.158.1304.0_x64__8wekyb3d8bbwe\bin'
[Reflection.Assembly]::LoadFrom("$bin\Microsoft.PowerBI.Tabular.Json.dll") | Out-Null
$a = [Reflection.Assembly]::LoadFrom("$bin\Microsoft.PowerBI.Tabular.dll")
$ns = ($a.GetTypes() | ? { $_.Name -eq 'Server' -and $_.Namespace -like '*Tabular' } | select -first 1).Namespace
$s = New-Object "$ns.Server"; $s.Connect("Data Source=localhost:$port")
$m = $s.Databases[0].Model
function E($t, $v) { [Enum]::Parse($a.GetType("$ns.$t"), $v) }

function AddM($name, $mexpr, $cols) {
    $t = New-Object "$ns.Table"; $t.Name = $name
    foreach ($c in $cols) {
        $col = New-Object "$ns.DataColumn"; $col.Name = $c[0]; $col.SourceColumn = $c[0]; $col.DataType = (E 'DataType' $c[1])
        $t.Columns.Add($col)
    }
    $p = New-Object "$ns.Partition"; $p.Name = $name
    $src = New-Object "$ns.MPartitionSource"; $src.Expression = $mexpr; $p.Source = $src
    $t.Partitions.Add($p); $m.Tables.Add($t)
}
$db = 'Source = Sql.Database(".\SQLEXPRESS", "Rate_Gap")'

if ($step -eq 'all' -or $step -eq 'tables') {
    AddM 'FactScorecard' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v2_state_scorecard"]}[Data],
    Keep = Table.SelectColumns(v, {"state_name", "ma_members", "counties", "contracts", "enroll_growth_3yr_pct", "pay_growth_2026_pct", "pay_3yr_pct", "chg_2027_pct", "nonmed_share_cy2023_pct", "nonmed_chg_1yr_pp", "nonmed_chg_3yr_pp", "rank_enrollment", "rank_enroll_growth", "rank_pay_2026", "rank_pay_3yr", "rank_chg_2027", "rank_nonmed_share", "rank_nonmed_chg_3yr", "top10_count"}),
    Typed = Table.TransformColumnTypes(Keep, {{"state_name", type text}, {"ma_members", Int64.Type}, {"counties", Int64.Type}, {"contracts", Int64.Type}, {"enroll_growth_3yr_pct", type number}, {"pay_growth_2026_pct", type number}, {"pay_3yr_pct", type number}, {"chg_2027_pct", type number}, {"nonmed_share_cy2023_pct", type number}, {"nonmed_chg_1yr_pp", type number}, {"nonmed_chg_3yr_pp", type number}, {"rank_enrollment", Int64.Type}, {"rank_enroll_growth", Int64.Type}, {"rank_pay_2026", Int64.Type}, {"rank_pay_3yr", Int64.Type}, {"rank_chg_2027", Int64.Type}, {"rank_nonmed_share", Int64.Type}, {"rank_nonmed_chg_3yr", Int64.Type}, {"top10_count", Int64.Type}})
in
    Typed
"@ @(@('state_name','String'),@('ma_members','Int64'),@('counties','Int64'),@('contracts','Int64'),@('enroll_growth_3yr_pct','Double'),@('pay_growth_2026_pct','Double'),@('pay_3yr_pct','Double'),@('chg_2027_pct','Double'),@('nonmed_share_cy2023_pct','Double'),@('nonmed_chg_1yr_pp','Double'),@('nonmed_chg_3yr_pp','Double'),@('rank_enrollment','Int64'),@('rank_enroll_growth','Int64'),@('rank_pay_2026','Int64'),@('rank_pay_3yr','Int64'),@('rank_chg_2027','Int64'),@('rank_nonmed_share','Int64'),@('rank_nonmed_chg_3yr','Int64'),@('top10_count','Int64'))

    AddM 'FactOutlook' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v2_state_outlook"]}[Data],
    Keep = Table.SelectColumns(v, {"state_name", "actual_2024_pct", "actual_2025_pct", "actual_2026_pct", "trailing_3yr_mean_pct", "announced_2027_pct", "projection_trend_2027_pct", "announced_minus_trend_pct_points", "rank_announced_2027", "nonmed_cy2021_pct", "nonmed_cy2022_pct", "nonmed_cy2023_pct", "nonmed_projection_mean_pct", "nonmed_projection_low_pct", "nonmed_projection_high_pct"}),
    Typed = Table.TransformColumnTypes(Keep, {{"state_name", type text}, {"actual_2024_pct", type number}, {"actual_2025_pct", type number}, {"actual_2026_pct", type number}, {"trailing_3yr_mean_pct", type number}, {"announced_2027_pct", type number}, {"projection_trend_2027_pct", type number}, {"announced_minus_trend_pct_points", type number}, {"rank_announced_2027", Int64.Type}, {"nonmed_cy2021_pct", type number}, {"nonmed_cy2022_pct", type number}, {"nonmed_cy2023_pct", type number}, {"nonmed_projection_mean_pct", type number}, {"nonmed_projection_low_pct", type number}, {"nonmed_projection_high_pct", type number}})
in
    Typed
"@ @(@('state_name','String'),@('actual_2024_pct','Double'),@('actual_2025_pct','Double'),@('actual_2026_pct','Double'),@('trailing_3yr_mean_pct','Double'),@('announced_2027_pct','Double'),@('projection_trend_2027_pct','Double'),@('announced_minus_trend_pct_points','Double'),@('rank_announced_2027','Int64'),@('nonmed_cy2021_pct','Double'),@('nonmed_cy2022_pct','Double'),@('nonmed_cy2023_pct','Double'),@('nonmed_projection_mean_pct','Double'),@('nonmed_projection_low_pct','Double'),@('nonmed_projection_high_pct','Double'))

    AddM 'FactOutlookLong' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v2_state_outlook_long"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"state_name", type text}, {"year", Int64.Type}, {"series", type text}, {"value_pct", type number}, {"weight", Int64.Type}})
in
    Typed
"@ @(@('state_name','String'),@('year','Int64'),@('series','String'),@('value_pct','Double'),@('weight','Int64'))

    AddM 'DimState' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "dim_state_licence"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"state_ssa", type text}, {"state_name", type text}}),
    Lic = Table.AddColumn(Typed, "licensed_text", each if [licensed] = null then "Not set" else if [licensed] = true then "Yes" else "No", type text),
    Keep = Table.SelectColumns(Lic, {"state_ssa", "state_name", "licensed_text"})
in
    Keep
"@ @(@('state_ssa','String'),@('state_name','String'),@('licensed_text','String'))
    $m.SaveChanges() | Out-Null
    "tables added"
}

if ($step -eq 'all' -or $step -eq 'model') {
    function Rel($ft, $fc, $tt, $tc) {
        foreach ($r in $m.Relationships) { if ($r.FromTable.Name -eq $ft -and $r.ToTable.Name -eq $tt -and $r.FromColumn.Name -eq $fc) { return } }
        $r = New-Object "$ns.SingleColumnRelationship"; $r.FromColumn = $m.Tables[$ft].Columns[$fc]; $r.ToColumn = $m.Tables[$tt].Columns[$tc]
        $r.FromCardinality = (E 'RelationshipEndCardinality' 'Many'); $r.ToCardinality = (E 'RelationshipEndCardinality' 'One'); $m.Relationships.Add($r)
    }
    foreach ($f in 'FactScorecard','FactOutlook','FactOutlookLong') { Rel $f 'state_name' 'DimState' 'state_name' }
    $none = E 'AggregateFunction' 'None'
    foreach ($tn in 'FactScorecard','FactOutlook','FactOutlookLong') {
        foreach ($c in $m.Tables[$tn].Columns) { if ($c.Name -notlike 'RowNumber*' -and $c.DataType -ne (E 'DataType' 'String')) { $c.SummarizeBy = $none } }
    }
    $mt = $m.Tables['_Measures']
    $cur = $null; $defs = @()
    foreach ($l in (Get-Content "$PSScriptRoot\measures_master.txt" -Encoding UTF8)) {
        if ($l -like '### *') { $p = $l.Substring(4).Split('|'); $cur = @{ name = $p[0].Trim(); fmt = $p[1].Trim(); folder = $p[2].Trim(); desc = $p[3].Trim(); expr = @() }; $defs += $cur }
        elseif ($cur) { $cur.expr += $l }
    }
    foreach ($df in $defs) {
        $old = $mt.Measures[$df.name]; if ($old) { $mt.Measures.Remove($old) | Out-Null }
        $me = New-Object "$ns.Measure"; $me.Name = $df.name; $me.Expression = ($df.expr -join "`n")
        $me.FormatString = $df.fmt; $me.DisplayFolder = $df.folder; $me.Description = $df.desc; $mt.Measures.Add($me)
    }
    $m.SaveChanges() | Out-Null
    "relationships: " + $m.Relationships.Count + "; measures: " + $mt.Measures.Count
}
$s.Disconnect()
