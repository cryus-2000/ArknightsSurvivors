param([string]$Root = $PSScriptRoot)
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
    static Color[] Palette(string id) {
        string shared = "#080E18,#263348,#4B4D5A,#3D1A2B,";
        string extra;
        switch (id) {
            case "bone": extra="#1B2940,#30445F,#50617B,#7A8294,#75737A,#AAA7A5,#D1CABD,#E2D9C5"; break;
            case "stone": extra="#202637,#3A4257,#606679,#35435F,#596782,#8F96A5,#A6A4A0,#D9D0BE,#633547,#91546A"; break;
            case "carmen": extra="#1C202A,#333844,#575B66,#777B82,#634D48,#A48375,#C7AD91,#8E9298,#BDC0BC,#DFD9C9,#666F7D,#9CA6AF,#C8CBD0,#47283D,#75445E,#98667B"; break;
            case "brood": extra="#362C3A,#71717D,#96939B,#BDB6AE,#D9CFBF,#54172F,#87304B,#B44D68"; break;
            default: throw new Exception(id);
        }
        return Array.ConvertAll((shared+extra).Split(','), Hex);
    }
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
    static int HeadLight(string root,string id,Bitmap body,Bitmap layer,int ox,int oy,int bw,int bh) {
        // User revision: generated edits are placement guides only. Never paste their body pixels.
        // All new head lights live exclusively in a separate same-canvas emission layer.
        int[] roi=id=="bone" ? new int[]{21,14,28,21} : id=="stone" ? new int[]{23,20,31,27} : new int[]{20,24,25,29};
        int minX=int.MaxValue,minY=int.MaxValue,maxX=-1,maxY=-1;double sx=0,sy=0,weight=0;
        using(Bitmap guide=new Bitmap(Path.Combine(root,"generated","head_guides",id+".png"))) {
            for(int y=0;y<guide.Height;y++) for(int x=0;x<guide.Width;x++) if(guide.GetPixel(x,y).A>=128) {
                minX=Math.Min(minX,x);minY=Math.Min(minY,y);maxX=Math.Max(maxX,x);maxY=Math.Max(maxY,y);
            }
            for(int y=minY;y<=maxY;y++) for(int x=minX;x<=maxX;x++) {
                Color c=guide.GetPixel(x,y);if(c.A<128 || c.R<85 || c.R<c.G*1.45 || c.R<c.B*1.1) continue;
                double fx=(x-minX)/(double)(maxX-minX),fy=(y-minY)/(double)(maxY-minY);
                if(id=="carmen" ? fy>.32 || fx<.2 || fx>.65 : fx<.55 || fy<.3 || fy>.7) continue;
                double w=c.R-c.G;sx+=x*w;sy+=y*w;weight+=w;
            }
        }
        if(weight<=0) throw new Exception("no head marker in guide "+id);
        int cx=ox+(int)Math.Round((sx/weight-minX)/(maxX-minX)*(bw-1));
        int cy=oy+(int)Math.Round((sy/weight-minY)/(maxY-minY)*(bh-1));
        // User: Carmen's frontal/forehead placement is awkward. Translate the existing
        // independent five-pixel light to the rear side of the hat band; no new body pixels.
        if(id=="carmen") { cx=22;cy=26; }
        int bestX=-1,bestY=-1;double best=double.MaxValue;
        for(int y=roi[1];y<roi[3];y++) for(int x=roi[0];x<roi[2];x++) {
            if(!On(body,x,y)||!On(body,x-1,y)||!On(body,x+1,y)||!On(body,x,y-1)||!On(body,x,y+1)) continue;
            double d=(x-cx)*(x-cx)+(y-cy)*(y-cy);
            if(d<best) {best=d;bestX=x;bestY=y;}
        }
        if(bestX<0) throw new Exception("no opaque head area "+id);
        int[,] offsets=new int[,]{{0,0},{-1,0},{0,1},{0,-1},{1,0}};
        Color[] light=new Color[]{Hex("#B44D68"),Hex("#87304B"),Hex("#54172F"),Hex("#87304B"),Hex("#54172F")};
        int n=0;string points="";
        for(int i=0;i<5;i++) {
            int x=bestX+offsets[i,0],y=bestY+offsets[i,1];
            if(x<roi[0]||x>=roi[2]||y<roi[1]||y>=roi[3]||!On(body,x,y)) continue;
            layer.SetPixel(x,y,light[i]);points+=(n>0?",":"")+"["+x+","+y+"]";n++;
        }
        HeadReport="{\"id\":\""+id+"\",\"center\":["+bestX+","+bestY+"],\"roi\":["+String.Join(",",roi)+"],\"pixels\":["+points+"],\"layer_only\":true}";
        return n;
    }
    public static string Run(string root,string id,int canvasWidth,int canvasHeight,int bodyHeight) {
        HeadReport="";
        Color[] palette=Palette(id); string input=Path.Combine(root,"generated",id+".png");
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
                if(n>0 && coverage>=.12) { body.SetPixel(x,y,Nearest(r/n,g/n,b/n,palette));active++; }
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
                // Existing brood organ is retained. New head indicators are added separately below.
                if(id=="brood" && (c.ToArgb()==Hex("#54172F").ToArgb() || c.ToArgb()==Hex("#87304B").ToArgb() || c.ToArgb()==Hex("#B44D68").ToArgb())) {
                    emission.SetPixel(offsetX+x,offsetY+y,c);emitted++;
                }
            }
            if(id!="brood") emitted=HeadLight(root,id,output,emission,offsetX,offsetY,bw,bodyHeight);
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
$headRecords=@()
foreach($item in $job.jobs) {
    [EnemyStaticExport]::Run($Root,$item.id,$item.canvas_1x[0],$item.canvas_1x[1],$item.visible_height_1x)
    if([EnemyStaticExport]::HeadReport) { $headRecords+=([EnemyStaticExport]::HeadReport | ConvertFrom-Json) }
}
[IO.File]::WriteAllText((Join-Path $Root 'head_glow_layout.json'),((ConvertTo-Json -InputObject @($headRecords) -Depth 8) -replace "`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false))
