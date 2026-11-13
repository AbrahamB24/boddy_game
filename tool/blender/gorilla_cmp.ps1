# usage: powershell -File tool/blender/gorilla_cmp.ps1 <render dir> <sheet jpg>
param($d, $sheetPath)
Add-Type -AssemblyName System.Drawing
$sheet=[System.Drawing.Image]::FromFile($sheetPath)
$bmp=New-Object System.Drawing.Bitmap 1200,1080
$g=[System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(40,40,44)); $g.InterpolationMode='HighQualityBicubic'
$rows=@(@(0,250),@(250,505),@(505,768))
for($s=0;$s -lt 3;$s++){
 $y0=$rows[$s][0]+25
 $g.DrawImage($sheet,(New-Object System.Drawing.Rectangle 0,($s*360),300,300),(New-Object System.Drawing.Rectangle 40,$y0,230,230),[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawImage($sheet,(New-Object System.Drawing.Rectangle 300,($s*360),300,300),(New-Object System.Drawing.Rectangle 340,$y0,230,230),[System.Drawing.GraphicsUnit]::Pixel)
 $i=0;foreach($v in 'front','q'){$im=[System.Drawing.Image]::FromFile("$d\gorilla_s${s}_$v.png");$g.DrawImage($im,600+$i*300,($s*360),300,300);$im.Dispose();$i++}
}
$bmp.Save("$d\cmp.png",[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
