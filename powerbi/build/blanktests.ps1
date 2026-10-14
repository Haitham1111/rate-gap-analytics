# blanktests.ps1 <port>  - run every measure through edge-case filter contexts and print the values.
# Needs the report open in Power BI Desktop; find the port with Get-NetTCPConnection on the msmdsrv process.
param($port)
$d = $PSScriptRoot; $w = $env:TEMP   # dax.ps1 sits next to this script
function T($label, $filt, $ms) {
  $cols = ($ms | % { """$_"", CALCULATE ( [$_]" + $(if ($filt) { ", $filt" }) + " )" }) -join ', '
  "EVALUATE ROW ( $cols )" | Set-Content "$w\qt.dax"
  $o = & "$d\dax.ps1" $port "$w\qt.dax"
  "### $label  [$filt]"
  if ($o[0] -like 'ERROR*') { $o[0]; return }
  $h = $o[0] -split "`t"; $v = $o[1] -split "`t"
  for ($i = 0; $i -lt $h.Count; $i++) { $x = $v[$i]; if ($x -match '^-?[0-9.]+(E-?[0-9]+)?$') { $x = [Math]::Round([double]$x, 4) }; "  " + $h[$i].Trim('[', ']') + " = " + $x }
}
$all = @('Members','Contracts Published','Payment Growth %','Payment Index (2018=100)','Weighted MLR','Non-Medical Share','Non-Medical Change (pp)','County In Scope','Counties In Scope','County Payment Growth 2018-23 %','County Non-Med Change 2018-23 (pp)','Non-Med Share 2023 (5k+ Counties)','AZ Non-Medical Share','National Non-Medical Share','AZ Minus National (pp)','AZ Payment Growth %','Contracts MLR Over 100%','Contracts Under 85% MLR','Avg Contract Payment Growth %','Avg Contract Non-Med Change (pp)')
$cty = @('Members','Non-Medical Share','Non-Medical Change (pp)','Payment Growth %','County In Scope','County Payment Growth 2018-23 %','County Non-Med Change 2018-23 (pp)','Non-Med Share 2023 (5k+ Counties)')
T 'T1 first year, no prior year' 'DimYear[yr] = 2018' @('Non-Medical Change (pp)','Payment Growth %','Payment Index (2018=100)','AZ Payment Growth %','Non-Medical Share','Weighted MLR','AZ Minus National (pp)')
T 'T2 year with no data (2016 not in DimYear)' 'FILTER ( ALL ( DimYear[yr] ), DimYear[yr] = 2016 )' $all
T 'T3 tiny county, 300 members in 2023' 'DimCounty[county_label] = "Kimble, Texas"' $cty
T 'T3b tiny county, year 2023' 'DimCounty[county_label] = "Kimble, Texas", DimYear[yr] = 2023' @('Members','Non-Medical Share','Non-Medical Change (pp)')
T 'T4 county just under the 5,000 cutoff (4,857 in 2023, 5,000+ in 2018)' 'DimCounty[county_label] = "Kandiyohi, Minnesota"' $cty
T 'T5 county with no MA enrollment at all' 'DimCounty[county_label] = "Aleutians East, Alaska"' $cty
T 'T5b county with no enrollment, year 2023' 'DimCounty[county_label] = "Aleutians East, Alaska", DimYear[yr] = 2023' @('Members','Non-Medical Share','Non-Medical Change (pp)','Payment Growth %','Weighted MLR')
T 'T5c county with only 47 member-years of MA enrollment in total (Petroleum, MT), never in scope' 'DimCounty[county_label] = "Petroleum, Montana"' $cty
T 'T6 Arizona 2019 (control)' 'FactCounty[state_ssa] = "03", DimYear[yr] = 2019' @('AZ Non-Medical Share','National Non-Medical Share','AZ Minus National (pp)','AZ Payment Growth %','Non-Medical Change (pp)')
T 'T7 year 2023 control, all measures' 'DimYear[yr] = 2023' $all
T 'T8 two years selected 2021 and 2022 (uses latest year)' 'DimYear[yr] IN { 2021, 2022 }' @('Non-Medical Change (pp)','Payment Index (2018=100)','Payment Growth %')
T 'T9 Maricopa AZ county, year 2023' 'DimCounty[county_label] = "Maricopa, Arizona", DimYear[yr] = 2023' $cty
