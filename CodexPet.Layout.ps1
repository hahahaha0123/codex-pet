# Recompute dimensions and font metrics. Never transform a text subtree.
$script:LayoutBases=@{}
$script:LayoutScale=1.0
function Get-PetThickness([Windows.Thickness]$base,[double]$factor,[switch]$Border) {
    $values=@($base.Left,$base.Top,$base.Right,$base.Bottom) | ForEach-Object {
        $v=[math]::Round($_*$factor)
        if($Border -and $_ -gt 0) {[math]::Max(1,$v)} else {$v}
    }
    return [Windows.Thickness]::new($values[0],$values[1],$values[2],$values[3])
}
function Set-PetElementScale($element,$base,[double]$factor) {
    foreach($property in @('Width','Height','MaxWidth','MaxHeight','FontSize')) {
        if($base.ContainsKey($property)) {$element.$property=[math]::Max(1,[math]::Round($base[$property]*$factor))}
    }
    foreach($property in @('Margin','Padding','BorderThickness')) {
        if($base.ContainsKey($property)) {$element.$property=Get-PetThickness $base[$property] $factor -Border:($property -eq 'BorderThickness')}
    }
    if($base.ContainsKey('CornerRadius')) {
        $c=$base.CornerRadius
        $element.CornerRadius=[Windows.CornerRadius]::new([math]::Round($c.TopLeft*$factor),[math]::Round($c.TopRight*$factor),[math]::Round($c.BottomRight*$factor),[math]::Round($c.BottomLeft*$factor))
    }
    $element.UseLayoutRounding=$true;$element.SnapsToDevicePixels=$true
    [Windows.Media.TextOptions]::SetTextFormattingMode($element,[Windows.Media.TextFormattingMode]::Display)
    [Windows.Media.TextOptions]::SetTextRenderingMode($element,[Windows.Media.TextRenderingMode]::ClearType)
}
function Register-PetLayout([Windows.DependencyObject]$node) {
    if($node -is [Windows.FrameworkElement] -and -not $script:LayoutBases.ContainsKey($node)) {
        $base=@{}
        foreach($property in @('Width','Height','MaxWidth','MaxHeight','FontSize')) {
            if($node.PSObject.Properties[$property]) {
                $value=[double]$node.$property
                if(-not [double]::IsNaN($value) -and -not [double]::IsInfinity($value)) {$base[$property]=$value}
            }
        }
        foreach($property in @('Margin','Padding','BorderThickness','CornerRadius')) {
            if($node.PSObject.Properties[$property] -and $node.Name -ne 'DesktopRoot') {$base[$property]=$node.$property}
        }
        $script:LayoutBases[$node]=$base
        Set-PetElementScale $node $base $script:LayoutScale
    }
    foreach($child in [Windows.LogicalTreeHelper]::GetChildren($node)) {
        if($child -is [Windows.DependencyObject]) {Register-PetLayout $child}
    }
}
function Set-PetLayoutScale([double]$factor) {
    $script:LayoutScale=[math]::Max(.2,[math]::Min(1.0,$factor))
    foreach($node in $script:LayoutBases.Keys) {Set-PetElementScale $node $script:LayoutBases[$node] $script:LayoutScale}
    if($ui.CardShadow -and $ui.CardShadow.Effect) {
        $ui.CardShadow.Effect.BlurRadius=[math]::Round(18*$script:LayoutScale)
        $ui.CardShadow.Effect.ShadowDepth=[math]::Round(2*$script:LayoutScale)
    }
}
function Unregister-PetLayout([Windows.DependencyObject]$node) {
    foreach($child in [Windows.LogicalTreeHelper]::GetChildren($node)) {
        if($child -is [Windows.DependencyObject]) {Unregister-PetLayout $child}
    }
    $script:LayoutBases.Remove($node)
}
