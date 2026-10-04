param([switch]$Animation)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
$temp=Join-Path $env:TEMP ('codex-pet-diagnostics-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
function Assert($ok,$message) {if(-not $ok){throw $message};Write-Output ('PASS '+$message)}
$mutex=$null
try {
    foreach($name in @('CodexPet.ps1','CodexPet.Data.ps1','CodexPet.Language.ps1','CodexPet.Layout.ps1','ModelUsage.cs','SessionCatalog.cs','HistoryUsage.cs','api-prices.json','pet.config.example.json','pet-view.xaml')) {
        Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $temp $name)
    }
    foreach($name in @('locales','GIF动作')) {Copy-Item -LiteralPath (Join-Path $root $name) -Destination (Join-Path $temp $name) -Recurse}
    [void][IO.Directory]::CreateDirectory((Join-Path $temp 'assets'))
    Copy-Item -LiteralPath (Join-Path $root 'assets\animations.json') -Destination (Join-Path $temp 'assets\animations.json')
    $config=Join-Path $temp 'pet.config.json';[IO.File]::WriteAllText($config,'{"codexHome":"DO-NOT-READ","language":"ja-JP","pinnedPath":"DO-NOT-READ"}')
    $state=Join-Path $temp 'state';[void][IO.Directory]::CreateDirectory($state)
    $signal=Join-Path $state 'stop.signal';[IO.File]::WriteAllText($signal,'preserve-stop-signal')
    $before=(Get-FileHash -LiteralPath $config).Hash
    $created=$false;$mutex=[Threading.Mutex]::new($false,'Local\CodexPetXiaoKe',[ref]$created)
    $ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $modes=@(@('-Preview','-ExpandedPreview','-Language','en-US'),@('-SmokeSeconds','2'))
    if($Animation){$modes+=,@('-AnimationCheck')}
    foreach($mode in $modes) {
        $lines=& $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $temp 'CodexPet.ps1') @mode 2>&1
        if($LASTEXITCODE -ne 0){throw ($lines -join "`n")}
        Assert ((Get-FileHash -LiteralPath $config).Hash -eq $before) ($mode[0]+' leaves local preferences unchanged')
        Assert ([IO.File]::ReadAllText($signal) -eq 'preserve-stop-signal') ($mode[0]+' preserves normal stop signal')
        Assert (@(Get-ChildItem -LiteralPath $state -File).Count -eq 1) ($mode[0]+' never writes normal runtime state')
        $other=[Threading.Mutex]::OpenExisting('Local\CodexPetXiaoKe');$other.Dispose()
        Assert ($true) ($mode[0]+' keeps the normal instance mutex intact')
    }
    $runs=Join-Path $temp 'dist\checks\runs'
    $smoke=Get-ChildItem -LiteralPath $runs -Filter pet.log -Recurse | Where-Object {([IO.File]::ReadAllText($_.FullName)).Contains('smoke: 3 synthetic sessions')}
    Assert (@($smoke).Count -eq 1) 'smoke exercises three synthetic sessions'
    Assert (@(Get-ChildItem -LiteralPath $runs -Filter '*.png' -Recurse).Count -eq 1) 'preview written only to diagnostic output'
    if($Animation) {
        $report=Get-ChildItem -LiteralPath $runs -Filter animation-check.json -Recurse | Select-Object -First 1
        $results=[IO.File]::ReadAllText($report.FullName)|ConvertFrom-Json
        Assert ($results.Count -eq 16 -and @($results|Where-Object {-not $_.Passed}).Count -eq 0) 'all 16 animations display all six frames'
    }
} finally {
    if($mutex){$mutex.Dispose()}
    $resolved=[IO.Path]::GetFullPath($temp);$prefix=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\codex-pet-diagnostics-'
    if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
