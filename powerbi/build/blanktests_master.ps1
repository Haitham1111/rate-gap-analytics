# blanktests_master.ps1 <port>  - run each new master measure through edge-case filter contexts.
param($port)
$d = $PSScriptRoot; $w = $env:TEMP
function T($label, $filt, $ms) {
  $cols = ($ms | % { """$_"", CALCULATE ( [$_]" + $(if ($filt) { ", $filt" }) + " )" }) -join ', '
  "EVALUATE ROW ( $cols )" | Set-Content "$w\qtm.dax"
  $o = & "$d\dax.ps1" $port "$w\qtm.dax"
  "### $label  [$filt]"
  if ($o[0] -like 'ERROR*') { $o[0]; return }
  $h = $o[0] -split "`t"; $v = $o[1] -split "`t"
  for ($i = 0; $i -lt $h.Count; $i++) { $x = $v[$i]; if ($x -match '^-?[0-9.]+(E-?[0-9]+)?$') { $x = [Math]::Round([double]$x, 4) }; "  " + $h[$i].Trim('[', ']') + " = " + $x }
}
$all = @('State MA Members','States Counted','State Announced 2027 Change %','State 3-Year Payment Growth %','State 2026 Payment Growth %','State Non-Medical Share CY2023','State Top 10 Count','Top 10 States Share of MA Members','Outlook Value %')
T 'M1 all 51 areas (control)' '' $all
T 'M2 no state in context (empty)' 'FILTER ( ALL ( DimState[state_name] ), DimState[state_name] = "NOWHERE" )' $all
T 'M3 one state, Arizona' 'DimState[state_name] = "ARIZONA"' $all
T 'M4 a small market, Wyoming' 'DimState[state_name] = "WYOMING"' $all
T 'M5 District of Columbia' 'DimState[state_name] = "DISTRICT OF COLUMBIA"' $all
T 'M6 outlook series with no rows (Actual 2027)' 'FactOutlookLong[series] = "Actual", FactOutlookLong[year] = 2027' @('Outlook Value %')
T 'M7 two states selected' 'DimState[state_name] IN { "ARIZONA", "TEXAS" }' @('State MA Members','State Top 10 Count','State Announced 2027 Change %')
