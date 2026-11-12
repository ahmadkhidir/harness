# Generates the Harness brand mark, lockups, and platform app icons.
#
# The mark is a weaver's reed: a closed rectangular frame with evenly spaced
# vertical threads, one of which is driven past the top edge and continues as a
# short stub. Geometry and colors come from docs/Harness/branding.md.
#
# Run from the prototype directory:
#   pwsh -File tool/generate_branding_assets.ps1

Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$brandingDir = Join-Path $root 'assets/branding'
New-Item -ItemType Directory -Force -Path $brandingDir | Out-Null

$fontDir = Join-Path $root 'assets/fonts'
$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$pfc.AddFontFile((Join-Path $fontDir 'Geist-SemiBold.ttf'))
$pfc.AddFontFile((Join-Path $fontDir 'GeistMono-Regular.ttf'))
$sansFamily = $pfc.Families | Where-Object { $_.Name -eq 'Geist SemiBold' } | Select-Object -First 1
if (-not $sansFamily) { throw 'Geist font family not found.' }

# Brand inks.
$inkLight = [System.Drawing.ColorTranslator]::FromHtml('#0F1615')
$inkDark = [System.Drawing.ColorTranslator]::FromHtml('#EFF3F2')
$secondaryLight = [System.Drawing.ColorTranslator]::FromHtml('#4A5553')
$secondaryDark = [System.Drawing.ColorTranslator]::FromHtml('#9DA8A6')
$tealLight = [System.Drawing.ColorTranslator]::FromHtml('#0B7D76')
$tealDark = [System.Drawing.ColorTranslator]::FromHtml('#48B0A7')
$tileDark = [System.Drawing.ColorTranslator]::FromHtml('#141A19')
$tileLight = [System.Drawing.ColorTranslator]::FromHtml('#F7F9F8')

function New-Canvas {
    param([int]$Width, [int]$Height)
    $bmp = New-Object System.Drawing.Bitmap($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $g.Clear([System.Drawing.Color]::Transparent)
    return @{ Bitmap = $bmp; Graphics = $g }
}

function Close-Canvas {
    param($Canvas, [string]$Path)
    $Canvas.Graphics.Dispose()
    $Canvas.Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $Canvas.Bitmap.Dispose()
}

# Draws the mark at $X,$Y with $Size pixels for the 24-unit grid.
function Draw-Mark {
    param(
        [System.Drawing.Graphics]$Graphics,
        [double]$X,
        [double]$Y,
        [double]$Size,
        [System.Drawing.Color]$Ink,
        [System.Drawing.Color]$ActiveInk
    )
    $u = $Size / 24.0
    $framePen = New-Object System.Drawing.Pen($Ink, (2.0 * $u))
    $framePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $framePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $framePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    $threadPen = New-Object System.Drawing.Pen($Ink, (1.5 * $u))
    $threadPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $threadPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    $activePen = New-Object System.Drawing.Pen($ActiveInk, (1.5 * $u))
    $activePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $activePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    # Closed frame.
    $rect = New-Object System.Drawing.RectangleF(
        [single]($X + 4.5 * $u),
        [single]($Y + 8.0 * $u),
        [single](15.0 * $u),
        [single](12.0 * $u)
    )
    $Graphics.DrawRectangle($framePen, $rect)

    # Evenly spaced resting threads.
    foreach ($slotX in @(8.25, 15.75)) {
        $Graphics.DrawLine(
            $threadPen,
            [single]($X + $slotX * $u),
            [single]($Y + 8.0 * $u),
            [single]($X + $slotX * $u),
            [single]($Y + 20.0 * $u)
        )
    }

    # The one raised thread: through the frame and past the top edge.
    $Graphics.DrawLine(
        $activePen,
        [single]($X + 12.0 * $u),
        [single]($Y + 3.5 * $u),
        [single]($X + 12.0 * $u),
        [single]($Y + 20.0 * $u)
    )

    $framePen.Dispose()
    $threadPen.Dispose()
    $activePen.Dispose()
}

# Optical 16-unit variant used at 16-20px, where the full mark's four slots
# would collapse into a solid block. Two resting threads keep the slots open.
function Draw-SmallMark {
    param(
        [System.Drawing.Graphics]$Graphics,
        [double]$X,
        [double]$Y,
        [double]$Size,
        [System.Drawing.Color]$Ink,
        [System.Drawing.Color]$ActiveInk
    )
    $u = $Size / 16.0
    $framePen = New-Object System.Drawing.Pen($Ink, (1.5 * $u))
    $framePen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Miter
    $framePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $framePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    $threadPen = New-Object System.Drawing.Pen($Ink, (1.25 * $u))
    $threadPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $threadPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    $activePen = New-Object System.Drawing.Pen($ActiveInk, (1.25 * $u))
    $activePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Square
    $activePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Square

    # Frame, shifted down to optically center the raised stub.
    $rect = New-Object System.Drawing.RectangleF(
        [single]($X + 2.5 * $u),
        [single]($Y + 5.4 * $u),
        [single](11.0 * $u),
        [single](8.0 * $u)
    )
    $Graphics.DrawRectangle($framePen, $rect)

    foreach ($slotX in @(6.0, 10.0)) {
        $Graphics.DrawLine(
            $threadPen,
            [single]($X + $slotX * $u),
            [single]($Y + 5.4 * $u),
            [single]($X + $slotX * $u),
            [single]($Y + 13.4 * $u)
        )
    }

    $Graphics.DrawLine(
        $activePen,
        [single]($X + 8.0 * $u),
        [single]($Y + 2.4 * $u),
        [single]($X + 8.0 * $u),
        [single]($Y + 13.4 * $u)
    )

    $framePen.Dispose()
    $threadPen.Dispose()
    $activePen.Dispose()
}

function Draw-TrackedText {
    param(
        [System.Drawing.Graphics]$Graphics,
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.Brush]$Brush,
        [double]$X,
        [double]$Y,
        [double]$Tracking
    )
    $format = [System.Drawing.StringFormat]::GenericTypographic
    $cursor = $X
    foreach ($ch in $Text.ToCharArray()) {
        $Graphics.DrawString([string]$ch, $Font, $Brush, [single]$cursor, [single]$Y, $format)
        $measure = $Graphics.MeasureString([string]$ch, $Font, [System.Drawing.PointF]::Empty, $format)
        $cursor += $measure.Width + $Tracking
    }
}

function Get-TrackedMetrics {
    param([string]$Text, [System.Drawing.Font]$Font, [double]$Tracking, [System.Drawing.Graphics]$Graphics)
    $format = [System.Drawing.StringFormat]::GenericTypographic
    $width = 0.0
    $height = 0.0
    foreach ($ch in $Text.ToCharArray()) {
        $measure = $Graphics.MeasureString([string]$ch, $Font, [System.Drawing.PointF]::Empty, $format)
        $width += $measure.Width + $Tracking
        $height = [Math]::Max($height, $measure.Height)
    }
    return @{ Width = [Math]::Max(0, $width - $Tracking); Height = $height }
}

# ---------------------------------------------------------------------------
# Mark-only images (transparent).
# ---------------------------------------------------------------------------
foreach ($theme in @('light', 'dark')) {
    $ink = if ($theme -eq 'dark') { $inkDark } else { $inkLight }
    $canvas = New-Canvas -Width 1024 -Height 1024
    Draw-Mark -Graphics $canvas.Graphics -X 0 -Y 0 -Size 1024 -Ink $ink -ActiveInk $ink
    Close-Canvas $canvas (Join-Path $brandingDir "mark-$theme.png")

    $secondary = if ($theme -eq 'dark') { $secondaryDark } else { $secondaryLight }
    $teal = if ($theme -eq 'dark') { $tealDark } else { $tealLight }
    $canvas = New-Canvas -Width 1024 -Height 1024
    Draw-Mark -Graphics $canvas.Graphics -X 0 -Y 0 -Size 1024 -Ink $secondary -ActiveInk $teal
    Close-Canvas $canvas (Join-Path $brandingDir "mark-active-$theme.png")

    # Optical variant for 16-20px uses.
    $canvas = New-Canvas -Width 512 -Height 512
    Draw-SmallMark -Graphics $canvas.Graphics -X 0 -Y 0 -Size 512 -Ink $ink -ActiveInk $ink
    Close-Canvas $canvas (Join-Path $brandingDir "mark-small-$theme.png")
}

# ---------------------------------------------------------------------------
# Wordmark-only images (transparent), Geist Sans SemiBold, tracking -1%.
# ---------------------------------------------------------------------------
foreach ($theme in @('light', 'dark')) {
    $ink = if ($theme -eq 'dark') { $inkDark } else { $inkLight }
    $fontSize = 240.0
    $tracking = $fontSize * -0.01
    $font = New-Object System.Drawing.Font($sansFamily, [single]$fontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $padding = 24
    $probe = New-Canvas -Width 32 -Height 32
    $metrics = Get-TrackedMetrics -Text 'Harness' -Font $font -Tracking $tracking -Graphics $probe.Graphics
    $probe.Graphics.Dispose(); $probe.Bitmap.Dispose()

    $canvas = New-Canvas -Width ([int][Math]::Ceiling($metrics.Width + $padding * 2)) -Height ([int][Math]::Ceiling($metrics.Height + $padding * 2))
    $brush = New-Object System.Drawing.SolidBrush($ink)
    Draw-TrackedText -Graphics $canvas.Graphics -Text 'Harness' -Font $font -Brush $brush -X $padding -Y $padding -Tracking $tracking
    Close-Canvas $canvas (Join-Path $brandingDir "wordmark-$theme.png")
    $brush.Dispose(); $font.Dispose()
}

# ---------------------------------------------------------------------------
# Horizontal and vertical lockups (transparent).
# ---------------------------------------------------------------------------
foreach ($theme in @('light', 'dark')) {
    $ink = if ($theme -eq 'dark') { $inkDark } else { $inkLight }
    $fontSize = 240.0
    $tracking = $fontSize * -0.01
    $font = New-Object System.Drawing.Font($sansFamily, [single]$fontSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $padding = 32
    $markSize = $fontSize * 1.08
    $gap = $markSize * 0.34

    $probe = New-Canvas -Width 32 -Height 32
    $metrics = Get-TrackedMetrics -Text 'Harness' -Font $font -Tracking $tracking -Graphics $probe.Graphics
    $probe.Graphics.Dispose(); $probe.Bitmap.Dispose()

    # Horizontal: mark leads, name follows.
    $w = $padding * 2 + $markSize + $gap + $metrics.Width
    $h = $padding * 2 + [Math]::Max($markSize, $metrics.Height)
    $canvas = New-Canvas -Width ([int][Math]::Ceiling($w)) -Height ([int][Math]::Ceiling($h))
    Draw-Mark -Graphics $canvas.Graphics -X $padding -Y ($padding + ($h - $padding * 2 - $markSize) / 2) -Size $markSize -Ink $ink -ActiveInk $ink
    $brush = New-Object System.Drawing.SolidBrush($ink)
    $textY = ($h - $metrics.Height) / 2
    Draw-TrackedText -Graphics $canvas.Graphics -Text 'Harness' -Font $font -Brush $brush -X ($padding + $markSize + $gap) -Y $textY -Tracking $tracking
    Close-Canvas $canvas (Join-Path $brandingDir "lockup-horizontal-$theme.png")
    $brush.Dispose()

    # Vertical: mark above the name.
    $w = $padding * 2 + [Math]::Max($markSize, $metrics.Width)
    $h = $padding * 2 + $markSize + $gap * 0.7 + $metrics.Height
    $canvas = New-Canvas -Width ([int][Math]::Ceiling($w)) -Height ([int][Math]::Ceiling($h))
    Draw-Mark -Graphics $canvas.Graphics -X (($w - $markSize) / 2) -Y $padding -Size $markSize -Ink $ink -ActiveInk $ink
    $brush = New-Object System.Drawing.SolidBrush($ink)
    Draw-TrackedText -Graphics $canvas.Graphics -Text 'Harness' -Font $font -Brush $brush -X (($w - $metrics.Width) / 2) -Y ($padding + $markSize + $gap * 0.7) -Tracking $tracking
    Close-Canvas $canvas (Join-Path $brandingDir "lockup-vertical-$theme.png")
    $brush.Dispose(); $font.Dispose()
}

# ---------------------------------------------------------------------------
# App icon master: mark in text-primary ink on a solid graphite tile.
# ---------------------------------------------------------------------------
function New-AppIcon {
    param(
        [int]$Size,
        [System.Drawing.Color]$Background,
        [System.Drawing.Color]$Ink,
        [double]$MarkFraction,
        [switch]$Small
    )
    $canvas = New-Canvas -Width $Size -Height $Size
    $canvas.Graphics.Clear($Background)
    $markSize = $Size * $MarkFraction
    if ($Small) {
        Draw-SmallMark -Graphics $canvas.Graphics -X (($Size - $markSize) / 2) -Y (($Size - $markSize) / 2) -Size $markSize -Ink $Ink -ActiveInk $Ink
    } else {
        Draw-Mark -Graphics $canvas.Graphics -X (($Size - $markSize) / 2) -Y (($Size - $markSize) / 2) -Size $markSize -Ink $Ink -ActiveInk $Ink
    }
    return $canvas
}

$appIcon = New-AppIcon -Size 1024 -Background $tileDark -Ink $inkDark -MarkFraction 0.82
Close-Canvas $appIcon (Join-Path $brandingDir 'app-icon-1024.png')

$appIconSmall = New-AppIcon -Size 1024 -Background $tileDark -Ink $inkDark -MarkFraction 0.86 -Small
Close-Canvas $appIconSmall (Join-Path $brandingDir 'app-icon-small-1024.png')

$appIconLight = New-AppIcon -Size 1024 -Background $tileLight -Ink $inkLight -MarkFraction 0.82
Close-Canvas $appIconLight (Join-Path $brandingDir 'app-icon-light-1024.png')

# Store-listing tile used behind the mark on busy imagery.
$tile = New-Canvas -Width 1024 -Height 1024
$tile.Graphics.Clear($tileDark)
Draw-Mark -Graphics $tile.Graphics -X 0 -Y 0 -Size 1024 -Ink $inkDark -ActiveInk $inkDark
Close-Canvas $tile (Join-Path $brandingDir 'tile-dark-1024.png')

# ---------------------------------------------------------------------------
# Resolution-aware in-app variants (1x/2x/3x are rendered from the 1024 master
# by the packaging step; Flutter scales the master down with high-quality
# filtering for the 16-56px uses).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Platform icons.
# ---------------------------------------------------------------------------
$iconMaster = New-Object System.Drawing.Bitmap((Join-Path $brandingDir 'app-icon-1024.png'))
$iconSmallMaster = New-Object System.Drawing.Bitmap((Join-Path $brandingDir 'app-icon-small-1024.png'))

function Get-IconMaster {
    param([int]$Size)
    if ($Size -le 40) { return $iconSmallMaster }
    return $iconMaster
}

function Save-ResizedPng {
    param([System.Drawing.Bitmap]$Source, [int]$Size, [string]$Path)
    $canvas = New-Canvas -Width $Size -Height $Size
    $destRect = New-Object System.Drawing.Rectangle(0, 0, $Size, $Size)
    $canvas.Graphics.DrawImage($Source, $destRect, 0, 0, $Source.Width, $Source.Height, [System.Drawing.GraphicsUnit]::Pixel)
    Close-Canvas $canvas $Path
}

# Android launcher icons.
$androidSizes = @{
    'mipmap-mdpi'    = 48
    'mipmap-hdpi'    = 72
    'mipmap-xhdpi'   = 96
    'mipmap-xxhdpi'  = 144
    'mipmap-xxxhdpi' = 192
}
foreach ($entry in $androidSizes.GetEnumerator()) {
    $dir = Join-Path $root "android/app/src/main/res/$($entry.Key)"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Save-ResizedPng -Source (Get-IconMaster $entry.Value) -Size $entry.Value -Path (Join-Path $dir 'ic_launcher.png')
}

# iOS app icons.
$iosDir = Join-Path $root 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
$iosSizes = @{
    'Icon-App-20x20@1x.png'   = 20
    'Icon-App-20x20@2x.png'   = 40
    'Icon-App-20x20@3x.png'   = 60
    'Icon-App-29x29@1x.png'   = 29
    'Icon-App-29x29@2x.png'   = 58
    'Icon-App-29x29@3x.png'   = 87
    'Icon-App-40x40@1x.png'   = 40
    'Icon-App-40x40@2x.png'   = 80
    'Icon-App-40x40@3x.png'   = 120
    'Icon-App-60x60@2x.png'   = 120
    'Icon-App-60x60@3x.png'   = 180
    'Icon-App-76x76@1x.png'   = 76
    'Icon-App-76x76@2x.png'   = 152
    'Icon-App-83.5x83.5@2x.png' = 167
    'Icon-App-1024x1024@1x.png' = 1024
}
foreach ($entry in $iosSizes.GetEnumerator()) {
    Save-ResizedPng -Source (Get-IconMaster $entry.Value) -Size $entry.Value -Path (Join-Path $iosDir $entry.Key)
}

# macOS app icons.
$macosDir = Join-Path $root 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
$macosSizes = @{
    'app_icon_16.png'   = 16
    'app_icon_32.png'   = 32
    'app_icon_64.png'   = 64
    'app_icon_128.png'  = 128
    'app_icon_256.png'  = 256
    'app_icon_512.png'  = 512
    'app_icon_1024.png' = 1024
}
foreach ($entry in $macosSizes.GetEnumerator()) {
    Save-ResizedPng -Source (Get-IconMaster $entry.Value) -Size $entry.Value -Path (Join-Path $macosDir $entry.Key)
}

# Web icons.
$webIconsDir = Join-Path $root 'web/icons'
Save-ResizedPng -Source (Get-IconMaster 32) -Size 32 -Path (Join-Path $root 'web/favicon.png')
Save-ResizedPng -Source (Get-IconMaster 192) -Size 192 -Path (Join-Path $webIconsDir 'Icon-192.png')
Save-ResizedPng -Source (Get-IconMaster 512) -Size 512 -Path (Join-Path $webIconsDir 'Icon-512.png')
Save-ResizedPng -Source (Get-IconMaster 192) -Size 192 -Path (Join-Path $webIconsDir 'Icon-maskable-192.png')
Save-ResizedPng -Source (Get-IconMaster 512) -Size 512 -Path (Join-Path $webIconsDir 'Icon-maskable-512.png')

# Windows .ico with PNG-compressed frames.
$icoSizes = @(16, 24, 32, 48, 64, 128, 256)
$frameStreams = @()
foreach ($size in $icoSizes) {
    $ms = New-Object System.IO.MemoryStream
    $canvas = New-Canvas -Width $size -Height $size
    $destRect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
    $srcMaster = Get-IconMaster $size
    $canvas.Graphics.DrawImage($srcMaster, $destRect, 0, 0, $srcMaster.Width, $srcMaster.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $canvas.Bitmap.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $canvas.Graphics.Dispose(); $canvas.Bitmap.Dispose()
    $frameStreams += ,$ms.ToArray()
    $ms.Dispose()
}
$icoPath = Join-Path $root 'windows/runner/resources/app_icon.ico'
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$icoSizes.Count)
$offset = 6 + (16 * $icoSizes.Count)
for ($i = 0; $i -lt $icoSizes.Count; $i++) {
    $s = $icoSizes[$i]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim); $bw.Write([byte]$dim)
    $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([UInt16]1); $bw.Write([UInt16]32)
    $bw.Write([UInt32]$frameStreams[$i].Length)
    $bw.Write([UInt32]$offset)
    $offset += $frameStreams[$i].Length
}
foreach ($frame in $frameStreams) { $bw.Write($frame) }
$bw.Dispose(); $fs.Dispose()
$iconMaster.Dispose()
$iconSmallMaster.Dispose()
$pfc.Dispose()

Write-Host "Generated branding assets in $brandingDir and platform icon sets."
