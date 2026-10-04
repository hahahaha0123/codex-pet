$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot) 'CodexPet.Data.ps1')
$temp=Join-Path $env:TEMP ('codex-pet-test-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory($temp)
function Assert($ok,$label) { if(-not $ok) {throw $label}; Write-Output ('PASS '+$label) }
try {
 $path=Join-Path $temp 'rollout.jsonl'
 $rows=@(
  [ordered]@{type='session_meta';payload=[ordered]@{id='fixture';cwd='F:\demo';base_instructions=('x'*18000)}},
  @{type='event_msg';payload=@{type='task_started'}},
  @{type='event_msg';payload=@{type='token_count';info=@{total_token_usage=@{total_tokens=24000};last_token_usage=@{total_tokens=4200};model_context_window=10000}}}
 )
 $lines=@($rows | ForEach-Object {$_ | ConvertTo-Json -Depth 8 -Compress})
 [IO.File]::WriteAllText($path,($lines -join "`n"))
 $s=Read-CodexSnapshot $path
 Assert ($s.Id -eq 'fixture' -and $s.Cwd -eq 'F:\demo') 'long header metadata'
 Assert ($s.Status -eq 'working' -and $s.Total -eq 24000 -and $s.Context -eq 4200) 'working and usage'
 [IO.File]::AppendAllText($path,"`n"+'{"type":"event_msg","payload":{"type":"task_complete"}}'+"`n"+'{"unfinished":')
 Assert ((Read-CodexSnapshot $path).Status -eq 'ready') 'completion plus partial trailing JSON'
 [IO.File]::AppendAllText($path,"`n"+'{"type":"event_msg","payload":{"type":"turn_aborted"}}')
 Assert ((Read-CodexSnapshot $path).Status -eq 'paused') 'aborted turn'
 $tail=Read-SharedTail $path 128
 Assert ($tail.Length -le 128 -and $tail.Contains('turn_aborted')) 'bounded tail'
 Assert (@(Find-CodexSessions $temp).Count -eq 0) 'missing sessions directory'
} finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue; [IO.Directory]::Delete($temp) }
