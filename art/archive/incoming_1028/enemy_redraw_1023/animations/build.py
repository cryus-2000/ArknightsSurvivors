"""Original Spine attachment -> shared logical grid -> body / independent emit.

No pixels, joints or palettes are extracted from approved f0 images.
Raw supersampled source evidence lives in ignored build/. Pixel components ship.
"""
import argparse, hashlib, html, json, os, pathlib, subprocess
import numpy as np
from PIL import Image, ImageDraw
from completion import extend
from custom_sources import prepare

HERE=pathlib.Path(__file__).resolve().parent
ROOT=HERE.parents[4]
OLD=ROOT/'art/incoming/cj_enemy_native_actions_1018'
BUILD=ROOT/'build/enemy_actions_1023'
RUNTIME=pathlib.Path('E:/ArknightsSurvivors/build/prts_ref/_node')
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,v): p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def rgb(s): return tuple(bytes.fromhex(s.lstrip('#')))

def plan(j):
    ident=j['id']; source=ident.replace('_phase2','').replace('_boss','')
    if ident in ('tear','mimic_disguised'): return None
    old=read(OLD/source/'render_job.json')
    cat=read(next((OLD/source).glob('native*/animation_catalog.json')))['anims']
    maps={'idle':'Idle','move':'Move','attack':'Attack'}
    if source=='reaper': maps={'idle':'Skill_Idle','move':'Skill_Move','attack':'Skill_Attack','dormant':'Idle','awaken':'Skill_Begin'}
    if source=='paranoia': maps={k:('C2_' if ident.endswith('phase2') else 'C1_')+v for k,v in maps.items()}
    if ident=='ishar_phase2': maps={k:v+'_02' for k,v in maps.items()}
    if ident=='skimmer': maps={k:v+'_01' for k,v in maps.items()}
    if source in ('carmen','iberia'): maps.update(attack='Attack_1',melee='Attack_2')
    if source in ('bishop','archon','immortal'): maps['feign']='Die_Idle'
    if ident=='knight_boss': maps={'idle':'Move_2','move':'Move_2'}
    elite=j['group'] not in ('群怪','普通','大型普通','召唤物')
    frames=[{'name':'reference','anim':maps['idle'],'t':0}];actions=[];missing=[]
    for action,anim in maps.items():
        if anim not in cat:
            missing.append({'action':action,'reason':'no matching original Spine animation'});continue
        duration=cat[anim]['dur'];loop=action in ('idle','move','dormant','feign')
        count=(6 if elite else 4) if loop else (8 if elite else 6)
        times=list(np.linspace(0,duration,count,endpoint=not loop))
        if not loop: times[-1]=max(0,duration-0.001)
        events=cat[anim]['events']
        for e in events:
            ix=min(range(1,count-1),key=lambda n:abs(times[n]-e['t']))
            times[ix]=float(e['t'])
        times=sorted(times)
        names=[]
        for ix,t in enumerate(times):
            name=f'{action}_{ix:02}';names.append(name);frames.append({'name':name,'anim':anim,'t':float(t)})
        actions.append({'action':action,'source_animation':anim,'frames':count,'duration_seconds':duration,'sample_times':times,'source_events':events,'event_frames':[min(range(count),key=lambda n:abs(times[n]-e['t'])) for e in events],'loop':loop,'frame_names':names})
    # Pick only a verified original slot. Bind its reference-local point to its bone.
    choices=list((OLD/source).glob('native*/'+maps['idle']+'_00_parts.json')) or list((OLD/source).glob('native*/reference_parts.json'))
    slots=read(choices[0])
    names=[x['slot'] for x in slots]
    preferred={'bone':'C_Body_01','runner':'C_Mouth_01','brood':'C_Weapon','stone':'C_Head_01','skimmer':'C_Ball_01','carmen':'Hat_A'}
    selected=preferred.get(ident)
    if selected not in names:
        selected=next((n for n in reversed(names) if 'head' in n.lower()),None)
    if not selected: selected=next((n for n in reversed(names) if 'body' in n.lower()),names[-1])
    out=BUILD/ident
    render={k:old[k] for k in ('skel','atlas','json') if k in old}
    render.update(id=ident,height=j['visible_height_1x'],canvas=j['canvas_1x'],out_dir=str(out),frames=frames,glow_slot=selected,glow_uv=[0.25,0.65] if ident=='carmen' else [0.65,0.45])
    # Sparse original edge attachments lose coverage at binary grid sampling.
    # One reference calibration applies to every pose; never fit per frame.
    if ident=='skimmer':render['height']=32
    if ident=='izumik':render['height']=86
    return extend(j,render,actions,missing,cat,OLD)

def pixelize(image,palette,ident):
    im=image.resize((image.width//4,image.height//4),Image.Resampling.BOX)
    a=np.array(im);mask=a[:,:,3]>=128
    out=np.zeros_like(a)
    c=a[:,:,:3][mask].astype(np.int32)
    if ident=='brood':
        # The original nut/core is pale warm pink. The approved new material is
        # dark blue; keep neutral shell highlights and its independent head glow.
        warm=(c[:,0]>c[:,2]*1.08)&(c[:,0]>c[:,1]*1.025)
        c[warm]=(np.array([38,51,72])[None,:]+(c[warm].mean(1)[:,None]/255)*np.array([37,26,19])).astype(np.int32)
    if len(c):
        d=((c[:,None,:]-palette[None,:,:])**2).sum(2)
        out[mask,:3]=palette[d.argmin(1)];out[mask,3]=255
    return Image.fromarray(out)

def export(j,actions,missing):
    ident=j['id'];raw=BUILD/ident;cat=read(raw/'catalog.json');w,raw_h=cat['frame_size'];h=j['canvas_1x'][1]
    palette=np.array([rgb(s) for s in j['palette']],dtype=np.int32)
    if ident=='mimic_disguised':
        original=np.array(Image.open(ROOT/j['reference']).convert('RGBA'))
        opaque=original[:,:,:3][original[:,:,3]>=128]
        reduced=Image.fromarray(opaque.reshape(1,-1,3)).quantize(colors=16,method=Image.Quantize.MEDIANCUT).convert('RGB')
        palette=np.unique(np.array(reduced).reshape(-1,3),axis=0).astype(np.int32)
    # Remove only shared transparent margins. Height stays at the brief's canvas
    # size, with a single crop and origin for the entire character's action set.
    top=raw_h;bottom=0
    for f in cat['frames']:
        im=Image.open(raw/(f['name']+'.png')).convert('RGBA').resize((w,raw_h),Image.Resampling.BOX)
        box=im.getchannel('A').point(lambda v:255 if v>=128 else 0).getbbox()
        if box:top=min(top,box[1]);bottom=max(bottom,box[3])
    if bottom-top>h-2:raise ValueError(ident+' action union exceeds fixed canvas')
    crop_y=max(bottom-h+1,min(top-1,round(cat['origin'][1]-(h-4))))
    crop=(0,crop_y,w,crop_y+h);origin=[cat['origin'][0],cat['origin'][1]-crop_y]
    out=HERE/ident;out.mkdir(exist_ok=True)
    byname={f['name']:f for f in cat['frames']};lost=[];assets=[];previews=[]
    for act in actions:
        n=act['frames'];body=Image.new('RGBA',(w*n,h));emit=body.copy();parts={};frames=[];sources=[]
        frame_meta=[]
        for ix,name in enumerate(act['frame_names']):
            f=byname[name];f['source_crop_1x']=list(crop);composite=Image.new('RGBA',(w,h));src=Image.open(raw/(name+'.png')).convert('RGBA');sources.append(src.resize((w,raw_h),Image.Resampling.NEAREST).crop(crop))
            binding=cat.get('glow_binding') or {};glow_visible=bool(binding.get('component'))
            for p in f['parts']:
                part=pixelize(Image.open(raw/p['file']).convert('RGBA'),palette,ident).crop(crop)
                if p['slot']==binding.get('slot') and part.getbbox():glow_visible=True
                key=p['slot']+'__'+p['attachment'];key=''.join(c if c.isalnum() or c in '_-' else '_' for c in key)
                if key not in parts:parts[key]=Image.new('RGBA',(w*n,h))
                parts[key].paste(part,(ix*w,0));composite.alpha_composite(part)
                if not part.getbbox():lost.append({'frame':name,'slot':p['slot'],'attachment':p['attachment']})
                p['pixel_component']='components/'+act['action']+'/'+key+'.png'
                p['source_file']='build/enemy_actions_1023/'+ident+'/'+p['file']
            body.paste(composite,(ix*w,0));frames.append(composite)
            light=Image.new('RGBA',(w,h));d=ImageDraw.Draw(light)
            f['glow_active']=glow_visible
            if f['glow'] and composite.getbbox() and glow_visible:
                x,y=map(round,f['glow']);y-=crop_y;colors=[rgb(c)+(255,) for c in j['emission_palette']]
                d.line((x-1,y,x+1,y),fill=colors[0]);d.line((x,y-1,x,y+1),fill=colors[1]);d.point((x,y),fill=colors[2])
            emit.paste(light,(ix*w,0));frame_meta.append(f)
        stem='e_'+ident+'_'+act['action']
        for suffix,im in [('',body),('_emit',emit)]:
            p=out/(stem+suffix+'.png');im.save(p)
            p2=out/(stem+suffix+'@2x.png');im.resize((im.width*2,im.height*2),Image.Resampling.NEAREST).save(p2)
            for asset in (p,p2):assets.append({'file':str(asset.relative_to(HERE)).replace('\\','/'),'sha256':sha(asset)})
        for key,im in parts.items():
            p=out/'components'/act['action']/(key+'.png');p.parent.mkdir(parents=True,exist_ok=True);im.save(p)
        write(out/(act['action']+'_parts.json'),frame_meta)
        # Explicit source vs reassembled pixel per-frame contact sheet.
        sheet=Image.new('RGB',(w*n*3,h*6+24),(24,30,38))
        draw=ImageDraw.Draw(sheet);draw.text((3,2),'SOURCE / PIXEL (same poses)',fill='white')
        for ix in range(n):
            for row,im in enumerate((sources[ix],frames[ix])):
                z=im.resize((w*3,h*3),Image.Resampling.NEAREST);sheet.paste(z,(ix*w*3,24+row*h*3),z)
        sheet.save(out/(act['action']+'_contact.png'))
        previews.append({'id':ident,'name':j['name'],'action':act['action'],'strip':ident+'/'+stem+'@2x.png','emit':ident+'/'+stem+'_emit@2x.png','size':[w*2,h*2],**act})
    record={'id':ident,'name':j['name'],'construction':cat.get('source'),'frame_size':[w,h],'origin':origin,'source_crop_1x':list(crop),'scale_fixed_across_actions':cat['scale'],'idle_height_target':j['visible_height_1x'],'palette':['#'+''.join(f'{int(c):02X}' for c in row) for row in palette],'color_cap':j['color_cap'],'actions':actions,'unavailable':missing,'glow_binding':cat['glow_binding'],'subpixel_parts':lost,'assets':assets,'status':'review candidate; not integrated','source_hashes':{k:sha(pathlib.Path(v)) for k,v in read(BUILD/(ident+'_job.json')).items() if k in ('skel','atlas','json','art_source')}}
    write(out/'manifest.json',record)
    return previews

def review(previews):
    from review_ui import page
    write(HERE/'preview.json',previews)
    (HERE/'review.html').write_text(page(previews),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ids',nargs='*');parser.add_argument('--reuse-source',action='store_true');args=parser.parse_args()
    jobs=read(HERE.parent/'remaining/job.json')['jobs'];BUILD.mkdir(parents=True,exist_ok=True)
    prefix=(OLD/'custom_boss/render_custom.js').read_text(encoding='utf-8').split('  // 统一缩放')[0]
    renderer=BUILD/'render.js';renderer.write_text(prefix+(HERE/'render_tail.js').read_text(encoding='utf-8'),encoding='utf-8')
    env=os.environ.copy();env['NODE_PATH']=str(RUNTIME/'node_modules');previews=[];exceptions=[]
    for j in jobs:
        if args.ids and j['id'] not in args.ids:continue
        p=plan(j)
        if not p:
            actions,missing=prepare(j,ROOT,BUILD);previews.extend(export(j,actions,missing));continue
        render,actions,missing=p;write(BUILD/(j['id']+'_job.json'),render)
        print('Rendering',j['id'],flush=True)
        if not args.reuse_source:subprocess.run(['node',str(renderer),str(RUNTIME/'spine-canvas-3.8.js'),str(BUILD/(j['id']+'_job.json'))],env=env,check=True)
        previews.extend(export(j,actions,missing));print('Exported',j['id'],flush=True)
    previews=[]
    for mp in sorted(HERE.glob('*/manifest.json')):
        m=read(mp);w,h=m['frame_size']
        for a in m['actions']:
            stem='e_'+m['id']+'_'+a['action']
            previews.append({'id':m['id'],'name':m['name'],'strip':m['id']+'/'+stem+'@2x.png','emit':m['id']+'/'+stem+'_emit@2x.png','size':[w*2,h*2],**a})
    review(previews)
    if not args.ids:write(HERE/'exceptions.json',exceptions)

if __name__=='__main__':main()
