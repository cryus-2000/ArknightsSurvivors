"""Approved batch-1 native animation expansion. Only writes beside this script."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import hashlib, json, math
import numpy as np
from scipy import ndimage

OUT = Path(__file__).resolve().parent
BATCH = OUT.parent.parent
NATIVE = BATCH.parent / 'de_summon_style_alignment_1020'
BASE = json.loads((BATCH / 'animation_keyframe_manifest.json').read_text(encoding='utf-8'))
SPECS = {a['name']: a for a in BASE['assets']}
ENTRIES, CHECKS = [], []
(OUT/'frames').mkdir(exist_ok=True)
(OUT/'pose_guides').mkdir(exist_ok=True)
(OUT/'contact').mkdir(exist_ok=True)

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def rgba(im):
    a=np.array(im.convert('RGBA'));a[a[:,:,3]==0]=0
    return Image.fromarray(a)
def hard(im,cut=96):
    a=np.array(im.convert('RGBA'));a[:,:,3]=np.where(a[:,:,3]>=cut,255,0);a[a[:,:,3]==0]=0
    return Image.fromarray(a)
def up(im): return im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST)
def small(im): return im.resize((im.width//2,im.height//2),Image.Resampling.NEAREST)
def accepted(name,representative=False):
    return Image.open(BATCH/SPECS[name]['keyframes'][int(representative)]['file']).convert('RGBA')
def hashed(path): return {'path':str(Path(path).resolve()),'sha256':sha(path)}

def native_pose(creature,action,frame):
    folder=NATIVE/creature/action
    m=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    body=Image.new('RGBA',(256,256));parts=[]
    for p in m['parts'][frame]:
        if not p.get('body_included',True): continue
        path=folder/p['path'];im=Image.open(path).convert('RGBA')
        assert sha(path)==p['sha256']
        body.alpha_composite(im)
        parts.append({k:p[k] for k in ('id','slot','attachment','bone','parent','draw_order','bone_world','vertices','triangles','deform','path','sha256') if k in p})
    strip=Image.open(folder/'full_motion_strip.png').convert('RGBA')
    assert body.tobytes()==strip.crop((frame*256,0,(frame+1)*256,256)).tobytes()
    return body,m,{'action':action,'source_frame':frame,'source_time':m['sample_times'][frame],
                   'source_manifest':hashed(folder/'manifest.json'),'parts':parts,
                   'original_draw_order_preserved':True,'body_attachment_recomposition_exact':True}

def shift_to_canvas(body,size,offset):
    im=Image.new('RGBA',size);im.alpha_composite(body,tuple(offset))
    before=np.count_nonzero(np.array(body)[:,:,3]);after=np.count_nonzero(np.array(im)[:,:,3])
    assert before==after,(size,offset,before,after)
    return im

def strip_save(frames,path):
    w,h=frames[0].size;out=Image.new('RGBA',(w*len(frames),h))
    for f,im in enumerate(frames):
        assert im.size==(w,h);out.paste(im,(f*w,0))
    out.save(path)
    return path

def contact(name,frames,guides=None):
    w,h=frames[0].size;scale=min(1,230/max(w,h));cw=round(w*scale);ch=round(h*scale)
    cols=min(len(frames),6);rows=math.ceil(len(frames)/cols)
    sheet=Image.new('RGB',(cols*(cw+14),rows*(ch+32)),(28,39,51));d=ImageDraw.Draw(sheet)
    for i,im in enumerate(frames):
        if guides is not None and (not name.endswith('melt_front') or i<5):
            im=Image.alpha_composite(guides[i],im)
        im=im.resize((cw,ch),Image.Resampling.NEAREST);x=(i%cols)*(cw+14);y=(i//cols)*(ch+32)
        d.text((x+3,y+3),f'f{i:02}',fill='white');sheet.paste(im,(x+4,y+24),im)
    path=OUT/'contact'/f'{name}.png';sheet.save(path)
    return path

def deliver(name,frames,fps,origin,segments,frame_meta,sources,guides=None,**extra):
    spec=SPECS[name];w,h=spec['physical_size'];assert len(frames)==spec['frame_count']
    assert all(im.size==(w,h) for im in frames)
    for source in sources:assert sha(source['path'])==source['sha256'],source['path']
    path=OUT/f'{name}@2x.png';strip_save(frames,path)
    rows=[]
    for i,im in enumerate(frames):
        a=np.array(im);assert set(np.unique(a[:,:,3]))<={0,255}
        fp=OUT/'frames'/f'{name}_f{i:02}@2x.png';im.save(fp)
        rows.append({'frame':i,'file':str(fp.relative_to(BATCH)).replace('\\','/'),'sha256':sha(fp),
                     'bbox':im.getbbox(),'opaque_pixels':int(np.count_nonzero(a[:,:,3])),**frame_meta[i]})
    ent=dict(spec)
    for field in ['keyframes','native_sources','native_pose_guides']:ent.pop(field,None)
    ent.update(file=str(path.relative_to(BATCH)).replace('\\','/'),sha256=sha(path),fps=fps,
               suggested_fps=fps,origin_px_2x=origin,segments=segments,frames=rows,
               rgba_mib=w*h*4*len(frames)/1048576,source_files=sources,
               status='full_animation_final_art_delivery',runtime_verified=False,
               approved_keyframe_source_hashes=[hashed(BATCH/k['file']) for k in spec['keyframes']],**extra)
    if guides is not None:
        gp=OUT/'pose_guides'/f'{name}_native_guide@2x.png';strip_save(guides,gp)
        ent.update(pose_guide_strip=str(gp.relative_to(BATCH)).replace('\\','/'),
                   pose_guide_strip_sha256=sha(gp),pose_guide_frame_size_2x=[w,h],
                   pose_guide_origin_px_2x=origin,pose_guide_frame_mapping=list(range(len(frames))),
                   pose_guide_runtime_policy='PREVIEW ONLY: original runtime summon body already exists; do not stack a second entity',
                   pose_guide_visible_frames=([0,1,2,3,4] if name.endswith('melt_front') else list(range(len(frames)))))
    contact(name,frames,guides)
    (OUT/f'{name}.json').write_text(json.dumps(ent,ensure_ascii=False,indent=2),encoding='utf-8')
    ENTRIES.append(ent)
    CHECKS.append({'name':name,'frame_count':len(frames),'frame_size_2x':[w,h],
                   'binary_alpha':True,'rgba_mib':ent['rgba_mib'],'within_5_mib':ent['rgba_mib']<=5,
                   'unique_frames':len({hashlib.sha256(f.tobytes()).hexdigest() for f in frames}),
                   'approved_keyframes_preserved':all(frames[k['frame']].tobytes()==Image.open(BATCH/k['file']).convert('RGBA').tobytes() for k in spec['keyframes'])})
    return ent

# Sea creature: retain source draw order, mesh poses, density, and approved common translation.
name='fx_ult_skalter_seaborn_front'
choices=[('Start',0),('Start',2),('Start',6),('Start',10),('Skill',1),('Skill',4),('Skill',5),('Skill',7),('Skill',13),('Start',2)]
sea,meta=[],[];raws=[]
for i,(action,frame) in enumerate(choices):
    body,m,rec=native_pose('seaborn',action,frame)
    # Last two source poses reverse the source emergence: actual jaw closure, then actual submerged pose.
    im=shift_to_canvas(body,(320,320),(32,132));sea.append(im)
    rec.update(offset_only_px_2x=[32,132],source_root_px_2x=[128,184],native_body_pixels_unchanged=True)
    meta.append(rec);raws=m['source_files']
sea[0]=accepted(name);sea[6]=accepted(name,True)
front=deliver(name,sea,12,[160,316],{'start':[0,5],'loop':[6,7],'close':[8,9]},meta,raws,
  world_anchor='shared seaborn foot/root',native_scale_preserved=True,loop_mode='ping_pong_two_native_open_jaw_poses',
  close_behavior='native Skill jaw closure followed by original Start submersion, then despawn; no whole-body squash',
  front_to_back_frame_mapping=[0,0,1,1,2,2,3,4,5,5],
  common_world_origin_mapping={'front_origin_px_2x':[160,316],'back_origin_px_2x':[160,48]},
  loop_transition_note='Before looping, reach mouth-open f6. During beam hold alternate f6/f7. On close play f8/f9 then hide.',
  native_source_action_durations_seconds={'Start':1.0,'Skill':1.0666667222976685},
  source_time_mapping_note='Brief timing is 10 frames / 12 fps with a held two-frame loop. Frames 0-3 sample Start at 0, 0.1667, 0.5, 0.8333 s; frames 4-7 sample Skill at 0.0821, 0.3282, 0.3333, 0.4923 s. Close uses Skill at 0.9846 s then original Start at 0.1667 s in reverse-emergence order. Exact source_time is in every frame record; this is an edited FX timeline, not native source duration.')

# Water follows the approved raster crest as moving elliptical material, not an alpha pulsing decal.
def ellipse_flow(im,theta,radial=1.0,flatten=1.0):
    w,h=im.size;yy,xx=np.indices((h,w),dtype=float);cx=(w-1)/2;cy=(h-1)/2
    px=(xx-cx)/radial;py=(yy-cy)/(radial*flatten);co=math.cos(theta);si=math.sin(theta)
    # Scale angular distance in the plane of an ellipse, preserving its floor projection.
    sx=np.rint(cx+px*co+py*3.3*si).astype(int);sy=np.rint(cy-px/3.3*si+py*co).astype(int)
    good=(sx>=0)&(sx<w)&(sy>=0)&(sy<h);a=np.array(im);out=np.zeros_like(a);out[good]=a[sy[good],sx[good]]
    return Image.fromarray(out)
name='fx_ult_skalter_seaborn_back';base=small(accepted(name,True));first=small(accepted(name))
water=[up(first),up(ellipse_flow(base,-.065,.72)),up(ellipse_flow(base,-.025,.92)),up(base),
       up(ellipse_flow(base,.035,1.0)),up(ellipse_flow(base,.08,.82,.47))]
# Fine falling drops in the close frame travel downward; leave the center empty for the summon.
cw=small(water[5]);da=ImageDraw.Draw(cw)
for x,y in [(32,25),(47,30),(114,29),(129,23)]:da.rectangle((x,y,x+1,y+1),fill=(47,112,122,255))
water[5]=up(cw)
deliver(name,water,12,[160,48],{'start':[0,2],'loop':[3,4],'close':[5,5]},
  [{'ellipse_material_rotation_rad':[0,-.065,-.025,0,.035,.08][i],
    'radial_scale':[1,.72,.92,1,1,.82][i],'water_motion':'crest advection; last frame flattened ripple with falling droplets'} for i in range(6)],
  [hashed(BATCH/'revision_water.png')],world_anchor='shared seaborn foot/root',
  front_to_back_frame_mapping=[0,0,1,1,2,2,3,4,5,5],
  common_world_origin_mapping={'front_origin_px_2x':[160,316],'back_origin_px_2x':[160,48]},
  back_loop_sync='Back f3 accompanies front f6; back f4 accompanies front f7. Start advances once per two front frames.',
  approved_raster_reuse='Dark navy/teal approved source; no generated body; no white flash.')

# Melt: original native charging/release poses remain a separate same-index guide.
name='fx_ult_kaltsit_melt_front';charge=small(accepted(name));burst=small(accepted(name,True))
def radial_transport(source,t,energy=True):
    a=np.array(source);yy,xx=np.indices(a.shape[:2],dtype=float);cx=cy=95.5;dx=xx-cx;dy=yy-cy-.9*t*t
    theta=np.arctan2(dy,dx);sector=np.floor((theta+math.pi)/(math.pi/8)).astype(int)
    speed=1.0+.19*np.sin(sector*2.7);rad=1+.10*t*speed
    sx=np.rint(cx+dx/rad).astype(int);sy=np.rint(cy+dy/rad).astype(int)
    good=(sx>=0)&(sx<192)&(sy>=0)&(sy<192);out=np.zeros_like(a);out[good]=a[sy[good],sx[good]]
    return Image.fromarray(out)

def melt_fragments(source,t):
    """Move whole original plates and hot chips, avoiding a checkerboard erosion dissolve."""
    a=np.array(source);rr=a[:,:,0].astype(int);gg=a[:,:,1].astype(int)
    armor=(a[:,:,3]>0)&((rr<80)|(rr<gg*1.6))&(a[:,:,:3].max(axis=2)<155)
    labels,count=ndimage.label(armor)
    out=Image.new('RGBA',source.size)
    for label in range(1,count+1):
        mask=labels==label;ys,xs=np.where(mask)
        if len(xs)<6 or (t>3 and label%3):continue
        # Each black armor facet stays intact while flying in its own direction and dropping.
        cx=float(xs.mean());cy=float(ys.mean());vec=np.array([cx-95.5,cy-95.5]);length=max(1,np.linalg.norm(vec));vec/=length
        vx=vec[0]*(4+label%4);vy=vec[1]*(3+label%3)
        dx=round(vx*t);dy=round(vy*t+1.2*t*t)
        part=np.zeros_like(a);part[mask]=a[mask]
        if t>3:
            # Cool remaining facets, keep coherent opaque fragments rather than noisy alpha.
            part[mask,:3]=np.rint(part[mask,:3]*(.55 if label%3 else .75)).astype('uint8')
        out.alpha_composite(Image.fromarray(part),(dx,dy))
    yy,xx=np.indices(a.shape[:2]);rad=np.hypot(xx-95.5,yy-95.5)
    glow=(a[:,:,3]>0)&(rr>gg*1.6)&(rad>40)
    labels,count=ndimage.label(glow)
    for label in range(1,count+1):
        mask=labels==label;ys,xs=np.where(mask)
        if not 2<=len(xs)<=90:continue
        if t>3 and label%3:continue
        cx=float(xs.mean());cy=float(ys.mean());angle=math.atan2(cy-95.5,cx-95.5)
        dx=round(math.cos(angle)*t*5);dy=round(math.sin(angle)*t*4+1.3*t*t)
        part=np.zeros_like(a);part[mask]=a[mask];out.alpha_composite(Image.fromarray(part),(dx,dy))
    return out

def preburst(source,progress):
    a=np.array(source);yy,xx=np.indices(a.shape[:2]);radius=np.hypot(xx-95.5,yy-95.5)
    # A charge builds from the red core into discrete outward rays; not a full-frame uniform scale.
    radial=np.minimum(1,.32+progress*.68)
    out=np.zeros_like(a);sx=np.rint(95.5+(xx-95.5)/radial).astype(int);sy=np.rint(95.5+(yy-95.5)/radial).astype(int)
    good=(sx>=0)&(sx<192)&(sy>=0)&(sy<192)
    out[good]=a[sy[good],sx[good]]
    if progress<.7:
        live=(xx+2*yy)%9>=int((.7-progress)*8);out[~live]=0
    return Image.fromarray(out)

melt=[up(charge),up(preburst(burst,.22)),up(preburst(burst,.51)),up(preburst(burst,.83)),up(burst),
      up(radial_transport(burst,1.0)),up(melt_fragments(burst,1.6)),up(melt_fragments(burst,3.4))]
guides=[];meta=[]
for f,sourceframe in enumerate([5,6,7,8,9,10,11,12]):
    body,m,rec=native_pose('mon3tr','Skill_2',sourceframe)
    p=next(p for p in m['parts'][sourceframe] if p['slot']=='C_Body_III')
    factor=m['source_scale']*m['pixel_scale'];core=[128+p['bone_world']['x']*factor,184-p['bone_world']['y']*factor]
    offset=[round(192-core[0]),round(192-core[1])]
    guides.append(shift_to_canvas(body,(384,384),offset));rec.update(core_bone='C_Body_III',core_on_source=core,body_offset_px_2x=offset,
      guide_visibility='visible before/through burst f4, hidden after body sacrifice',motion='native Skill_2 deformation and articulation; FX fragments independent')
    meta.append(rec);raws=m['source_files']
deliver(name,melt,24,[192,192],{'charge':[0,2],'burst':[3,5],'close':[6,7]},meta,
  [*raws,hashed(BATCH/'revision_melt.png')],guides=guides,
  body_policy='FX-only production texture; native Skill_2 body in preview-only pose guide',
  particle_motion='outward ray-dependent speed plus downward acceleration; central red-white flash expires before final debris',
  body_handoff='Use the real runtime Mon3tr body. Center FX at its C_Body_III core; hide sacrificed body after f4.',
  native_source_action_duration_seconds=1.2666666507720947,
  source_time_mapping_note='Brief fixes 8 / 24 fps. Native Skill_2 samples 0.3958 through 0.95 s provide real charge/release poses under this 0.3333 s edited FX timeline; f4 is original OnAttack at 0.6667 s. Guides f5-f7 are preserved but hidden after sacrifice.')

# Rebuild: structure paths and contours are sampled from the changing ORIGINAL Start attachment poses.
name='fx_ult_kaltsit_rebuild_orbit';rebuild=[];guides=[];meta=[]
sourceframes=[0,2,4,6,8,10,12,14,16,18,19,19]
green=(126,186,62,255);dim=(60,100,38,255);bright=(181,220,99,255)
for f,sourceframe in enumerate(sourceframes):
    body,m,rec=native_pose('mon3tr','Start',sourceframe);guide=shift_to_canvas(body,(256,256),(0,69));guides.append(guide)
    nodes={}
    for p in m['parts'][sourceframe]:
        if not p.get('body_included',True):continue
        b=Image.open(NATIVE/'mon3tr/Start'/p['path']).getbbox()
        if b:nodes[p['slot']]=((b[0]+b[2])/2,(b[1]+b[3])/2+69)
    im=Image.new('RGBA',(128,128));d=ImageDraw.Draw(im)
    progress=min(1,f/9);core=np.array(nodes.get('C_Body_III',(128,210)))/2
    # Traveling fragments converge on source joint nodes instead of a static decorative ring.
    for k,(slot,node) in enumerate(sorted(nodes.items())):
        if k%2 or 'Light' in slot:continue
        target=np.array(node)/2;angle=k*2.399963;distance=(1-progress)*(24+(k%4)*4)
        pos=target+np.array([math.cos(angle),math.sin(angle)])*distance
        if f<10:
            x,y=map(round,pos);tail=pos+(pos-target)*.15
            d.line((x,y,round(tail[0]),round(tail[1])),fill=green,width=1)
            d.point((x,y),fill=bright)
    if f>=3:
        for seq in [('C_Body_I','C_Body_II','C_Body_III','C_Body_IV'),('C_L_Arm_A','C_L_Arm_B'),('C_R_Arm_A','C_R_Arm_B')]:
            pts=[np.array(nodes[k])/2 for k in seq if k in nodes]
            if len(pts)>1:
                for j in range(len(pts)-1):
                    a=pts[j];b=pts[j+1];end=a+(b-a)*min(1,(f-2)/3)
                    d.line((round(a[0]),round(a[1]),round(end[0]),round(end[1])),fill=green if f<10 else dim,width=1)
        al=np.array(small(guide).getchannel('A'));edge=al>np.array(Image.fromarray(al).filter(ImageFilter.MinFilter(3)))
        yy,xx=np.indices(edge.shape);edge &= ((xx+yy+f*2)//7)%3==0
        if f<6:edge &= yy>(128-f*13)
        arr=np.array(im);arr[edge]=green if f<10 else dim
        if f==11:arr[((xx+2*yy)%4)>0]=0
        im=Image.fromarray(arr)
    rebuild.append(up(im));rec.update(offset_only_px_2x=[0,70],source_root_px_2x=[128,184],
       native_body_pixels_unchanged=True,structure_nodes_px_2x={k:list(v) for k,v in nodes.items()},
       particle_target='current original attachment center; inward transport in source-pose geometry')
    rec['offset_only_px_2x']=[0,69]
    meta.append(rec);raws=m['source_files']
rebuild[0]=accepted(name);rebuild[9]=accepted(name,True)
deliver(name,rebuild,16,[128,253],{'start':[0,2],'assemble':[3,9],'close':[10,11]},meta,raws,guides=guides,
  body_policy='FX-only structure overlay; original Start body is preview-only guide and is the existing runtime entity',
  body_handoff='Map real runtime Mon3tr Start pose times from frame records. f9 reaches the original approved finished body; f10/f11 settle and remove structure light.',
  original_start_source_duration_seconds=1.6666666269302368,delivery_duration_seconds=.75,
  source_time_mapping_note='The brief prescribes 12 frames/16 fps; sample the complete original Start over 0.75 s. Do not treat this as unchanged native source duration.',
  origin_revision_note='Native guide translated upward 1 physical pixel for every frame (root y253 rather than keyframe-study y254), preserving all original foot pixels in intermediate Start poses. Approved FX f0/f9 pixels retained.')

# Anchor is rigid original equipment: no newly drawn fluke or shaft. Shared source scale at all angles.
name='fx_ult_ulpianus_anchor_front';folder=BATCH/'references/native_anchor'
src=json.loads((folder/'source.json').read_text(encoding='utf-8'));pm=json.loads((folder/'pixel_manifest.json').read_text(encoding='utf-8'))
parts=[Image.open(folder/'parts'/f"{s['slot']}.png").convert('RGBA') for s in src['slots']]
full=Image.new('RGBA',(512,512))
for p in parts:full.alpha_composite(p.rotate(-12,Image.Resampling.BICUBIC,center=(256,256)))
ys,xs=np.where(np.array(full.getchannel('A'))>=96);radius=max(np.hypot(xs-256,ys-256));scale=42/radius
transform=(1/scale,0,256-48/scale,0,1/scale,256-48/scale)
anchor=[];meta=[]
for angle in [0,45,90,135]:
    im=Image.new('RGBA',(96,96));partsproof=[]
    for s,p in zip(src['slots'],parts):
        q=p.rotate(-12-angle,Image.Resampling.BICUBIC,center=(256,256))
        q=hard(q.transform((96,96),Image.Transform.AFFINE,transform,Image.Resampling.BICUBIC));im.alpha_composite(q)
        partsproof.append({'slot':s['slot'],'attachment':s['attachment'],'bone':s['bone'],'parent':s['parent'],
                           'source':hashed(folder/'parts'/f"{s['slot']}.png")})
    anchor.append(up(im));meta.append({'clockwise_degrees':angle,'parts':partsproof,'shared_source_scale':scale,'shared_source_pivot':[256,256],
                                    'motion':'rigid original weapon rotation; program interpolates orientation, no body animation'})
anchor[0]=accepted(name);anchor[2]=accepted(name,True)
deliver(name,anchor,None,[96,96],{'orientation_samples':[0,1,2,3]},meta,pm['source_files'],
  rotation_degrees=[0,45,90,135],angle_frames=[0,45,90,135],rotation_pivot=[96,96],
  preview_rotation_degrees_per_second=180,
  playback_mode='orientation lookup, never auto-loop as gameplay animation',
  body_policy='Original Ulpianus weapon attachments, original draw order, no chain, fixed shared scale',
  quarter_turn_exact=anchor[2].tobytes()==anchor[0].transpose(Image.Transpose.ROTATE_270).tobytes())

(OUT/'entries.json').write_text(json.dumps(ENTRIES,ensure_ascii=False,indent=2),encoding='utf-8')
assert all(c['approved_keyframes_preserved'] and c['within_5_mib'] for c in CHECKS)
(OUT/'qa.json').write_text(json.dumps({'assets':CHECKS,'total_production_rgba_mib':sum(e['rgba_mib'] for e in ENTRIES),
 'native_source_hashes_checked':True,'no_game_edits':True,'runtime_verified':False,
 'guides_are_preview_only':True,'seaborn_common_world_origin_mapping':front['common_world_origin_mapping'],
 'seaborn_front_to_back_mapping':front['front_to_back_frame_mapping']},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'written':len(ENTRIES),'frames':sum(e['frame_count'] for e in ENTRIES),'checks':CHECKS},ensure_ascii=False,indent=2))
