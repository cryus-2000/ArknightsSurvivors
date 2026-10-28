from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat
import json, hashlib, shutil, math

R=Path(__file__).resolve().parent
D=R/'delivery'; D.mkdir(exist_ok=True)
B=R.parent/'headhunt_bag_1022'/'delivery'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
source=Image.open(R/'pixel_source.png').convert('RGBA')
native=source.resize((192,200),Image.Resampling.BOX)
native=native.quantize(colors=64,method=Image.Quantize.FASTOCTREE,dither=Image.Dither.NONE).convert('RGBA')
native.putalpha(native.getchannel('A').point(lambda a: round(a/51)*51))
# Remove the ground pool altogether. Lower emission must originate on the
# actual slanted zipper, not under/alongside the bag. Work on the native grid.
alpha=native.getchannel('A')
for y in range(200):
    for x in range(192):
        if y>=130:
            spread=max(0,150-y)*.35
            zipper_y=177.5-.192*x
            if x<51-spread or x>142+spread or y>zipper_y:
                alpha.putpixel((x,y),0)
native.putalpha(alpha)
field=native.resize((384,400),Image.Resampling.NEAREST)
field.save(D/'static_field@2x.png')
contract=json.loads((B/'playback_contract.json').read_text())
base=Image.open(B/'ui_hh_bag_zip@2x.png').convert('RGBA')
front=Image.open(B/'ui_hh_bag_zip_front@2x.png').convert('RGBA')
rear=[]; inner=[]
# The entire light field is stationary. Only independent short streaks move.
N=24
durations=[83,83,84]*8
particles=[]
tracks=[]
for frame in range(N):
    p=Image.new('RGBA',(192,200)); draw=ImageDraw.Draw(p)
    positions=[]
    for k in range(14):
        distance=(k*17+frame*5)%120
        y=159-distance
        slope=(-.40+.80*((k*5)%14)/13)
        x=round(96+slope*distance+(k%3-1)*4)
        positions.append((x,y))
        # Hard pixel clusters. Constant palette, no time-varying opacity.
        if k%3:
            length=4+k%5
            tail=(round(x-slope*length),y+length)
            draw.line((x,y,*tail),fill=(255,214,97,204),width=2)
            draw.line((x,y,round(x-slope*2),y+2),fill=(255,255,212,255),width=1)
        else:
            draw.polygon([(x,y),(x+2,y+2),(x,y+4),(x-1,y+1)],fill=(255,237,151,255))
    tracks.append(positions)
    particles.append(p.resize((384,400),Image.Resampling.NEAREST))
    rear.append(field.copy())
    inner.append(field.crop((64,50,320,370)))
# Track motion is upward except respawning at the zipper, never a wave warp.
for f in range(1,N):
    for old,new in zip(tracks[f-1],tracks[f]):
        assert new[1]-old[1] in (-5,115)
assert len({p.tobytes() for p in particles})==N
assert len({f.tobytes() for f in rear})==1
assets=[]
for name,frames,origin in [('fx_hh_rear_field',rear,[192,322]),('fx_hh_mouth_reference',inner,[128,272]),('fx_hh_rising_fragments',particles,[192,322])]:
    w,h=frames[0].size
    sheet=Image.new('RGBA',(w*N,h))
    for i,f in enumerate(frames): sheet.paste(f,(i*w,0))
    path=D/(name+'@2x.png'); sheet.save(path)
    sheet.resize((w*N//2,h//2),Image.Resampling.NEAREST).save(D/(name+'.png'))
    assert len({f.tobytes() for f in frames})==(N if name=='fx_hh_rising_fragments' else 1)
    assert sheet.getchannel('A').getextrema()[0]==0
    assets.append(dict(file=path.name,frame_size=[w,h],frames=N,fps=12,origin=origin,sha256=sha(path)))
clips=[]
reveals=[]
for stage,(sx,sy) in enumerate(contract['slider_positions']):
    # Limit inner layer to bag footprint as rear already draws the upper rays.
    midy=round((sy+48)/2)
    footprint=Image.new('L',(256,320))
    ImageDraw.Draw(footprint).rectangle((0,272-midy,255,319),fill=255)
    moving_clip=ImageChops.multiply(Image.open(B/'frames'/f'light_clip_{stage}.png').convert('L'),footprint) if stage else Image.new('L',(256,320))
    fixed_clip=Image.new('L',(256,320))
    fixed_clip.paste(moving_clip,(round((sx+220)/2)-128,midy-66))
    # Rear light is already visible through transparent space. Restore inner
    # light only where the bag base actually covered it, not the entire rectangle.
    bag_coverage=Image.new('L',(256,320))
    bag_coverage.paste(base.crop((stage*256,0,(stage+1)*256,152)).getchannel('A'),(0,206))
    fixed_clip=ImageChops.multiply(fixed_clip,bag_coverage)
    assert not ImageChops.subtract(fixed_clip,bag_coverage).getbbox()
    clips.append(fixed_clip)
    reveal=Image.new('L',(384,400))
    if stage:
        p=stage/7
        # Reveal pixels in place from the opened zipper segment, never translate texture.
        for y in range(400):
            above=max(0,322-y)
            growth=max(0,min(1,(322*p-above)/20+1))
            if y>322: growth=max(0,min(1,(p-.3)/.7))
            for x in range(384):
                spread=(above*.42+110)*p*p
                left=192+sx-128-spread
                right=284+spread
                edge=max(0,min(1,(x-left)/12,(right-x)/12))
                reveal.putpixel((x,y),round(255*growth*edge*p))
        if stage==7: reveal=Image.new('L',(384,400),255)
    reveals.append(reveal)
clipstrip=Image.new('L',(2048,320))
for i,c in enumerate(clips): clipstrip.paste(c,(256*i,0))
clipstrip.save(D/'fx_hh_mouth_clip@2x.png')
revealstrip=Image.new('L',(384*8,400))
for i,m in enumerate(reveals): revealstrip.paste(m,(384*i,0))
revealstrip.save(D/'fx_hh_rear_reveal@2x.png')

def compose(stage,frame,bg=(25,34,44,255)):
    canvas=Image.new('RGBA',(640,512),bg)
    xy=(160,330); sx,sy=contract['slider_positions'][stage]
    anchor=(xy[0]+128,xy[1]+66)
    if stage:
        f=rear[frame].copy(); f.putalpha(ImageChops.multiply(f.getchannel('A'),reveals[stage]))
        canvas.alpha_composite(f,(anchor[0]-192,anchor[1]-322))
        sparks=particles[frame].copy()
        sparks.putalpha(ImageChops.multiply(sparks.getchannel('A'),reveals[stage]))
        canvas.alpha_composite(sparks,(anchor[0]-192,anchor[1]-322))
    canvas.alpha_composite(base.crop((stage*256,0,(stage+1)*256,152)),xy)
    if stage:
        m=inner[frame].copy(); m.alpha_composite(particles[frame].crop((64,50,320,370)))
        m.putalpha(ImageChops.multiply(ImageChops.multiply(m.getchannel('A'),clips[stage]),reveals[stage].crop((64,50,320,370))))
        canvas.alpha_composite(m,(anchor[0]-128,anchor[1]-272))
    canvas.alpha_composite(front.crop((stage*256,0,(stage+1)*256,152)),xy)
    return canvas

frames=[compose(7,f) for f in range(N)]
frames[0].save(D/'preview.png')
compose(7,0,(160,160,160,255)).save(D/'preview_light.png')
board=Image.new('RGBA',(2560,512*((N+3)//4)))
for i,f in enumerate(frames): board.paste(f,((i%4)*640,(i//4)*512))
board.save(D/'frame_board.png')
# PNG/APNG is authoritative for soft alpha; GIF is an optional review convenience.
frames[0].save(D/'loop.png',save_all=True,append_images=frames[1:],duration=durations,loop=0)
frames[0].convert('RGB').save(D/'loop.gif',save_all=True,append_images=[f.convert('RGB') for f in frames[1:]],duration=[80,80,90]*8,loop=0,disposal=2)
opening=[compose(i,i%N) for i in range(8)]+frames*3
opening[0].save(D/'opening.png',save_all=True,append_images=opening[1:],duration=[150]*8+durations*3,loop=0)
manifest=dict(assets=assets,clip=dict(file='fx_hh_mouth_clip@2x.png',frames=8,frame_size=[256,320],origin=[128,272],sha256=sha(D/'fx_hh_mouth_clip@2x.png')),source_sha256=sha(R/'pixel_source.png'),bag_dependencies={n:sha(B/n) for n in ['ui_hh_bag_zip@2x.png','ui_hh_bag_zip_front@2x.png','playback_contract.json']},layer_order=['rear field (unclipped)','original bag base','inner light multiplied by new mouth_clip for zipper stage','original bag front'],placement='bag_top_left + midpoint(slider,right_end) - each_layer_origin',animation='4-frame alpha pulse at12fps; preserve existing zipper timings; stage0 hidden',native_pixel_grid=True,engine_tested=False)
manifest.update(placement='FIXED bag_top_left + (128,66) - each_layer_origin; never follow slider',layer_order=['rear field multiplied by rear_reveal[zip stage]','original bag base','inner light multiplied by fixed mouth_clip[zip stage]','original bag front'],reveal=dict(file='fx_hh_rear_reveal@2x.png',frames=8,frame_size=[384,400],origin=[192,322],sha256=sha(D/'fx_hh_rear_reveal@2x.png')))
manifest['animation']='24 frames at12fps: static pixel light field; only separate short streaks and shards rise from zipper; no warp, no brightness modulation'
manifest['layer_order']=['rear field * reveal','rising fragments * reveal','bag base','(inner field + fragments crop) * mouth_clip * reveal crop','bag front']
manifest['pixel_grid']=dict(native=[192,200],display_pixel=2,alpha_levels=[0,51,102,153,204,255])
(D/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
# Check exact 2x pixel replication for all exported FX strips.
for asset in assets:
    im=Image.open(D/asset['file']).convert('RGBA')
    assert im.resize((im.width//2,im.height//2),Image.Resampling.NEAREST).resize(im.size,Image.Resampling.NEAREST).tobytes()==im.tobytes()
# Check exported files, clips, source/bag dependencies and APNG playback metadata.
for a in assets:
    i=Image.open(D/a['file']); w,h=a['frame_size']
    assert i.size==(w*N,h) and sha(D/a['file'])==a['sha256']
assert not clips[0].getbbox()
assert not reveals[0].getbbox()
assert reveals[1].getpixel((192,40))==0
assert reveals[7].getextrema()==(255,255)
stageboard=Image.new('RGBA',(640*4,512*2))
for s in range(8): stageboard.paste(compose(s,0),((s%4)*640,(s//4)*512))
stageboard.save(D/'opening_stages.png')
assert Image.open(D/'loop.png').n_frames==N
assert Image.open(D/'opening.png').n_frames>=8
for n,h in manifest['bag_dependencies'].items(): assert sha(B/n)==h
# At full opening, substantial light exists beside the opaque lower bag.
alpha=rear[0].getchannel('A')
assert not alpha.crop((0,356,384,400)).getbbox()
assert not alpha.crop((0,300,100,400)).getbbox()
assert not alpha.crop((286,300,384,400)).getbbox()
energies=[ImageStat.Stat(f.convert('L')).sum[0] for f in frames]
variation=100*(max(energies)-min(energies))/(sum(energies)/len(energies))
assert variation<.5
assert all(f.crop((0,414,640,512)).tobytes()==frames[0].crop((0,414,640,512)).tobytes() for f in frames)
(D/'qa.json').write_text(json.dumps(dict(passed=True,checks=['sheet sizes and hashes','exact 2px grid on three FX strips','static base identical across 24 frames','24 unique upward particle frames','inner light limited to bag coverage','stage0 no light','original bag hashes unchanged','APNG frame counts','ground and bag bottom unchanged across loop'],loop_brightness_range_percent=variation,native_grid=True,engine_tested=False,user_review='pending'),indent=2),encoding='utf-8')
print(json.dumps({'passed':True,'assets':len(assets),'opening_frames':Image.open(D/'opening.png').n_frames,'brightness_range_percent':variation}))
