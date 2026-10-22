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
bag_strip=Image.open(B/'ui_hh_bag_zip@2x.png').convert('RGBA')
front_strip=Image.open(B/'ui_hh_bag_zip_front@2x.png').convert('RGBA')
clip_strip=Image.open(R.parent/'delivery'/'fx_hh_mouth_clip@2x.png').convert('L')
old_reveal=Image.open(R.parent/'delivery'/'fx_hh_rear_reveal@2x.png').convert('L')
bases=[bag_strip.crop((i*256,0,(i+1)*256,152)) for i in range(8)]
fronts=[front_strip.crop((i*256,0,(i+1)*256,152)) for i in range(8)]
clips=[clip_strip.crop((i*256,0,(i+1)*256,320)) for i in range(8)]
reveals=[]
contract=json.loads((B/'playback_contract.json').read_text())
for stage,(sx,sy) in enumerate(contract['slider_positions']):
    mask=Image.new('L',(192,200))
    if stage:
        progress=stage/7
        height=210*progress**.65
        left=(64+sx)/2; right=142
        center=(left+right)/2
        for y in range(200):
            up=max(0,175-y)
            spread=up*.34*progress
            for x in range(192):
                # An irregular rising jet front, not a flat rectangular reveal.
                tip=(abs(x-center)*.20 + (((x//4)*13)%17)*.65)
                rise=max(0,min(1,(height-up-tip)/10))
                side=max(0,min(1,(x-left+spread)/5,(right+spread-x)/5))
                mask.putpixel((x,y),round(255*rise*side*(.6+.4*progress)))
        if stage==7: mask=Image.new('L',(192,200),255)
    large=mask.resize((384,400),Image.Resampling.NEAREST)
    if reveals: large=ImageChops.lighter(large,reveals[-1])
    reveals.append(large)
base,front,clip=bases[7],fronts[7],clips[7]

# Scroll source-derived light texture upward inside the approved broad column.
# There is no sinusoidal displacement, crosswise warp, or whole-field fade.
source_native=np.array(field.resize((192,200),Image.Resampling.NEAREST))
yy,xx=np.mgrid[:200,:192]
rgb=source_native[:,:,:3].astype(float)
# Halo and dark gaps keep their source colours. The gold core carries flow.
gold=np.clip((rgb[:,:,0]-rgb[:,:,2]*1.2)/60,0,1)*np.clip((rgb[:,:,0]-120)/80,0,1)
vertical=np.clip((174-yy)/24,0,1)*np.clip(yy/12,0,1)
central=np.clip((xx-48)/28,0,1)*np.clip((144-xx)/28,0,1)
flow_weight=(gold*vertical*central*.80)[:,:,None]
# Mirrored endpoints make the scrolling colour tile continuous at its wrap.
period=96
stripe=rgb[28:76].copy()
tile=np.concatenate((stripe,stripe[::-1]),axis=0)

def beam_frame(frame):
    rows=(yy+frame*8)%period
    flowing=tile[rows,xx]
    out=source_native.copy()
    out[:,:,:3]=np.rint(rgb*(1-flow_weight)+flowing*flow_weight).clip(0,255).astype('uint8')
    return Image.fromarray(out).resize((384,400),Image.Resampling.NEAREST)

def compose(sparks,beam=None,stage=7,reveal=None):
    light=(field if beam is None else beam).copy(); light.alpha_composite(sparks)
    mask=reveals[stage] if reveal is None else reveal
    light.putalpha(ImageChops.multiply(light.getchannel('A'),mask))
    canvas=Image.new('RGBA',(640,512),(25,34,44,255))
    canvas.alpha_composite(light,(96,46))
    canvas.alpha_composite(bases[stage],(160,330))
    inner=light.crop((64,78,320,398))
    inner.putalpha(ImageChops.multiply(inner.getchannel('A'),clips[stage]))
    canvas.alpha_composite(inner,(160,124))
    canvas.alpha_composite(fronts[stage],(160,330))
    return canvas.crop((0,46,640,512))

# Sparse accents accompany the independently animated main light field.
# Each track begins at the zipper and follows one straight beam, no field warp.
targets=[(43,68),(64,43),(92,20),(116,47),(148,74),(59,88),(105,35),(132,88),(80,59),(52,55),(125,30),(99,10)]
sparks=[]; frames=[]; positions=[]; beams=[]
for f in range(N):
    native=Image.new('RGBA',(192,200)); d=ImageDraw.Draw(native); track=[]
    for k,(tx,ty) in enumerate(targets):
        age=(f+k*5)%12
        p=age/12
        sx=87+(k*5)%19; sy=177-(sx-87)*.20
        x=sx+(tx-sx)*p; y=sy+(ty-sy)*p
        track.append((age,y))
        # Only individual fragments fade at birth/death. Main light stays exact.
        envelope=min(1,age/1,(11-age)/2)
        a=round(252*max(0,envelope)/42)*42
        ix,iy=round(x),round(y)
        if k%3==0:
            d.polygon([(ix,iy),(ix+1,iy+1),(ix,iy+3),(ix-1,iy+1)],fill=(255,233,156,a))
        else:
            length=min(10+k%6,max(0,round(sy)-iy))
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
assert len({p.tobytes() for p in sparks})==12
assert Image.open(R/'loop.png').n_frames==N
assert sheet.resize((192*N,200),Image.Resampling.NEAREST).resize(sheet.size,Image.Resampling.NEAREST).tobytes()==sheet.tobytes()
for f in range(1,N):
    for (a0,y0),(a1,y1) in zip(positions[f-1],positions[f]):
        assert a1==0 or y1<y0
assert all(p.getchannel('A').crop((0,362,384,400)).getbbox() is None for p in sparks)
assert all(ImageChops.difference(frames[0].crop((0,368,640,466)),f.crop((0,368,640,466))).getbbox() is None for f in frames)
energy=[ImageStat.Stat(f.convert('L')).sum[0] for f in frames]
variation=100*(max(energy)-min(energy))/(sum(energy)/N)
assert variation<3
assert len({b.tobytes() for b in beams})==12
beam_deltas=[np.abs(np.array(beams[(i+1)%N],dtype=float)-np.array(beams[i],dtype=float)).mean() for i in range(N)]
assert beam_deltas[-1]<2*sum(beam_deltas[:-1])/(N-1)
assert beam_sheet.resize((192*N,200),Image.Resampling.NEAREST).resize(beam_sheet.size,Image.Resampling.NEAREST).tobytes()==beam_sheet.tobytes()
qa=dict(passed=True,frames=N,fps=12,duration_ms=sum(DUR),brightness_range_percent=variation,beam_loop_seam_ratio=beam_deltas[-1]/(sum(beam_deltas[:-1])/(N-1)),checks=['12-frame main flow cycle, twice per preview','loop seam within normal frame change','gold texture flows upward at double speed; long launch streaks; halo alpha fixed','12-frame fast fragment cycle','straight upward trajectories from zipper','2px particle grid','no light below bag','bag bottom identical across frames','APNG duration and frames'],engine_tested=False)
(R/'qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
(R/'manifest.json').write_text(json.dumps(dict(status='animation candidate',static_reference='light@2x.png',animated=['flowing_beams@2x.png','rising_fragments@2x.png'],frame_size=[384,400],frames=N,fps=12,origin=[192,350],placement='bag_top_left + (128,66) - origin',inner_crop=[64,78,256,320],layer_order=['flowing beams + fragments','bag base','same light crop * fixed mouth clip','bag front'],reference='reference.png',source_sha256=hashlib.sha256((R/'source.png').read_bytes()).hexdigest()),indent=2),encoding='utf-8')
# Complete zipper sequence: 0.4s closed, 1.2s right-to-left opening,
# then 2s of the new flowing light. Original bag stages and handles unchanged.
opening=[compose(sparks[0],beams[0],stage=0)]
opening_durations=[400]
opening_stages=[0]
for stage in range(1,8):
    span=170 if stage<7 else 180
    for step in range(2):
        f=(2*(stage-1)+step)%N
        # New light grows in the already-open section; its texture origin is fixed.
        reveal=Image.blend(reveals[stage-1],reveals[stage],(step+1)/2)
        opening.append(compose(sparks[f],beams[f],stage,reveal))
        opening_durations.append(span//2)
        opening_stages.append(stage)
for i in range(N):
    f=(14+i)%N
    opening.append(compose(sparks[f],beams[f]))
    opening_durations.append(DUR[i]); opening_stages.append(7)
opening[0].save(R/'opening.png',save_all=True,append_images=opening[1:],duration=opening_durations,loop=0,disposal=0,blend=0)
opening[0].convert('RGB').save(R/'opening.gif',save_all=True,append_images=[f.convert('RGB') for f in opening[1:]],duration=opening_durations,loop=0,disposal=2)
board=Image.new('RGBA',(2560,932))
for stage in range(8):
    im=compose(sparks[stage],beams[stage],stage)
    board.paste(im,((stage%4)*640,(stage//4)*466))
board.save(R/'opening_stages.png')
reveal_sheet=Image.new('L',(384*8,400))
for i,m in enumerate(reveals): reveal_sheet.paste(m,(384*i,0))
reveal_sheet.save(R/'opening_reveal@2x.png')
assert not reveals[0].getbbox()
assert reveals[7].getextrema()==(255,255)
for i in range(1,8): assert ImageChops.subtract(reveals[i-1],reveals[i]).getbbox() is None
assert sum(opening_durations[:15])==1600 and sum(opening_durations)==3600
assert Image.open(R/'opening.png').n_frames==len(opening)
empty=compose(Image.new('RGBA',(384,400)),Image.new('RGBA',(384,400)),0)
assert ImageChops.difference(empty,opening[0]).getbbox() is None
assert all(ImageChops.subtract(clips[i].crop((0,206,256,320)),bases[i].getchannel('A').crop((0,0,256,114))).getbbox() is None for i in range(8))
contract=json.loads((B/'playback_contract.json').read_text())
assert all(contract['slider_positions'][i][0]>contract['slider_positions'][i+1][0] for i in range(7))
qa.update(opening_frames=len(opening),opening_duration_ms=sum(opening_durations),closed_ms=400,fully_open_ms=1600,opening_checks=['closed bag has no light','right-to-left original zipper stages','monotonic in-place light reveal','inner mask within bag coverage','original handles/front overlay last'])
(R/'qa.json').write_text(json.dumps(qa,indent=2),encoding='utf-8')
manifest=json.loads((R/'manifest.json').read_text())
manifest['opening']=dict(preview='opening.png',stage_count=8,reveal='opening_reveal@2x.png',reveal_frame_size=[384,400],reveal_origin=[192,350],durations_ms=opening_durations,stages=opening_stages,closed_ms=400,fully_open_ms=1600,engine_tested=False)
(R/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
(R/'review.html').write_text("""<!doctype html><meta charset="utf-8"><title>完整开包 · 金白光柱</title><style>body{margin:0;background:#19222c;color:#c9d4df;font:14px sans-serif;text-align:center}img{display:block;margin:auto;width:min(960px,100vw);image-rendering:pixelated}button{color:inherit;background:#25313f;border:1px solid #526474;padding:8px 16px;cursor:pointer;margin:6px}</style><img id="preview" src="opening.png?v=3"><button onclick="document.getElementById('preview').src='opening.png?v='+Date.now()">重播完整开包</button><button onclick="document.getElementById('preview').src='loop.png?v=3'">只看全开循环</button><p>闭合 → 拉链向左拉开 → 金光从开口快速喷涌 → 光纹循环</p><p>加强上冲速度与长光条 · 素材合成预览，尚未接入游戏。</p>""",encoding='utf-8')
assert len({b.tobytes() for b in beams})==12
change=ImageChops.difference(beams[0],beams[6]).convert('RGB').getbbox()
assert change and change[1]<100
print(json.dumps(qa))
