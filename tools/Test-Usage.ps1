$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $root 'ModelUsage.cs') -ReferencedAssemblies System.Web.Extensions
Add-Type -Path (Join-Path $root 'SessionCatalog.cs') -ReferencedAssemblies System.Web.Extensions
function Assert($ok,$label) {if(-not $ok){throw $label};Write-Output ('PASS '+$label)}
function Context([string]$model,[string]$tier='standard') { @{type='turn_context';payload=@{model=$model;service_tier=$tier}} | ConvertTo-Json -Depth 6 -Compress }
function Tokens([long]$inputCount,[long]$cached,[long]$outputCount,[long]$lastInput=1000) {
 @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{input_tokens=$inputCount;cached_input_tokens=$cached;cache_write_input_tokens=0;output_tokens=$outputCount;total_tokens=($inputCount+$outputCount)};last_token_usage=@{input_tokens=$lastInput;total_tokens=($lastInput+100)};model_context_window=1000000}}} | ConvertTo-Json -Depth 8 -Compress
}
$path=Join-Path $env:TEMP ('codex-pet-usage-'+[guid]::NewGuid()+'.jsonl')
$worker=[CodexPet.ModelUsage]::new((Join-Path $root 'api-prices.json'))
try {
 $rows=@((Context 'gpt-6-sol'),(Tokens 1000 800 100),(Tokens 1000 800 100),(Context 'gpt-6-astra' 'priority'),(Tokens 1500 1000 300),(Context 'gpt-6.1-sol'),(Tokens 301500 201000 400 300000))
 [IO.File]::WriteAllText($path,($rows -join "`n")+"`n")
 $s=$worker.ParseFixture($path) | ConvertFrom-Json
 Assert ($s.Total -eq 301900 -and $s.Models.Count -eq 3) 'per-model attribution and duplicate counters'
 $sol=$s.Models | Where-Object Model -eq 'gpt-6-sol'
 Assert ([math]::Abs($sol.Cost-.00156) -lt .00000001) 'cached input counted inside input, reasoning not doubled'
 $astra=$s.Models | Where-Object Model -eq 'gpt-6-astra'
 Assert ([math]::Abs($astra.Cost-.0264) -lt .00000001) 'priority pricing and model switch delta'
 $latest=$s.Models | Where-Object Model -eq 'gpt-6.1-sol'
 Assert ($latest.Total -eq 300100 -and [math]::Abs($latest.Cost-.4415) -lt .00000001) 'long context multipliers'
 [IO.File]::AppendAllText($path,(Context 'unknown-model')+"`n"+(Tokens 500 0 10)+"`n")
 $s=$worker.ParseFixture($path) | ConvertFrom-Json
 Assert ($s.Total -eq 302410 -and -not $s.Priced) 'counter reset and unknown model remains unpriced'
 $worker.Start();$worker.Follow($path)
 $deadline=(Get-Date).AddSeconds(4)
 do {Start-Sleep -Milliseconds 100;$live=$worker.Snapshot()|ConvertFrom-Json} while($live.Total -ne 302410 -and (Get-Date) -lt $deadline)
 Assert ($live.Total -eq 302410 -and $live.Path -eq $path -and -not $live.Loading) 'background streaming matches selected file'
 $more=Tokens 700 0 20
 [IO.File]::AppendAllText($path,$more)
 Start-Sleep -Milliseconds 650
 Assert (($worker.Snapshot()|ConvertFrom-Json).Total -eq 302410) 'partial trailing line deferred'
 [IO.File]::AppendAllText($path,"`n")
 $deadline=(Get-Date).AddSeconds(3)
 do {Start-Sleep -Milliseconds 100;$live=$worker.Snapshot()|ConvertFrom-Json} while($live.Total -ne 302620 -and (Get-Date) -lt $deadline)
 Assert ($live.Total -eq 302620) 'appended bytes counted once'
 $codexHome=Join-Path $env:USERPROFILE '.codex'
 if((Test-Path -LiteralPath $codexHome) -and @(Get-ChildItem -LiteralPath $codexHome -Filter 'state_*.sqlite').Count) {
  $sessions=[CodexPet.SessionCatalog]::Read($codexHome)|ConvertFrom-Json
  if(@($sessions).Count){Assert ($sessions[0].Title -and (Test-Path -LiteralPath $sessions[0].FullName)) 'catalog title, project and authoritative rollout path'}
  else{Write-Output 'SKIP local catalog: no readable sessions'}
 }else{Write-Output 'SKIP local catalog: Codex is not installed; fixture checks remain enabled'}
} finally {$worker.Dispose();Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue}
