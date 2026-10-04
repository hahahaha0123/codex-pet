param([string]$Version='2.6.0')
$ErrorActionPreference='Stop'
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
    foreach($path in $files) {
        if($path -match '^\.github/') {continue}
        $destination=Join-Path $stage $path
        [void][IO.Directory]::CreateDirectory((Split-Path $destination))
        Copy-Item -LiteralPath (Join-Path $root $path) -Destination $destination
    }
    Copy-Item -LiteralPath (Join-Path $stage 'pet.config.example.json') -Destination (Join-Path $stage 'pet.config.json')
    $archive=Join-Path $dist ('codex-pet-'+$Version+'-windows.zip')
    Compress-Archive -LiteralPath (Get-ChildItem -LiteralPath $stage -Force).FullName -DestinationPath $archive -Force
    Get-FileHash -LiteralPath $archive -Algorithm SHA256 | ForEach-Object {Write-Output ($_.Hash.ToLower()+'  '+(Split-Path $_.Path -Leaf))} | Set-Content -LiteralPath ($archive+'.sha256') -Encoding ASCII
    Write-Output $archive
} finally {Pop-Location}
