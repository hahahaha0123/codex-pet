$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationCore, WindowsBase
$root=Split-Path $PSScriptRoot
$batches=@(
 @('greet','happy','run','runRight'),
 @('stretch','bow','work','shy'),
 @('laugh','surprise','angry','cry'),
 @('yawn','sleep','hug','hold')
)
for($batch=0;$batch -lt 4;$batch++) {
 $path=Join-Path $root ('assets\animation-sheets\sheet-{0}.png' -f $batch)
 $source=[Windows.Media.Imaging.BitmapImage]::new()
 $source.BeginInit(); $source.CacheOption='OnLoad'; $source.UriSource=[Uri]::new($path); $source.EndInit(); $source.Freeze()
 $width=[int][math]::Floor($source.PixelWidth/6); $height=[int][math]::Floor($source.PixelHeight/4)
 for($row=0;$row -lt 4;$row++) {
  $dir=Join-Path $root ('assets\animations\'+$batches[$batch][$row]); [void][IO.Directory]::CreateDirectory($dir)
  for($col=0;$col -lt 6;$col++) {
   $rect=[Windows.Int32Rect]::new($col*$width,$row*$height,$width,$height)
   $frame=[Windows.Media.Imaging.CroppedBitmap]::new($source,$rect)
   $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new(); $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($frame))
   $file=[IO.File]::Create((Join-Path $dir ('{0:D2}.png' -f $col)))
   try {$encoder.Save($file)} finally {$file.Dispose()}
  }
 }
 Write-Output ('sheet {0}: {1}x{2} -> 24 frames' -f $batch,$source.PixelWidth,$source.PixelHeight)
}
