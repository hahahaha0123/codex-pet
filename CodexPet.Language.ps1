$script:LanguagePacks=@{}
$script:MenuTextKeys=@{}
$script:PetLanguage='zh-CN'
$script:PetCulture=[Globalization.CultureInfo]::GetCultureInfo('zh-CN')
function Import-PetLanguages([string]$directory) {
    foreach($file in Get-ChildItem -LiteralPath $directory -Filter '*.json') {
        $pack=[IO.File]::ReadAllText($file.FullName)|ConvertFrom-Json
        $strings=@{};foreach($p in $pack.strings.PSObject.Properties){$strings[$p.Name]=[string]$p.Value}
        $script:LanguagePacks[$pack.code]=@{Name=$pack.name;Strings=$strings}
    }
}
function Select-PetLanguage([string]$requested) {
    $code=$requested
    if($code -eq 'auto') {
        $name=[Globalization.CultureInfo]::CurrentUICulture.Name
        $code=if($name -match '^zh-(TW|HK|MO)'){'zh-TW'}elseif($name -match '^zh'){'zh-CN'}elseif($name -match '^ja'){'ja-JP'}else{'en-US'}
    }
    if(-not $script:LanguagePacks.ContainsKey($code)) {$code='zh-CN'}
    $script:PetLanguage=$code;$script:PetCulture=[Globalization.CultureInfo]::GetCultureInfo($code)
}
function Get-PetString([string]$key,[object[]]$values=@()) {
    $strings=$script:LanguagePacks[$script:PetLanguage].Strings
    $format=if($strings.ContainsKey($key)){$strings[$key]}elseif($script:LanguagePacks['zh-CN'].Strings.ContainsKey($key)){$script:LanguagePacks['zh-CN'].Strings[$key]}else{$key}
    if($values.Count) {return [string]::Format($script:PetCulture,$format,$values)}
    return $format
}
function Format-PetNumber([double]$value,[string]$format='N0') {return $value.ToString($format,$script:PetCulture)}
function Get-PetModelName([string]$name) {if($name -eq '未识别模型'){Get-PetString 'unknown_model'}else{$name}}
function Apply-PetLanguage {
    Select-PetLanguage $cfg.language
    $window.Title=Get-PetString 'window_title'
    $ui.CurrentCost.Text=Get-PetString 'estimate_unknown';$ui.TotalCost.Text=Get-PetString 'estimate_unknown'
    $ui.UsageScope.Text=Get-PetString 'history_scope' @('—')
    $fonts=switch($script:PetLanguage){'ja-JP'{'Yu Gothic UI, Meiryo, Microsoft YaHei UI, Segoe UI'}'zh-TW'{'Microsoft JhengHei UI, Microsoft YaHei UI, Segoe UI'}'en-US'{'Segoe UI, Microsoft YaHei UI'}default{'Microsoft YaHei UI, Segoe UI'}}
    $window.FontFamily=[Windows.Media.FontFamily]::new($fonts)
    if($menu){$menu.FontFamily=$window.FontFamily}
    foreach($pair in @{ContextLabel='context';TpsLabel='task_speed';CurrentLabel='current_usage'}.GetEnumerator()) {$ui[$pair.Key].Text=Get-PetString $pair.Value}
    $ui.TotalLabel.Text=(Get-PetString 'history_total')+' '+$(if($ui.ModelDetails.Visibility -eq 'Visible'){'▴'}else{'▾'})
    foreach($item in $script:MenuTextKeys.Keys) {$item.Header=Get-PetString $script:MenuTextKeys[$item]}
    if($scaleTitle) {$scaleTitle.Text=(Get-PetString 'scale')+'  ';$scaleInput.ToolTip=Get-PetString 'scale_tip'}
    if($languageMenu) {
        foreach($item in $languageMenu.Items) {$item.IsChecked=($item.Tag -eq $cfg.language);if($item.Tag -eq 'auto'){$item.Header=Get-PetString 'system_language'}}
    }
    if($script:speechKey -and (Get-Date) -lt $script:speechUntil) {$ui.Speech.Text=Get-PetString $script:speechKey}
}
