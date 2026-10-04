param([string]$Version='2.6.1')
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'){throw 'Invalid version'}
$root=Split-Path $PSScriptRoot
$archive=Join-Path $root ('dist\codex-pet-'+$Version+'-windows.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Assert($ok,$name){if(-not $ok){throw $name};Write-Output ('PASS '+$name)}
$zip=[IO.Compression.ZipFile]::OpenRead($archive)
try {
    $names=@($zip.Entries|ForEach-Object {$_.FullName.Replace('\','/')})
    Assert (@($names|Where-Object {$_ -match '(^|/)(\.\.|state|dist|\.git|\.github)/|(^|/)(follow\.config\.json|auth\.json|\.env(?:\..*)?)$|\.(sqlite(?:-wal|-shm)?|log|pem|key|zip)$|:'}).Count -eq 0) 'archive excludes private runtime state and unsafe paths'
    foreach($required in @('start-pet.cmd','CodexPet.ps1','ModelUsage.cs','SessionCatalog.cs','HistoryUsage.cs','assets/animations.json','pet.config.example.json','pet.config.json','LICENSE','VERSION')) {
        Assert ($names -contains $required) ('runtime entry included: '+$required)
    }
    $entry=$zip.Entries|Where-Object FullName -eq 'pet.config.json'
    $reader=[IO.StreamReader]::new($entry.Open());try{$config=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
    Assert (-not $config.codexHome -and -not $config.pinnedPath -and $config.left -eq -1 -and $config.top -eq -1) 'bundled configuration contains no local paths or position'
    $entry=$zip.Entries|Where-Object FullName -eq 'VERSION'
    $reader=[IO.StreamReader]::new($entry.Open());try{$packVersion=$reader.ReadToEnd().Trim()}finally{$reader.Dispose()}
    Assert ($packVersion -eq $Version) 'archive version matches requested release'
}finally{$zip.Dispose()}
$hash=(Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower()
$expected=([IO.File]::ReadAllText($archive+'.sha256') -split '\s+')[0]
Assert ($hash -eq $expected) 'archive SHA256 matches checksum file'
$extract=Join-Path $root ('dist\package-check-'+[guid]::NewGuid().ToString('N'))
[IO.Compression.ZipFile]::ExtractToDirectory($archive,$extract)
$ps=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
foreach($mode in @(@('-Preview','-ExpandedPreview','-Language','en-US'),@('-SmokeSeconds','2'))) {
    $result=& $ps -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $extract 'CodexPet.ps1') @mode 2>&1
    if($LASTEXITCODE -ne 0){throw ($result -join "`n")}
    Assert ($true) ('extracted package runs '+$mode[0])
}
Write-Output ('Package inspection files: '+$extract)
