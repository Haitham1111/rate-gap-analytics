# rg_model.ps1 <port>  - rebuild the open Power BI model for The Rate Gap through TOM.
# Removes the template tables, adds the Rate Gap tables (SQL Server views), relationships and measures.
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
function AddCalc($name, $expr, $cols) {
    $t = New-Object "$ns.Table"; $t.Name = $name
    $p = New-Object "$ns.Partition"; $p.Name = $name
    $src = New-Object "$ns.CalculatedPartitionSource"; $src.Expression = $expr; $p.Source = $src; $t.Partitions.Add($p)
    foreach ($c in $cols) {
        $col = New-Object "$ns.CalculatedTableColumn"; $col.Name = $c[0]; $col.SourceColumn = '[' + $c[0] + ']'; $col.DataType = (E 'DataType' $c[1])
        $t.Columns.Add($col)
    }
    $m.Tables.Add($t)
}

if ($step -eq 'all' -or $step -eq 'tables') {
    # 1. clear the template
    $m.Relationships.Clear()
    foreach ($t in @($m.Tables)) { $m.Tables.Remove($t) | Out-Null }
    $m.SaveChanges() | Out-Null
    "cleared"

    # 2. tables from SQL Server views
    $db = 'Source = Sql.Database(".\SQLEXPRESS", "Rate_Gap")'
    AddM 'FactCounty' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v_county_trend"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"year", Int64.Type}, {"ssa_code", type text}, {"state_ssa", type text}, {"enrollment", Int64.Type}, {"contracts", Int64.Type}, {"rate_0", type number}, {"payment_growth_pct", type number}, {"mlr_weighted", type number}, {"nonmed_share", type number}, {"nonmed_share_prior", type number}, {"nonmed_change_pp", type number}}),
    Keep = Table.SelectColumns(Typed, {"year", "ssa_code", "state_ssa", "enrollment", "contracts", "rate_0", "payment_growth_pct", "mlr_weighted", "nonmed_share", "nonmed_share_prior", "nonmed_change_pp"})
in
    Keep
"@ @(@('year','Int64'),@('ssa_code','String'),@('state_ssa','String'),@('enrollment','Int64'),@('contracts','Int64'),@('rate_0','Double'),@('payment_growth_pct','Double'),@('mlr_weighted','Double'),@('nonmed_share','Double'),@('nonmed_share_prior','Double'),@('nonmed_change_pp','Double'))

    AddM 'DimCounty' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "dim_county"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"ssa_code", type text}, {"state_ssa", type text}, {"state_name", type text}, {"county_name", type text}}),
    Label = Table.AddColumn(Typed, "county_label", each if [state_name] = null then Text.Proper([county_name]) else Text.Proper([county_name]) & ", " & Text.Proper([state_name]), type text)
in
    Label
"@ @(@('ssa_code','String'),@('state_ssa','String'),@('state_name','String'),@('county_name','String'),@('county_label','String'))

    AddM 'FactMLR' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v_contract_mlr"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"year", Int64.Type}, {"contract_id", type text}, {"org_name", type text}, {"adjusted_mlr", type number}}),
    Keep = Table.SelectColumns(Typed, {"year", "contract_id", "org_name", "adjusted_mlr"})
in
    Keep
"@ @(@('year','Int64'),@('contract_id','String'),@('org_name','String'),@('adjusted_mlr','Double'))

    AddM 'FactContract' @"
let
    $db,
    v = Source{[Schema = "dbo", Item = "v_contract_quartile"]}[Data],
    Typed = Table.TransformColumnTypes(v, {{"year", Int64.Type}, {"contract_id", type text}, {"org_name", type text}, {"enrollment", Int64.Type}, {"counties", Int64.Type}, {"adjusted_mlr", type number}, {"nonmed_share", type number}, {"nonmed_change_pp", type number}, {"payment_growth_pct", type number}, {"quartile", Int64.Type}}),
    Keep = Table.SelectColumns(Typed, {"year", "contract_id", "org_name", "enrollment", "counties", "adjusted_mlr", "nonmed_share", "nonmed_change_pp", "payment_growth_pct", "quartile"}),
    Sorted = Table.Sort(Keep, {{"year", Order.Ascending}, {"contract_id", Order.Ascending}})
in
    Sorted
"@ @(@('year','Int64'),@('contract_id','String'),@('org_name','String'),@('enrollment','Int64'),@('counties','Int64'),@('adjusted_mlr','Double'),@('nonmed_share','Double'),@('nonmed_change_pp','Double'),@('payment_growth_pct','Double'),@('quartile','Int64'))

    AddCalc 'DimYear' 'SELECTCOLUMNS ( GENERATESERIES ( 2018, 2023, 1 ), "yr", [Value] )' @(,@('yr','Int64'))
    AddCalc '_Measures' 'ROW ( "Dummy", 1 )' @(,@('Dummy','Int64'))

    # 3. model annotations: no auto date tables
    foreach ($an in @($m.Annotations)) { if ($an.Name -eq '__PBI_TimeIntelligenceEnabled') { $an.Value = '0' } }
    $q = $m.Annotations | ? { $_.Name -eq 'PBI_QueryOrder' }
    if ($q) { $q.Value = '["FactCounty","DimCounty","FactMLR","FactContract"]' }
    $m.SaveChanges() | Out-Null
    "tables added: " + (($m.Tables | % { $_.Name }) -join ', ')
}

if ($step -eq 'all' -or $step -eq 'refresh') {
    foreach ($n in 'FactCounty','DimCounty','FactMLR','FactContract') { $m.Tables[$n].RequestRefresh((E 'RefreshType' 'Full')) }
    $m.SaveChanges() | Out-Null
    foreach ($n in 'DimYear','_Measures') { $m.Tables[$n].RequestRefresh((E 'RefreshType' 'Calculate')) }
    $m.SaveChanges() | Out-Null
    "refreshed"
}

if ($step -eq 'all' -or $step -eq 'model') {
    function Rel($ft, $fc, $tt, $tc) {
        foreach ($r in $m.Relationships) { if ($r.FromTable.Name -eq $ft -and $r.ToTable.Name -eq $tt -and $r.FromColumn.Name -eq $fc) { return } }
        $r = New-Object "$ns.SingleColumnRelationship"; $r.FromColumn = $m.Tables[$ft].Columns[$fc]; $r.ToColumn = $m.Tables[$tt].Columns[$tc]
        $r.FromCardinality = (E 'RelationshipEndCardinality' 'Many'); $r.ToCardinality = (E 'RelationshipEndCardinality' 'One'); $m.Relationships.Add($r)
    }
    Rel 'FactCounty' 'year' 'DimYear' 'yr'; Rel 'FactMLR' 'year' 'DimYear' 'yr'; Rel 'FactContract' 'year' 'DimYear' 'yr'
    Rel 'FactCounty' 'ssa_code' 'DimCounty' 'ssa_code'

    # hide plumbing columns and stop numeric columns summing by default
    $none = E 'AggregateFunction' 'None'
    foreach ($tn in 'FactCounty','FactMLR','FactContract') {
        foreach ($c in $m.Tables[$tn].Columns) { if ($c.Name -notlike 'RowNumber*' -and $c.DataType -ne (E 'DataType' 'String')) { $c.SummarizeBy = $none } }
    }
    $m.Tables['DimYear'].Columns['yr'].SummarizeBy = $none
    foreach ($c in 'year','ssa_code','state_ssa') { $m.Tables['FactCounty'].Columns[$c].IsHidden = $true }
    foreach ($c in 'year') { $m.Tables['FactMLR'].Columns[$c].IsHidden = $true; $m.Tables['FactContract'].Columns[$c].IsHidden = $true }
    $m.Tables['_Measures'].Columns['Dummy'].IsHidden = $true

    # measures from measures.txt  (### name|format|folder|description, then DAX lines)
    $mt = $m.Tables['_Measures']; foreach ($x in @($mt.Measures)) { $mt.Measures.Remove($x) | Out-Null }
    $cur = $null; $defs = @()
    foreach ($l in (Get-Content "$PSScriptRoot\measures.txt" -Encoding UTF8)) {
        if ($l -like '### *') { $p = $l.Substring(4).Split('|'); $cur = @{ name = $p[0].Trim(); fmt = $p[1].Trim(); folder = $p[2].Trim(); desc = $p[3].Trim(); expr = @() }; $defs += $cur }
        elseif ($cur) { $cur.expr += $l }
    }
    foreach ($df in $defs) {
        $me = New-Object "$ns.Measure"; $me.Name = $df.name; $me.Expression = ($df.expr -join "`n")
        if ($df.fmt -ne '@') { $me.FormatString = $df.fmt }
        $me.DisplayFolder = $df.folder; $me.Description = $df.desc; $mt.Measures.Add($me)
    }
    $m.SaveChanges() | Out-Null
    "relationships: " + $m.Relationships.Count + "; measures: " + $mt.Measures.Count
}
$s.Disconnect()
