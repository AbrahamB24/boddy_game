# usage: powershell -File tool/blender/griffin_cmp.ps1 <render dir> <sheet jpg>
# writes cmp_s0..2.png: top row = sheet crops (front, 3/4, side, back), bottom row = renders (side view mirrored to face left like the sheet)
param($d, $sheetPath, $prog)
Add-Type -AssemblyName System.Drawing
$sheet=[System.Drawing.Image]::FromFile($sheetPath)
$R=@(
 @(@(100,55,250,232),@(430,55,620,232),@(760,55,985,232),@(1130,55,1280,232)),
 @(@(78,262,272,465),@(405,262,632,465),@(735,262,1010,465),@(1100,262,1300,465)),
 @(@(8,500,342,738),@(352,500,652,738),@(692,500,1040,738),@(1048,500,1362,738)))
$views='front','q','side','back'
function Fit($g,$im,$sr,$dx,$dy,$dw,$dh,$flip){
  $sw=$sr.Width;$sh=$sr.Height;$k=[Math]::Min($dw/$sw,$dh/$sh);$w=$sw*$k;$h=$sh*$k
  $x=$dx+($dw-$w)/2;$y=$dy+($dh-$h)/2
  if($flip){$g.DrawImage($im,(New-Object System.Drawing.Rectangle ([int]($x+$w)),([int]$y),(-[int]$w),([int]$h)),$sr,[System.Drawing.GraphicsUnit]::Pixel)}
  else{$g.DrawImage($im,(New-Object System.Drawing.Rectangle ([int]$x),([int]$y),([int]$w),([int]$h)),$sr,[System.Drawing.GraphicsUnit]::Pixel)}
}
for($s=0;$s -lt 3;$s++){
 $bmp=New-Object System.Drawing.Bitmap 1320,640
 $g=[System.Drawing.Graphics]::FromImage($bmp);$g.Clear([System.Drawing.Color]::FromArgb(40,40,44));$g.InterpolationMode='HighQualityBicubic'
 for($i=0;$i -lt 4;$i++){
  $q=$R[$s][$i]
  Fit $g $sheet (New-Object System.Drawing.Rectangle $q[0],$q[1],($q[2]-$q[0]),($q[3]-$q[1])) ($i*330) 0 330 320 $false
  $f="$d\griffin_s${s}_$($views[$i]).png"
  if(Test-Path $f){$im=[System.Drawing.Image]::FromFile($f)
   Fit $g $im (New-Object System.Drawing.Rectangle 0,0,$im.Width,$im.Height) ($i*330) 320 330 320 (($views[$i] -eq 'q') -or (($views[$i] -eq 'side') -and ($s -lt 2)));$im.Dispose()}
 }
 $bmp.Save("$d\cmp_s$s.png",[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$bmp.Dispose()
}
# combined progress image (all three stage comparisons stacked), optional third arg = output path
if($prog){
 $all=New-Object System.Drawing.Bitmap 1320,1920
 $g=[System.Drawing.Graphics]::FromImage($all)
 for($s=0;$s -lt 3;$s++){$im=[System.Drawing.Image]::FromFile("$d\cmp_s$s.png");$g.DrawImage($im,0,$s*640,1320,640);$im.Dispose()}
 $all.Save($prog,[System.Drawing.Imaging.ImageFormat]::Png);$g.Dispose();$all.Dispose()
}
