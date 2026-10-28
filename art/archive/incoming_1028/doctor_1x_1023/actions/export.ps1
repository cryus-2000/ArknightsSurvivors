$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing.Common,System.Drawing.Primitives,System.Private.Windows.GdiPlus,System.Private.Windows.Core -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class DoctorExport {
 public static readonly string[] Hex={"151821","232533","303346","414559","535970","686f83","828a99","a5a9b0","c5c3bd","e4dfd4","f0eadd","241f25","3c3036","514048","174554","246574","388d9c","58aeb8","83c3c6","795333","a3753e","c79555","293d4b","526978"};
 static Color[] Pal=Array.ConvertAll(Hex,h=>ColorTranslator.FromHtml("#"+h));
 public static int[] Box(Bitmap s,int x0,int y0,int w,int h) {int l=x0+w,t=y0+h,r=-1,b=-1;for(int y=y0;y<y0+h;y++)for(int x=x0;x<x0+w;x++)if(s.GetPixel(x,y).A>=128){l=Math.Min(l,x);t=Math.Min(t,y);r=Math.Max(r,x);b=Math.Max(b,y);}return new[]{l,t,r,b};}
 public static Bitmap Frame(Bitmap s,int[] rect,double ox,double oy,double scale,int lift=0) {
  var o=new Bitmap(64,64,PixelFormat.Format32bppArgb);
  for(int y=1;y<63;y++)for(int x=1;x<63;x++){
   double r=0,g=0,b=0,a=0;int n=0;
   int x0=(int)Math.Floor(ox+(x-32)/scale),x1=(int)Math.Ceiling(ox+(x+1-32)/scale);
   int y0=(int)Math.Floor(oy+(y+lift-61)/scale),y1=(int)Math.Ceiling(oy+(y+1+lift-61)/scale);
   for(int sy=y0;sy<y1;sy++)for(int sx=x0;sx<x1;sx++) {n++;if(sx<rect[0]||sy<rect[1]||sx>=rect[0]+rect[2]||sy>=rect[1]+rect[3])continue;var c=s.GetPixel(sx,sy);double alpha=c.A/255.0;a+=alpha;r+=c.R*alpha;g+=c.G*alpha;b+=c.B*alpha;}
   if(n==0||a/n<.42)continue;r/=a;g/=a;b/=a;int best=0;double d=1e20;
   for(int i=0;i<Pal.Length;i++){double dd=Math.Pow(r-Pal[i].R,2)+Math.Pow(g-Pal[i].G,2)+Math.Pow(b-Pal[i].B,2);if(dd<d){d=dd;best=i;}}o.SetPixel(x,y,Pal[best]);
  }return o;
 }
 public static void Strip(Bitmap[] fs,string path,int density) {using(var o=new Bitmap(fs.Length*64*density,64*density,PixelFormat.Format32bppArgb)){for(int i=0;i<fs.Length;i++)for(int y=0;y<64*density;y++)for(int x=0;x<64*density;x++)o.SetPixel(i*64*density+x,y,fs[i].GetPixel(x/density,y/density));o.Save(path,ImageFormat.Png);}}
 public static void Contact(Bitmap[] fs,string path) {using(var o=new Bitmap(fs.Length*256,256)){using(var g=Graphics.FromImage(o)){g.Clear(Color.FromArgb(49,61,73));}for(int i=0;i<fs.Length;i++)for(int y=0;y<256;y++)for(int x=0;x<256;x++){var c=fs[i].GetPixel(x/4,y/4);if(c.A>0)o.SetPixel(i*256+x,y,c);}o.Save(path,ImageFormat.Png);}}
}
'@
$root=$PSScriptRoot
$jobs=@(
 @{name='idle';cols=4;rows=1;fps=4;loop=$true;scale=40/632;origins=@(@(295,690),@(838,690),@(1381,690),@(1924,690))},
 @{name='run';cols=4;rows=2;fps=10;loop=$true;scale=40/390;origins=@(@(251,450),@(686,450),@(1125,450),@(1568,450),@(250,859),@(686,859),@(1125,859),@(1568,859))},
 @{name='hurt';cols=2;rows=1;fps=10;loop=$false;scale=40/725;origins=@(@(580,866),@(1310,866))},
 @{name='death';cols=4;rows=1;fps=6;loop=$false;scale=40/520;origins=@(@(250,655),@(730,655),@(1255,655),@(1840,655));rects=@(@(0,0,500,724),@(510,0,470,724),@(990,0,530,724),@(1550,0,622,724))}
)
$assets=@();$frameMeta=@();$saved=@{}
foreach($j in $jobs){
 $s=[Drawing.Bitmap]::new("$root/sources/$($j.name).png");$fs=[Collections.Generic.List[Drawing.Bitmap]]::new();$n=$j.cols*$j.rows
 for($i=0;$i -lt $n;$i++){
  if($j.rects){$rect=$j.rects[$i]}else{$cx=$i%$j.cols;$cy=[Math]::Floor($i/$j.cols);$x=[int][Math]::Round($cx*$s.Width/$j.cols);$y=[int][Math]::Round($cy*$s.Height/$j.rows);$rect=@($x,$y,([int][Math]::Round(($cx+1)*$s.Width/$j.cols)-$x),([int][Math]::Round(($cy+1)*$s.Height/$j.rows)-$y))}
  $o=$j.origins[$i];$f=[DoctorExport]::Frame($s,[int[]]$rect,$o[0],$o[1],$j.scale,0)
  if($j.name -eq 'death' -and $i -eq 0){$f.Dispose();$f=[Drawing.Bitmap]::new($saved.idle[0])}
  $fs.Add($f)
  $frameMeta+=@{action=$j.name;index=$i;source_rect=$rect;source_origin=$o;scale=$j.scale;bbox=[DoctorExport]::Box($f,0,0,64,64)}
 }
 $s.Dispose();$arr=$fs.ToArray();$saved[$j.name]=$arr
 foreach($density in @(1,2)){$file='doctor_'+$j.name+$(if($density -eq 2){'@2x'}else{''})+'.png';[DoctorExport]::Strip($arr,"$root/$file",$density);$assets+=@{file=$file;character='doctor';frame_width=64*$density;frame_height=64*$density;frame_count=$n;fps=$j.fps;anchor=@((32*$density),(60*$density));loop=$j.loop;hold_last_frame=(-not $j.loop);density=$density;sha256=(Get-FileHash "$root/$file").Hash.ToLower()}}
 [DoctorExport]::Contact($arr,"$root/$($j.name)_frames.png")
}
foreach($fs in $saved.Values){foreach($f in $fs){$f.Dispose()}}
@{assets=$assets;source='ImageGen approved Doctor v2; mechanical fixed-scale export';pixel_grid=1;palette=[DoctorExport]::Hex;engine_integrated=$false;hurt_runtime_trigger=$false} | ConvertTo-Json -Depth 10 | Set-Content "$root/manifest.json" -Encoding utf8
$frameMeta | ConvertTo-Json -Depth 8 | Set-Content "$root/frame_registration.json" -Encoding utf8
Write-Output 'Exported 4 actions / 18 frames at 1x and exact nearest-neighbor 2x.'
