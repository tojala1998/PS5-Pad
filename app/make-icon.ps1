$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDir = Join-Path $PSScriptRoot 'assets'
[IO.Directory]::CreateDirectory($assetDir) | Out-Null
$sizes = @{'AppIcon60x60@2x.png'=120; 'AppIcon60x60@3x.png'=180; 'PS5-Pad-icon.png'=512; 'AppIcon1024.png'=1024}
foreach ($entry in $sizes.GetEnumerator()) {
    $size = [int]$entry.Value
    $bitmap = New-Object Drawing.Bitmap ($size*2),($size*2)
    $g = [Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([Drawing.Color]::White)
    $g.ScaleTransform(($size*2/1024.0),($size*2/1024.0))
    $ink = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(21,29,43))
    $blue = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(24,109,245))
    $light = New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(242,246,251))
    $outline = New-Object Drawing.Pen ($ink),18
    $outline.LineJoin = [Drawing.Drawing2D.LineJoin]::Round
    $path = New-Object Drawing.Drawing2D.GraphicsPath
    $path.StartFigure()
    $path.AddBezier(330,320,260,309,218,357,198,430)
    $path.AddLine(198,430,150,646)
    $path.AddBezier(150,646,129,742,198,796,260,728)
    $path.AddLine(260,728,357,622)
    $path.AddBezier(357,622,440,640,584,640,667,622)
    $path.AddLine(667,622,764,728)
    $path.AddBezier(764,728,826,796,895,742,874,646)
    $path.AddLine(874,646,826,430)
    $path.AddBezier(826,430,806,357,764,309,694,320)
    $path.AddBezier(694,320,590,296,434,296,330,320)
    $path.CloseFigure()
    $g.FillPath($light,$path)
    $g.DrawPath($outline,$path)
    $g.FillRectangle($blue,425,331,174,12)
    $g.FillRectangle($ink,429,360,166,91)
    $g.FillRectangle($ink,280,410,31,118)
    $g.FillRectangle($ink,237,453,118,31)
    $g.FillEllipse($ink,360,528,88,88)
    $g.FillEllipse($ink,576,528,88,88)
    $g.FillEllipse($blue,387,555,34,34)
    $g.FillEllipse($blue,603,555,34,34)
    $g.FillEllipse($blue,708,398,30,30)
    $g.FillEllipse($ink,751,441,30,30)
    $g.FillEllipse($ink,665,441,30,30)
    $g.FillEllipse($ink,708,484,30,30)
    $final = New-Object Drawing.Bitmap $size,$size
    $fg = [Drawing.Graphics]::FromImage($final)
    $fg.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $fg.DrawImage($bitmap,0,0,$size,$size)
    $final.Save((Join-Path $assetDir $entry.Key),[Drawing.Imaging.ImageFormat]::Png)
    $fg.Dispose(); $final.Dispose(); $path.Dispose(); $outline.Dispose()
    $ink.Dispose(); $blue.Dispose(); $light.Dispose(); $g.Dispose(); $bitmap.Dispose()
}
Write-Output 'Generated the bright white PS5 Pad icons.'
