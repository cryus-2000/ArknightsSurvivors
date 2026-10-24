# -*- coding: utf-8 -*-
"""10-24 干员动作对时审计（docs/140）：每名干员单人无头跑一局（--balance --bot=expert），game/tests/anim_sync_probe.gd 逐帧记
起手 / 出手 / 伤害 / 弹体 / 跑步，这里汇总成全员一张表，标出偏差超过 1 帧的项。
    python tools/probes/anim_sync_probe.py [--ops a,b] [--t 60] [--seed 1] [--jobs 3] [--out build/anim_sync] [--reuse]
原始事件存 <out>/<op>.json，表存 <out>/table.md。只读探针，不改模拟。
"""
import argparse, json, os, sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import godot_runner as gr

ap = argparse.ArgumentParser()
ap.add_argument('--game', default=os.path.join(ROOT, 'game'))
ap.add_argument('--ops', default='')
ap.add_argument('--t', type=float, default=60.0)
ap.add_argument('--seed', type=int, default=1)
ap.add_argument('--jobs', type=int, default=3)
ap.add_argument('--out', default=os.path.join(ROOT, 'build', 'anim_sync'))
ap.add_argument('--reuse', action='store_true', help='不跑，直接用 <out>/<op>.json 出表')
a = ap.parse_args()
game = os.path.abspath(a.game)
ops = [x for x in a.ops.split(',') if x] or sorted(f[:-5] for f in os.listdir(os.path.join(game, 'data', 'characters')) if f.endswith('.json'))
os.makedirs(a.out, exist_ok=True)
if not a.reuse:
    gr.ensure_imported(game)


def one(op):
    p = os.path.join(a.out, op + '.json')
    if a.reuse and os.path.exists(p):
        return op, json.load(open(p, encoding='utf-8')), []
    args = [gr.find_godot(), '--headless', '--audio-driver', 'Dummy', '--path', game, 'res://tests/anim_sync_probe.tscn', '--',
            '--regression', '--balance', '--seed=%d' % a.seed, '--op=' + op, '--bot=expert', '--maxt=%d' % int(a.t + 30), '--probe-t=%g' % a.t]
    o, e, to = gr.run_godot(args, 900)
    line = [l for l in (o or '').splitlines() if l.startswith('ANIMSYNC ')]
    errs = [l for l in (o or '').splitlines() + (e or '').splitlines() if 'SCRIPT ERROR' in l]
    if not line:
        return op, None, errs[:3] or ['timeout=%s' % to, (e or '')[-400:]]
    d = json.loads(line[-1][len('ANIMSYNC '):])
    json.dump(d, open(p, 'w', encoding='utf-8'), ensure_ascii=False)
    return op, d, errs[:3]


def analyse(op, d):
    ev = d['ev']
    starts = [x for x in ev if x['e'] == 'START']
    rels = [x for x in ev if x['e'] == 'REL']
    row = {'op': op}
    # 出手帧偏差：画面帧号 − 声明出手帧（同一帧条时才算）；画面是别的帧条（序列 / 让位）单独计
    by = defaultdict(lambda: {'n': 0, 'dev': Counter(), 'other': Counter(), 'nofire': 0})
    for r in rels:
        b = by[r['kind'] + ':' + r['anim']]
        b['n'] += 1
        if r['fire'] < 0:
            b['nofire'] += 1
            continue
        if r['shown'] != r['anim']:
            b['other'][r['shown']] += 1
            continue
        b['dev'][r['f'] - r['fire']] += 1
    row['rel'] = {k: {'n': v['n'], 'dev': dict(v['dev']), 'other': dict(v['other']), 'nofire': v['nofire']} for k, v in by.items()}
    # 窗口 vs 间隔（普攻）：dur > cd 时动画卡住攻速（acting 期间不起手）
    win = defaultdict(list)
    for s in starts:
        if s['kind'] == 'attack':
            win[s['anim']].append(s)
    row['win'] = {}
    for k, v in win.items():
        cds = sorted(x['cd'] for x in v if x['cd'] > 0)
        row['win'][k] = {'n': len(v), 'dur': sorted(set(round(x['dur'], 4) for x in v))[:4], 'fire_at': sorted(set(round(x['fire_at'], 4) for x in v))[:4],
                         'cd_med': cds[len(cds) // 2] if cds else -1, 'phased': v[0]['phased'], 'frames': v[0]['frames'], 'fps': v[0]['fps'], 'fd': v[0]['fd'], 'fire': v[0]['fire']}
    # 出手 → 首笔伤害 / 弹体（帧）
    dmg = [x for x in ev if x['e'] == 'DMG']
    shots = [x for x in ev if x['e'] == 'SHOT']
    lag = Counter(); lag_shot = Counter()
    for r in rels:
        if r['kind'] != 'attack':
            continue
        nd = [x for x in dmg if r['t'] - 1e-6 <= x['t'] <= r['t'] + 0.5]
        ns = [x for x in shots if r['t'] - 1e-6 <= x['t'] <= r['t'] + 0.05]
        if ns:
            lag_shot[round((ns[0]['t'] - r['t']) * 60)] += 1
        if nd:
            lag[round((nd[0]['t'] - r['t']) * 60)] += 1
    row['lag'] = dict(lag); row['lag_shot'] = dict(lag_shot); row['srcs'] = dict(Counter(x['src'] for x in dmg).most_common(6))
    row['run'] = d['run']; row['move_atk'] = d['move_atk']; row['cut'] = d['cut']; row['aspd'] = d.get('aspd', 1); row['seq_mv'] = d.get('seq_mv', {})
    return row


rows = []
with ThreadPoolExecutor(max_workers=a.jobs) as ex:
    for op, d, errs in ex.map(one, ops):
        if d is None:
            print('FAILED', op, errs)
            continue
        for e in errs:
            print('  ', op, e[:200])
        rows.append(analyse(op, d))

L = ['# 干员动作对时审计表（tools/probes/anim_sync_probe.py，seed %d，%g 秒，单干员 --bot=expert）' % (a.seed, a.t), '',
     '出手帧偏差 = 出手（fire_t 到点）那一帧画面帧号 − 帧条声明 fire；`other` = 出手时画面不是该帧条（序列 / 让位换掉）。dur > cd 时动画卡攻速。', '',
     '| 干员 | 出手帧偏差（动作:帧条 n次 {偏差:次数}） | 普攻窗口 dur / 出手 / cd / 帧条 | 出手→首笔伤害（帧） | 跑步 mv / 有效fps / 夹限低/高/总 | 移动攻击 换条/帧 | 收势让位帧 | 技能段移动中滑行帧 |',
     '|---|---|---|---|---|---|---|---|']
flags = []
for r in rows:
    rel = []
    for k, v in sorted(r['rel'].items()):
        s = '%s n%d %s' % (k, v['n'], v['dev'])
        if v['other']: s += ' other%s' % v['other']
        if v['nofire']: s += ' 无fire%d' % v['nofire']
        rel.append(s)
        bad = sum(c for dv, c in v['dev'].items() if abs(int(dv)) > 1)
        if bad: flags.append('%s %s 出手帧偏差 >1 帧 %d/%d 次 %s' % (r['op'], k, bad, v['n'], v['dev']))
    win = []
    for k, v in r['win'].items():
        win.append('%s dur%s fire%s cd%.3f %df%s' % (k, v['dur'], v['fire_at'], v['cd_med'], v['frames'], ' phased' if v['phased'] else (' fd' if v['fd'] else ' %gfps' % v['fps'])))
        if v['cd_med'] > 0 and min(v['dur']) > v['cd_med'] + 1e-3:
            flags.append('%s %s 窗口 %.3f > 间隔 %.3f（动画卡攻速）' % (r['op'], k, min(v['dur']), v['cd_med']))
    ru = r['run']
    runs = 'mv%.0f fps%.1f/%.0f %d/%d/%d 重置%d' % (ru['mv'], ru['fps_eff'], ru['fps'], ru['lo'], ru['hi'], ru['ticks'], ru.get('resets', 0))
    if ru['ticks'] > 120 and abs(ru['fps_eff'] - ru['fps'] * min(2.0, max(0.6, ru['mv'] / 150.0))) > 1.5:
        flags.append('%s 跑步有效帧率 %.1f 与移速应有的 %.1f 不符' % (r['op'], ru['fps_eff'], ru['fps'] * min(2.0, max(0.6, ru['mv'] / 150.0))))
    for k, v in r['seq_mv'].items():
        if v >= 30:
            flags.append('%s 技能段 %s 移动中播放 %d 帧（腿不动，原地滑行）' % (r['op'], k, v))
    L.append('| %s | %s | %s | %s | %s | %d/%d | %d | %s |' % (r['op'], '<br>'.join(rel), '<br>'.join(win), r['lag'], runs, r['move_atk']['swap'], r['move_atk']['ticks'], r['cut'], r['seq_mv'] or ''))
L += ['', '## 标记（偏差 > 1 帧 / 动画卡攻速）', ''] + ['- ' + f for f in flags]
open(os.path.join(a.out, 'table.md'), 'w', encoding='utf-8').write('\n'.join(L) + '\n')
for r in rows:
    print(r['op'], 'rel', r['rel'], 'lag', r['lag'], 'srcs', r['srcs'])
print('\n'.join(['- ' + f for f in flags]))
print(os.path.join(a.out, 'table.md'))
