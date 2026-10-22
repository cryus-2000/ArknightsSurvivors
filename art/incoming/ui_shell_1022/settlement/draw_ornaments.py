"""Original navigation/print ornaments, drawn on a 2 px grid. No image generation."""
from pathlib import Path
from PIL import Image, ImageDraw
import math

P=Path(__file__).resolve().parent/'decor'
P.mkdir(exist_ok=True)

def navigation():
    n=192
    mask=Image.new('L',(n,n)); d=ImageDraw.Draw(mask)
    # A split navigation diamond, interrupted by two tidal traces.
    d.polygon([(96,13),(109,78),(165,96),(107,109),(96,175),(82,108),(27,96),(84,82)],fill=125)
    d.polygon([(96,13),(96,96),(84,82)],fill=215)
    d.polygon([(165,96),(96,96),(109,78)],fill=185)
    d.polygon([(96,175),(96,96),(107,109)],fill=200)
    d.polygon([(27,96),(96,96),(82,108)],fill=175)
    d.polygon([(96,76),(116,96),(96,116),(76,96)],fill=0)
    for a,b in [(6,64),(78,158),(174,243),(258,336)]:
        d.arc((25,25,167,167),a,b,fill=160,width=1)
    for a,b in [(25,57),(112,146),(202,224),(292,325)]:
        d.arc((19,19,173,173),a,b,fill=85,width=1)
    for angle in range(0,360,15):
        a=math.radians(angle)
        r=76; r2=80 if angle%45==0 else 78
        d.line([(round(96+math.cos(a)*r),round(96+math.sin(a)*r)),(round(96+math.cos(a)*r2),round(96+math.sin(a)*r2))],fill=125)
    for off in [-3,3]:
        d.line([(81,96+off),(90,91+off),(102,101+off),(111,96+off)],fill=200,width=1)
    # Screen-print density; ordered, never photographic noise.
    out=Image.new('RGBA',(n,n))
    for y in range(n):
        for x in range(n):
            v=mask.getpixel((x,y))
            threshold=((x%2)*2+y%2)*42
            if v>threshold:out.putpixel((x,y),(67,78,91,110 if v>170 else 65))
    out.resize((384,384),Image.Resampling.NEAREST).save(P/'navigation_watermark@2x.png')

def portrait_plate():
    im=Image.new('RGBA',(96,80));d=ImageDraw.Draw(im)
    d.polygon([(62,0),(95,0),(39,79),(6,79)],fill=(132,151,177,15))
    for a,b in [(193,261),(278,348),(13,80),(99,163)]:
        d.arc((16,2,84,70),a,b,fill=(139,157,180,40),width=1)
    d.line([(49,0),(49,5)],fill=(139,157,180,90))
    d.line([(49,69),(49,75)],fill=(139,157,180,90))
    for y in range(1,26,3):
        for x in range(74+y//2,96,3):d.point((x,y),fill=(139,157,180,55))
    for x in range(5,93,4):d.line([(x,77),(x,79 if x%12==1 else 78)],fill=(139,157,180,80))
    im.resize((192,160),Image.Resampling.NEAREST).save(P/'portrait_calibration@2x.png')

def topography():
    # Survey-style contours from an original height field, not official geography.
    im=Image.new('RGBA',(640,360));d=ImageDraw.Draw(im)
    def height(x,y):
        u=x+8*math.sin(y/38)+4*math.sin(y/17)
        v=y+7*math.sin(x/27)
        def hill(cx,cy,rx,ry,a):return a*math.exp(-((u-cx)/rx)**2-((v-cy)/ry)**2)
        return (hill(620,186,55,68,1.3)+hill(638,272,43,33,1.15)
                +hill(553,68,72,48,.9)+hill(485,302,48,55,.62)
                -hill(565,214,23,52,.35))
    values={(x,y):height(x,y) for y in range(24,327) for x in range(438,642)}
    for i,level in enumerate([.16,.29,.42,.55,.68,.81,.94,1.07,1.20,1.33]):
        alpha=57 if i in (2,6) else 30
        for y in range(24,326):
            for x in range(438,641):
                vertices=[(x,y),(x+1,y),(x+1,y+1),(x,y+1)]
                crossings=[]
                for k in range(4):
                    a,b=vertices[k],vertices[(k+1)%4];va,vb=values[a],values[b]
                    if (va<level)!=(vb<level):
                        t=(level-va)/(vb-va)
                        crossings.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
                for k in range(0,len(crossings)-1,2):
                    # One secondary level is interrupted to distinguish survey boundaries.
                    if i==0 and (x+y)//5%3==0:continue
                    d.line(crossings[k:k+2],fill=(104,126,143,alpha),width=1)
    # A few registration marks; no new labels competing with battle data.
    for x,y in [(620,191),(633,274),(544,69)]:
        for a,b in [((x-4,y),(x-1,y)),((x+1,y),(x+4,y)),((x,y-4),(x,y-1)),((x,y+1),(x,y+4))]:
            d.line([a,b],fill=(139,154,166,65),width=1)
    # Quiet reading zones, expressed at native half resolution.
    protected=[(0,0,640,24),(0,104,458,324),(374,37,508,98),(573,42,628,93),
               (477,108,635,139),(503,141,616,169),(503,193,616,221),
               (503,246,616,273),(503,287,616,318),(0,325,640,360)]
    for y in range(360):
        for x in range(640):
            rr,gg,bb,aa=im.getpixel((x,y))
            if not aa:continue
            gap=min(max(l-x,0,x-r,t-y,0,y-b) for l,t,r,b in protected)
            # Discrete pixel-grid falloff, no blur or glow.
            factor=min(1,max(0,gap)/9)
            im.putpixel((x,y),(rr,gg,bb,round(aa*factor)))
    im.resize((1280,720),Image.Resampling.NEAREST).save(P/'topography_sparse@2x.png')

navigation();portrait_plate();topography()
