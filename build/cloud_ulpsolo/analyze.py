import json,glob,math,statistics as st,collections
R='build/cloud_ulpsolo/raw/'
def load(pat):
    out=[]
    for f in sorted(glob.glob(R+pat+'_1028_*.json')):
        out+=json.load(open(f))['records']
    return out
def wilson(w,n):
    if n==0: return (0,0)
    z=1.96;p=w/n;d=1+z*z/n;c=p+z*z/(2*n);m=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))
    return ((c-m)/d,(c+m)/d)
def fmt(w,n):
    lo,hi=wilson(w,n); return f"{w}/{n}={100*w/n:.0f}% [{100*lo:.0f},{100*hi:.0f}]"
def mmss(s): return f"{int(s)//60}:{int(s)%60:02d}"
def mcnemar(a,b):  # dict seed->win
    ks=sorted(set(a)&set(b)); b01=sum(1 for k in ks if a[k] and not b[k]); b10=sum(1 for k in ks if b[k] and not a[k])
    n=b01+b10
    if n==0: p=1.0
    else:
        k=min(b01,b10); p=min(1.0,2*sum(math.comb(n,i) for i in range(k+1))/2**n)
    return len(ks),sum(a[k] for k in ks),sum(b[k] for k in ks),b01,b10,p
names={}
def first(r): return r['squad'][0]
out=[]
solo={}
for tier,pat in (('m18','solo_m18_s*'),('m0','solo_m0_s*')):
    solo[tier]=load(pat)
ops=sorted({first(r) for r in solo['m18']})
out.append("## 表一 改版单人（expert，tier0 tide0）\n")
out.append("| 档 | 开局 | 局数 | 胜率（Wilson95%） | 均存活 | 胜局用时中位 | 主控承伤/分钟 | 回复量/分钟（总 / 自身回复） |\n|---|---|---|---|---|---|---|---|")
rates={}
for tier in ('m18','m0'):
    for op in ops:
        rs=[r for r in solo[tier] if first(r)==op]
        n=len(rs); w=sum(1 for r in rs if r['data'].get('win'))
        wt=[r['data']['t'] for r in rs if r['data'].get('win')]
        tk=[r['data']['bot']['taken_pm'] for r in rs if isinstance(r['data'].get('bot'),dict) and 'taken_pm' in r['data']['bot']]
        hp=[sum(r['data'].get('heal',{}).values())/r['data']['t']*60 for r in rs if r['data'].get('t')]
        sh=[r['data'].get('heal',{}).get('自身回复',0)/r['data']['t']*60 for r in rs if r['data'].get('t')]
        rates[(tier,op)]=(w,n)
        out.append(f"| {tier} | {op} | {n} | {fmt(w,n)} | {mmss(st.mean(r['data']['t'] for r in rs))} | {mmss(st.median(wt)) if wt else '-'} | {st.mean(tk):.0f} | {st.mean(hp):.1f} / {st.mean(sh):.1f} |")
out.append("\n注：承伤/分钟=bot.taken_pm（全局受伤，单人局即主控）；回复量=heal 各来源合计（含拾取、补给、自身回复等）。\n")
out.append("## 表二 编队（X + 维萨德尔 + 塞雷娅，m18，8 seed）\n")
sq={}
out.append("| 编队 | 局数 | 胜率 | 均存活 | 胜局用时中位 |\n|---|---|---|---|---|")
for q in ('ulpianus','skadi','irene'):
    rs=load(f'sq_{q}_m18_s*'); sq[q]={r['seed']:bool(r['data'].get('win')) for r in rs}
    w=sum(sq[q].values());n=len(rs); wt=[r['data']['t'] for r in rs if r['data'].get('win')]
    out.append(f"| {q} | {n} | {fmt(w,n)} | {mmss(st.mean(r['data']['t'] for r in rs))} | {mmss(st.median(wt)) if wt else '-'} |")
out.append("\n配对（同 seed，McNemar 精确双侧）：\n\n| 对比 | 配对数 | A 胜 | B 胜 | A胜B负 | A负B胜 | p |\n|---|---|---|---|---|---|---|")
for o in ('skadi','irene'):
    n,a,b,x,y,p=mcnemar(sq['ulpianus'],sq[o]); out.append(f"| ulpianus vs {o} | {n} | {a} | {b} | {x} | {y} | {p:.3f} |")
out.append("\n## 表三 乌尔比安 改前 vs 改后（单人 m18，seed 1–16 配对）\n")
base=load('base_ulp_m18'); bm={r['seed']:bool(r['data'].get('win')) for r in base}
new={r['seed']:bool(r['data'].get('win')) for r in solo['m18'] if first(r)=='ulpianus'}
n,a,b,x,y,p=mcnemar(new,bm)
bw=[r['data']['t'] for r in base]; nw=[r['data']['t'] for r in solo['m18'] if first(r)=='ulpianus']
out.append("| 版本 | 局数 | 胜率 | 均存活 |\n|---|---|---|---|")
out.append(f"| 改前（regen 2.0，base 0.8） | {len(base)} | {fmt(sum(bm.values()),len(bm))} | {mmss(st.mean(bw))} |")
out.append(f"| 改后（regen 2.5，base 1） | {len(new)} | {fmt(sum(new.values()),len(new))} | {mmss(st.mean(nw))} |")
out.append(f"\n配对：{n} 对；改后胜改前负 {x}，改后负改前胜 {y}，McNemar p={p:.3f}。\n")
o=rates[('m18','ulpianus')]; others=[rates[('m18',op)] for op in ops if op!='ulpianus']
ow=sum(w for w,_ in others);on=sum(n for _,n in others)
ul=100*o[0]/o[1]; avg=100*ow/on
out.append(f"**结论**：乌尔比安单人 m18 胜率 {ul:.0f}%，其余 {len(others)} 名开局合计均值 {avg:.0f}%（{ow}/{on}），高出 {ul-avg:+.0f} 点，{'>' if ul-avg>10 else '≤'} 10 点。")
open('build/cloud_ulpsolo/_tables.md','w').write("\n".join(out))
print("\n".join(out))
