# -*- coding: utf-8 -*-
"""读 btrace 局内对照（tools/probes/btrace_patch.py + balance_run --keep BTRACE）：接潮组 7:00 之后每秒的两体状态，改前 / 改后对比。

用法：python tools/probes/btrace_report.py build/cloud/immortal28 [--types bishop,immortal]
目录下 base/ 与 new/ 各放一份 balance_run 的 json。每局按「该组第一次出现 → 两具都 D（打死）/ 队长生命 0 / 记录结束」切出战斗段，统计：
  结局（打死 / 队长阵亡 / 拖到终局）、战斗秒数、复苏次数、队长到最近一具活 Boss 的距离、站定（wind > 0）秒占比、
  主教近战 ai（靠拢或慌乱）秒占比、两体假死秒、各类预警出现秒数（tide_link = 统一、erupt = 迸发、stab = 连斩 …）、队长低血（<35%）秒。
只读结果，不跑游戏。
"""
import argparse, glob, json, os, statistics


def parse(line):
    # BTRACE t=<t> hp=<hp>/<max> boss=<type:hp/max:st:rev:dist:wind:ai:flags>;... warns=<act:n>,...
    out = {}
    for part in line.split(' ')[1:]:
        if '=' in part:
            k, v = part.split('=', 1)
            out[k] = v
    t = float(out['t'])
    hp, mhp = (float(x) for x in out['hp'].split('/'))
    bosses = {}
    for b in filter(None, out.get('boss', '').split(';')):
        f = b.split(':')
        if len(f) < 8:
            continue
        bh, bm = (float(x) for x in f[1].split('/'))
        bosses[f[0]] = {'hp': bh, 'max': bm, 'st': f[2], 'rev': int(f[3]), 'dist': float(f[4]), 'wind': float(f[5]), 'ai': f[6], 'fl': f[7] if len(f) > 7 else ''}
    warns = {}
    for w in filter(None, out.get('warns', '').split(',')):
        k, n = w.rsplit(':', 1)
        warns[k] = int(n)
    return t, hp, mhp, bosses, warns


def one_run(lines, types):
    rows = [parse(l) for l in lines if l.startswith('BTRACE ')]
    rows = [r for r in rows if all(tp in r[3] for tp in types)]
    if not rows:
        return None
    t0 = rows[0][0]
    res = {'outcome': 'timeout', 'secs': 0, 'rev': 0, 'dist': [], 'wind': 0, 'melee_bishop': 0, 'coma': 0, 'low': 0, 'warns': {}}
    for t, hp, mhp, bs, ws in rows:
        res['rev'] = max(res['rev'], sum(bs[tp]['rev'] for tp in types))
        if all(bs[tp]['st'] == 'D' for tp in types):
            res['outcome'] = 'killed'
            break
        if hp <= 0.0:
            res['outcome'] = 'died'
            break
        res['secs'] = t - t0
        alive = [bs[tp] for tp in types if bs[tp]['st'] == 'A']
        if alive:
            res['dist'].append(min(b['dist'] for b in alive))
        res['wind'] += sum(1 for b in alive if b['wind'] > 0.0)
        bi = bs.get('bishop')
        if bi and bi['st'] == 'A' and bi['ai'] == 'melee':
            res['melee_bishop'] += 1
        res['coma'] += sum(1 for tp in types if bs[tp]['st'] == 'C')
        if mhp > 0 and hp / mhp < 0.35:
            res['low'] += 1
        for k in ws:
            res['warns'][k] = res['warns'].get(k, 0) + 1
    if res['outcome'] == 'timeout' and rows[-1][0] < 590.0:
        res['outcome'] = 'died'   # 记录在终局前就断了：队长阵亡（hp 行没来得及打 0）
    return res


def med(a):
    return round(statistics.median(a), 1) if a else None


def side(path, types):
    runs = []
    for f in glob.glob(os.path.join(path, '**', '*.json'), recursive=True):
        d = json.load(open(f, encoding='utf-8'))
        for r in d.get('records', []):
            x = one_run(r.get('lines', []), types)
            if x:
                runs.append(x)
    return runs


def summary(name, runs):
    oc = {}
    for r in runs:
        oc[r['outcome']] = oc.get(r['outcome'], 0) + 1
    print('## %s：%d 局 有该组 / 结局 %s' % (name, len(runs), oc))
    keys = sorted({k for r in runs for k in r['warns']})
    for grp in ['killed', 'died', 'timeout', None]:
        rs = [r for r in runs if grp is None or r['outcome'] == grp]
        if not rs:
            continue
        secs = [r['secs'] for r in rs]
        per = lambda k: med([r[k] / max(1.0, r['secs']) for r in rs])
        print('  [%s] n=%d 战斗秒中位 %s | 复苏中位 %s | 距最近活 Boss 中位 %s | 站定秒占比 %s | 主教近战秒占比 %s | 假死秒占比 %s | 低血秒占比 %s' % (
            grp or '全部', len(rs), med(secs), med([r['rev'] for r in rs]), med([med(r['dist']) for r in rs if r['dist']]),
            per('wind'), per('melee_bishop'), per('coma'), per('low')))
        print('      预警出现秒数中位：' + '，'.join('%s %s' % (k, med([r['warns'].get(k, 0) for r in rs])) for k in keys))


ap = argparse.ArgumentParser()
ap.add_argument('dir')
ap.add_argument('--types', default='bishop,immortal')
a = ap.parse_args()
types = a.types.split(',')
for s in ['base', 'new']:
    summary(s, side(os.path.join(a.dir, s), types))
