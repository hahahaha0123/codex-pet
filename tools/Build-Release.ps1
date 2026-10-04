param([string]$Version='2.6.1')
$ErrorActionPreference='Stop'
if($Version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$'){throw 'Version must be a semantic version such as 2.6.1.'}
$root=Split-Path $PSScriptRoot
$dist=Join-Path $root 'dist';[void][IO.Directory]::CreateDirectory($dist)
$stage=Join-Path $dist ('stage-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($stage)
Push-Location $root
try {
    $gitStart=[Diagnostics.ProcessStartInfo]::new('git.exe','-c core.quotepath=false ls-files -z')
    $gitStart.WorkingDirectory=$root;$gitStart.UseShellExecute=$false;$gitStart.RedirectStandardOutput=$true;$gitStart.StandardOutputEncoding=[Text.Encoding]::UTF8;$gitStart.CreateNoWindow=$true
    $gitProcess=[Diagnostics.Process]::Start($gitStart);$listing=$gitProcess.StandardOutput.ReadToEnd();$gitProcess.WaitForExit()
    $files=@($listing.Split([char]0)|Where-Object {$_})
    if($gitProcess.ExitCode -ne 0 -or -not $files.Count){throw 'Stage the project files in Git before building a release.'}
    $privateFiles=@($files|Where-Object {$_ -match '(^|/)(state|dist|\.git)/|(^|/)(pet\.config\.json|follow\.config\.json|auth\.json|\.env(?:\..*)?)$|\.(sqlite(?:-wal|-shm)?|log|pem|key|zip)$'})
    if($privateFiles.Count){throw ('Refusing to package local or sensitive files: '+($privateFiles -join ', '))}
    foreach($path in $files) {
        if($path -match '^\.github/') {continue}
        $destination=Join-Path $stage $path
        [void][IO.Directory]::CreateDirectory((Split-Path $destination))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
    }
    Copy-Item -LiteralPath (Join-Path $stage 'pet.config.example.json') -Destination (Join-Path $stage 'pet.config.json')
    foreach($required in @('start-pet.cmd','stop-pet.cmd','CodexPet.ps1','CodexPet.Data.ps1','CodexPet.Language.ps1','CodexPet.Layout.ps1','CodexPet.Follow.ps1','ModelUsage.cs','SessionCatalog.cs','HistoryUsage.cs','pet-view.xaml','LICENSE','api-prices.json','assets/animations.json')) {
        if(-not (Test-Path -LiteralPath (Join-Path $stage $required))){throw ('Missing release runtime file: '+$required)}
    }
    foreach($clip in (Get-Content -LiteralPath (Join-Path $stage 'assets/animations.json') -Raw -Encoding UTF8|ConvertFrom-Json)) {
        if(-not (Test-Path -LiteralPath (Join-Path $stage $clip.file))){throw ('Missing animation: '+$clip.file)}
    }
    [IO.File]::WriteAllText((Join-Path $stage 'VERSION'),$Version+"`n",[Text.Encoding]::ASCII)
    $archive=Join-Path $dist ('codex-pet-'+$Version+'-windows.zip')
    Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -Force).FullName -DestinationPath $archive -Force
    Get-FileHash -LiteralPath $archive -Algorithm SHA256 | ForEach-Object {Write-Output ($_.Hash.ToLower()+'  '+(Split-Path $_.Path -Leaf))} | Set-Content -LiteralPath ($archive+'.sha256') -Encoding ASCII
    Write-Output $archive
} finally {Pop-Location}
