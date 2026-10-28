"""Grid-authored FX layers from existing glyph vocabulary; no game code changes."""
from pathlib import Path
import math, json, hashlib
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
P = ['080e18','10152b','1c2648','303f6b','4d5a9a','767ab7','a8afe0','dae5fa','f3f7ff']
C = [tuple(bytes.fromhex(v))+(255,) for v in P]
W,H=180,264
Y,X=np.mgrid[:H,:W]
DX,DY=X+.5-4,Y+.5-132
RR=np.hypot(DX,DY)
AA=np.arctan2(DY,DX)
MASK=(RR<=170)&(DX>=0)&(np.abs(AA)<=math.radians(50))

def blank(): return Image.new('RGBA',(W,H))
def point(r,a): return (round(4+r*math.cos(math.radians(a))),round(131.5+r*math.sin(math.radians(a))))
def clipped(im):
    a=np.array(im); a[~MASK]=0
    # Share a single upper half about the geometric y=132 origin.
    a[132:]=a[:132][::-1]
    return Image.fromarray(a)
def arc(draw,r,a,b,col,width=1):
    pts=[point(r,a+(b-a)*i/max(1,round((b-a)*r/30))) for i in range(max(1,round((b-a)*r/30))+1)]
    if len(pts)>1: draw.line(pts,fill=col,width=width)

# Existing approved angular alphabet: preserve strokes, reduce to a shared small grid.
atlas=Image.open(ROOT/'source/glyph_reference.png').convert('RGBA')
glyphs=[]
for k in range(16):
    cell=atlas.crop((k*64,0,(k+1)*64,atlas.height)); box=cell.getbbox()
    cell=cell.crop(box); cell.thumbnail((8,9),Image.Resampling.NEAREST)
    glyphs.append(cell)

def script_layer(phase, bright=False):
    # Floating ribbons are a separate upright layer; keep the field quiet.
    return blank()

def ground(phase):
    ar=np.array(blank())
    # Binary-alpha dark veil: 25% coverage, no interior calligraphy or light specks.
    veil=MASK & ((X%2)==0)&((Y%2)==0)
    ar[veil]=C[0]
    side=RR*np.sin(np.deg2rad(50)-np.abs(AA))
    band=MASK & (RR>17)&((RR>159)|(side<9))
    ar[band & ((X+Y)%2==0)]=C[1]
    im=Image.fromarray(ar);d=ImageDraw.Draw(im)
    arc(d,169,-49.5,49.5,C[3],2)
    arc(d,167,-48.8,48.8,C[2],1)
    for a in [-45,-30,-15,0,15,30,45]:
        arc(d,169,a-4,a+4,C[6],2)
    a=[-43,-31,-19,-7][phase]
    arc(d,169,a-1,a+1,C[8],2)
    for a in [-49.6,49.6]:
        d.line([point(12,a),point(167,a)],fill=C[3],width=2)
        for r in [42,80,118,151]:d.line([point(r,a),point(r+7,a)],fill=C[6],width=1)
    im.alpha_composite(script_layer(phase))
    return clipped(im)

grounds=[ground(i) for i in range(4)]
opens=[]
for i in range(8):
    if i==7: opens.append(grounds[0].copy());continue
    im=blank();d=ImageDraw.Draw(im)
    if i<3:
        tip=[47,101,168][i]
        d.line([(5,131),(tip,131)],fill=C[4],width=2)
        d.line([(tip-9,130),(tip,131),(tip-9,133)],fill=C[6],width=1)
    else:
        span=[9,23,39,50][i-3]
        arr=np.array(grounds[0]);arr[np.abs(AA)>math.radians(span)]=0
        if i<6:arr[(RR<160)&(RR>25)&((X+Y)%3!=0)]=0
        im=Image.fromarray(arr);d=ImageDraw.Draw(im)
        for a in [-span,span]:d.line([point(13,a),point(168,a)],fill=C[6],width=1)
    opens.append(clipped(im))

closes=[grounds[0].copy()]
for i in range(1,6):
    # Quiet interior clears toward the rim; only perimeter text briefly brightens.
    sweep=[0,40,79,118,152,169][i]
    ar=np.array(grounds[0]);ar[RR<sweep]=0
    im=Image.fromarray(ar)
    lit=np.array(script_layer(i,bright=i<4));lit[RR<sweep]=0
    if i>=4:lit[(X+Y)%3==0]=0
    im.alpha_composite(Image.fromarray(lit))
    closes.append(clipped(im))

slows=[]
for i in range(4):
    im=Image.new('RGBA',(24,24));d=ImageDraw.Draw(im)
    for a,b in [(15,64),(100,146),(203,246),(285,333)]:
        pts=[(round(11.5+7*math.cos(math.radians(t))),round(11.5+7*math.sin(math.radians(t)))) for t in range(a+i*5,b+i*5,4)]
        d.line(pts,fill=C[3],width=2);d.line(pts[1:-1],fill=C[4],width=1)
    for y in [7,12,17]:
        d.line([(6,y),(3,y-1+(i%2)),(1,y-1+(i%2))],fill=C[3],width=1)
    for x,y in [(14,5),(18,14),(9,18)]:d.line([(x,y),(x+1,y)],fill=C[6],width=1)
    outline=Image.new('RGBA',(24,24),C[0]);outline.putalpha(im.getchannel('A').filter(ImageFilter.MaxFilter(3)))
    outline.alpha_composite(im)
    ar=np.array(outline); yy,xx=np.mgrid[:24,:24];ar[(xx-11.5)**2+(yy-11.5)**2<5**2]=0
    slows.append(Image.fromarray(ar))

# Old continuous writing, turned upright; narrow strips keep the field readable.
script=Image.open(ROOT/'source/script_reference.png').convert('RGBA').resize((256,12),Image.Resampling.NEAREST)
ribbons=[]
pal=np.array([c[:3] for c in C],dtype=np.int32)
for k in range(8):
    phase=k//2
    band=script.crop((phase*64,2,phase*64+24,10)).transpose(Image.Transpose.ROTATE_90)
    out=Image.new('RGBA',(12,28))
    for y in range(24):
        wave=math.sin(y/24*math.pi*2+k*math.pi/4)
        width=round(6+wave)
        row=band.crop((0,y,8,y+1)).resize((width,1),Image.Resampling.NEAREST)
        ar=np.array(row);visible=ar[:,:,3]>127
        rgb=ar[:,:,:3].astype(np.float32)*(0.76+0.18*math.cos(y/24*math.pi*2-k*math.pi/4))
        nearest=np.argmin(((rgb[:,:,None,:]-pal[None,None,:,:])**2).sum(axis=3),axis=2)
        ar[:]=0;ar[visible]=np.array(C,dtype=np.uint8)[nearest[visible]]
        out.paste(Image.fromarray(ar),(round((12-width)/2+wave),y+2))
    ribbons.append(out)

ASSETS={'fan_open':(opens,16),'fan_ground':(grounds,6),'fan_close':(closes,16),'slow':(slows,12),'ribbon':(ribbons,8)}
manifest={'status':'user approved for art delivery; not integrated','palette':['#'+p for p in P], 'source':'existing Logos glyph vocabulary + grid-authored layers; imagegen component concept only','assets':[],'notes':['10-29 user revision: restore luminous edge, keep quiet dark interior, use old continuous script as small vertical floating strips along the edge.','Ground frame 0 == open frame 7 == close frame 0.','All symmetry is around geometric origin y=264 at @2x.']}
framesdir=ROOT/'preview';framesdir.mkdir(exist_ok=True)
for key,(frames,fps) in ASSETS.items():
    w,h=frames[0].size; sheet=Image.new('RGBA',(w*2*len(frames),h*2))
    for i,f in enumerate(frames):sheet.paste(f.resize((w*2,h*2),Image.Resampling.NEAREST),(i*w*2,0))
    name='fx_logos_s3_'+key+'@2x.png';sheet.save(ROOT/name,optimize=True)
    entry={'file':name,'frame_size':[w*2,h*2],'frames':len(frames),'fps':fps,'origin':([8,264] if key.startswith('fan_') else [24,24] if key=='slow' else [12,56]),'bytes':(ROOT/name).stat().st_size,'sha256':hashlib.sha256((ROOT/name).read_bytes()).hexdigest()}
    manifest['assets'].append(entry)
    for i,f in enumerate(frames):f.resize((w*2,h*2),Image.Resampling.NEAREST).save(framesdir/f'{key}_{i:02}.png')

# Presentation on the requested seabed tone, with true-sized reference orbit.
board=Image.new('RGB',(1100,620),'#0d1420');d=ImageDraw.Draw(board)
for j,(key,frame) in enumerate([('Open',opens[4]),('Hold',grounds[0]),('Clear',closes[3])]):
    tile=frame.resize((360,528),Image.Resampling.NEAREST);board.paste(tile,(j*365,55),tile);d.text((j*365+12,20),key,fill='#a8afe0')
board.save(framesdir/'contact.png')
grounds[0].resize((1440,2112),Image.Resampling.NEAREST).save(framesdir/'ground_8x.png')
manifest['total_runtime_bytes']=sum(a['bytes'] for a in manifest['assets'])
(ROOT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('runtime bytes',manifest['total_runtime_bytes'])
