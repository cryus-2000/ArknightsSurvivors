# 全员手感排查汇总（docs/196）：读 build/feel_audit/raw/*.json（balance_run --extra "--feelprobe"），写 build/feel_audit/agg.json 并打印
import json,glob,os,sys,statistics as st,collections
sys.path.insert(0,'tools'); import balance_run as BR
S2O=BR.src_to_op()
R=collections.defaultdict(list)
for f in glob.glob('build/feel_audit/raw/*.json'):
    for r in json.load(open(f,encoding='utf-8'))['records']:
        if 'data' in r: R[r['squad'][0]].append(r)
names={}
for f in glob.glob('game/data/characters/*.json'):
    d=json.load(open(f,encoding='utf-8')); names[d['id']]=d['name']
m=lambda xs: st.mean(xs) if xs else 0
out=[]
for op,rs in sorted(R.items()):
    D=[r['data'] for r in rs]; F=[d.get('feel',{}) for d in D]
    def fm(k): return m([f.get(k,0) for f in F])
    deaths=collections.Counter(d['bot'].get('death_src','?') for d in D if not d['win'])
    tail=collections.Counter()
    for d in D:
        if not d['win']:
            for k,v in d['bot'].get('curve_tail',{}).get('dsrc',{}).items(): tail[k]+=v
    th=[];dps=[];lead=[]
    for d in D:
        tot=sum(d['out'].values()) or 1
        lead.append(100*sum(v for k,v in d['out'].items() if S2O.get(k.split(' · ')[0])==op)/tot)
        for bo in d['bot'].get('bosses',[]):
            if BR._boss_phase(bo)!=2: continue
            w=bo.get('windows',[])
            if w: dps.append(sum(x.get('out',0) for x in w)/(15*len(w)))
            if bo.get('t1',-1)>=0 and bo.get('tv',-1)>=0: th.append(bo['t1']-bo['tv'])
    out.append(dict(op=op,name=names.get(op,op),n=len(D),win=100*m([1 if d['win'] else 0 for d in D]),t=m([d['t'] for d in D]),
        taken_pm=m([d['bot'].get('taken_pm',0) for d in D]),hits_pm=m([d['bot'].get('hits_pm',0) for d in D]),still=m([d['bot'].get('still_pct',0) for d in D]),
        near=fm('near_pct'),crowd=fm('crowd_pct'),tnear=fm('taken_near_pct'),stuck_cc=fm('stuck_cc_pct'),stuck_self=fm('stuck_self_pct'),pulled=fm('pulled_pm'),
        casts=fm('casts'),risky=fm('cast_risky_pct'),ctaken=fm('cast_taken_avg'),cnear=fm('cast_near_d'),lead=m(lead),
        boss_th=(st.median(th) if th else None),boss_kill=len(th),boss_dps=m(dps),
        deaths=deaths.most_common(3),tail=[k for k,_ in tail.most_common(3)]))
json.dump(out,open('build/feel_audit/agg.json','w',encoding='utf-8'),ensure_ascii=False,indent=1)
for o in out: print(o['op'],round(o['win']),round(o['t']),round(o['near'],1),round(o['tnear']),round(o['stuck_self'],1),round(o['pulled'],2),round(o['risky']),round(o['lead']),o['boss_th'],round(o['boss_dps']),o['deaths'][:2])
