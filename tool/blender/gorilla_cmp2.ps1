# usage: powershell -File tool/blender/gorilla_cmp2.ps1 <render dir> <sheet jpg>   (side + back: sheet left, render right)
param($d, $sheetPath)
Add-Type -AssemblyName System.Drawing
$sheet=[System.Drawing.Image]::FromFile($sheetPath)
$bmp=New-Object System.Drawing.Bitmap 1200,1080
$g=[System.Drawing.Graphics]::FromImage($bmp); $g.Clear([System.Drawing.Color]::FromArgb(40,40,44)); $g.InterpolationMode='HighQualityBicubic'
$rows=@(@(0,250),@(250,505),@(505,768))
$cols=@(@('side',860,200),@('back',1120,230))
for($s=0;$s -lt 3;$s++){
 $y0=$rows[$s][0]+45
 for($i=0;$i -lt 2;$i++){
  $c=$cols[$i]
  $g.DrawImage($sheet,(New-Object System.Drawing.Rectangle ($i*300),($s*360),300,300),(New-Object System.Drawing.Rectangle $c[1],$y0,$c[2],$c[2]),[System.Drawing.GraphicsUnit]::Pixel)
  $im=[System.Drawing.Image]::FromFile("$d\gorilla_s${s}_$($c[0]).png");$g.DrawImage($im,600+$i*300,($s*360),300,300);$im.Dispose()
 }
}
$bmp.Save("$d\cmp2.png",[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
