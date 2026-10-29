"""Approved native FX material -> fixed-grid full animation strips.

No image synthesis, whole-frame scaling or whole-frame camera motion: the authored
keyframes are reused as material, with independent core reveals, fragment travel
and gravity. The current Texas sword strip remains pixel-exact, frames 0..4.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib, json, math
import numpy as np

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[1]
GAME = Path('E:/ArknightsSurvivors/art/incoming')
NAMES = ['fx_ult_texas_slash_front', 'fx_ult_texas_sword_front',
         'fx_ult_exusiai_burst_front', 'fx_ult_exusiai_lock_orbit',
         'fx_ult_ulpianus_burst_front']
META = {a['name']: a for a in json.loads((ROOT/'animation_keyframe_manifest.json').read_text(encoding='utf8'))['assets']}
NEAR = Image.Resampling.NEAREST

def H(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def blank(size): return Image.new('RGBA', size)
def small(im): return im.resize((im.width//2, im.height//2), NEAR)
def big(im): return im.resize((im.width*2, im.height*2), NEAR)
def array(im): return np.asarray(im).copy()
def from_array(a):
    a[a[:,:,3] == 0] = 0
    return Image.fromarray(a.astype('uint8'))
def take(im, mask):
    a = array(im); a[~mask] = 0
    return from_array(a)
def tone(im, mul):
    a = array(im); a[:,:,:3] = np.round(a[:,:,:3].astype(float)*mul).clip(0,255)
    return from_array(a)
def pair(name): return [small(Image.open(ROOT/k['file']).convert('RGBA')) for k in META[name]['keyframes']]
def groups(im, mask=None):
    a = array(im); mask = a[:,:,3] > 0 if mask is None else mask.copy()
    found = []
    for y in range(im.height):
        for x in range(im.width):
            if not mask[y,x]: continue
            pending=[(x,y)]; mask[y,x]=False; points=[]
            while pending:
                px,py=pending.pop();points.append((px,py))
                for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx,ny=px+dx,py+dy
                    if 0<=nx<im.width and 0<=ny<im.height and mask[ny,nx]:
                        pending.append((nx,ny));mask[ny,nx]=False
            m=np.zeros(a.shape[:2],bool)
            for px,py in points:m[py,px]=True
            found.append((take(im,m),len(points),np.mean(points,axis=0)))
    return sorted(found,key=lambda v:-v[1])
def irregular_fragments(im, count, seed):
    """Partition existing painted material into irregular connected regions.

    This preserves authored texture while avoiding the square tile seams of a
    rectangular breakup. Seeds come from opaque source pixels, not new imagery.
    """
    a=array(im);ys,xs=np.where(a[:,:,3]>0);rng=np.random.default_rng(seed)
    chosen=rng.choice(len(xs),min(count,len(xs)),replace=False)
    seeds=np.stack((xs[chosen],ys[chosen]),axis=1);yy,xx=np.indices(a.shape[:2])
    distances=[]
    for j,(x,y) in enumerate(seeds):
        distances.append((xx-x)**2+(yy-y)**2+1.8*np.sin(xx*.61+j)*np.cos(yy*.43-j))
    owner=np.argmin(distances,axis=0)
    for j,(x,y) in enumerate(seeds):
        m=(owner==j)&(a[:,:,3]>0)
        if m.any():yield take(im,m),(float(xx[m].mean()),float(yy[m].mean())),j

def cool_fire(im,t):
    a=array(im);rgb=a[:,:,:3].astype(float);hot=rgb[:,:,0]>225
    rgb*= [1,.72,.44][t-1]
    if t==1:
        # Keep three temperature levels in the fading core. A single replacement
        # orange would flatten the source texture into a solid ball.
        green=a[:,:,1]
        rgb[hot&(green>200)]=np.array([255,180,72])
        rgb[hot&(green>130)&(green<=200)]=np.array([235,104,30])
        rgb[hot&(green<=130)]=np.array([199,63,20])
    elif t==2:
        rgb[hot]=np.array([166,61,25])
    else:
        rgb[hot]=np.array([93,35,24])
    a[:,:,:3]=rgb.clip(0,255)
    return from_array(a)

def slash():
    name=NAMES[0];start,peak=pair(name);w,h=peak.size
    yy,xx=np.indices((h,w));core_mask=abs(yy-h/2)<=5
    core=take(peak,core_mask);branches=take(peak,~core_mask)
    pieces=groups(branches);frames=[start]
    # The strike grows in thickness, with the existing hand-authored rough edge.
    for f in (1,2,3):
        im=blank((w,h)); radius=(1,2,5)[f-1]
        im.alpha_composite(take(peak,abs(yy-h/2)<=radius))
        for j,(piece,area,center) in enumerate(pieces):
            if area<2 or (j+f)%3==0:continue
            dx=round((center[0]-w/2)*(.006 if f==1 else .003)*(3-f))
            dy=round((center[1]-h/2)*(.15*(3-f)))
            im.alpha_composite(piece,(-dx,-dy))
        frames.append(im)
    frames.append(peak)
    # Continuous slash core fractures into short streaks. Material splinters leave
    # the cut in their authored directions rather than blinking in place.
    for t in (1,2,3):
        im=blank((w,h))
        if t==1:
            keep=(abs(yy-h/2)<=2)&((np.sin(xx*.083)+.5*np.sin(xx*.219))>-.85)
        elif t==2:
            keep=(abs(yy-h/2)<=1)&((np.sin(xx*.083)+.5*np.sin(xx*.219))>.65)
        else:
            keep=(abs(yy-h/2)<=1)&((np.sin(xx*.083)+.5*np.sin(xx*.219))>1.28)
        im.alpha_composite(tone(take(peak,keep),[1,.79,.5][t-1]))
        for j,(piece,area,center) in enumerate(pieces):
            if area<2 or (t==3 and j%3):continue
            # Upper and lower shards diverge; gravity curves their last step.
            sx=-1 if center[0]<w/2 else 1
            sy=-1 if center[1]<h/2 else 1
            dx=sx*t*(1+j%3);dy=sy*(t*2)+round(.45*t*t)
            cut=piece
            if t>=2:
                a=array(cut); py,px=np.indices(a.shape[:2])
                cut=take(cut,((px//2+py//2+j)%5)<(4-t))
            im.alpha_composite(tone(cut,[.9,.7,.5][t-1]),(dx,dy))
        frames.append(im)
    return [big(f) for f in frames], {
        'fps':24,'origin_px_2x':[384,40], 'segments':{'start':[0,2],'burst':[3,5],'out':[6,7]},
        'motion':'Authored core reveals in 1/2/5px bands; independent source splinters diverge and fall; core breaks into cooling streaks.',
        'representative_frame':4,'approved_keyframes_exact':[0,4]}

def sword():
    source=GAME/'fx_texas_sword_drop@2x.png';im=Image.open(source).convert('RGBA');fw=im.width//5
    frames=[]
    for f in range(5):
        out=blank((64,224));out.alpha_composite(im.crop((f*fw,0,(f+1)*fw,im.height)),(20,148));frames.append(out)
    final=frames[4].copy();d=ImageDraw.Draw(final)
    # Additional settling chips are separate from the native sword pixels. The
    # original source rectangle remains untouched, including its existing spark.
    for x,y,dx,col in [(14,218,-2,(88,112,154,255)),(47,218,2,(88,112,154,255)),
                       (17,222,-2,(182,157,75,255)),(44,222,2,(182,157,75,255))]:
        d.rectangle((x,y,x+1,y+1),fill=col)
        if y<220:d.rectangle((x+dx,y+2,x+dx+1,y+3),fill=(54,72,106,255))
    frames.append(final)
    return frames,{'fps':20,'origin_px_2x':[32,224],
        'segments':{'fall':[0,2],'impact':[3,4],'settle':[5,5]},'representative_frame':4,
        'native_source':str(source),'native_source_frame_count':5,'source_frame_map':[0,1,2,3,4,4],
        'source_to_delivery_offset':[20,148],'source_frame_size':[24,80],
        'motion':'Current runtime strip frames 0..4 unchanged in original order and at 20fps; sixth frame adds independently landed chips outside source rectangle.',
        'spec_change':'Old keyframe f3 showed native frame4. Full animation representative is now f4 to retain every native frame in original order; sixth settling frame preserves the 6-frame delivery contract.',
        'approved_keyframes_exact':[0]}

def explosion():
    name=NAMES[2];start,peak=pair(name);w,h=peak.size;yy,xx=np.indices((h,w));cx=cy=31.5
    rr=np.sqrt((xx-cx)**2+(yy-cy)**2);angle=np.arctan2(yy-cy,xx-cx)
    sector=((angle+math.pi)/(math.pi*2)*10).astype(int)%10
    components=groups(peak);frames=[start]
    im=blank((w,h));im.alpha_composite(take(peak,rr<8))
    # Independently approaching spark clusters, followed by the original peak.
    for j,(p,area,c) in enumerate(components[1:]):
        dx=round((c[0]-cx)*.26);dy=round((c[1]-cy)*.26)
        im.alpha_composite(p,(-dx,-dy))
    im.alpha_composite(take(peak,(rr>=8)&(rr<15)&(sector%3!=1)))
    frames.append(im);frames.append(peak)
    fragments=list(irregular_fragments(peak,26,317))
    for t in (1,2,3):
        im=blank((w,h))
        # Asymmetric chunks retain the source's silhouette, avoiding a regular
        # wheel of radial wedges. Hot areas cool to orange before dark red.
        for p,c,j in fragments:
            dx=round((c[0]-cx)*(.055*t+.009*t*t))
            dy=round((c[1]-cy)*(.055*t)+.85*t*t)
            if t==2 and j%4==0:continue
            if t==3:
                if j%3:continue
                p=take(p,(rr>12)&((xx+yy+j)%3!=0))
            elif t==2:
                p=take(p,(rr>3)|((xx+yy+j)%3==0))
            im.alpha_composite(cool_fire(p,t),(dx,dy))
        frames.append(im)
    return [big(f) for f in frames],{'fps':30,'origin_px_2x':[64,64],
        'segments':{'ignite':[0,1],'burst':[2,2],'out':[3,5]},'representative_frame':2,
        'motion':'Compact ignition; authored orange/red peak; asymmetric source-material fragments cool to orange/red, separate and curve down under gravity.',
        'approved_keyframes_exact':[0,2]}

def lock():
    name=NAMES[3];start,peak=pair(name);frames=[];gold=(231,169,58,255)
    for inset in [6,9,11,12,12,12]:
        im=blank((48,48));d=ImageDraw.Draw(im);far=47-inset
        for x,sx in [(inset,1),(far,-1)]:
            for y,sy in [(inset,1),(far,-1)]:d.line((x+sx*5,y,x,y,x,y+sy*5),fill=gold,width=1)
        frames.append(im)
    for t in (1,2):
        im=blank((48,48));d=ImageDraw.Draw(im)
        for x,sx in [(12,1),(35,-1)]:
            for y,sy in [(12,1),(35,-1)]:
                px=x-sx*(2*t);py=y-sy*t+round(.5*t*t)
                if t==1:
                    d.line((px,py,px+sx*2,py),fill=(199,136,41,255))
                    d.line((px-sx,py+sy*3,px-sx,py+sy*4),fill=(199,136,41,255))
                else:
                    d.point((px,py),fill=(137,91,34,255));d.point((px-sx*2,py+sy*5),fill=(137,91,34,255))
        frames.append(im)
    assert frames[0].tobytes()==start.tobytes() and frames[4].tobytes()==peak.tobytes()
    return [big(f) for f in frames],{'fps':24,'origin_px_2x':[48,48],
        'segments':{'start':[0,3],'loop':[4,5],'out':[6,7]},'representative_frame':4,
        'motion':'Four thin native corners converge, identical hold-loop endpoints, then each arm breaks into two outward moving fragments.',
        'loop_endpoint_exact':True,'approved_keyframes_exact':[0,4]}

def water():
    name=NAMES[4];start,peak=pair(name);a=array(peak);w,h=peak.size;yy,xx=np.indices((h,w))
    rgb=a[:,:,:3].astype(int);opaque=a[:,:,3]>0
    wet=opaque&(rgb[:,:,2]-rgb[:,:,0]>25)&(rgb[:,:,1]>70)
    stone=opaque&~wet; rocks=groups(peak,stone)
    water_layer=take(peak,wet);frames=[start]
    # Jet front climbs from ground. Every rock is independent and follows its
    # own upward launch; no full-frame scale transform is used.
    for f in (1,2):
        im=blank((w,h));threshold=(42,20)[f-1]
        rising_edge=threshold+4*np.sin(xx*.53)+3*np.sin(xx*.91+1)
        im.alpha_composite(take(water_layer,yy>=rising_edge))
        for j,(p,area,c) in enumerate(rocks):
            if area<3:continue
            dy=(43,16)[f-1]+j%3
            dx=round((31.5-c[0])*(.13 if f==1 else .04))
            im.alpha_composite(p,(dx,dy))
        frames.append(im)
    frames.append(peak)
    blocks=list(irregular_fragments(water_layer,55,919))
    for t in (1,2,3,4):
        im=blank((w,h))
        for p,c,j in blocks:
            # Sheet breaks into chunky drops with source-local variation. Outer
            # spray has larger lateral velocity than the central heavy jet.
            velocity=(c[0]-31.5)/16
            dx=round(velocity*t+(j%3-1)*t*.35)
            dy=round(t*t*3.8+(j%3-1)*t)
            keep=p
            if t>=2:
                pa=array(keep);ly,lx=np.indices((h,w))
                # Whole droplets disappear by lifetime, not alpha noise.
                if (j*3)%7 < (t-1):continue
                if t>=3:
                    # Preserve the brightest droplet material in each patch,
                    # with irregular shape and a brief falling tail.
                    keep=take(keep,((lx-c[0])**2+(ly-c[1])**2)<(6 if t==3 else 3))
            im.alpha_composite(tone(keep,[.97,.88,.75,.62][t-1]),(dx,dy))
        for j,(p,area,c) in enumerate(rocks):
            if area<5:continue
            dx=round((c[0]-31.5)/12*t)
            dy=round(4*t*t)
            # A rock whose lowest point has reached the floor is replaced by
            # short resting stone chips at the point of contact.
            box=p.getbbox()
            if box[3]+dy>=94:
                if t<4:
                    d=ImageDraw.Draw(im);landx=max(3,min(60,round(c[0]+dx)))
                    d.polygon([(landx-2,92),(landx,90),(landx+3,93),(landx+1,94)],fill=(55,55,54,255))
                continue
            im.alpha_composite(p,(dx,dy))
        if t==4:
            # Last wet fragments hit the ground as low splashes, then vanish at
            # strip end. Source material is retained, not a new halo.
            mask=(yy>=84)&((xx//3)%3==1)
            im.alpha_composite(tone(take(start,mask),.65))
        frames.append(im)
    return [big(f) for f in frames],{'fps':20,'origin_px_2x':[64,192],
        'segments':{'eruption':[0,3],'fall':[4,7]},'representative_frame':3,
        'motion':'Ground-up water-front reveal and independent neutral rock launches; jet breaks into source-texture droplets, rocks accelerate down and become contact chips.',
        'approved_keyframes_exact':[0,3]}

def export():
    OUT.mkdir(parents=True,exist_ok=True);entries=[];qa=[]
    builders=[slash,sword,explosion,lock,water]
    for name,builder in zip(NAMES,builders):
        frames,extra=builder();meta=META[name];w,h=meta['physical_size'];n=meta['frame_count']
        assert len(frames)==n and all(f.size==(w,h) for f in frames)
        sheet=blank((w*n,h))
        for i,im in enumerate(frames):
            ar=array(im);assert set(np.unique(ar[:,:,3]))<={0,255}
            assert np.count_nonzero(ar[:,:,3])>0
            sheet.alpha_composite(im,(i*w,0))
        p=OUT/(name+'@2x.png');sheet.save(p)
        sourcehash=[{'file':str(ROOT/k['file']),'sha256':H(ROOT/k['file'])} for k in meta['keyframes']]
        if name==NAMES[1]:sourcehash.append({'file':str(GAME/'fx_texas_sword_drop@2x.png'),'sha256':H(GAME/'fx_texas_sword_drop@2x.png')})
        entry={'name':name,'file':str(p),'physical_size':[w,h],'logical_size':[w//2,h//2],
            'frame_count':n,'layer':name.rsplit('_',1)[1], 'rgba_mib':w*h*n*4/1048576,
            'sha256':H(p),'sourcehash':sourcehash,'status':'full_animation_art_candidate','runtime_verified':False,**extra}
        exact=[]
        for f in entry['approved_keyframes_exact']:
            k=next(k for k in meta['keyframes'] if k['frame']==f)
            assert frames[f].tobytes()==Image.open(ROOT/k['file']).convert('RGBA').tobytes(),(name,f)
            exact.append(f)
        fq=[{'frame':i,'bbox':im.getbbox(),'opaque_pixels':int(np.count_nonzero(array(im)[:,:,3])),
              'sha256_rgba':hashlib.sha256(im.tobytes()).hexdigest()} for i,im in enumerate(frames)]
        # Each frame is mechanically distinct, except the deliberately stationary
        # lock hold-loop whose equality is a delivery requirement.
        for i in range(1,len(frames)):
            if name==NAMES[3] and i in (4,5):continue
            assert frames[i].tobytes()!=frames[i-1].tobytes(),(name,'duplicate',i)
        entries.append(entry);qa.append({'name':name,'dimensions':True,'binary_alpha':True,'approved_keyframes_exact':exact,'frames':fq})
    (OUT/'entries.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'qa.json').write_text(json.dumps({'assets':qa,'runtime_verified':False,'build_sha256':H(__file__)},ensure_ascii=False,indent=2),encoding='utf8')
    contact(entries)
    print(json.dumps({'assets':len(entries),'frames':sum(e['frame_count'] for e in entries),'rgba_mib':sum(e['rgba_mib'] for e in entries)},ensure_ascii=False))

def contact(entries):
    font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',15)
    # Full strips shown in two rows of four cells. Slash gets a dedicated full-
    # width view; other effects retain exact physical size on the contact sheet.
    W=1590;rows=[]
    for e in entries:
        w,h=e['physical_size'];n=e['frame_count'];src=Image.open(e['file']).convert('RGBA')
        if w>400:
            row=Image.new('RGBA',(W,50+((n+1)//2)*(h+28)),(16,25,30,255));d=ImageDraw.Draw(row)
            d.text((12,7),e['name']+' / '+str(e['fps'])+'fps',font=font,fill='white')
            for f in range(n):
                x=12+(f%2)*790;y=50+(f//2)*(h+28)
                row.alpha_composite(src.crop((f*w,0,(f+1)*w,h)),(x,y));d.text((x,y-18),str(f),font=font,fill='#94aeb8')
        else:
            row=Image.new('RGBA',(W,h+60),(16,25,30,255));d=ImageDraw.Draw(row)
            d.text((12,6),e['name']+' / '+str(e['fps'])+'fps',font=font,fill='white')
            for f in range(n):
                x=12+f*180;y=50;row.alpha_composite(src.crop((f*w,0,(f+1)*w,h)),(x,y));d.text((x,y-19),str(f),font=font,fill='#94aeb8')
        rows.append(row)
    im=Image.new('RGBA',(W,sum(r.height for r in rows)+20*len(rows)),(9,15,19,255));y=0
    for r in rows:im.alpha_composite(r,(0,y));y+=r.height+20
    im.convert('RGB').save(OUT/'contact_all_frames.png')
    # An enlarged material-action sheet helps inspect the short burst and water.
    rows=[]
    for e in entries[1:]:
        w,h=e['physical_size'];n=e['frame_count'];src=Image.open(e['file']).convert('RGBA')
        row=Image.new('RGBA',(max(1300,n*(w+15)),h+48),(17,25,30,255));d=ImageDraw.Draw(row)
        for f in range(n):
            x=f*(w+15)+5;row.alpha_composite(src.crop((f*w,0,(f+1)*w,h)),(x,36));d.text((x,8),str(f),font=font,fill='white')
        rows.append(row)
    out=Image.new('RGBA',(max(r.width for r in rows),sum(r.height+18 for r in rows)),(9,15,19,255));y=0
    for r in rows:out.alpha_composite(r,(0,y));y+=r.height+18
    out.convert('RGB').save(OUT/'detail_contact.png')

if __name__=='__main__':export()
