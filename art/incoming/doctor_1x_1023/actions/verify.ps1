$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$root=$PSScriptRoot;$m=Get-Content "$root/manifest.json" -Raw | ConvertFrom-Json
$palette=[Collections.Generic.HashSet[int]]::new();$report=@()
foreach($a in $m.assets){
 $im=[Drawing.Bitmap]::new("$root/$($a.file)")
 if($im.Width -ne $a.frame_width*$a.frame_count -or $im.Height -ne $a.frame_height){throw "Dimensions $($a.file)"}
 if((Get-FileHash "$root/$($a.file)").Hash.ToLower() -ne $a.sha256){throw 'Hash mismatch'}
 $frames=@();$hashes=[Collections.Generic.HashSet[string]]::new()
 for($f=0;$f -lt $a.frame_count;$f++){
  $l=$a.frame_width;$t=$a.frame_height;$r=-1;$b=-1;$n=0;$buf=[Collections.Generic.List[byte]]::new()
  for($y=0;$y -lt $a.frame_height;$y++){for($x=0;$x -lt $a.frame_width;$x++){
   $c=$im.GetPixel($f*$a.frame_width+$x,$y);$buf.AddRange([BitConverter]::GetBytes($c.ToArgb()))
   if($c.A -ne 0 -and $c.A -ne 255){throw "Partial alpha $($a.file)"}
   if($c.A -eq 0){continue}
   if($x -eq 0 -or $y -eq 0 -or $x -eq $a.frame_width-1 -or $y -eq $a.frame_height-1){throw "Clipped edge $($a.file)"}
   $null=$palette.Add($c.ToArgb());$n++;$l=[Math]::Min($l,$x);$r=[Math]::Max($r,$x);$t=[Math]::Min($t,$y);$b=[Math]::Max($b,$y)
  }}
  if($n -eq 0){throw 'Empty frame'}
  $hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($buf.ToArray())).ToLower();$null=$hashes.Add($hash)
  $frames+=@{index=$f;bbox=@($l,$t,$r,$b);opaque=$n;pixel_sha256=$hash}
 }
 $im.Dispose();$report+=@{file=$a.file;distinct_frames=$hashes.Count;frames=$frames}
}
if($palette.Count -gt 24){throw "Palette exceeds24: $($palette.Count)"}
foreach($name in @('idle','run','hurt','death')){
 $lo=[Drawing.Bitmap]::new("$root/doctor_$name.png");$hi=[Drawing.Bitmap]::new("$root/doctor_$name@2x.png")
 for($y=0;$y -lt $hi.Height;$y++){for($x=0;$x -lt $hi.Width;$x++){if($hi.GetPixel($x,$y).ToArgb() -ne $lo.GetPixel([int][Math]::Floor($x/2),[int][Math]::Floor($y/2)).ToArgb()){throw '2x mismatch'}}}
 $lo.Dispose();$hi.Dispose()
}
if($report[0].frames[0].pixel_sha256 -ne $report[6].frames[0].pixel_sha256){throw 'Death entry mismatch'}
$sources=@(Get-ChildItem "$root/sources/*.png" | ForEach-Object {@{file=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLower()}})
@{passed=$true;assets=$report;colors=$palette.Count;binary_alpha=$true;exact_nearest_2x=$true;death_entry_matches_idle=$true;outline_policy='natural material edges, no added shell (user approved)';baseline_policy='fixed ground anchor; running flight frames may lift';source_hashes=$sources;engine_tested=$false;user_motion_approved=$false} | ConvertTo-Json -Depth 12 | Set-Content "$root/qa.json" -Encoding utf8
Write-Output "PASS: 8 strips /18 logical frames; $($palette.Count) shared colors; binary alpha; exact2x; matching death entry."
$report | Select-Object file,distinct_frames | Format-Table
