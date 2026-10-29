"""Complete six approved repeat materials; no root manifest or game mutations."""
from pathlib import Path
import json, math, hashlib, shutil, subprocess
import numpy as np
from PIL import Image, ImageDraw
import imageio_ffmpeg

R=Path(__file__).resolve().parent
B=R.parents[1]
GAME=Path('E:/ArknightsSurvivors/art/incoming')
for folder in ('sources','previews','frames'):(R/folder).mkdir(exist_ok=True)
NAMES=['texas_scar_back','skalter_beam_front','skalter_domain_back','kaltsit_crack_back','ulpianus_chain_front','ulpianus_crack_back']
A={a['name']:a for a in json.loads((B/'animation_keyframe_manifest.json').read_text(encoding='utf8'))['assets']}
H=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()
def binary(im):
    a=np.array(im.convert('RGBA'));a[:,:,3]=np.where(a[:,:,3]>=128,255,0);a[a[:,:,3]==0]=0
    return Image.fromarray(a)
def source(name):
    entry=A[name];out=[];rec=[]
    for k in entry['keyframes']:
        original=B/k['file'];assert H(original)==k['sha256']
        p=R/'sources'/original.name
        if not p.exists():shutil.copy2(original,p)
        assert H(p)==k['sha256']
        im=Image.open(p).convert('RGBA');out.append(np.array(im.resize(tuple(entry['logical_size']),Image.Resampling.NEAREST)))
        rec.append({'path':str(original),'snapshot_file':str(p.relative_to(B)).replace('\\','/'),'sha256':H(p),'approved_keyframe':k['frame']})
    return out,rec
def close(a):
    """The shared sample at x=0/x=w-1 is periodic in coverage AND RGBA."""
    a=a.copy();a[:,-1]=a[:,0];a[a[:,:,3]==0]=0;return a
def shift_y(a,offset):
    h,w=a.shape[:2];out=np.zeros_like(a)
    for x,dy in enumerate(offset):
        ys=np.where(a[:,x,3]>0)[0];d=ys+int(dy);ok=(d>=0)&(d<h);out[d[ok],x]=a[ys[ok],x]
    return out
def arc_offset(w,h,r):
    x=np.arange(w)-(w-1)/2
    return np.rint(r-np.sqrt(r*r-x*x)).astype(int)
def periodic(a,phase):
    p=a[:,:-1];i=(np.arange(a.shape[1]-1)-round(phase))%p.shape[1]
    out=np.zeros_like(a);out[:,:-1]=p[:,i];out[:,-1]=out[:,0];return out
def dust(im,frame,n,kind,tracks):
    """Source-colored chips travel outward, rise, then fall; no random flashing."""
    out=im.copy();h,w=out.shape[:2];t=frame/(n-1)
    visible=out[out[:,:,3]>0]
    if not len(visible):return out
    bright=visible[np.argsort(visible[:,:3].max(axis=1))[-max(2,len(visible)//8):]]
    for i in range(10 if kind=='crack' else 7):
        x0=3+(i*17+11)%(w-7);y0=h//2-1
        sign=-1 if i%2 else 1
        # Peak chips are readable; late samples visibly return toward the ground.
        age=max(0,t-.12);dx=sign*(2+i%3)*age*3
        dy=-(4+i%3)*math.sin(math.pi*min(1,age/.88))+(2+i%2)*age*age
        if kind=='scar':dy=-(4+i%3)*math.sin(math.pi*min(1,t/.78))+2*t*t
        x=round(x0+dx)%(w-1);y=max(1,min(h-2,round(y0+dy)))
        keep=(frame>0 and frame<n-1) if kind=='crack' else (frame<n-1)
        if keep:
            col=bright[(i*7)%len(bright)].copy()
            if frame==n-2:col[:3]=(col[:3].astype(float)*.68).astype(np.uint8)
            out[y,x]=col
            if kind=='crack' and frame in (2,3):out[min(h-2,y+1),x]=col
        tracks.append({'particle':i,'frame':frame,'x':x,'y':y,'visible':bool(keep)})
    return close(out)

entries=[];all_frames={};qa=[];motion={}
for short in NAMES:
    name='fx_ult_'+short;entry=A[name];(f0,peak),sources=source(name)
    w,h=entry['logical_size'];n=entry['frame_count'];fps=int(entry['timing'].split('/')[1].split()[0])
    arc=entry.get('arc_reference_radius');tracks=[];frames=[]
    if 'beam' in short:
        # Advect the approved rough crimson sheath and cyan core together. This
        # moves the actual material pixels; the volume is never opacity-blinked.
        frames=[periodic(peak,(w-1)*f/n) for f in range(n)]
        behavior='循环材质沿 +x 推进一个完整周期；青绿直芯、深红粗糙边和 80 显示线宽保持。'
        seg={'loop':[0,n-1]}
    elif 'domain' in short:
        bend=arc_offset(w,h,arc);flat=shift_y(peak,-bend)
        frames=[close(shift_y(periodic(flat,(w-1)*f/n),bend)) for f in range(n)]
        behavior='先按已确认参考半径展平，仅沿切线搬运真实纹理像素，再还原弧；循环相位等步回接。'
        seg={'loop':[0,n-1]}
    elif 'chain' in short:
        frames=[close(f0),close(peak)]
        behavior='保留已确认的两态链节晃动；轮廓和链节高光均变化，非静图透明度闪烁。'
        seg={'loop':[0,1]}
    elif 'scar' in short:
        yy,xx=np.indices((h,w));center=h/2
        for f in range(n):
            t=f/(n-1);a=f0.copy();off=np.abs(yy-center)>2
            a[off]=0
            # Progressive erosion of the persistent cut, while detached chips
            # follow separate ballistic paths and the warm light extinguishes.
            keep=((xx*13+yy*7)%19)>=round(t*13)
            a[~keep]=0;a[:,:,:3]=(a[:,:,:3].astype(float)*(1-.64*t)).astype(np.uint8)
            a=dust(a,f,n,'scar',tracks);frames.append(close(a))
        behavior='切口按固定空间纹理逐步侵蚀；暖色碎屑沿外侧飞出、落回并熄灭，整条淡出。'
        seg={'decay':[0,n-1]}
    else:
        yy,xx=np.indices((h,w));dist=np.abs(xx-(w-1)/2)/((w-1)/2)
        for f in range(n):
            if f==0:a=f0.copy()
            elif f<4:
                reveal=dist<([0,.42,.87,1.01][f]);a=f0.copy();a[reveal]=peak[reveal]
                # Two crack banks separate by one native pixel during opening,
                # rather than showing an unchanged texture at another opacity.
                if f in (1,2):
                    med=np.array([np.median(np.where(f0[:,x,3]>0)[0]) if np.any(f0[:,x,3]) else h/2 for x in range(w)])
                    moved=np.zeros_like(a)
                    for x in range(w):
                        for y in np.where(a[:,x,3]>0)[0]:
                            dy=(-1 if y<med[x] else 1) if reveal[y,x] else 0
                            if 0<=y+dy<h:moved[y+dy,x]=a[y,x]
                    a=moved
            else:
                a=peak.copy();a[:,:,:3]=(a[:,:,:3].astype(float)*(.60 if f==4 else .26)).astype(np.uint8)
                if f==5:a[((xx*5+yy*11)%13)<8]=0
            if f!=0:a=dust(a,f,n,'crack',tracks)
            frames.append(close(a))
        behavior='闭合裂缝从弧段中央向两端张开；裂口两岸分离，源材质碎屑抛起再落地，末两帧冷却侵蚀。'
        seg={'open':[0,3],'afterglow':[4,5]}
    outframes=[]
    for f,a in enumerate(frames):
        im=binary(Image.fromarray(a)).resize((w*2,h*2),Image.Resampling.NEAREST);outframes.append(im)
        im.save(R/'frames'/f'{name}_f{f:02d}@2x.png')
    strip=Image.new('RGBA',(w*2*n,h*2))
    for f,im in enumerate(outframes):strip.paste(im,(f*w*2,0))
    file=R/(name+'@2x.png');strip.save(file);all_frames[name]=outframes
    origin=[0,h] if entry['origin']=='左端中心' else [w,h]
    rec={'name':name,'file':str(file.relative_to(B)).replace('\\','/'),'fps':fps,'origin_px_2x':origin,
         'physical_size':[w*2,h*2],'logical_size':[w,h],'frame_count':n,'layer':short.rsplit('_',1)[-1],
         'segments':seg,'representative_frame':entry['representative_frame'],'rgba_mib':w*2*h*2*4*n/1048576,
         'tile_axis':'x','seam_endpoint_equal_every_frame':True,'sourcehash':sources,'sha256':H(file),
         'arc_reference_radius_logical':arc,'arc_span_degrees':30 if arc else None,
         'arc_overlap_px_2x':2 if arc else 0,'motion_note':behavior,'runtime_verified':False,
         'approved_shape_preserved':True,'full_animation_candidate':True,'brief_commit':'975cfaf31'}
    if arc:rec['arc_reference_circle_center_local_logical']=[w/2,h/2+arc]
    if 'beam' in short:rec.update(review_draw_width=80,texture_size_unchanged=True)
    if 'loop' in seg:rec['phase_period_frames']=n
    else:rec['end_behavior']='末帧残痕随实例结束；不可把尾帧当循环。'
    entries.append(rec);motion[name]=tracks
    arr=[np.array(im) for im in outframes];diff=[];silhouette_diff=[]
    for i in range(n):
        a=arr[i];assert np.array_equal(a[:,0],a[:,-1]),(name,i,'seam')
        assert set(np.unique(a[:,:,3]))<={0,255};assert outframes[i].size==(w*2,h*2)
        if i:
            diff.append(int(np.any(a!=arr[i-1],axis=2).sum()))
            silhouette_diff.append(int(((a[:,:,3]>0)!=(arr[i-1][:,:,3]>0)).sum()))
    assert all(x>0 for x in diff),(name,'duplicate frames')
    q={'name':name,'frames':n,'dimensions':True,'binary_alpha':True,'every_frame_endpoint_rgba_equal':True,
       'adjacent_changed_pixels':diff,'unique_frames':len({a.tobytes() for a in arr}),
       'adjacent_silhouette_changed_pixels':silhouette_diff,
       'particle_trajectory_count':len({p['particle'] for p in tracks})}
    if 'loop' in seg:
        wrap=int(np.any(arr[-1]!=arr[0],axis=2).sum());q['loop_wrap_changed_pixels']=wrap
        q['loop_wrap_to_largest_step_ratio']=wrap/max(diff)
        assert wrap>0 and wrap<=max(diff)*1.4,(name,'loop seam jump')
    qa.append(q)

# Contact sheet at exact @2x density, no smoothing.
contact_width=max(1260,max(300+e['frame_count']*(e['physical_size'][0]+8) for e in entries)+12)
contact=Image.new('RGB',(contact_width,6*160),'#24313b');d=ImageDraw.Draw(contact)
for row,entry in enumerate(entries):
    name=entry['name'];d.text((10,row*160+9),name,fill='white')
    d.text((10,row*160+27),f"{entry['frame_count']} frames / {entry['fps']} fps",fill='#9eb9c6')
    for f,im in enumerate(all_frames[name]):
        x=300+f*(im.width+8);y=row*160+48
        contact.paste(im,(x,y),im);d.text((x,y-14),f'f{f}',fill='#c7d5dc')
contact.save(R/'previews/contact_sheet.png')

ground_file=GAME/'tiles.png';ground=Image.open(ground_file).convert('RGB')
def canvas(bg):
    out=Image.new('RGB',(640,360),'black')
    if bg:
        for y in range(0,360,ground.height):
            for x in range(0,640,ground.width):out.paste(ground,(x,y))
    return out
def center(layer,im,p):layer.alpha_composite(im,(round(p[0]-im.width/2),round(p[1]-im.height/2)))
def scene(entry,f,bg):
    out=canvas(bg);layer=Image.new('RGBA',out.size);im=all_frames[entry['name']][f]
    if entry['arc_reference_radius_logical']:
        radius=125;scale=radius/(entry['arc_reference_radius_logical']*2)
        im=im.resize((round(im.width*scale)+2,max(1,round(im.height*scale))),Image.Resampling.NEAREST)
        for k in range(12):
            theta=math.tau*k/12
            # Texture is a shallow concave-up 30-degree arc. Its local top
            # points inward; rotate the tangent and put midpoint on the circle.
            rot=im.rotate(-math.degrees(theta)-90,Image.Resampling.NEAREST,expand=True)
            center(layer,rot,(320+radius*math.cos(theta),180+radius*math.sin(theta)))
    else:
        repeats=8 if 'chain' in entry['name'] else 3
        mat=Image.new('RGBA',(im.width*repeats,im.height))
        for k in range(repeats):mat.alpha_composite(im,(k*im.width,0))
        # Preserve 80px beam width. Only preview length is fitted to viewport.
        if mat.width>560:mat=mat.resize((560,mat.height),Image.Resampling.NEAREST)
        center(layer,mat,(320,180))
    out.paste(layer,(0,0),layer);dr=ImageDraw.Draw(out);dr.text((12,12),entry['name'],fill='white')
    dr.text((12,30),f"original {entry['fps']} fps / display30 / {'game ground' if bg else 'black'} / f{f}",fill='#b8c7cf')
    return out
ffmpeg=imageio_ffmpeg.get_ffmpeg_exe()
for entry in entries:
    name=entry['name'];path=R/'previews'/(name+'.mp4')
    cmd=[ffmpeg,'-y','-f','rawvideo','-pix_fmt','rgb24','-s','640x360','-r','30','-i','-','-an','-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(path)]
    proc=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    for j in range(180):
        t=(j%90)/30;n=entry['frame_count'];fps=entry['fps']
        index=int(t*fps)%n if 'loop' in entry['segments'] else min(n-1,int((t%(n/fps+.35))*fps))
        proc.stdin.write(scene(entry,index,j>=90).tobytes())
    proc.stdin.close();err=proc.stderr.read();assert proc.wait()==0,err.decode(errors='replace')
    assert path.stat().st_size<=5*1024*1024
    entry['preview_mp4']=str(path.relative_to(B)).replace('\\','/');entry['preview_bytes']=path.stat().st_size
    scene(entry,entry['representative_frame'],True).save(R/'previews'/(name+'_placement.png'))

(R/'entries.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf8')
(R/'qa.json').write_text(json.dumps({'assets':qa,'assets_checked':len(entries),'frames_checked':sum(e['frame_count'] for e in entries),'rgba_mib':sum(e['rgba_mib'] for e in entries),'ground_source':{'path':str(ground_file),'sha256':H(ground_file)},'runtime_verified':False},ensure_ascii=False,indent=2),encoding='utf8')
(R/'particle_tracks.json').write_text(json.dumps(motion,ensure_ascii=False,indent=2),encoding='utf8')
print('PASS segments:',len(entries),'assets,',sum(e['frame_count'] for e in entries),'frames; every-frame RGBA seams, dimensions, alpha, unique frames and loop steps; 6 MP4 previews')
