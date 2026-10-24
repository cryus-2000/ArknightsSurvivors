"""Four static menu studies: crisp pixel scene, smooth typographic UI."""
from pathlib import Path
from functools import lru_cache
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

P = Path(__file__).resolve().parent
ROOT = next(p for p in P.parents if (p/'game/fonts/ui.ttf').exists())
S = 3
W, H = 1280, 720
OUT = (1920,1080)
WHITE = '#e4e9ec'
MUTED = '#a0b2c0'
LINE = '#526a7a'
CYAN = '#4ed1e2'
INK = '#15232d'
FONT_PATHS = {
    'bold':ROOT/'game/fonts/ui.ttf',
    'serif':ROOT/'game/fonts/serif.ttf',
    'regular':Path('C:/Windows/Fonts/msyh.ttc'),
    'latin':Path('C:/Windows/Fonts/bahnschrift.ttf'),
}
TEXT_BOXES = []
CURRENT = ''


@lru_cache(None)
def font(size,face):
    return ImageFont.truetype(str(FONT_PATHS[face]),round(size*S))


def text(im,x,y,value,size=22,color=WHITE,face='regular',spacing=0):
    d=ImageDraw.Draw(im)
    f=font(size,face)
    cursor=x*S
    if spacing:
        for char in value:
            d.text((cursor,y*S),char,font=f,fill=color,anchor='lt')
            cursor+=d.textlength(char,font=f)+spacing*S
        width=(cursor-x*S)/S-spacing
    else:
        d.text((x*S,y*S),value,font=f,fill=color,anchor='lt')
        width=d.textlength(value,font=f)/S
    TEXT_BOXES.append((CURRENT,value,round(x,2),round(y,2),round(width,2),size))
    assert x>=0 and y>=0 and x+width<=W+1 and y+size<=H+1,(CURRENT,value,x,y,width)


def rect(im,box,fill,outline=None,width=1):
    ImageDraw.Draw(im).rectangle(tuple(round(v*S) for v in box),fill=fill,outline=outline,width=round(width*S))


def poly(im,pts,fill):
    ImageDraw.Draw(im).polygon([(round(x*S),round(y*S)) for x,y in pts],fill=fill)


def line(im,pts,fill=LINE,width=1):
    ImageDraw.Draw(im).line([(round(x*S),round(y*S)) for x,y in pts],fill=fill,width=max(1,round(width*S)),joint='curve')


def circle(im,x,y,r,fill=None,outline=WHITE,width=1):
    ImageDraw.Draw(im).ellipse(((x-r)*S,(y-r)*S,(x+r)*S,(y+r)*S),fill=fill,outline=outline,width=round(width*S))


def arrow(im,x,y,length=30,color=CYAN,width=1.5):
    line(im,[(x,y),(x+length,y)],color,width)
    line(im,[(x+length-9,y-9),(x+length,y),(x+length-9,y+9)],color,width)


def icon(im,x,y,kind,color=WHITE,scale=1):
    def pts(items): return [(x+a*scale,y+b*scale) for a,b in items]
    def ln(items): line(im,pts(items),color,1.25*scale)
    if kind=='headhunt':
        circle(im,x-3*scale,y-5*scale,4*scale,None,color,1.25*scale)
        ln([(-11,10),(-11,6),(-8,2),(1,2),(5,6),(5,10)])
        ln([(6,-8),(11,-5),(10,0),(7,2),(12,4),(14,9)])
    elif kind=='gallery':
        ln([(0,12),(-11,7),(-14,7),(-14,-10),(-6,-10),(0,-6),(6,-10),(14,-10),(14,7),(11,7),(0,12),(0,-6)])
        ln([(-10,-5),(-5,-3)]);ln([(5,-3),(10,-5)])
    elif kind=='cognition':
        ln([(-12,-6),(0,5),(10,-11)]);ln([(0,5),(13,12)])
        for a,b in [(-12,-6),(0,5),(10,-11),(13,12)]:
            ln([(a,b-3),(a+3,b),(a,b+3),(a-3,b),(a,b-3)])
    elif kind=='trial':
        ln([(-11,-10),(11,10)]);ln([(-11,10),(11,-10)])
        ln([(-11,-10),(-6,-9),(-10,-5)]);ln([(11,-10),(6,-9),(10,-5)])
    elif kind=='settings':
        for a,b in [(-10,-7),(0,4),(10,-2)]:
            ln([(a,-13),(a,b-3)]);ln([(a,b+3),(a,13)])
            circle(im,x+a*scale,y+b*scale,3*scale,None,color,1.2*scale)


def logo(im,x=895,y=32,width=334):
    src=Image.open(P/'assets/logo.png').convert('RGBA')
    # The logo is a frozen approved pixel asset; smooth UI does not redraw its identity.
    size=(round(width*S),round(width*src.height/src.width*S))
    im.alpha_composite(src.resize(size,Image.Resampling.NEAREST),(round(x*S),round(y*S)))


def layer():return Image.new('RGBA',(W*S,H*S),(0,0,0,0))


def footer(im,start=50,y=680,color=MUTED):
    x=start
    for value in ['设置','操作说明','退出']:
        text(im,x,y,value,14,color)
        x+=len(value)*14+30


def tiny_header(im,x=49,y=36):
    rect(im,(x,y,x+3,y+23),CYAN)
    text(im,x+16,y,'罗德岛',16)
    text(im,x+16,y+27,'TERMINAL',9,MUTED,'latin',2.8)


def variant_a():
    im=layer();logo(im);tiny_header(im)
    line(im,[(192,48),(456,48)],'#3c5566')
    for idx,(y,cn,en,kind) in enumerate([(231,'寻访','HEADHUNT','headhunt'),(340,'图鉴','GALLERY','gallery'),(449,'认知塑造','COGNITION','cognition')]):
        icon(im,73,y+21,kind,WHITE,1.05)
        text(im,109,y,cn,30)
        text(im,111,y+45,en,10,MUTED,'latin',2.5)
        line(im,[(109,y+70),(295 if idx==2 else 253,y+70)],'#3d5362')
    icon(im,73,585,'trial',MUTED,.7)
    text(im,109,573,'试炼',19,MUTED)
    text(im,158,578,'测试版',10,MUTED)
    line(im,[(888,518),(930,518)],CYAN,2)
    text(im,944,513,'OPERATION',10,MUTED,'latin',3)
    text(im,884,548,'集结出发',54,WHITE,'bold')
    arrow(im,1150,580,67,CYAN,2)
    line(im,[(888,623),(1225,623)],'#6c8898')
    text(im,888,638,'DEPLOY',10,MUTED,'latin',3.5)
    text(im,1177,636,'Enter',13,WHITE,'latin')
    footer(im)
    return im


def variant_b():
    im=layer();logo(im)
    poly(im,[(39,34),(342,34),(380,73),(380,617),(348,649),(39,649)],(212,224,231,240))
    rect(im,(39,34,44,649),CYAN)
    text(im,69,60,'罗德岛',17,INK,'bold')
    text(im,69,88,'OPERATIONS / TERMINAL',9,'#596e7d','latin',2)
    line(im,[(69,119),(346,119)],'#9eafb9')
    text(im,69,147,'集结',45,INK,'bold')
    text(im,69,198,'出发',45,INK,'bold')
    text(im,70,263,'DEPLOY',11,'#657c8d','latin',3.5)
    poly(im,[(280,155),(349,155),(349,242),(280,242)],'#243f55')
    arrow(im,299,199,30,WHITE,1.5)
    line(im,[(69,299),(348,299)],'#a6b5bd')
    for y,cn,en,kind in [(331,'寻访','HEADHUNT','headhunt'),(411,'图鉴','GALLERY','gallery'),(491,'认知塑造','COGNITION','cognition')]:
        icon(im,84,y+14,kind,'#38546a',.8)
        text(im,116,y-3,cn,24,INK)
        text(im,117,y+29,en,9,'#617786','latin',2)
        arrow(im,321,y+15,18,'#45657c',1)
    line(im,[(69,560),(347,560)],'#a6b5bd')
    icon(im,83,601,'trial','#45657c',.65)
    text(im,115,587,'试炼',20,INK)
    text(im,171,594,'测试版',10,'#617786')
    footer(im,52,680)
    line(im,[(405,90),(428,90),(428,66)],'#667f90')
    line(im,[(1198,618),(1227,618),(1227,591)],'#667f90')
    text(im,1102,641,'RHODES ISLAND',9,MUTED,'latin',2)
    return im


def variant_c():
    im=layer();logo(im);tiny_header(im)
    for x,cn in [(50,'设置'),(117,'操作说明'),(213,'退出')]:text(im,x,119,cn,14,MUTED)
    # Bottom dock leaves the jellyfish and central ruins readable.
    rect(im,(40,560,1240,680),(13,26,36,238))
    line(im,[(40,560),(1240,560)],'#6c8290')
    rect(im,(40,560,44,680),CYAN)
    for x,cn,en,kind in [(75,'寻访','HEADHUNT','headhunt'),(277,'图鉴','GALLERY','gallery'),(476,'认知塑造','COGNITION','cognition')]:
        icon(im,x+17,599,kind,'#c1d0d8',.9)
        text(im,x+52,584,cn,22)
        text(im,x+53,622,en,9,MUTED,'latin',2)
    for x in [251,451,675]:line(im,[(x,591),(x,647)],'#385160')
    icon(im,712,599,'trial',MUTED,.8)
    text(im,741,585,'试炼',21)
    text(im,743,621,'测试版',10,MUTED)
    poly(im,[(877,560),(1240,560),(1240,680),(855,680)],'#c7dce4')
    rect(im,(1235,560,1240,680),CYAN)
    text(im,909,586,'集结出发',31,INK,'bold')
    text(im,911,638,'DEPLOY',10,'#486477','latin',3)
    arrow(im,1122,608,73,INK,2)
    text(im,1160,641,'Enter',12,'#486477','latin')
    return im


def variant_d():
    im=layer();logo(im)
    line(im,[(49,43),(349,43)],'#688495')
    text(im,49,60,'RHODES ISLAND',10,MUTED,'latin',3.3)
    # Editorial title: large type carries the action, support menus move to the lower right.
    text(im,48,170,'集结',78,WHITE,'serif')
    text(im,139,261,'出发',78,WHITE,'serif')
    line(im,[(51,368),(330,368)],'#6b8797')
    rect(im,(51,367,114,370),CYAN)
    text(im,53,390,'DEPLOY',13,WHITE,'latin',5)
    arrow(im,259,399,65,CYAN,2)
    text(im,53,435,'Enter',12,MUTED,'latin')
    # Offset, thin framed modules pick up the current gallery/settings language.
    for x,y,cn,en,kind in [(827,503,'寻访','HEADHUNT','headhunt'),(1024,503,'图鉴','GALLERY','gallery'),(827,593,'认知塑造','COGNITION','cognition')]:
        wide=393 if kind=='cognition' else 196
        rect(im,(x,y,x+wide,y+79),(17,33,45,228))
        line(im,[(x,y),(x+wide-5,y)],'#617b8b')
        icon(im,x+28,y+29,kind,'#bdcdd7',.75)
        text(im,x+55,y+13,cn,23)
        text(im,x+56,y+49,en,9,MUTED,'latin',2)
        if kind=='cognition':arrow(im,x+341,y+37,27,CYAN,1.2)
    icon(im,69,580,'trial',MUTED,.7)
    text(im,99,568,'试炼',18,MUTED)
    text(im,151,575,'测试版',10,MUTED)
    footer(im,51,678)
    return im


VARIANTS=[('A','悬浮导航',variant_a),('B','档案侧栏',variant_b),('C','底部控制台',variant_c),('D','字标构成',variant_d)]


def main():
    global CURRENT
    source_bg=Image.open(P/'assets/background_native.png').convert('RGBA')
    bg=source_bg.resize(OUT,Image.Resampling.NEAREST)
    desktop_bg=source_bg.resize((W,H),Image.Resampling.NEAREST)
    board=Image.new('RGB',(2560,1576),'#0e1720')
    bd=ImageDraw.Draw(board)
    for idx,(key,name,fn) in enumerate(VARIANTS):
        CURRENT=key
        vector_layer=fn()
        overlay=vector_layer.resize(OUT,Image.Resampling.LANCZOS)
        overlay.save(P/f'{key}_ui.png')
        full=Image.alpha_composite(bg,overlay).convert('RGB')
        full.save(P/f'{key}_overview.png')
        desktop=Image.alpha_composite(desktop_bg,vector_layer.resize((W,H),Image.Resampling.LANCZOS)).convert('RGB')
        desktop.save(P/f'{key}_desktop.png')
        x=(idx%2)*1280;y=(idx//2)*788
        bd.text((x+28,y+18),f'{key} / {name}',font=ImageFont.truetype(str(FONT_PATHS['regular']),24),fill=WHITE)
        board.paste(desktop,(x,y+68))
    board.save(P/'comparison.png')
    (P/'layout_bounds.json').write_text(json.dumps(TEXT_BOXES,ensure_ascii=False,indent=2),encoding='utf-8')
    manifest={
        'status':'four static concept variants; not approved or integrated',
        'canvas':list(OUT),'desktop_canvas':[W,H],'background_native':[640,360],'background_scaling':'nearest 3x or 2x; unchanged pixels, including comparison',
        'ui':'antialiased text and geometric icons; supersampled separately from scene',
        'logo':'approved 21 pixel logo retained; not redrawn',
        'variants':{key:name for key,name,_ in VARIANTS},
        'menu_entries':['集结出发','寻访','图鉴','认知塑造','试炼（测试版）','设置','操作说明','退出'],
        'generation':'programmatic composition only; no new generated imagery',
        'assets':{f.name:hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted((P/'assets').glob('*.png'))},
        'fonts':{k:str(v) for k,v in FONT_PATHS.items()},
    }
    (P/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Rendered 4 full scenes at 1920x1080 + 1280x720, 4 UI layers and comparison sheet.')


if __name__=='__main__':main()
