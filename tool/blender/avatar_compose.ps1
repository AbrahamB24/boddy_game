# Stacks tinted avatar layers into one PNG, the way the app does (multiply by the colour, x1.2 gain).
#   powershell -File tool/blender/avatar_compose.ps1 -Dir docs/renders/avatar_t1/full -Out x.png `
#       -Layers "body/base:#e8b890,top/tunic:#c0392b,..."
param([string]$Dir, [string]$Out, [string]$Layers, [double]$Scale = 1.0)
Add-Type -AssemblyName System.Drawing
$parts = $Layers -split ','
$first = $true; $bmp = $null; $g = $null
foreach ($p in $parts) {
    $kv = $p -split ':'
    $path = Join-Path $Dir ($kv[0] + '.png')
    if (-not (Test-Path $path)) { continue }
    $img = [System.Drawing.Bitmap]::FromFile((Resolve-Path $path))
    if ($first) {
        $bmp = New-Object System.Drawing.Bitmap ([int]($img.Width * $Scale)), ([int]($img.Height * $Scale))
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::FromArgb(255, 70, 110, 140))
        $g.InterpolationMode = 'NearestNeighbor'
        $first = $false
    }
    $m = New-Object System.Drawing.Imaging.ColorMatrix
    if ($kv.Length -gt 1) {
        $c = [System.Drawing.ColorTranslator]::FromHtml($kv[1])
        $gain = 1.2
        $m.Matrix00 = [Math]::Min(1.4, $c.R / 255.0 * $gain)
        $m.Matrix11 = [Math]::Min(1.4, $c.G / 255.0 * $gain)
        $m.Matrix22 = [Math]::Min(1.4, $c.B / 255.0 * $gain)
    }
    $ia = New-Object System.Drawing.Imaging.ImageAttributes
    $ia.SetColorMatrix($m)
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $g.DrawImage($img, $rect, 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $ia)
    $img.Dispose()
}
$bmp.Save((Join-Path (Get-Location) $Out), [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
