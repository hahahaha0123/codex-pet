$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path $root 'CodexPet.Language.ps1')
Import-PetLanguages (Join-Path $root 'locales')
function Assert($value,$name){if(-not $value){throw $name};Write-Output ('PASS '+$name)}
$keys=@($script:LanguagePacks['zh-CN'].Strings.Keys|Sort-Object)
$window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'pet-view.xaml')))
$ui=@{};foreach($name in @('ContextLabel','TpsLabel','CurrentLabel','TotalLabel','ModelDetails','Speech','Project','CurrentCost','TotalCost','UsageScope')){$ui[$name]=$window.FindName($name)}
$cfg=[pscustomobject]@{language='zh-CN'}
$ui.Project.Text='桌宠 · 用户会话'
$menu=[Windows.Controls.ContextMenu]::new();$menu.Resources.MergedDictionaries.Add($window.Resources)
$item=[Windows.Controls.MenuItem]::new();$script:MenuTextKeys[$item]='feed';[void]$menu.Items.Add($item)
$script:speechKey='poke1';$script:speechUntil=(Get-Date).AddMinutes(1)
foreach($code in @('zh-CN','zh-TW','en-US','ja-JP')) {
 $pack=$script:LanguagePacks[$code].Strings
 Assert (@(Compare-Object $keys @($pack.Keys|Sort-Object)).Count -eq 0) ($code+' complete translation keys')
 foreach($key in $keys) {
  Assert ($pack[$key].Length -gt 0) ($code+' '+$key+' nonempty')
  $a=@([regex]::Matches($pack[$key],'\{\d+(?::[^}]+)?\}')|ForEach-Object Value|Sort-Object)
  $b=@([regex]::Matches($script:LanguagePacks['zh-CN'].Strings[$key],'\{\d+(?::[^}]+)?\}')|ForEach-Object Value|Sort-Object)
  if(@(Compare-Object $a $b).Count){throw ($code+' placeholder mismatch: '+$key)}
 }
 $cfg.language=$code;Apply-PetLanguage
 Assert ($ui.ContextLabel.Text -eq $pack.context -and $item.Header -eq $pack.feed -and $ui.Speech.Text -eq $pack.poke1) ($code+' labels menus and active dialogue update')
 Assert ($ui.Project.Text -eq '桌宠 · 用户会话') ($code+' user project data preserved')
 $tip=Get-PetString 'tps_tip' @(12345,2.5)
 Assert ($tip -notmatch '\{\d' -and $tip.Contains('12,345')) ($code+' numeric placeholders formatted')
}
Select-PetLanguage 'invalid-code';Assert ($script:PetLanguage -eq 'zh-CN') 'invalid setting falls back to simplified Chinese'
Select-PetLanguage 'auto';Assert ($script:LanguagePacks.ContainsKey($script:PetLanguage)) 'system language resolves to a supported pack'
Write-Output 'PASS all language checks'
