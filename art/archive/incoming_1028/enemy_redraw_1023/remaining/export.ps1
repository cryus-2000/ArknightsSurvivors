param([string]$Root = $PSScriptRoot, [string[]]$Ids = @())
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies @('System.Drawing.Common','System.Drawing.Primitives','System.Private.Windows.GdiPlus','System.Private.Windows.Core') -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Collections.Generic;

public static class EnemyStaticExport {
    public static string HeadReport="";
    static Color Hex(string s) { return ColorTranslator.FromHtml(s); }
    static Color Nearest(double r, double g, double b, Color[] palette) {
        double best=double.MaxValue; Color chosen=palette[0];
        foreach(Color c in palette) {
            double d=(r-c.R)*(r-c.R)*.30+(g-c.G)*(g-c.G)*.45+(b-c.B)*(b-c.B)*.25;
            if(d<best) { best=d; chosen=c; }
        }
        return chosen;
    }
    static Bitmap Double(Bitmap source) {
        Bitmap output=new Bitmap(source.Width*2,source.Height*2,PixelFormat.Format32bppArgb);
        for(int y=0;y<source.Height;y++) for(int x=0;x<source.Width;x++) {
            Color c=source.GetPixel(x,y);
            for(int dy=0;dy<2;dy++) for(int dx=0;dx<2;dx++) output.SetPixel(x*2+dx,y*2+dy,c);
        }
        return output;
    }
    static bool On(Bitmap b,int x,int y) { return x>=0 && y>=0 && x<b.Width && y<b.Height && b.GetPixel(x,y).A==255; }
    static int Light(Bitmap body,Bitmap layer,int ox,int oy,int bw,int bh,double[] points,Color[] colors) {
        int count=0; string centres="";
        for(int k=0;k<points.Length;k+=2) {
            int tx=ox+(int)Math.Round(points[k]*(bw-1)),ty=oy+(int)Math.Round(points[k+1]*(bh-1));
            int cx=-1,cy=-1;double best=double.MaxValue;
            for(int y=Math.Max(1,ty-3);y<Math.Min(body.Height-1,ty+4);y++) for(int x=Math.Max(1,tx-3);x<Math.Min(body.Width-1,tx+4);x++) {
                if(!On(body,x,y)||!On(body,x-1,y)||!On(body,x+1,y)||!On(body,x,y-1)||!On(body,x,y+1))continue;
                double d=(x-tx)*(x-tx)+(y-ty)*(y-ty);if(d<best){best=d;cx=x;cy=y;}
            }
            if(cx<0){cx=tx;cy=ty;}
            int[,] offsets={{0,0},{-1,0},{1,0},{0,-1},{0,1}};
            for(int i=0;i<5;i++){int x=cx+offsets[i,0],y=cy+offsets[i,1];if(On(body,x,y)){layer.SetPixel(x,y,colors[i==0?2:i%2]);count++;}}
            centres+=(k>0?",":"")+"["+cx+","+cy+"]";
        }
        HeadReport="["+centres+"]"; return count;
    }
    public static void Reuse(string root,string id,string[] colorsHex) {
        Color[] colors=Array.ConvertAll(colorsHex,Hex);
        bool chest=id=="mimic_disguised";
        string source=chest?Path.Combine(root,"references",id+".png"):Path.Combine(root,"..","f0","e_"+id+"_idle_f0.png");
        using(Bitmap original=new Bitmap(source)) {
            Bitmap body=new Bitmap(chest?32:original.Width,chest?32:original.Height,PixelFormat.Format32bppArgb);
            Bitmap emit=new Bitmap(body.Width,body.Height,PixelFormat.Format32bppArgb);
            if(chest) { for(int y=0;y<original.Height;y++)for(int x=0;x<original.Width;x++)body.SetPixel(9+x,17+y,original.GetPixel(x,y)); }
            else {
                using(Bitmap oldEmit=new Bitmap(Path.Combine(root,"..","f0","e_"+id+"_idle_f0_emit.png"))) {
                    for(int y=0;y<body.Height;y++)for(int x=0;x<body.Width;x++) {
                        Color b=original.GetPixel(x,y),e=oldEmit.GetPixel(x,y); body.SetPixel(x,y,b);
                        if(e.A>0){int tone=e.R>=170?2:e.R>=120?1:0;emit.SetPixel(x,y,colors[tone]);
                            if(id=="brood") body.SetPixel(x,y,Hex(tone==2?"#50617B":tone==1?"#30445F":"#1B2940"));
                        }
                    }
                }
            }
            string name=Path.Combine(root,"f0","e_"+id+"_idle_f0");
            body.Save(name+".png",ImageFormat.Png);emit.Save(name+"_emit.png",ImageFormat.Png);
            using(Bitmap high=Double(body)) high.Save(name+"@2x.png",ImageFormat.Png);
            using(Bitmap high=Double(emit)) high.Save(name+"_emit@2x.png",ImageFormat.Png);
            body.Dispose();emit.Dispose();
        }
    }
    public static string Run(string root,string id,int canvasWidth,int canvasHeight,int bodyHeight,string[] paletteHex,double[] points,string[] lightHex) {
        HeadReport="";
        Color[] palette=Array.ConvertAll(paletteHex,Hex); Color[] lights=Array.ConvertAll(lightHex,Hex); string input=Path.Combine(root,"generated",id+".png");
        using(Bitmap source=new Bitmap(input)) {
            int minX=source.Width,minY=source.Height,maxX=-1,maxY=-1;
            for(int y=0;y<source.Height;y++) for(int x=0;x<source.Width;x++) if(source.GetPixel(x,y).A>=128) {
                minX=Math.Min(minX,x); minY=Math.Min(minY,y); maxX=Math.Max(maxX,x); maxY=Math.Max(maxY,y);
            }
            if(maxX<minX) throw new Exception("empty generated source "+id);
            int bw=Math.Min(canvasWidth-4,(int)Math.Round((maxX-minX+1.0)/(maxY-minY+1)*bodyHeight));
            Bitmap body=new Bitmap(bw,bodyHeight,PixelFormat.Format32bppArgb);
            int active=0;
            // Generated artwork is registered to the final logical grid; no old runtime sprite is rescaled here.
            // Each cell samples only opaque foreground and snaps to the explicit working material palette.
            for(int y=0;y<bodyHeight;y++) for(int x=0;x<bw;x++) {
                int x0=minX+(int)Math.Floor(x*(maxX-minX+1.0)/bw);
                int x1=minX+(int)Math.Ceiling((x+1)*(maxX-minX+1.0)/bw);
                int y0=minY+(int)Math.Floor(y*(maxY-minY+1.0)/bodyHeight);
                int y1=minY+(int)Math.Ceiling((y+1)*(maxY-minY+1.0)/bodyHeight);
                double r=0,g=0,b=0; int n=0;
                for(int yy=y0;yy<y1;yy++) for(int xx=x0;xx<x1;xx++) {
                    Color c=source.GetPixel(xx,yy); if(c.A<128) continue;
                    n++;r+=c.R;g+=c.G;b+=c.B;
                }
                double coverage=(double)n/((x1-x0)*(y1-y0));
                if(n>0 && coverage>=.12) {
                    double rr=r/n,gg=g/n,bb=b/n;
                    // Restore Ishar's teal cloth material after an overly slate-blue source redraw.
                    if(id=="ishar" && bb>rr*1.25 && bb>gg*1.12) { gg=bb*.95; bb=bb*.98; }
                    // The small path fragment inherits the original blue gills, not generated pink ones.
                    if(id=="fractal" && rr>gg*1.15 && rr>bb*1.03) { bb=rr;gg=rr*.72;rr=rr*.52; }
                    body.SetPixel(x,y,Nearest(rr,gg,bb,palette));active++;
                }
            }
            // Alpha islands left by resampling cannot become stray one-pixel debris.
            Bitmap clean=(Bitmap)body.Clone(); int islands=0;
            for(int y=0;y<bodyHeight;y++) for(int x=0;x<bw;x++) if(On(body,x,y)) {
                int neighbors=0;
                for(int dy=-1;dy<=1;dy++) for(int dx=-1;dx<=1;dx++) if((dx!=0||dy!=0)&&On(body,x+dx,y+dy)) neighbors++;
                if(neighbors==0) { clean.SetPixel(x,y,Color.Transparent);islands++; }
            }
            body.Dispose();body=clean;
            Bitmap outlined=(Bitmap)body.Clone();
            for(int y=0;y<bodyHeight;y++) for(int x=0;x<bw;x++) if(On(body,x,y)) {
                bool top=!On(body,x,y-1), left=!On(body,x-1,y), bottom=!On(body,x,y+1), right=!On(body,x+1,y);
                if(!(top||left||bottom||right)) continue;
                Color c=body.GetPixel(x,y),edge=palette[0];
                if(!(bottom||right)) {
                    edge=c.R>c.G*1.25 && c.R>c.B*1.05 ? palette[3] : c.B>c.R+10 ? palette[1] : palette[2];
                }
                outlined.SetPixel(x,y,edge);
            }
            body.Dispose();body=outlined;
            int footX=canvasWidth/2,footY=canvasHeight-4,offsetX=footX-bw/2,offsetY=footY-bodyHeight;
            Bitmap output=new Bitmap(canvasWidth,canvasHeight,PixelFormat.Format32bppArgb);
            Bitmap emission=new Bitmap(canvasWidth,canvasHeight,PixelFormat.Format32bppArgb);
            int emitted=0;
            for(int y=0;y<bodyHeight;y++) for(int x=0;x<bw;x++) {
                Color c=body.GetPixel(x,y); if(c.A==0) continue;
                output.SetPixel(offsetX+x,offsetY+y,c);
            }
            emitted=Light(output,emission,offsetX,offsetY,bw,bodyHeight,points,lights);
            string dir=Path.Combine(root,"f0");Directory.CreateDirectory(dir);
            string file="e_"+id+"_idle_f0";
            output.Save(Path.Combine(dir,file+".png"),ImageFormat.Png);
            emission.Save(Path.Combine(dir,file+"_emit.png"),ImageFormat.Png);
            using(Bitmap hires=Double(output)) hires.Save(Path.Combine(dir,file+"@2x.png"),ImageFormat.Png);
            using(Bitmap hires=Double(emission)) hires.Save(Path.Combine(dir,file+"_emit@2x.png"),ImageFormat.Png);
            output.Dispose();emission.Dispose();body.Dispose();
            return id+" | body="+bw+"x"+bodyHeight+" | source_bbox="+minX+","+minY+","+(maxX+1)+","+(maxY+1)+" | sampled="+active+" | removed_islands="+islands+" | emit="+emitted;
        }
    }
}
'@
$job = Get-Content -Raw -LiteralPath (Join-Path $Root 'job.json') | ConvertFrom-Json
$records=@()
if($Ids.Count -gt 0 -and (Test-Path (Join-Path $Root 'head_glow_layout.json'))) {
    $records=@(Get-Content -Raw (Join-Path $Root 'head_glow_layout.json') | ConvertFrom-Json | Where-Object { $_.id -notin $Ids })
}
foreach($item in $job.jobs) {
    if($Ids.Count -gt 0 -and $item.id -notin $Ids) { continue }
    if(!(Test-Path -LiteralPath (Join-Path $Root "generated/$($item.id).png"))) { [EnemyStaticExport]::Reuse($Root,$item.id,[string[]]$item.emission_palette); continue }
    $points=@(); foreach($point in $item.emission_points_normalized){ $points+= $point[0]; $points+=$point[1] }
    [EnemyStaticExport]::Run($Root,$item.id,$item.canvas_1x[0],$item.canvas_1x[1],$item.visible_height_1x,[string[]]$item.palette,[double[]]$points,[string[]]$item.emission_palette)
    $records+=@{id=$item.id;centers=([EnemyStaticExport]::HeadReport | ConvertFrom-Json)}
}
[IO.File]::WriteAllText((Join-Path $Root 'head_glow_layout.json'),((ConvertTo-Json -InputObject @($records) -Depth 8) -replace "`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
