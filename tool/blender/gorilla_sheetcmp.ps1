# usage: powershell -File tool/blender/gorilla_sheetcmp.ps1 <render dir> <images dir> <stages e.g. 0,1,2> <out png>
param($d, $im, $stages, $outp)
Add-Type -AssemblyName System.Drawing
$st = $stages.Split(',')
$b=New-Object System.Drawing.Bitmap 1600,(800*$st.Count); $g=[System.Drawing.Graphics]::FromImage($b); $g.Clear([System.Drawing.Color]::FromArgb(50,50,54)); $g.InterpolationMode='HighQualityBicubic'
$row=0
foreach($s in $st){ $s_=[System.Drawing.Image]::FromFile("$im\$([int]$s+3).png"); $y=$row*800
 $g.DrawImage($s_,(New-Object System.Drawing.Rectangle 0,$y,400,400),(New-Object System.Drawing.Rectangle 0,0,512,512),[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawImage($s_,(New-Object System.Drawing.Rectangle 400,$y,400,400),(New-Object System.Drawing.Rectangle 0,512,512,512),[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawImage($s_,(New-Object System.Drawing.Rectangle 800,$y,400,400),(New-Object System.Drawing.Rectangle 512,0,512,512),[System.Drawing.GraphicsUnit]::Pixel)
 $g.DrawImage($s_,(New-Object System.Drawing.Rectangle 1200,$y,400,400),(New-Object System.Drawing.Rectangle 512,512,512,512),[System.Drawing.GraphicsUnit]::Pixel)
 $x=0; foreach($v in 'front','side','back','q'){ $f="$d\gorilla_s${s}_$v.png"; if(Test-Path $f){ $m=[System.Drawing.Image]::FromFile($f); $g.DrawImage($m,$x,$y+400,400,400); $m.Dispose()}; $x+=400}; $s_.Dispose(); $row++}
$b.Save($outp,[System.Drawing.Imaging.ImageFormat]::Png)
