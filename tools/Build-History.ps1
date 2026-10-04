param([string]$CodexHome=(Join-Path $env:USERPROFILE '.codex'))
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $root 'SessionCatalog.cs'),(Join-Path $root 'ModelUsage.cs'),(Join-Path $root 'HistoryUsage.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
$history=[CodexPet.HistoryUsage]::new($CodexHome,(Join-Path $root 'api-prices.json'),(Join-Path $root 'state\history-cache.json'))
try {$history.ScanOnce();$snapshot=$history.Snapshot();[IO.File]::WriteAllText((Join-Path $root 'state\history-summary.json'),$snapshot,[Text.Encoding]::UTF8);$data=$snapshot|ConvertFrom-Json;[pscustomobject]@{Sources=$data.Sources;Total=$data.Total;Models=@($data.Models).Count;Missing=$data.Missing;Errors=$data.Errors}|ConvertTo-Json}finally{$history.Dispose()}
