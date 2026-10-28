from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat
import json, hashlib
import numpy as np
R=Path(__file__).resolve().parent
B=R.parent.parent/'headhunt_bag_1022'/'delivery'
N=24
DUR=[83,83,84]*8
field=Image.open(R/'source.png').convert('RGBA').resize((192,200),Image.Resampling.BOX).resize((384,400),Image.Resampling.NEAREST)
field.save(R/'light@2x.png')
base=Image.open(B/'ui_hh_bag_zip@2x.png').convert('RGBA').crop((1792,0,2048,152))
front=Image.open(B/'ui_hh_bag_zip_front@2x.png').convert('RGBA').crop((1792,0,2048,152))
clip=Image.open(R.parent/'delivery'/'fx_hh_mouth_clip@2x.png').convert('L').crop((1792,0,2048,320))

# Flow texture only along rays originating at the zipper. Angular coordinates
# never change, so straight beams cannot bend sideways into the rejected waves.
source_native=np.array(field.resize((192,200),Image.Resampling.NEAREST))
yy,xx=np.mgrid[:200,:192]
dx=xx-96.; dy=175.-yy
radius=np.hypot(dx,dy)
angle=np.arctan2(dx,dy)
root=np.clip((radius-18)/40,0,1)
root=root*root*(3-2*root)

def beam_frame(frame):
    phase=frame/N
    # Axial texture advection: bright details advance outward, tips extend and
    # dissolve independently. No global opacity/gain and no lateral displacement.
    displacement=11*root*np.sin(2*np.pi*(radius/95-phase)+angle*7)
    sample_radius=np.maximum(0,radius-displacement)
    scale=np.divide(sample_radius,radius,out=np.ones_like(radius),where=radius>0)
    sx=np.rint(96+dx*scale).astype(int)
    sy=np.rint(175-dy*scale).astype(int)
    valid=(sx>=0)&(sx<192)&(sy>=0)&(sy<200)
    out=np.zeros_like(source_native)
    out[valid]=source_native[sy[valid],sx[valid]]
    # The zipper root and below it remain precisely fixed.
    fixed=(radius<18)|(yy>=174)
    out[fixed]=source_native[fixed]
    return Image.fromarray(out).resize((384,400),Image.Resampling.NEAREST)

def compose(sparks,beam=None):
    light=(field if beam is None else beam).copy(); light.alpha_composite(sparks)
    canvas=Image.new('RGBA',(640,512),(25,34,44,255))
    canvas.alpha_composite(light,(96,46))
    canvas.alpha_composite(base,(160,330))
    inner=light.crop((64,78,320,398))
    inner.putalpha(ImageChops.multiply(inner.getchannel('A'),clip))
    canvas.alpha_composite(inner,(160,124))
    canvas.alpha_composite(front,(160,330))
    return canvas

# Sparse accents accompany the independently animated main light field.
# Each track begins at the zipper and follows one straight beam, no field warp.
targets=[(43,68),(64,43),(92,20),(116,47),(148,74),(59,88),(105,35),(132,88),(80,59)]
sparks=[]; frames=[]; positions=[]; beams=[]
for f in range(N):
    native=Image.new('RGBA',(192,200)); d=ImageDraw.Draw(native); track=[]
    for k,(tx,ty) in enumerate(targets):
        age=(f+k*7)%N
        p=age/N
        sx=87+(k*5)%19; sy=177-(sx-87)*.20
        x=sx+(tx-sx)*p; y=sy+(ty-sy)*p
        track.append((age,y))
        # Only individual fragments fade at birth/death. Main light stays exact.
        envelope=min(1,age/2,(N-1-age)/4)
        a=round(210*max(0,envelope)/42)*42
        ix,iy=round(x),round(y)
        if k%3==0:
            d.polygon([(ix,iy),(ix+1,iy+1),(ix,iy+3),(ix-1,iy+1)],fill=(255,233,156,a))
        else:
            length=4+k%3
            vx=(tx-sx)/(sy-ty)
            d.line((ix,iy,round(ix-vx*length),iy+length),fill=(255,193,83,round(a*.55)),width=1)
            d.line((ix,iy,round(ix-vx*2),iy+2),fill=(255,249,210,a),width=1)
    p=native.resize((384,400),Image.Resampling.NEAREST)
    beam=beam_frame(f); beams.append(beam)
    sparks.append(p); frames.append(compose(p,beam)); positions.append(track)

compose(Image.new('RGBA',(384,400))).save(R/'preview.png')
frames[0].save(R/'loop.png',save_all=True,append_images=frames[1:],duration=DUR,loop=0,disposal=0,blend=0)
frames[0].convert('RGB').save(R/'loop.gif',save_all=True,append_images=[f.convert('RGB') for f in frames[1:]],duration=[80,80,90]*8,loop=0,disposal=2)
beam_sheet=Image.new('RGBA',(384*N,400))
for f,b in enumerate(beams): beam_sheet.paste(b,(384*f,0))
beam_sheet.save(R/'flowing_beams@2x.png')
beam_sheet.resize((192*N,200),Image.Resampling.NEAREST).save(R/'flowing_beams.png')
sheet=Image.new('RGBA',(384*N,400))
for f,p in enumerate(sparks): sheet.paste(p,(384*f,0))
sheet.save(R/'rising_fragments@2x.png')
sheet.resize((192*N,200),Image.Resampling.NEAREST).save(R/'rising_fragments.png')
board=Image.new('RGBA',(640*4,512*2))
for i,f in enumerate(range(0,N,3)): board.paste(frames[f],((i%4)*640,(i//4)*512))
board.save(R/'motion_board.png')
assert len({p.tobytes() for p in sparks})==N
assert Image.open(R/'loop.png').n_frames==N
assert sheet.resize((192*N,200),Image.Resampling.NEAREST).resize(sheet.size,Image.Resampling.NEAREST).tobytes()==sheet.tobytes()
for f in range(1,N):
    for (a0,y0),(a1,y1) in zip(positions[f-1],positions[f]):
        assert a1==0 or y1<y0
assert all(p.getchannel('A').crop((0,362,384,400)).getbbox() is None for p in sparks)
assert all(ImageChops.difference(frames[0].crop((0,414,640,512)),f.crop((0,414,640,512))).getbbox() is None for f in frames)
energy=[ImageStat.Stat(f.convert('L')).sum[0] for f in frames]
variation=100*(max(energy)-min(energy))/(sum(energy)/N)
assert variation<3
assert len({b.tobytes() for b in beams})==N
beam_deltas=[np.abs(np.array(beams[(i+1)%N],dtype=float)-np.array(beams[i],dtype=float)).mean() for i in range(N)]
assert beam_deltas[-1]<2*sum(beam_deltas[:-1])/(N-1)
assert beam_sheet.resize((192*N,200),Image.Resampling.NEAREST).resize(beam_sheet.size,Image.Resampling.NEAREST).tobytes()==beam_sheet.tobytes()
qa=dict(passed=True,frames=N,fps=12,duration_ms=sum(DUR),brightness_range_percent=variation,beam_loop_seam_ratio=beam_deltas[-1]/(sum(beam_deltas[:-1])/(N-1)),checks=['24 unique main beam frames','loop seam within normal frame change','beam texture moves along straight radial axes; no global brightness modulation','24 unique particle frames','straight upward trajectories from zipper','2px particle grid','no light below bag','bag bottom identical across frames','APNG duration and frames'],engine_tested=False)
(R/'qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
(R/'manifest.json').write_text(json.dumps(dict(status='animation candidate',static_reference='light@2x.png',animated=['flowing_beams@2x.png','rising_fragments@2x.png'],frame_size=[384,400],frames=N,fps=12,origin=[192,350],placement='bag_top_left + (128,66) - origin',inner_crop=[64,78,256,320],layer_order=['flowing beams + fragments','bag base','same light crop * fixed mouth clip','bag front'],source_sha256=hashlib.sha256((R/'source.png').read_bytes()).hexdigest()),indent=2),encoding='utf-8')
(R/'review.html').write_text('''<!doctype html><meta charset="utf-8"><title>开包光效 · 动态试稿</title><style>body{margin:0;background:#19222c;color:#c9d4df;font:14px sans-serif;text-align:center}img{display:block;margin:auto;width:min(960px,100vw);image-rendering:pixelated}button{color:inherit;background:#25313f;border:1px solid #526474;padding:8px 16px;cursor:pointer;margin:6px}</style><img id="preview" src="loop.png?v=3"><button onclick="document.getElementById('preview').src='loop.png?v=3'">播放动画</button><button onclick="document.getElementById('preview').src='preview.png?v=3'">查看静态</button><p>主光束沿直线涌动 · 亮芯推进与末端消散 · 动态试稿，未接入游戏</p>''',encoding='utf-8')
assert len({b.tobytes() for b in beams})==N
change=ImageChops.difference(beams[0],beams[6]).getbbox()
assert change and change[1]<100
print(json.dumps(qa))
