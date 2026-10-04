param([switch]$Install,[switch]$Enable,[switch]$Disable,[switch]$Probe,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
$state=Join-Path $root 'state';[void][IO.Directory]::CreateDirectory($state)
$settings=Join-Path $root 'follow.config.json'
$shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'CodexPet-FollowCodex.lnk'
$stop=Join-Path $state 'follow-stop.signal'
function Get-CodexWindow {
 foreach($p in @(Get-Process -Name ChatGPT,Codex -ErrorAction SilentlyContinue)) {
  try {
   if($p.MainWindowHandle -eq 0) {continue}
   if($p.Path -match '\\OpenAI\.Codex_[^\\]+\\app\\ChatGPT\.exe$' -or $p.Path -match '\\(?:Programs\\)?Codex\\Codex\.exe$') {
    return [string]$p.Id+':'+[string]$p.MainWindowHandle
   }
  } catch {}
 }
 return ''
}
function Test-PetRunning {
 try {$m=[Threading.Mutex]::OpenExisting('Local\CodexPetXiaoKe');$m.Dispose();return $true} catch {return $false}
}
function Get-FollowEnabled {
 if(-not (Test-Path -LiteralPath $settings)) {return $true}
 try {return [bool]([IO.File]::ReadAllText($settings)|ConvertFrom-Json).enabled} catch {return $false}
}
function Set-FollowEnabled([bool]$enabled) {[IO.File]::WriteAllText($settings,([pscustomobject]@{enabled=$enabled}|ConvertTo-Json),[Text.Encoding]::UTF8)}
function Test-ShouldLaunch([string]$previous,[string]$current,[bool]$petRunning) {return ($current -ne '' -and $current -ne $previous -and -not $petRunning)}
if($SelfTest) {
 $cases=@(
  @{Previous='';Current='100:200';Running=$false;Expected=$true;Name='new app opens pet'},
  @{Previous='100:200';Current='100:200';Running=$false;Expected=$false;Name='manual pet close stays closed'},
  @{Previous='';Current='100:200';Running=$true;Expected=$false;Name='existing pet is not duplicated'},
  @{Previous='100:200';Current='';Running=$false;Expected=$false;Name='closed app does not launch'},
  @{Previous='100:200';Current='101:300';Running=$false;Expected=$true;Name='reopened app launches again'}
 )
 foreach($case in $cases) {if((Test-ShouldLaunch $case.Previous $case.Current $case.Running) -ne $case.Expected) {throw $case.Name};Write-Output ('PASS '+$case.Name)}
 exit
}
if($Probe) {[pscustomobject]@{CodexWindow=(Get-CodexWindow);PetRunning=(Test-PetRunning);Enabled=(Get-FollowEnabled);Registered=(Test-Path -LiteralPath $shortcut)}|ConvertTo-Json;exit}
if($Disable) {
 Set-FollowEnabled $false
 if(Test-Path -LiteralPath $shortcut) {Remove-Item -LiteralPath $shortcut}
 [IO.File]::WriteAllText($stop,'stop');exit
}
if($Enable) {Set-FollowEnabled $true}
if(-not (Get-FollowEnabled)) {exit}
if($Install -or $Enable) {
 $oldShortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'CodexPet-XiaoKe.lnk'
 if(Test-Path -LiteralPath $oldShortcut) {Remove-Item -LiteralPath $oldShortcut}
 $shell=New-Object -ComObject WScript.Shell;$link=$shell.CreateShortcut($shortcut)
 $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
 $link.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'CodexPet.Follow.ps1')+'"'
 $link.WorkingDirectory=$root;$link.WindowStyle=7;$link.Description='Open desktop pet when the Codex desktop window opens';$link.Save()
}
$created=$false;$mutex=[Threading.Mutex]::new($true,'Local\CodexPetFollowCodex',[ref]$created)
if(-not $created) {$mutex.Dispose();exit}
if(Test-Path -LiteralPath $stop) {Remove-Item -LiteralPath $stop}
[IO.File]::WriteAllText((Join-Path $state 'follow.pid'),[string]$PID)
$lastWindow=''
try {
 while((Get-FollowEnabled) -and -not (Test-Path -LiteralPath $stop)) {
  $window=Get-CodexWindow
  # React only to a new app window. Closing the pet manually does not respawn it.
  if(Test-ShouldLaunch $lastWindow $window (Test-PetRunning)) {
   $child=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'CodexPet.ps1')+'"') -WindowStyle Hidden -PassThru
   [IO.File]::WriteAllText((Join-Path $state 'launched.pid'),[string]$child.Id)
  }
  $lastWindow=$window
  [IO.File]::WriteAllText((Join-Path $state 'follow-state.json'),([pscustomobject]@{CodexWindow=$window;PetRunning=(Test-PetRunning);Enabled=$true;Updated=(Get-Date -Format o)}|ConvertTo-Json),[Text.Encoding]::UTF8)
  Start-Sleep -Seconds 3
 }
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
