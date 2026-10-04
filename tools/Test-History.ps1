$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -Path (Join-Path $root 'ModelUsage.cs'),(Join-Path $root 'SessionCatalog.cs'),(Join-Path $root 'HistoryUsage.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
function Assert($value,$name){if(-not $value){throw $name};Write-Output ('PASS '+$name)}
function Event([string]$type,$payload,[string]$timestamp='2026-10-01T00:00:00Z'){[ordered]@{timestamp=$timestamp;type=$type;payload=$payload}|ConvertTo-Json -Depth 9 -Compress}
function Usage([long]$inputCount,[long]$outputCount){Event 'event_msg' @{type='token_count';info=@{total_token_usage=@{input_tokens=$inputCount;cached_input_tokens=0;cache_write_input_tokens=0;output_tokens=$outputCount;total_tokens=($inputCount+$outputCount)};last_token_usage=@{input_tokens=$inputCount;total_tokens=($inputCount+$outputCount)};model_context_window=1000000}}}
$temp=Join-Path $env:TEMP ('codex-history-'+[guid]::NewGuid())
[void][IO.Directory]::CreateDirectory((Join-Path $temp 'sessions'))
[void][IO.Directory]::CreateDirectory((Join-Path $temp 'archived_sessions'))
$parent='00000000-0000-7000-8000-000000000001';$child='00000000-0000-7000-8000-000000000002'
$parentPath=Join-Path $temp ('sessions\rollout-'+$parent+'.jsonl');$childPath=Join-Path $temp ('archived_sessions\rollout-'+$child+'.jsonl');$cache=Join-Path $temp 'history.json'
$history=$null;$owner=[CodexPet.ModelUsage]::new((Join-Path $root 'api-prices.json'))
try {
 $oldStart=1790812800;$newStart=$oldStart+60
 $context=Event 'turn_context' @{model='gpt-6-sol'}
 $parentRows=@((Event 'session_meta' @{id=$parent;timestamp='2026-10-01T00:00:00Z'}),$context,(Event 'event_msg' @{type='task_started';turn_id='parent';started_at=$oldStart}),(Usage 1000 100),(Event 'event_msg' @{type='task_complete';turn_id='parent';duration_ms=10000} '2026-10-01T00:00:10Z'))
 [IO.File]::WriteAllText($parentPath,($parentRows -join "`n")+"`n")
 $childRows=@((Event 'session_meta' @{id=$child;forked_from_id=$parent;timestamp='2026-10-01T00:01:00Z'}),$context,(Event 'event_msg' @{type='task_started';turn_id='parent';started_at=$oldStart} '2026-10-01T00:01:00Z'),(Usage 1000 100),(Event 'event_msg' @{type='task_complete';turn_id='parent';duration_ms=10000}),(Event 'event_msg' @{type='task_started';turn_id='child';started_at=$newStart}),(Usage 1300 150),(Event 'event_msg' @{type='task_complete';turn_id='child';duration_ms=10000} '2026-10-01T00:01:10Z'))
 [IO.File]::WriteAllText($childPath,($childRows -join "`n")+"`n")
 $s=$owner.ParseFixture($parentPath)|ConvertFrom-Json
 Assert ($s.TaskOutput -eq 100 -and [math]::Abs($s.TaskTps-10) -lt .0001) 'task output / completed duration'
 $s=$owner.ParseFixture($childPath)|ConvertFrom-Json
 Assert ($s.Total -eq 350 -and $s.TaskOutput -eq 50 -and $s.TaskTps -eq 5) 'fork replay skipped, inherited cumulative baseline retained'
 $history=[CodexPet.HistoryUsage]::new($temp,(Join-Path $root 'api-prices.json'),$cache);$history.ScanOnce();$s=$history.Snapshot()|ConvertFrom-Json
 Assert ($s.Total -eq 1450 -and $s.Sources -eq 2) 'history includes active and archived without replay duplicate'
 $history.Dispose();$history=[CodexPet.HistoryUsage]::new($temp,(Join-Path $root 'api-prices.json'),$cache)
 Assert (($history.Snapshot()|ConvertFrom-Json).Total -eq 1450) 'cached historical total available before rescanning'
 $history.ScanOnce();$s=$history.Snapshot()|ConvertFrom-Json
 Assert ($s.Total -eq 1450) 'persistent cache reload does not count again'
 [IO.File]::AppendAllText($childPath,(Usage 1400 175)+"`n");$history.ScanOnce();$s=$history.Snapshot()|ConvertFrom-Json
 Assert ($s.Total -eq 1575) 'new appended usage added only as delta'
 $childRows[0]=Event 'session_meta' @{id=$parent;timestamp='2026-10-01T00:01:00Z'}
 [IO.File]::WriteAllText($childPath,($childRows -join "`n")+"`n"+(Usage 1400 175)+"`n")
 $history.ScanOnce();$s=$history.Snapshot()|ConvertFrom-Json
 Assert ($s.Total -eq 1575) 'legacy fork with inherited metadata id excludes old replay'
 $duplicate=Join-Path $temp ('archived_sessions\copy-'+$parent+'.jsonl');Copy-Item -LiteralPath $parentPath -Destination $duplicate
 $history.ScanOnce();$s=$history.Snapshot()|ConvertFrom-Json
 Assert ($s.Total -eq 1575 -and $s.Sources -eq 2) 'duplicate physical file with same session id counted once'
 $global=[ordered]@{'local-projects'=@{p=@{name='桌宠';rootPaths=@('F:\巴菲特游戏')}};'thread-project-assignments'=@{t=@{projectId='p';projectKind='local'}}}
 $globalPath=Join-Path $temp '.codex-global-state.json';[IO.File]::WriteAllText($globalPath,($global|ConvertTo-Json -Depth 8),[Text.Encoding]::UTF8)
 Assert ([CodexPet.SessionCatalog]::ProjectName($temp,'t','F:\巴菲特游戏') -eq '桌宠') 'saved project label used instead of folder leaf'
 $global['local-projects'].p.name='新桌宠';[IO.File]::WriteAllText($globalPath,($global|ConvertTo-Json -Depth 8),[Text.Encoding]::UTF8)
 Assert ([CodexPet.SessionCatalog]::ProjectName($temp,'t','F:\巴菲特游戏') -eq '新桌宠') 'project rename reloaded without stale cache'
 Assert ([CodexPet.SessionCatalog]::ProjectName($temp,'other','F:\巴菲特游戏\codex-pet') -eq '新桌宠') 'project root fallback works for nested working directory'
} finally {
 if($history){$history.Dispose()};$owner.Dispose()
 $resolved=[IO.Path]::GetFullPath($temp);$safePrefix=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\codex-history-'
 if(-not $resolved.StartsWith($safePrefix,[StringComparison]::OrdinalIgnoreCase)){throw 'unsafe temporary cleanup path'}
 Remove-Item -LiteralPath $resolved -Recurse -Force
}
