param([switch]$Preview, [switch]$ExpandedPreview, [switch]$AnimationCheck, [int]$SmokeSeconds = 0, [string]$Language)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$isDiagnostic = $Preview -or $AnimationCheck -or $SmokeSeconds -gt 0
$diagnosticRoot = if($isDiagnostic) {Join-Path $root ('dist\checks\runs\'+[guid]::NewGuid().ToString('N'))} else {$null}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -Path (Join-Path $root 'ModelUsage.cs'),(Join-Path $root 'SessionCatalog.cs'),(Join-Path $root 'HistoryUsage.cs') -ReferencedAssemblies System.Web.Extensions,System.Core
. (Join-Path $root 'CodexPet.Data.ps1')
. (Join-Path $root 'CodexPet.Layout.ps1')
. (Join-Path $root 'CodexPet.Language.ps1')
Import-PetLanguages (Join-Path $root 'locales')
$stateDir = if($isDiagnostic) {Join-Path $diagnosticRoot 'state'} else {Join-Path $root 'state'}
[void][IO.Directory]::CreateDirectory($stateDir)
$log = Join-Path $stateDir 'pet.log'
function Write-Log([string]$message) { Add-Content -LiteralPath $log -Encoding UTF8 -Value ((Get-Date -Format s) + ' ' + $message) }
try {
$cfgPath=if($isDiagnostic) {Join-Path $diagnosticRoot 'pet.config.json'} else {Join-Path $root 'pet.config.json'}
if(-not (Test-Path -LiteralPath $cfgPath)) {Copy-Item -LiteralPath (Join-Path $root 'pet.config.example.json') -Destination $cfgPath}
$cfg=Get-Content -LiteralPath $cfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
if(-not $cfg.PSObject.Properties['scale']) {Add-Member -InputObject $cfg -NotePropertyName scale -NotePropertyValue .8}
if(-not $cfg.PSObject.Properties['language']) {Add-Member -InputObject $cfg -NotePropertyName language -NotePropertyValue 'zh-CN'}
if($Language){$cfg.language=$Language}
if($cfg.language -ne 'auto' -and -not $script:LanguagePacks.ContainsKey($cfg.language)){$cfg.language='zh-CN'}
Select-PetLanguage $cfg.language
if (-not $cfg.codexHome) { $cfg.codexHome=Join-Path $env:USERPROFILE '.codex' }
if($isDiagnostic) {
    $cfg.codexHome=Join-Path $diagnosticRoot 'codex-home';$cfg.pinnedPath=''
    [void][IO.Directory]::CreateDirectory($cfg.codexHome)
    if($SmokeSeconds -gt 0) {
        $fixtureDir=Join-Path $cfg.codexHome ('sessions\'+(Get-Date -Format 'yyyy\MM\dd'))
        [void][IO.Directory]::CreateDirectory($fixtureDir)
        foreach($number in 1..3) {
            $id='00000000-0000-7000-8000-'+$number.ToString('000000000000')
            $rows=@(
                @{type='session_meta';payload=@{id=$id;cwd=('C:\CodexPetFixture\Project'+$number)}},
                @{type='turn_context';payload=@{model='gpt-6-sol'}},
                @{type='event_msg';payload=@{type='task_complete'}}
            ) | ForEach-Object {$_|ConvertTo-Json -Depth 6 -Compress}
            [IO.File]::WriteAllText((Join-Path $fixtureDir ('rollout-'+$id+'.jsonl')),($rows -join "`n")+"`n",[Text.Encoding]::UTF8)
        }
    }
}
$created=$false
$mutexName=if($isDiagnostic){'Local\CodexPetXiaoKe.Check.'+[guid]::NewGuid().ToString('N')}else{'Local\CodexPetXiaoKe'}
$mutex=New-Object Threading.Mutex($true,$mutexName,[ref]$created)
if (-not $created -and -not $Preview -and -not $AnimationCheck -and $SmokeSeconds -eq 0) { exit }
$stopPath=Join-Path $stateDir 'stop.signal'
if (Test-Path -LiteralPath $stopPath) { Remove-Item -LiteralPath $stopPath }
$window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $root 'pet-view.xaml')))
$ui=@{}
foreach($name in @('DesktopRoot','Pet','PetScale','PetTilt','PetMove','Sprite','Bubble','Speech','CardFrame','CardShadow','Card','CardText','Status','Project','Tokens','ContextLabel','Context','TpsLabel','TaskTps','CurrentLabel','Model','CurrentCost','TotalToggle','TotalLabel','TotalTokens','TotalCost','DetailsScroll','ModelDetails','UsageScope')) { $ui[$name]=$window.FindName($name) }
$scale=[math]::Max(.2,[math]::Min(1.0,[double]$cfg.scale));Register-PetLayout $window.Content;Set-PetLayoutScale $scale
$poses=@{}
$clips=@{}
$manifestPath=Join-Path $root 'assets\animations.json'
if(-not (Test-Path -LiteralPath $manifestPath)) {throw 'GIF 动作清单缺失，请使用完整桌宠包。'}
if(Test-Path -LiteralPath $manifestPath) {
 foreach($entry in (Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json)) {
  $decoder=[Windows.Media.Imaging.GifBitmapDecoder]::new([Uri]::new((Join-Path $root $entry.file)),[Windows.Media.Imaging.BitmapCreateOptions]::PreservePixelFormat,[Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
  $frames=@($decoder.Frames);if($frames.Count -lt 2) {throw ('GIF 没有连续帧：'+$entry.label)};foreach($frame in $frames) {$frame.Freeze()}
  $clips[$entry.key]=[pscustomobject]@{Frames=$frames;Duration=$entry.durationMs;Label=$entry.label};$poses[$entry.key]=$frames[0]
 }
}
$usageWorker=[CodexPet.ModelUsage]::new((Join-Path $root 'api-prices.json'));$usageWorker.Start()
$historyWorker=$null
if(-not $Preview -and -not $AnimationCheck -and $SmokeSeconds -eq 0) {$historyWorker=[CodexPet.HistoryUsage]::new($cfg.codexHome,(Join-Path $root 'api-prices.json'),(Join-Path $stateDir 'history-cache.json'));$historyWorker.Start()}
$script:pose='greet';$ui.Sprite.Source=$poses.greet;$script:poseClock=[Diagnostics.Stopwatch]::StartNew()
$script:speechUntil=[datetime]::MinValue; $script:poseUntil=[datetime]::MinValue
$script:lastInteraction=Get-Date; $script:pokes=@(); $script:dragging=$false
$script:sequence=@();$script:sequenceStart=Get-Date;$script:playbackFrame=0
$script:snapshot=New-CodexSnapshot; $script:files=@(); $script:ticks=0; $script:frame=0
$script:lastPath=''; $script:lastWrite=[datetime]::MinValue; $script:previousStatus='waiting'
function Set-Pose([string]$name,[switch]$Restart) { if($clips.ContainsKey($name) -and ($script:pose -ne $name -or $Restart)) { $script:pose=$name;$script:poseClock.Restart();$script:playbackFrame=0;$ui.Sprite.Source=$poses[$name] } }
function Clear-PetModelDetails {
 foreach($child in $ui.ModelDetails.Children) {Unregister-PetLayout $child}
 $ui.ModelDetails.Children.Clear()
}
function Update-ModelUsage {
 $data=$usageWorker.Snapshot() | ConvertFrom-Json
 if($data.Path -ne $script:snapshot.Path -or $data.Error -or -not $data.Path) {$ui.Tokens.Text=Get-PetString 'reading';$ui.TaskTps.Text='— tok/s';$ui.CurrentCost.Text=Get-PetString 'estimate_unknown';return}
 $current=@($data.Models | Where-Object {$_.Model -eq $data.Model}) | Select-Object -First 1
 $ui.Model.Text=Get-PetModelName $data.Model;$ui.Model.ToolTip=$data.Model
 $ui.Tokens.Text=if($current){(Format-PetNumber $current.Total)+' tok'}else{'0 tok'}
 $ui.CurrentCost.Text=if($current -and $current.Priced){Get-PetString 'estimate' @((Format-PetNumber $current.Cost 'N4'))}elseif($current){Get-PetString 'unpriced'}else{Get-PetString 'estimate' @('0.0000')}
 $ui.TaskTps.Text=if($null -ne $data.TaskTps -and $data.TaskOutput -gt 0){(Format-PetNumber $data.TaskTps 'N1')+' tok/s'}else{'— tok/s'}
 $ui.TaskTps.ToolTip=Get-PetString 'tps_tip' @($data.TaskOutput,$data.TaskSeconds)
 if($data.Window -gt 0){$pct=100*$data.Context/$data.Window;$ui.Context.Text=(Format-PetNumber $pct 'N1')+'%'}
}
function Update-HistoryUsage {
 if(-not $historyWorker){return}
 $data=$historyWorker.Snapshot() | ConvertFrom-Json
 if($data.Error){$ui.UsageScope.Text=Get-PetString 'history_error';return}
 $ui.TotalTokens.Text=(Format-PetNumber $data.Total)+' tok'
 $ui.TotalCost.Text=Get-PetString $(if($data.Priced){'estimate'}else{'partial'}) @((Format-PetNumber $data.Cost 'N4'))
 $ui.UsageScope.Text=if($data.Loading){Get-PetString 'history_progress' @($data.Scanned,$data.Sources)}else{Get-PetString 'history_scope' @((Format-PetNumber $data.Sources))}
 $ui.UsageScope.ToolTip=Get-PetString 'history_tip' @($data.Missing,$data.Errors)
 [IO.File]::WriteAllText((Join-Path $stateDir 'history-summary.json'),($data|ConvertTo-Json -Depth 8),[Text.Encoding]::UTF8)
 Clear-PetModelDetails
 foreach($row in ($data.Models | Sort-Object Total -Descending)) {
  $block=[Windows.Controls.StackPanel]::new();$block.Margin=[Windows.Thickness]::new(0,0,0,10)
  $title=[Windows.Controls.TextBlock]::new();$title.Text=Get-PetModelName $row.Model;$title.FontSize=14;$title.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#BDE8D7');$title.TextTrimming='CharacterEllipsis';$title.ToolTip=$row.Model
  $value=[Windows.Controls.TextBlock]::new();$cost=if($row.Priced){Get-PetString 'estimate' @((Format-PetNumber $row.Cost 'N4'))}else{Get-PetString 'unpriced'};$value.Text=(Format-PetNumber $row.Total)+' tok  ·  '+$cost;$value.FontSize=14;$value.Foreground=[Windows.Media.Brushes]::LightGray;$value.TextWrapping='Wrap'
  $value.ToolTip=Get-PetString 'buckets_tip' @($row.Input,$row.Cached,$row.Writes,$row.Output)
  [void]$block.Children.Add($title);[void]$block.Children.Add($value);Register-PetLayout $block;[void]$ui.ModelDetails.Children.Add($block)
 }
}
function Say([string]$text,[string]$pose='shy',[int]$seconds=4) {
    $script:sequence=@()
    $script:speechKey=$text;$ui.Speech.Text=Get-PetString $text;$ui.Bubble.Visibility='Visible'
    $script:speechUntil=(Get-Date).AddSeconds($seconds); $script:poseUntil=$script:speechUntil
    $script:lastInteraction=Get-Date; Set-Pose $pose -Restart
}
function Say-Sequence([string]$text,[string[]]$actions) {
    Say $text $actions[0] ($actions.Count*3)
    $script:sequence=$actions;$script:sequenceStart=Get-Date
}
function Save-Config {
    if($isDiagnostic) {return}
    $cfg.left=$window.Left; $cfg.top=$window.Top; $cfg.topmost=$window.Topmost
    $cfg.collapsed=($ui.CardFrame.Visibility -eq 'Collapsed')
    [IO.File]::WriteAllText($cfgPath,($cfg | ConvertTo-Json), (New-Object Text.UTF8Encoding($true)))
}
function Toggle-Card { if($ui.CardFrame.Visibility -eq 'Visible') {$ui.CardFrame.Visibility='Collapsed'} else {$ui.CardFrame.Visibility='Visible'} }
function Refresh-Pet {
    try {
        $script:refreshFailed=$false
        $script:ticks++
        if($script:ticks%5 -eq 1 -or $script:files.Count -eq 0) { $script:files=@(Find-CodexSessions $cfg.codexHome) }
        $selected=$null
        if($cfg.pinnedPath -and (Test-Path -LiteralPath $cfg.pinnedPath)) { $selected=Get-Item -LiteralPath $cfg.pinnedPath }
        elseif($script:files.Count) { $selected=Get-Item -LiteralPath $script:files[0].FullName }
        if($selected) {
            if($selected.FullName -ne $script:lastPath -or $selected.LastWriteTime -ne $script:lastWrite) {
                $next=Read-CodexSnapshot $selected.FullName
                if($next.Path -eq $script:snapshot.Path) {
                    if(-not $next.UsageKnown) { $next.Total=$script:snapshot.Total; $next.Context=$script:snapshot.Context; $next.Window=$script:snapshot.Window; $next.UsageKnown=$script:snapshot.UsageKnown }
                    if($next.Status -eq 'unknown') { $next.Status=$script:snapshot.Status }
                    if($next.Model -eq 'Codex') { $next.Model=$script:snapshot.Model }
                }
                $metadata=$script:files | Where-Object {$_.FullName -eq $selected.FullName} | Select-Object -First 1
                if($metadata -and $metadata.Cwd) {$next.Cwd=$metadata.Cwd}
                if($metadata -and $metadata.Id) {$next.Id=$metadata.Id}
                $script:snapshot=$next; $script:lastPath=$selected.FullName; $script:lastWrite=$selected.LastWriteTime
            }
        } else { $script:snapshot=New-CodexSnapshot }
        $s=$script:snapshot
        if($s.Status -eq 'working' -and $s.Updated -and ((Get-Date)-$s.Updated).TotalMinutes -gt 10) {$s.Status='unknown'}
        $ui.Status.Text=Get-PetString $s.Status
        $meta=$script:files | Where-Object {$_.FullName -eq $s.Path} | Select-Object -First 1
        if($meta.Cwd){$s.Cwd=$meta.Cwd}
        $projectName=if($meta.ProjectName){$meta.ProjectName}elseif($s.Cwd){Split-Path $s.Cwd -Leaf}else{Get-PetString 'unknown_project'}
        $ui.Project.Text=$projectName+' · '+$meta.Title
        $ui.Project.ToolTip=Get-PetString 'project_tip' @($meta.ProjectRoot,$s.Cwd,$meta.Title,$s.Id)
        $usageWorker.Follow($s.Path)
        $ui.Context.Text='—'
        if($s.Window -gt 0) { $pct=100*$s.Context/$s.Window; $ui.Context.Text=(Format-PetNumber $pct 'N1')+'%' }
        $ui.Tokens.ToolTip=Get-PetString 'tokens_tip'
        $ui.Context.ToolTip=Get-PetString 'context_tip'
        $ui.Model.Text=Get-PetString 'reading_model';Update-ModelUsage;Update-HistoryUsage
        if($script:previousStatus -ne $s.Status) {
            if($s.Status -eq 'working') { Say 'start_work' 'stretch' }
            if($s.Status -eq 'ready' -and $script:previousStatus -eq 'working') { Say-Sequence 'finish_work' @('happy','laugh','bow') }
        }
        $script:previousStatus=$s.Status
        [IO.File]::WriteAllText((Join-Path $stateDir 'ui-state.json'),([pscustomobject]@{SessionId=$s.Id;Path=$s.Path;Project=$s.Cwd;Title=$meta.Title;ProjectName=$projectName;ProjectRoot=$meta.ProjectRoot;Model=$ui.Model.Text;TaskTps=$ui.TaskTps.Text;Current=$ui.Tokens.Text;Total=$ui.TotalTokens.Text;Scale=$cfg.scale;Language=$script:PetLanguage;LanguageSetting=$cfg.language;Clips=$clips.Count;Details=($ui.ModelDetails.Visibility -eq 'Visible')} | ConvertTo-Json),[Text.Encoding]::UTF8)
    } catch { Write-Log ('refresh: '+$_.Exception.Message); $script:refreshFailed=$true;$ui.Status.Text=Get-PetString 'read_error' }
}
$window.Topmost=[bool]$cfg.topmost
if($cfg.collapsed) {$ui.CardFrame.Visibility='Collapsed'}
$window.Add_SourceInitialized({
    $area=[Windows.SystemParameters]::WorkArea
    $left=[Windows.SystemParameters]::VirtualScreenLeft;$top=[Windows.SystemParameters]::VirtualScreenTop
    $window.Left=if($cfg.left -ge $left -and $cfg.left -lt $left+[Windows.SystemParameters]::VirtualScreenWidth-50) {$cfg.left} else {$area.Right-510}
    $window.Top=if($cfg.top -ge $top -and $cfg.top -lt $top+[Windows.SystemParameters]::VirtualScreenHeight-50) {$cfg.top} else {$area.Bottom-305}
})
$window.Add_MouseLeftButtonDown({
    param($sender,$e)
    if($e.ClickCount -eq 2) { Toggle-Card; return }
    $script:mouseDown=$e.GetPosition($window); $script:origin=New-Object Windows.Point($window.Left,$window.Top)
    $script:dragging=$false; [void]$window.CaptureMouse(); $script:lastInteraction=Get-Date
})
$window.Add_MouseMove({
    param($sender,$e)
    if($window.IsMouseCaptured -and $e.LeftButton -eq 'Pressed') {
        $p=$e.GetPosition($window); $dx=$p.X-$script:mouseDown.X; $dy=$p.Y-$script:mouseDown.Y
        if([math]::Abs($dx)+[math]::Abs($dy) -gt 5 -or $script:dragging) {
            $script:dragging=$true;$script:sequence=@();Set-Pose 'runRight';$window.Left+=$dx;$window.Top+=$dy
        }
    }
})
$window.Add_MouseLeftButtonUp({
    if(-not $window.IsMouseCaptured) {return}; $window.ReleaseMouseCapture()
    if($script:dragging) {
        $a=[Windows.SystemParameters]::VirtualScreenLeft; $b=[Windows.SystemParameters]::VirtualScreenTop
        $window.Left=[math]::Max($a,[math]::Min($window.Left,$a+[Windows.SystemParameters]::VirtualScreenWidth-$window.ActualWidth))
        $window.Top=[math]::Max($b,[math]::Min($window.Top,$b+[Windows.SystemParameters]::VirtualScreenHeight-$window.ActualHeight))
        Say 'moved' 'bow'; $script:dragging=$false
    } else {
        $now=Get-Date; $script:pokes=@($script:pokes | Where-Object {($now-$_).TotalSeconds -lt 3})+@($now)
        if($script:pokes.Count -ge 5) {Say 'angry_line' 'angry'}
        else { Say (@('poke1','poke2','poke3','poke4') | Get-Random) (@('shy','greet','surprise') | Get-Random) }
    }
})
$ui.Pet.Add_MouseEnter({$ui.PetScale.ScaleX=1.025; $ui.PetScale.ScaleY=1.025})
$ui.Pet.Add_MouseLeave({$ui.PetScale.ScaleX=1; $ui.PetScale.ScaleY=1})
$menu=New-Object Windows.Controls.ContextMenu
$menu.Resources.MergedDictionaries.Add($window.Resources)
$menu.Background=$window.Resources['SurfaceBackground'];$menu.Foreground=$window.Resources['SurfaceText'];$menu.BorderBrush=$window.Resources['SurfaceBorder']
$ui.TotalToggle.Add_PreviewMouseLeftButtonDown({param($sender,$e) $e.Handled=$true})
$ui.TotalToggle.Add_PreviewMouseLeftButtonUp({param($sender,$e)
 $e.Handled=$true
 if($ui.ModelDetails.Visibility -eq 'Collapsed') {$ui.ModelDetails.Visibility='Visible';$ui.DetailsScroll.Visibility='Visible';$ui.TotalLabel.Text=(Get-PetString 'history_total')+' ▴'} else {$ui.ModelDetails.Visibility='Collapsed';$ui.DetailsScroll.Visibility='Collapsed';$ui.TotalLabel.Text=(Get-PetString 'history_total')+' ▾'}
})
function Add-Menu([string]$label,[scriptblock]$action) {
    $item=New-Object Windows.Controls.MenuItem; $item.Header=Get-PetString $label;$script:MenuTextKeys[$item]=$label;$item.Add_Click($action); [void]$menu.Items.Add($item); return $item
}
$languageMenu=[Windows.Controls.MenuItem]::new();$languageMenu.Header=Get-PetString 'language';$script:MenuTextKeys[$languageMenu]='language';[void]$menu.Items.Add($languageMenu)
foreach($code in @('auto','zh-CN','zh-TW','en-US','ja-JP')) {
 $item=[Windows.Controls.MenuItem]::new();$item.Tag=$code;$item.IsCheckable=$true;$item.IsChecked=($cfg.language -eq $code)
 $item.Header=if($code -eq 'auto'){Get-PetString 'system_language'}else{$script:LanguagePacks[$code].Name}
 $item.Add_Click({param($sender,$e) $cfg.language=[string]$sender.Tag;Apply-PetLanguage;Refresh-Pet;if(-not $Preview -and -not $AnimationCheck -and $SmokeSeconds -eq 0){Save-Config}})
 [void]$languageMenu.Items.Add($item)
}
[void](Add-Menu 'feed'  {Say-Sequence 'fed' @('happy','laugh','hug')})
[void](Add-Menu 'rest' {Say 'resting' 'sleep' 30})
$actionMenu=[Windows.Controls.MenuItem]::new();$actionMenu.Header=Get-PetString 'actions';$script:MenuTextKeys[$actionMenu]='actions';[void]$menu.Items.Add($actionMenu)
foreach($key in ($clips.Keys | Sort-Object)) {
 $item=[Windows.Controls.MenuItem]::new();$item.Header=Get-PetString ('action_'+$key);$script:MenuTextKeys[$item]='action_'+$key;$item.Tag=$key
 $item.Add_Click({param($sender,$e) Say ('action_'+$sender.Tag) $sender.Tag 8});[void]$actionMenu.Items.Add($item)
}
$scaleItem=[Windows.Controls.MenuItem]::new();$scaleItem.StaysOpenOnClick=$true
$scalePanel=[Windows.Controls.StackPanel]::new();$scalePanel.Orientation='Horizontal'
$scaleTitle=[Windows.Controls.TextBlock]::new();$scaleTitle.Text=(Get-PetString 'scale')+'  ';$scaleTitle.VerticalAlignment='Center';[void]$scalePanel.Children.Add($scaleTitle)
$scaleInput=[Windows.Controls.TextBox]::new();$scaleInput.Width=50;$scaleInput.MaxLength=3;$scaleInput.Text=[string][int]($scale*100);$scaleInput.HorizontalContentAlignment='Center'
$scaleInput.Background=$window.Resources['SurfaceBackground'];$scaleInput.Foreground=$window.Resources['SurfaceText'];$scaleInput.BorderBrush=$window.Resources['SurfaceBorder']
$scaleInput.ToolTip=Get-PetString 'scale_tip'
$scaleInput.Add_PreviewTextInput({param($sender,$e) $e.Handled=($e.Text -notmatch '^\d+$')})
$scaleInput.Add_LostKeyboardFocus({
 $value=0;if([int]::TryParse($scaleInput.Text,[ref]$value) -and $value -ge 20 -and $value -le 100) {$cfg.scale=$value/100;Set-PetLayoutScale $cfg.scale} else {$scaleInput.Text=[string][int]($cfg.scale*100)}
})
$scaleInput.Add_KeyDown({param($sender,$e)
 if($e.Key -eq 'Enter') {$value=0;if([int]::TryParse($scaleInput.Text,[ref]$value) -and $value -ge 20 -and $value -le 100) {$cfg.scale=$value/100;Set-PetLayoutScale $cfg.scale;$menu.IsOpen=$false} else {$scaleInput.Text=[string][int]($cfg.scale*100)};$e.Handled=$true}
})
[void]$scalePanel.Children.Add($scaleInput)
$percent=[Windows.Controls.TextBlock]::new();$percent.Text=' %';$percent.VerticalAlignment='Center';[void]$scalePanel.Children.Add($percent)
$scaleItem.Header=$scalePanel;[void]$menu.Items.Add($scaleItem)
[void](Add-Menu 'toggle_card' {Toggle-Card})
[void](Add-Menu 'topmost' {$window.Topmost=-not $window.Topmost})
$sessionsMenu=New-Object Windows.Controls.MenuItem; $sessionsMenu.Header=Get-PetString 'sessions';$script:MenuTextKeys[$sessionsMenu]='sessions'; [void]$menu.Items.Add($sessionsMenu)
$menu.Add_Opened({
    $script:files=@(Find-CodexSessions $cfg.codexHome)
    $sessionsMenu.Items.Clear()
    $auto=New-Object Windows.Controls.MenuItem; $auto.Header=Get-PetString 'auto_session'; $auto.IsCheckable=$true; $auto.IsChecked=(-not $cfg.pinnedPath)
    $auto.Add_Click({$cfg.pinnedPath=''; $script:lastPath=''; Refresh-Pet}); [void]$sessionsMenu.Items.Add($auto)
    foreach($f in $script:files) {
        $item=New-Object Windows.Controls.MenuItem
        $title=if($f.Title){$f.Title}else{$f.BaseName}
        if($title.Length -gt 26){$title=$title.Substring(0,26)+'…'}
        $project=if($f.ProjectName){$f.ProjectName}elseif($f.Cwd){Split-Path $f.Cwd -Leaf}else{Get-PetString 'unknown_project'}
        $item.Header=$project+' · '+$title
        $item.ToolTip=$f.Cwd+"`n"+$f.Title+"`n"+$f.Id;$item.Tag=$f.FullName
        $item.IsCheckable=$true; $item.IsChecked=($cfg.pinnedPath -eq $f.FullName)
        $item.Add_Click({param($sender,$e) $cfg.pinnedPath=$sender.Tag; $script:lastPath=''; Refresh-Pet})
        [void]$sessionsMenu.Items.Add($item)
    }
})
[void](Add-Menu 'refresh' {$script:files=@(); $script:lastPath=''; Refresh-Pet})
[void](Add-Menu 'open_data' {Start-Process explorer.exe -ArgumentList ('"'+$cfg.codexHome+'"')})
[void](Add-Menu 'follow' {
    $shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'CodexPet-FollowCodex.lnk'
    if(Test-Path -LiteralPath $shortcut) {
        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'CodexPet.Follow.ps1')+'" -Disable') -WindowStyle Hidden
        Say 'follow_off' 'greet'
    } else {
        Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'CodexPet.Follow.ps1')+'" -Install -Enable') -WindowStyle Hidden
        Say 'follow_on' 'greet'
    }
})
[void](Add-Menu 'exit' {$window.Close()})
$window.ContextMenu=$menu
Apply-PetLanguage
function Clamp-Window {
 $left=[Windows.SystemParameters]::VirtualScreenLeft;$top=[Windows.SystemParameters]::VirtualScreenTop
 $window.Left=[math]::Max($left,[math]::Min($window.Left,$left+[Windows.SystemParameters]::VirtualScreenWidth-$window.ActualWidth))
 $window.Top=[math]::Max($top,[math]::Min($window.Top,$top+[Windows.SystemParameters]::VirtualScreenHeight-$window.ActualHeight))
}
$window.Add_SizeChanged({if($window.IsVisible) {Clamp-Window}})
$animation=New-Object Windows.Threading.DispatcherTimer; $animation.Interval=[timespan]::FromMilliseconds(50)
$animation.Add_Tick({
    $script:frame++; $t=$script:frame/20; $now=Get-Date
    $ui.PetMove.Y=[math]::Sin($t*2)*2.5; $ui.PetTilt.Angle=[math]::Sin($t*1.5)*1.1
    if($clips.Count) {$ui.PetMove.Y=0;$ui.PetTilt.Angle=0}
    if(-not $script:dragging -and -not $AnimationCheck -and $script:sequence.Count) {
        $slot=[int][math]::Floor(($now-$script:sequenceStart).TotalSeconds/3)
        if($slot -lt $script:sequence.Count) {Set-Pose $script:sequence[$slot]} else {$script:sequence=@()}
    }
    if(-not $script:dragging -and -not $AnimationCheck -and $now -gt $script:poseUntil) {
        if($script:refreshFailed) {Set-Pose 'cry'}
        elseif($script:snapshot.Status -eq 'working') {
            $workActions=@('work','work','run','stretch');$slot=[int][math]::Floor($t/8)%$workActions.Count;Set-Pose $workActions[$slot]
        }
        elseif(($now-$script:lastInteraction).TotalSeconds -gt 180) {Set-Pose 'sleep'}
        elseif(-not $script:snapshot.Path) {Set-Pose 'yawn'}
        else {$idleActions=@('greet','hold','hug','laugh','bow');$slot=[int][math]::Floor($t/8)%$idleActions.Count;Set-Pose $idleActions[$slot]}
    }
    if($clips.ContainsKey($script:pose)) {
        $clip=$clips[$script:pose];$index=[int][math]::Floor($script:poseClock.ElapsedMilliseconds/$clip.Duration)%$clip.Frames.Count
        $script:playbackFrame=$index;$ui.Sprite.Source=$clip.Frames[$index]
        if($script:frame%20 -eq 0 -and -not $AnimationCheck) {
            [IO.File]::WriteAllText((Join-Path $stateDir 'playback-state.json'),([pscustomobject]@{Mode='GIF';Action=$script:pose;Frame=$index;Frames=$clip.Frames.Count;Source=$ui.Sprite.Source.GetHashCode();Updated=(Get-Date -Format o)} | ConvertTo-Json),[Text.Encoding]::UTF8)
        }
        if($AnimationCheck -and $null -ne $script:checkObserved) {[void]$script:checkObserved.Add($ui.Sprite.Source.GetHashCode())}
    }
    if($now -gt $script:speechUntil) {
        if($script:snapshot.Status -eq 'working') {$ui.Speech.Text=Get-PetString 'thinking'; $ui.Bubble.Visibility='Visible'}
        elseif($script:pose -eq 'sleep') {$ui.Speech.Text=Get-PetString 'sleeping'; $ui.Bubble.Visibility='Visible'}
        else {$ui.Bubble.Visibility='Collapsed'}
    }
})
$refresh=New-Object Windows.Threading.DispatcherTimer; $refresh.Interval=[timespan]::FromSeconds(2)
$refresh.Add_Tick({if(Test-Path -LiteralPath $stopPath) {$window.Close()} elseif(-not $AnimationCheck) {Refresh-Pet}})
$window.Add_Closed({$animation.Stop();$refresh.Stop();$usageWorker.Dispose();if($historyWorker){$historyWorker.Dispose()};if(-not $Preview -and -not $AnimationCheck -and $SmokeSeconds -eq 0) {Save-Config};if($created) {$mutex.ReleaseMutex()};$mutex.Dispose();Write-Log 'closed'})
Refresh-Pet
if($Preview) {
    $ui.Status.Text=Get-PetString 'preview';$ui.Project.Text=Get-PetString 'preview_project';$ui.Tokens.Text='12,480 tok';$ui.Context.Text='7.2%';$ui.TaskTps.Text='18.6 tok/s';$ui.Model.Text='gpt-6.1-sol';$ui.CurrentCost.Text='API ≈ $0.0128';$ui.TotalTokens.Text='24,960 tok';$ui.TotalCost.Text='API ≈ $0.0640';$ui.UsageScope.Text=Get-PetString 'preview_scope'
    if($ExpandedPreview) {
     $ui.ModelDetails.Visibility='Visible';$ui.DetailsScroll.Visibility='Visible';$ui.TotalLabel.Text=(Get-PetString 'history_total')+' ▴'
     Clear-PetModelDetails
     foreach($text in @('gpt-6.1-sol   12,480 tok  ≈ $0.0128','gpt-6-astra   12,480 tok  ≈ $0.0512')) {$line=[Windows.Controls.TextBlock]::new();$line.Text=$text;$line.FontSize=14;$line.Foreground=[Windows.Media.Brushes]::LightGray;$line.Margin=[Windows.Thickness]::new(0,0,0,8);Register-PetLayout $line;[void]$ui.ModelDetails.Children.Add($line)}
    }
    $visual=$window.Content
    $visual.Measure([Windows.Size]::new(1000,1000)); $visual.Arrange([Windows.Rect]::new(0,0,$visual.DesiredSize.Width,$visual.DesiredSize.Height)); $visual.UpdateLayout()
    $render=[Windows.Media.Imaging.RenderTargetBitmap]::new([int]$visual.DesiredSize.Width,[int]$visual.DesiredSize.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $render.Render($visual); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
    $previewName=if($ExpandedPreview){'preview-expanded.png'}else{'preview.png'}
    if($Language){$previewName=$previewName.Replace('.png','-'+$script:PetLanguage+'.png')}
    $previewPath=Join-Path $diagnosticRoot $previewName
    $out=[IO.File]::Create($previewPath);try {$encoder.Save($out)} finally {$out.Dispose()}
    Write-Output ('preview saved: '+$previewPath);$usageWorker.Dispose();if($created) {$mutex.ReleaseMutex()};$mutex.Dispose();exit
}
Write-Log ('started; GIF clips='+$clips.Count+'; session='+$script:snapshot.Id)
$animation.Start(); $refresh.Start()
if($AnimationCheck) {
    $script:checkActions=@($clips.Keys | Sort-Object);$script:checkSlot=0;$script:checkResults=@();$script:checkObserved=[Collections.Generic.HashSet[int]]::new()
    Say 'animation_check' $script:checkActions[0] 60
    $checker=[Windows.Threading.DispatcherTimer]::new();$checker.Interval=[timespan]::FromMilliseconds(2400)
    $checker.Add_Tick({
        $name=$script:checkActions[$script:checkSlot];$count=$script:checkObserved.Count
        $script:checkResults+=[pscustomobject]@{Action=$name;VisibleFrames=$count;Expected=$clips[$name].Frames.Count;Passed=($count -eq $clips[$name].Frames.Count)}
        Write-Log ('animation check: '+$name+'; visible frames='+$count)
        $script:checkSlot++
        if($script:checkSlot -ge $script:checkActions.Count) {
            $checker.Stop();[IO.File]::WriteAllText((Join-Path $stateDir 'animation-check.json'),($script:checkResults | ConvertTo-Json),[Text.Encoding]::UTF8);$window.Close()
        } else {$script:checkObserved=[Collections.Generic.HashSet[int]]::new();Say 'animation_check' $script:checkActions[$script:checkSlot] 60}
    });$checker.Start()
}
if($SmokeSeconds -gt 0) {
    $savedLanguage=$cfg.language
    foreach($languageCode in @('zh-CN','zh-TW','en-US','ja-JP')) {
        $choice=$languageMenu.Items | Where-Object {$_.Tag -eq $languageCode} | Select-Object -First 1
        $choice.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
        if($script:PetLanguage -ne $languageCode -or $ui.ContextLabel.Text -ne (Get-PetString 'context') -or $actionMenu.Items[0].Header -ne (Get-PetString ('action_'+$actionMenu.Items[0].Tag))) {throw 'language menu did not update labels and action menu'}
        if(@($languageMenu.Items|Where-Object IsChecked).Count -ne 1) {throw 'language selection is not exclusive'}
    }
    $cfg.language=$savedLanguage;Apply-PetLanguage;Refresh-Pet
    Write-Log 'smoke: four languages switched live through the menu; numeric input and data binding preserved'
    if($ui.Card.Background.Color.ToString() -ne '#FF19252A' -or $ui.Bubble.Background.Color.ToString() -ne '#FF19252A' -or $menu.Background.Color.ToString() -ne '#FF19252A' -or $scaleInput.Background.Color.ToString() -ne '#FF19252A') {throw 'surface colors differ'}
    $window.ApplyTemplate() | Out-Null;$menu.ApplyTemplate() | Out-Null
    $actionMenu.ApplyTemplate() | Out-Null
    $popup=$actionMenu.Template.FindName('PART_Popup',$actionMenu)
    if($popup.Child.Background.Color.ToString() -ne '#FF19252A') {throw 'submenu surface differs'}
    Write-Log 'smoke: card, bubble, menu, submenu and percent input use opaque #19252A'
    $savedPin=$cfg.pinnedPath
    $checkedSessions=0
    foreach($target in ($script:files | Select-Object -First 3)) {
        $expected=Read-CodexSnapshot $target.FullName
        $cfg.pinnedPath=$target.FullName;$script:lastPath='';Refresh-Pet
        if($script:snapshot.Path -ne $target.FullName -or $script:snapshot.Id -ne $expected.Id -or $script:snapshot.Cwd -ne $expected.Cwd) {throw 'session/project binding failed'}
        $metrics=$usageWorker.Snapshot() | ConvertFrom-Json
        if($metrics.Path -ne $target.FullName -and $ui.Tokens.Text -ne (Get-PetString 'reading')) {throw 'stale model fields shown after switch'}
        $checkedSessions++
    }
    $cfg.pinnedPath=$savedPin;$script:lastPath='';Refresh-Pet
    if($checkedSessions -ne 3) {throw 'synthetic session fixtures were not exercised'}
    Write-Log ('smoke: '+$checkedSessions+' synthetic sessions switched with matching id, project and metrics source')
    $savedScale=$cfg.scale
    foreach($pct in @(20,60,80,100)) {
        $scaleInput.Text=[string]$pct
        $event=[Windows.Input.KeyboardFocusChangedEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,0,$scaleInput,$window);$event.RoutedEvent=[Windows.Input.Keyboard]::LostKeyboardFocusEvent;$scaleInput.RaiseEvent($event)
        if([math]::Abs($ui.CardFrame.Width-300*$pct/100) -gt .001 -or [math]::Abs($ui.Pet.Width-220*$pct/100) -gt .001) {throw 'scale input failed'}
        if($ui.Context.FontSize -ne [math]::Round(14*$pct/100) -or -not $ui.DesktopRoot.LayoutTransform.Value.IsIdentity -or $ui.Card.Effect) {throw 'text is still transformed or rasterized with shadow'}
    }
    $scaleInput.Text=[string][int]($savedScale*100);$event=[Windows.Input.KeyboardFocusChangedEventArgs]::new([Windows.Input.Keyboard]::PrimaryDevice,0,$scaleInput,$window);$event.RoutedEvent=[Windows.Input.Keyboard]::LostKeyboardFocusEvent;$scaleInput.RaiseEvent($event)
    if($clips.Count -ne 16 -or @($clips.Values | Where-Object {$_.Frames.Count -ne 6}).Count) {throw 'GIF decoder frame count failed'}
    Write-Log 'smoke: integer text metrics at 20/60/80/100; no text transform or shadow effect; 16 GIF clips x 6 frames passed'
    $smoke=New-Object Windows.Threading.DispatcherTimer; $smoke.Interval=[timespan]::FromSeconds($SmokeSeconds)
    $smoke.Add_Tick({$smoke.Stop(); $window.Close()}); $smoke.Start()
}
[void]$window.ShowDialog()
if($AnimationCheck -and @($script:checkResults|Where-Object {-not $_.Passed}).Count) {throw 'one or more GIF animations failed frame verification'}
if($isDiagnostic) {Write-Output ('diagnostics saved: '+$diagnosticRoot)}
} catch { Write-Log ($_ | Out-String); throw }
