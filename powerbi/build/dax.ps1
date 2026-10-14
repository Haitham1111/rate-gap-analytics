# dax.ps1 <port> <queryfile>  -> prints result rows (tab separated)
param($port,$qf)
$bin='C:\Program Files\WindowsApps\Microsoft.MicrosoftPowerBIDesktop_2.158.1304.0_x64__8wekyb3d8bbwe\bin'
[Reflection.Assembly]::LoadFrom("$bin\Microsoft.PowerBI.AdomdClient.dll") | Out-Null
$c=New-Object Microsoft.AnalysisServices.AdomdClient.AdomdConnection("Data Source=localhost:$port"); $c.Open()
$cmd=$c.CreateCommand(); $cmd.CommandText=(Get-Content $qf -Raw)
try { $r=$cmd.ExecuteReader(); $h=@(); for($i=0;$i -lt $r.FieldCount;$i++){$h+=$r.GetName($i)}; ($h -join "`t")
  while($r.Read()){ $v=@(); for($i=0;$i -lt $r.FieldCount;$i++){ $x=$r.GetValue($i); if($x -is [DBNull] -or $x -eq $null){$v+='(BLANK)'}else{$v+=[string]$x} }; ($v -join "`t") } ; $r.Close() }
catch { "ERROR: " + $_.Exception.InnerException.Message + $_.Exception.Message }
$c.Close()
