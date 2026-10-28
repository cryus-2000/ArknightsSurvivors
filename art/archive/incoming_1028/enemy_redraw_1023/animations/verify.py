"""Independent strip/component checks; does not edit delivery pixels."""
import hashlib,json,pathlib
import numpy as np
from PIL import Image
P=pathlib.Path(__file__).resolve().parent
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
fail=[];notes=[];rows=[];count=0
for mp in sorted(P.glob('*/manifest.json')):
    m=read(mp);w,h=m['frame_size'];palette=set();base=mp.parent
    if not (0<=m['origin'][0]<w and 0<=m['origin'][1]<h):fail.append(m['id']+' origin outside canvas')
    for a in m['assets']:
        p=P/a['file']
        if hashlib.sha256(p.read_bytes()).hexdigest()!=a['sha256']:fail.append(str(p)+' hash')
    for act in m['actions']:
        n=act['frames'];stem='e_'+m['id']+'_'+act['action'];meta=read(base/(act['action']+'_parts.json'))
        for suffix in ('','_emit'):
            lo=Image.open(base/(stem+suffix+'.png')).convert('RGBA');hi=Image.open(base/(stem+suffix+'@2x.png')).convert('RGBA')
            if lo.size!=(w*n,h):fail.append(stem+suffix+' dimensions')
            ar=np.array(lo)
            if not set(np.unique(ar[:,:,3])).issubset({0,255}):fail.append(stem+suffix+' alpha')
            if not np.array_equal(np.array(hi),np.repeat(np.repeat(ar,2,0),2,1)):fail.append(stem+suffix+' density')
            if not suffix:palette.update(map(tuple,ar[:,:,:3][ar[:,:,3]>0]))
            for i in range(n):
                tile=lo.crop((i*w,0,(i+1)*w,h));box=tile.getbbox()
                if not box:
                    allowed=(suffix=='_emit' and (m['id']=='mimic_disguised' or act['action']=='death' or meta[i].get('glow_active') is False)) or act['action']=='death'
                    if not allowed:fail.append(stem+suffix+' empty '+str(i))
                    continue
                if box[0]<=0 or box[1]<=0 or box[2]>=w or box[3]>=h:fail.append(stem+suffix+' clipping '+str(i))
                if not suffix:
                    raw=P.parents[4]/'build/enemy_actions_1023'/m['id']/(meta[i]['name']+'.png')
                    if raw.exists():
                        original=Image.open(raw).convert('RGBA');rb=original.getbbox()
                        if rb and (rb[0]==0 or rb[1]==0 or rb[2]==original.width or rb[3]==original.height):fail.append(stem+' clipped source '+str(i))
                    recon=Image.new('RGBA',(w,h))
                    for part in meta[i]['parts']:
                        comp=Image.open(base/part['pixel_component']).convert('RGBA').crop((i*w,0,(i+1)*w,h));recon.alpha_composite(comp)
                    if recon.tobytes()!=tile.tobytes():fail.append(stem+' recomposition '+str(i))
                    if i==0 and act['action']=='idle':
                        actual=box[3]-box[1]
                        if abs(actual-m['idle_height_target'])>1:fail.append(m['id']+' idle height '+str(actual))
            count+=1
        for e,i in zip(act.get('playback_events',act['source_events']),act['event_frames']):
            if abs(act['sample_times'][i]-e['t'])>1e-6:fail.append(stem+' event sampling')
        if not all(x<y for x,y in zip(act['sample_times'],act['sample_times'][1:])):fail.append(stem+' non-increasing times')
        release=act.get('release_frame')
        if release is not None and not 0<=release<n:fail.append(stem+' release frame')
        if act['action']=='wound':
            idle=Image.open(base/('e_'+m['id']+'_idle.png')).convert('RGBA').crop((0,0,w,h))
            hit=Image.open(base/(stem+'.png')).convert('RGBA')
            if hit.tobytes()==idle.tobytes():fail.append(stem+' wound identical to idle')
    if len(palette)>m['color_cap']:fail.append(m['id']+' color cap')
    rows.append({'id':m['id'],'actions':len(m['actions']),'body_colors':len(palette),'subpixel_part_samples':len(m['subpixel_parts']),'unavailable':m['unavailable']})
    if m['subpixel_parts']:notes.append(m['id']+': subpixel attachments are preserved in metadata and source evidence, see manifest')
result={'passed':not fail,'strips_1x':count,'errors':fail,'warnings':notes,'characters':rows,'checks':['hash','dimensions','binary alpha','exact nearest 2x','no edge clipping','palette cap','exact attachment recomposition','fixed reference scale','original event samples'],'static_review':'contact sheets inspected separately; not blanket approved','motion_review':'browser review supplied; real-time playback not certified','engine':'not integrated','user_approval':'pending animation review','legacy_verifier_note':'uniform external outline and fixed per-frame ground baseline assumptions do not match original Spine airborne/attack poses; independent checks used'}
(P/'qa.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'passed':not fail,'strips':count,'characters':len(rows),'errors':fail},ensure_ascii=False))
raise SystemExit(0 if not fail else 1)
