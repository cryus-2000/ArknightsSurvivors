import json,glob,math,statistics as st,collections
G=collections.defaultdict(dict) # (grp,tier)->{(op,seed):rec}
errs=[];first=None
for f in sorted(glob.glob('raw/*.json')):
    for r in json.load(open(f))['records']:
        tag=f.split('/')[-1]; grp='A_base' if tag.startswith('A') else 'B_ce'; tier='m18' if '_m18_' in tag else 'm0'
        if r.get('script_errors'):
            errs.append((grp,tier,r['squad'][0],r['seed']))
            first=first or r['first_error']
        if 'data' not in r: continue
        d=r['data']
        G[(grp,tier)][(r['squad'][0],r['seed'])]=(1 if d['win'] else 0,d['t'],d['bot'].get('taken_pm'))
def wil(k,n):
    if n==0: return (0,0)
    z=1.96;p=k/n;den=1+z*z/n;c=(p+z*z/2/n)/den;h=z*math.sqrt(p*(1-p)/n+z*z/4/n/n)/den
    return c-h,c+h
OPS=['eyjafjalla','suzuran','kaltsit','mizuki','saria','skadi','wisadel']
NAME={'eyjafjalla':'艾雅法拉','suzuran':'铃兰','kaltsit':'凯尔希','mizuki':'水月','saria':'塞雷娅','skadi':'斯卡蒂','wisadel':'维什戴尔'}
def cell(grp,tier,op):
    rs=[v for (o,s),v in G[(grp,tier)].items() if o==op]
    n=len(rs);k=sum(x[0] for x in rs);lo,hi=wil(k,n)
    tp=[x[2] for x in rs if x[2] is not None]
    return n,k,lo,hi,(st.mean(x[1] for x in rs) if rs else 0),(st.median(tp) if tp else 0)
L=["# 艾雅法拉 / 铃兰开局底子对照 C+E","","A_base = 0eb5ce16a；B_ce = 44ced437d（两人减伤 1.0→1.5、铃兰生命 105→115、艾雅攻击 25→30）。高手机器人，--tier=0 --tide=0；seed 1–16，每开局每格 16 局。","","## 表一 胜率 / 平均存活 / 每分钟承伤中位","","| 组 | 档 | 开局 | 局数 | 胜率 | Wilson 95% | 平均存活(s) | 每分钟承伤中位 |","|---|---|---|---|---|---|---|---|"]
for tier in ['m0','m18']:
  for grp in ['A_base','B_ce']:
    for op in OPS:
        n,k,lo,hi,t,tp=cell(grp,tier,op)
        L.append(f"| {grp} | {tier} | {NAME[op]} | {n} | {k/n*100 if n else 0:.1f}% ({k}) | {lo*100:.1f}–{hi*100:.1f}% | {t:.0f} | {tp:.0f} |")
L+=["","## 表二 与其余 5 名开局均值的差（点）及同 seed 配对 McNemar","","对照 A_base 与 B_ce 同 (开局, seed) 配对；b = A 胜 B 负，c = A 负 B 胜，双侧精确二项检验。","","| 组 | 档 | 开局 | 胜率 | 其余5名均值 | 差(点) |","|---|---|---|---|---|---|"]
def rest(grp,tier,op):
    v=[cell(grp,tier,o)[1]/max(cell(grp,tier,o)[0],1) for o in OPS if o not in('eyjafjalla','suzuran')]
    return st.mean(v)*100
ok={}
for tier in ['m0','m18']:
  for grp in ['A_base','B_ce']:
    for op in ['eyjafjalla','suzuran']:
        n,k,*_=cell(grp,tier,op); w=k/n*100; r=rest(grp,tier,op)
        ok[(grp,tier,op)]=w-r
        L.append(f"| {grp} | {tier} | {NAME[op]} | {w:.1f}% | {r:.1f}% | {w-r:+.1f} |")
L+=["","其余 5 名 = 凯尔希、水月、塞雷娅、斯卡蒂、维什戴尔。","","### 同 seed 配对 McNemar（B_ce vs A_base）","","| 档 | 开局 | A 胜 B 负 | A 负 B 胜 | 双侧 p |","|---|---|---|---|---|"]
def binom_p(b,c):
    n=b+c
    if n==0: return 1.0
    m=min(b,c); p=sum(math.comb(n,i) for i in range(m+1))/2**n
    return min(1.0,2*p)
for tier in ['m0','m18']:
    for op in OPS:
        b=c=0
        for (o,s),a in G[('A_base',tier)].items():
            if o!=op: continue
            x=G[('B_ce',tier)].get((o,s))
            if x is None: continue
            if a[0] and not x[0]: b+=1
            if x[0] and not a[0]: c+=1
        L.append(f"| {tier} | {NAME[op]} | {b} | {c} | {binom_p(b,c):.3f} |")
within=all(ok[('B_ce',t,o)]>=-10 for t in ['m0','m18'] for o in ['艾雅法拉' and 'eyjafjalla','suzuran'])
det="；".join(f"{t}：艾雅 {ok[('B_ce',t,'eyjafjalla')]:+.1f}、铃兰 {ok[('B_ce',t,'suzuran')]:+.1f}" for t in ['m0','m18'])
L+=["",f"**结论**：B_ce 下两人{'都在' if within else '并非都在'}其余 5 名均值 −10 点以内（{det}）。",""]
L.append(f"script_errors：{len(errs)} 局；第一条：{first or '无'}"+(f"（{errs[0]}）" if errs else ""))
open('summary.md','w').write("\n".join(L)+"\n")
print("\n".join(L))
