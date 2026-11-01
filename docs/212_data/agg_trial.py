import json, statistics as st, collections, sys
R=[json.loads(l) for l in open('docs/212_data/trial_diag.txt',encoding='utf-8')]
bad=[r['key'] for r in R if not r['rec'] or r['errors']]
print('bad',bad[:5],len(bad))
G=collections.defaultdict(list)
for r in R:
    if r['rec']: G[r['key'][0]].append(r)
med=lambda a: st.median(a) if a else 0
for g,rs in G.items():
    T=[x['rec']['t'] for x in rs]; wins=sum(1 for x in rs if x['rec']['result']=='win'); in150=sum(1 for x in rs if x['rec']['result']=='win' and x['rec']['t']<=150)
    # taken % maxhp per min
    tpm=[100*x['rec']['taken_total']/x['rec']['max_hp']/(x['rec']['t']/60) for x in rs]
    hits=[sum(v['hits'] for v in x['rec']['taken'].values())/(x['rec']['t']/60) for x in rs]
    # per move
    M=collections.defaultdict(lambda:[0.0,0,0])  # dmg, hits, casts
    tsum=sum(x['rec']['t'] for x in rs)
    for x in rs:
        mh=x['rec']['max_hp']
        for k,v in x['rec']['taken'].items(): M[k][0]+=100*v['dmg']/mh; M[k][1]+=v['hits']
        for k,c in x['rec'].get('casts',{}).items(): M[k][2]+=c
    tot=sum(v[0] for v in M.values()) or 1
    print(f"\n== {g} n={len(rs)} 用时中位 {med(T):.0f}（m0 {med([x['rec']['t'] for x in rs if x['key'][1].endswith('m0')]):.0f} / m18 {med([x['rec']['t'] for x in rs if x['key'][1].endswith('m18')]):.0f}） 胜 {wins}/{len(rs)} ≤150s {in150}  承伤%/分 {med(tpm):.0f}  被打中/分 {med(hits):.1f}")
    rows=sorted(M.items(),key=lambda kv:-kv[1][0])
    for k,(d,h,c) in rows[:12]:
        hr=f"{h}/{c}={h/c:.0%}" if c else f"{h}/-"
        print(f"   {k:28s} 承伤占比 {100*d/tot:5.1f}%  每次命中 {d/h if h else 0:5.1f}%HP  命中/出手 {hr}")
    zero=[k for k,(d,h,c) in M.items() if c>=10 and h/c<0.05]
    if zero: print('   几乎打不中（出手≥10、命中<5%）:', zero)
