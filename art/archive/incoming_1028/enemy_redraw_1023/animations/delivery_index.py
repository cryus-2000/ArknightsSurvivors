"""Read-only coverage and coordinator integration map; never changes game data."""
import hashlib,json,pathlib,subprocess
P=pathlib.Path(__file__).resolve().parent;ROOT=P.parents[4];MAIN=ROOT.parents[1]
read=lambda p:json.loads(p.read_text(encoding='utf-8'))
enemies=read(MAIN/'game/data/enemies.json');runtime=read(MAIN/'game/data/enemy_pixels.json')
base_overrides={'knight':'e_knight_walk','knight_boss':'e_knight','ishar_phase2':'e_ishar_t','paranoia_phase2':'e_paranoia_phase2','iberia':'e_saint_dark','carmen':'e_saint'}
extra={('paranoia','attack'):'e_paranoia_gaze',('paranoia_phase2','attack'):'e_paranoia_phase2_howl',('ishar_phase2','transform'):'e_ishar_transform',('ishar_phase2','t_sing'):'e_ishar_t_sing',('carmen','saint_reload'):'e_saint_reload',('iberia','saint_dark_reload'):'e_saint_dark_reload',('iberia','saint_dark_lob'):'e_saint_dark_lob'}
items=[];coverage=[];errors=[]
for mp in sorted(P.glob('*/manifest.json')):
    m=read(mp);ident=m['id'];names={a['action'] for a in m['actions']}
    required={'idle','wound','reveal'} if ident=='mimic_disguised' else {'idle','move','attack','wound','death'}
    if ident=='knight_boss':required|={'charge','charge_form','thrust','spin','plant'}
    if ident=='knight':required.add('charge')
    absent=sorted(required-names)
    if absent:errors.append({'id':ident,'missing':absent})
    coverage.append({'id':ident,'actions':sorted(names),'missing':absent,'not_applicable':['move','attack','death: use revealed form'] if ident=='mimic_disguised' else []})
    base=base_overrides.get(ident,enemies.get(ident,{}).get('tex','e_'+ident))
    for a in m['actions']:
        name=a['action'];key=extra.get((ident,name),base+('' if name=='idle' else '_'+name));old=runtime.get(key)
        items.append({'id':ident,'action':name,'body':f'{ident}/e_{ident}_{name}@2x.png','emit':f'{ident}/e_{ident}_{name}_emit@2x.png','frame_size_2x':[x*2 for x in m['frame_size']],'origin_2x':[x*2 for x in m['origin']],'frames':a['frames'],'candidate_runtime_key':key,'existing_runtime_key':key if old else None,'existing_frame_count':old.get('frames') if old else None,'requires_selector_update':bool(old and old.get('frames')!=a['frames']),'source_events':a['source_events'],'playback_events':a.get('playback_events',a['source_events']),'event_frames':a['event_frames'],'release_frame':a.get('release_frame'),'timing_policy':'keep current gameplay anticipation/release/recovery; preview duration is not an attack period'})
index={'states':len(coverage),'action_sets':len(items),'wound_sets':sum(x['action']=='wound' for x in items),'death_sets':sum(x['action']=='death' for x in items),'coverage_passed':not errors,'coverage_errors':errors,'coverage':coverage,'main_reference_commit':subprocess.check_output(['git','-C',str(MAIN),'rev-parse','HEAD'],text=True).strip(),'integration_status':'not integrated; filenames are delivery candidates, no game files changed','motion_status':'static frame evidence inspected; continuous playback not certified','files':items}
(P/'integration_map.json').write_text(json.dumps(index,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:index[k] for k in ['states','action_sets','wound_sets','death_sets','coverage_passed','coverage_errors']},ensure_ascii=False))
raise SystemExit(0 if index['coverage_passed'] else 1)
