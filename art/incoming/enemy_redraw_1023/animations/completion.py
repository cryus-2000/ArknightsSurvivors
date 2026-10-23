"""Second batch: original extra actions and authored native-bone gap filling."""
import ast,math,pathlib

def _plans(path,boss=False):
    tree=ast.parse(path.read_text(encoding='utf-8'))
    node=next(n.value for n in tree.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='plans' for t in n.targets))
    if not boss:return ast.literal_eval(node)
    def f(anim,t,bones=None):return {'anim':anim,'t':t,'bones':bones or {}}
    return eval(compile(ast.Expression(node),str(path),'eval'),{'__builtins__':{},'f':f})

def extend(j,render,actions,missing,cat,old):
    ident=j['id'];source=ident.replace('_phase2','').replace('_boss','')
    idle=actions[0]['source_animation'];elite=j['group'] not in ('群怪','普通','大型普通','召唤物')
    def add(name,poses,duration,loop=False,events=None,kind='authored native bone pose',replace=False,event_indices=None):
        if replace:
            actions[:]=[a for a in actions if a['action']!=name]
            render['frames'][:]=[f for f in render['frames'] if not f['name'].startswith(name+'_')]
        if any(a['action']==name for a in actions):return
        n=len(poses);times=[duration*i/(n if loop else max(1,n-1)) for i in range(n)]
        if n>1 and not loop:times[-1]=max(times[-2]+.001,duration-.001)
        names=[]
        for i,p in enumerate(poses):
            fn=f'{name}_{i:02}';names.append(fn);render['frames'].append({'name':fn,**p})
        ev=events or []
        inds=event_indices if event_indices is not None else [min(range(n),key=lambda k:abs(times[k]-e['t'])) for e in ev]
        for e,ix in zip(ev,inds):times[ix]=e['t']
        actions.append({'action':name,'source_animation':poses[0]['anim'],'construction':kind,'frames':n,'duration_seconds':duration,'sample_times':times,'source_events':ev,'event_frames':inds,'loop':loop,'frame_names':names,'pose_times':[p['t'] for p in poses],'release_frame':inds[0] if inds else None})
    def native(name,anim,loop=False,count=None):
        if anim not in cat:return
        n=count or (6 if elite else 4) if loop else count or (8 if elite else 6)
        dur=cat[anim]['dur'];ts=[dur*i/(n if loop else n-1) for i in range(n)]
        if not loop:ts[-1]=max(0,dur-.001)
        for e in cat[anim]['events']:
            k=min(range(1,n-1),key=lambda k:abs(ts[k]-e['t']));ts[k]=e['t']
        ts.sort();poses=[{'anim':anim,'t':t} for t in ts]
        add(name,poses,dur,loop,kind='original Spine animation')
        a=actions[-1];a['sample_times']=ts;a['source_events']=cat[anim]['events'];a['event_frames']=[min(range(n),key=lambda k:abs(ts[k]-e['t'])) for e in a['source_events']]
    death='C2_Die' if ident=='paranoia_phase2' else 'C1_Die' if ident=='paranoia' else 'Die_02' if ident=='ishar_phase2' else 'Die_01' if ident=='skimmer' else 'Die'
    if source!='knight':native('death',death)
    if ident=='knight_boss':native('death','Die',count=4)
    if source in ('bishop','archon','immortal'):native('revive','Die_Loop',True)
    if source in ('carmen','iberia','fractal','path','ishar') and not ident.endswith('phase2'):native('skill','Skill')
    if ident=='ishar_phase2':
        native('transform','Start_02')
        a=next(a for a in actions if a['action']=='transform');fs=[f for f in render['frames'] if f['name'].startswith('transform_')]
        source_times=list(reversed(a['sample_times']));dur=a['duration_seconds']
        for f,t in zip(fs,source_times):f['t']=t
        a['pose_times']=source_times;a['sample_times']=[dur-t for t in source_times];a['sample_times'][0]=0
        a['playback_events']=[{'name':e['name'],'t':dur-e['t']} for e in a['source_events']]
        a['event_frames']=[min(range(len(fs)),key=lambda k:abs(a['sample_times'][k]-e['t'])) for e in a['playback_events']]
        a['construction']='original Start_02 sampled in reverse for human-to-large transformation'
    if source=='mimic':native('reveal','Start')
    if source=='skimmer':native('change','Change')
    if source=='izumik':
        for name,anim,loop in [('root_begin','Skill_1_Begin',False),('root_loop','Skill_1_Loop',True),('root_end','Skill_1_End',False),('share','Skill_2',False),('revive','Revive',False)]:native(name,anim,loop)
    if source=='paranoia':native('revive','C1_Revive2')
    # Source slot inventory, not an f0-derived skeleton.
    import json
    sc=list((old/source).glob('native*/'+idle+'_00_parts.json')) or list((old/source).glob('native*/reference_parts.json'))
    slots=json.loads(sc[0].read_text(encoding='utf-8'))
    bones=list(dict.fromkeys(s['bone'] for s in slots))
    head=next((b for b in bones if 'head' in b.lower()),None)
    torso=next((b for b in bones if b.lower() in ('chest','c_body','c_body_01','c_weapon')),bones[-1])
    recoil={torso:{'rotation':6}}
    if head and head!=torso:recoil[head]={'rotation':-7}
    if source=='knight':recoil={'F_Waist':{'rotation':8},'F_Head':{'rotation':-7}}
    if ident=='knight_boss':recoil['C_Head']={'rotation':6}
    # Alternate forms can have distinct bone sets. Select their actual visible slots.
    if ident.endswith('phase2'):
        choices=list((old/source).glob('native*/'+idle+'_00_parts.json'))
        if choices:
            sb=json.loads(choices[0].read_text());target=next((s['bone'] for s in sb if 'head' in s['bone'].lower()),sb[-1]['bone']);recoil={target:{'rotation':-7}}
    add('wound',[{'anim':idle,'t':0,'bones':recoil}],.12)
    if ident=='knight':
        walk=json.loads((old/'knight_walk/job.json').read_text(encoding='utf-8'))
        for name,duration in [('charge',.72),('death',.667)]:
            poses=[{'anim':f['anim'],'t':f['t'],'bones':f.get('edits',{})} for f in walk['frames'] if f['name'].startswith(name)]
            add(name,poses,duration)
            if name=='charge':actions[-1]['release_frame']=2
    small=_plans(old/'custom_small/build_custom.py')
    if source in small:
        for act,keys in small[source].items():
            name=act.lower();loop=name in ('move','enraged')
            if source=='pocket' and name=='swell':
                for key in keys:
                    for field,val in key.get('C_Body',{}).items():
                        if field.startswith('scale'):key['C_Body'][field]=1+(val-1)*.7
            poses=[{'anim':idle,'t':cat[idle]['dur']*i/len(keys),'bones':b} for i,b in enumerate(keys)]
            add(name,poses,.8 if not loop else cat[idle]['dur'],loop)
            if name=='attack':actions[-1]['release_frame']=2
    bp=_plans(old/'custom_boss/build_custom.py',True)
    if source in bp and source!='knight':
        for key,poses in bp[source].items():
            name=key.removeprefix('e_'+source+'_')
            if name.startswith('e_'):name=name[2:]
            # Transformation is exported with the transformed form's correct scale.
            if 'transform' in name or (source=='ishar' and not ident.endswith('phase2')):continue
            add(name,poses,len(poses)*.16,name=='charge')
    if ident=='knight_boss':
        for key,poses in bp['knight'].items():
            name=key.removeprefix('e_knight_')
            if name in ('e_knight','move','death'):continue
            if name in ('spin','plant'):
                for p in poses:
                    b=p['bones']
                    if 'rotation' in b.get('F_Weapon',{}):b['F_Weapon']['rotation']=16+(b['F_Weapon']['rotation']-16)*(.45 if name=='spin' else .4)
                    if name=='plant' and 'y' in b.get('F_L_Forearm_ik',{}):b['F_L_Forearm_ik']['y']*=.4
            add(name,poses,len(poses)*.16,name=='charge_form')
            if name in ('attack','charge','spin'):actions[-1]['release_frame']=2
            if name=='plant':actions[-1]['release_frame']=3
            if name=='thrust':actions[-1]['release_frame']=1
        poses=[]
        for i in range(6):
            q=math.sin(i*math.tau/6)
            poses.append({'anim':'Move_2','t':0,'bones':{'F_Waist':{'rotation':q*1.5},'F_Head':{'rotation':-q},'C_Neck':{'rotation':q*1.5},'C_Tail_1':{'rotation':q*3}}})
        add('idle',poses,2.0,True,replace=True)
    if ident=='path':
        frames=[f for f in render['frames'] if f['name'].startswith('death_')]
        for i,f in enumerate(frames):
            u=[0,.5,1,1,.8,.4,0,0][i]
            f['bones']={'Neck':{'rotation':-42*u},'Chest':{'rotation':-6*u}}
        next(a for a in actions if a['action']=='death')['construction']='original death with authored neck clearance for fixed canvas'
    done={a['action'] for a in actions};missing[:]=[m for m in missing if m['action'] not in done]
    return render,actions,missing
