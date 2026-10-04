function Read-SharedTail([string]$Path, [int]$Limit = 524288) {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $start = [Math]::Max(0, $fs.Length - $Limit)
        [void]$fs.Seek($start, [IO.SeekOrigin]::Begin)
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $text = $sr.ReadToEnd()
        if ($start -gt 0) { $text = $text.Substring($text.IndexOf("`n") + 1) }
        return $text
    } finally { $fs.Dispose() }
}

function New-CodexSnapshot {
    [pscustomobject]@{ Path=''; Id=''; Cwd=''; Status='waiting'; Model='Codex'; Total=0L; Context=0L; Window=0L; Updated=$null; UsageKnown=$false }
}

function Read-CodexSnapshot([string]$Path) {
    $s = New-CodexSnapshot
    $s.Path = $Path
    $s.Status = 'unknown'
    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $s.Updated = $file.LastWriteTime
    $s.Id = $file.BaseName
    # Read only a bounded header and tail; never load a complete conversation.
    $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try {
        $buffer = New-Object byte[] 8192
        $count = $fs.Read($buffer, 0, $buffer.Length)
        $head = [Text.Encoding]::UTF8.GetString($buffer, 0, $count)
        foreach ($key in @('id','cwd')) {
            $m = [regex]::Match($head, ('"' + $key + '"\s*:\s*("(?:\\.|[^"\\])*")'))
            if ($m.Success) { $s.$key = $m.Groups[1].Value | ConvertFrom-Json }
        }
    } finally { $fs.Dispose() }
    foreach ($line in (Read-SharedTail $Path).Split("`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -notmatch '"type"\s*:\s*"(event_msg|turn_context)"') { continue }
        try { $j = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $p = $j.payload
        if ($j.type -eq 'turn_context') {
            if($p.model) { $s.Model = $p.model }
            if($p.cwd) { $s.Cwd = $p.cwd }
        }
        if ($j.type -ne 'event_msg') { continue }
        switch ($p.type) {
            'task_started' { $s.Status='working' }
            'task_complete' { $s.Status='ready' }
            'turn_aborted' { $s.Status='paused' }
            'token_count' {
                if ($p.info) {
                    $s.Total = [long]$p.info.total_token_usage.total_tokens
                    $s.Context = [long]$p.info.last_token_usage.total_tokens
                    $s.Window = [long]$p.info.model_context_window
                    $s.UsageKnown = $true
                }
            }
            'agent_message' { if ($p.phase -eq 'final_answer') { $s.Status='ready' } }
        }
    }
    # A recent write alone is not evidence of generation. Unknown state stays unknown.
    if ($s.Status -eq 'working' -and ((Get-Date)-$s.Updated).TotalMinutes -gt 10) { $s.Status='unknown' }
    return $s
}

function Find-CodexSessions([string]$CodexHome) {
    if ('CodexPet.SessionCatalog' -as [type]) {
        try {
            $catalog=[CodexPet.SessionCatalog]::Read($CodexHome) | ConvertFrom-Json
            if($catalog.Count) {foreach($session in $catalog) {Write-Output $session};return}
        } catch { }
    }
    $root = Join-Path $CodexHome 'sessions'
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    $files = @()
    foreach ($day in @((Get-Date), (Get-Date).AddDays(-1))) {
        $dir = Join-Path $root ($day.ToString('yyyy\MM\dd'))
        if (Test-Path -LiteralPath $dir) { $files += @(Get-ChildItem -LiteralPath $dir -Filter '*.jsonl' -File) }
    }
    if ($files.Count -eq 0) { $files = @(Get-ChildItem -LiteralPath $root -Filter '*.jsonl' -File -Recurse) }
    return @($files | Sort-Object LastWriteTime -Descending | Select-Object -First 12)
}
