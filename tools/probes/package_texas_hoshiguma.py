"""德克萨斯 / 星熊 64 画布 @2x 接入打包（10-20，docs/108 §5 / §9）。

来源（只读）：
- 原作动作条：codex-art 工作树 art/incoming/cb_18_prts_native_actions_1017/<id>/（8 帧采样，192 画布，原点 (95.5|96.5, 151.x)）
  按整数平移对齐到游戏原点：192 画布直接当 96 画布（@2x 原点 (96,152)），装得下 128 的裁 (32,32) 当 64 画布（@2x 原点 (64,120)）；
  无盾版按 manifest 逐帧部件重组、去掉 C_Weapon_* 盾牌部件（与原条逐像素相同，只少盾）。
- 新做动作：tools/spine_run_trial 在原生骨架上出的帧（cfg/<id>_<动作>.json，见 docs/plans/2026-10-20-spine-run-trial.md），
  先出帧（NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules）：
    node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/<cfg>.json --out build/sr/<id>/<动作>/frames
  cfg → 动作目录：texas.json → run、texas_sprint → sprint、texas_dash → dash、texas_back → back、texas_s3start → s3start、
  texas_s3dash → s3dash；hoshiguma.json → run、hoshiguma_run_noshield → run_noshield、hoshiguma_s1 / _s1_ns → s1 / s1_ns、
  hoshiguma_throw / _throwns → throw / throwns、hoshiguma_catch / _catch_ns → catch / catch_ns。
出手时刻不变：每条的 frame_durations 求和 = 旧条 frames/fps，fire_time = 旧 (fire+0.5)/fps。
用法：python tools/probes/package_texas_hoshiguma.py [hoshiguma] [texas]
"""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CB = Path('E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/cb_18_prts_native_actions_1017')
RT = ROOT / 'build/sr'
OUT = ROOT / 'art/incoming'
SHIELD = {'C_Weapon_A2', 'C_Weapon_B2', 'C_Weapon_C2', 'C_Weapon_D2'}
provenance = {}


def cb_frames(op, act, idx=range(8), drop=None, only=None):
    """原作条第 idx 帧（192 画布）；drop / only = 去掉 / 只留这些槽的部件（按 manifest 重组）"""
    m = json.loads((CB / op / 'manifest.json').read_text(encoding='utf-8'))
    a = next(x for x in m['actions'] if x['action'] == act)
    assert a['canvas'] == [192, 192], (op, act)
    src = CB / op / a['file'].replace(chr(92), '/')
    provenance[src.relative_to(CB).as_posix()] = hashlib.sha256(src.read_bytes()).hexdigest()
    st = Image.open(src).convert('RGBA')
    out = []
    for i in idx:
        if drop is None and only is None:
            out.append(st.crop((i * 192, 0, i * 192 + 192, 192)))
            continue
        c = Image.new('RGBA', (192, 192))
        for p in a['records'][i]['parts']:
            if (drop and p['slot'] in drop) or (only and p['slot'] not in only):
                continue
            c.alpha_composite(Image.open(CB / op / p['file'].replace(chr(92), '/')).convert('RGBA'))
        out.append(c)
    return out


def rt_frames(op, act, idx=None):
    d = RT / op / act / 'frames'
    fs = sorted(d.glob('f[0-9][0-9].png'))
    # cfg 的 map：占位帧换成另一次出图的帧（"S<n>" = <id>_sprint 第 n 帧，冲刺跑步态由跑步模式出）
    cfg = ROOT / f'tools/spine_run_trial/cfg/{op}_{act}.json'
    if cfg.exists():
        mp = json.loads(cfg.read_text(encoding='utf-8')).get('map') or []
        fs = [RT / op / 'sprint' / 'frames' / f'f{int(m[1:]):02d}.png' if m else f for f, m in zip(fs, mp + [None] * len(fs))]
    ims = []
    for n, p in enumerate(fs):
        if idx is not None and n not in idx:
            continue
        provenance[f'build/sr/{op}/{act}/{p.name}'] = hashlib.sha256(p.read_bytes()).hexdigest()
        im = Image.open(p).convert('RGBA')
        if im.size[0] == 128:
            c = Image.new('RGBA', (192, 192)); c.paste(im, (32, 32)); im = c
        ims.append(im)
    if idx is not None:
        ims = [ims[sorted(idx).index(i)] for i in idx]
    return ims


def shift(im, dx):
    c = Image.new('RGBA', im.size); c.paste(im, (dx, 0)); return c


def fits128(ims):
    for im in ims:
        b = im.getchannel('A').getbbox()
        if b and (b[0] < 32 or b[1] < 32 or b[2] > 160 or b[3] > 160):
            return False
    return True


def shield_points(full, bare, size):
    """逐帧盾心（盾牌外接框中心，1x 帧内像素）：有盾帧与无盾帧的差异像素；没有盾 → None"""
    pts = []
    off = 32 if size == 128 else 0
    for a, b in zip(full, bare):
        A = np.asarray(a).astype(int); B = np.asarray(b).astype(int)
        diff = (A[..., 3] > 0) & ((B[..., 3] == 0) | (np.abs(A[..., :3] - B[..., :3]).sum(-1) > 0))
        ys, xs = np.nonzero(diff)
        if len(xs) < 40:
            pts.append(None); continue
        pts.append([round(((xs.min() + xs.max() + 1) / 2 - off) / 2, 1), round(((ys.min() + ys.max() + 1) / 2 - off) / 2, 1)])
    return pts


def save(op, slot, ims, size):
    strip = Image.new('RGBA', (size * len(ims), size))
    for i, im in enumerate(ims):
        assert set(np.unique(np.asarray(im)[:, :, 3])) <= {0, 255}, (op, slot, i)
        strip.paste(im.crop((32, 32, 160, 160)) if size == 128 else im, (size * i, 0))
    strip.save(OUT / f'op_{op}_{slot}@2x.png')


def spec(op, slot, n, size, durs, fire_time=None, extra=None):
    s = {'tex': f'op_{op}_{slot}', 'frames': n, 'fps': round(n / sum(durs), 6), 'foot': [32, 60] if size == 128 else [48, 76],
         'frame_durations': durs}
    if fire_time is not None:
        acc = 0.0
        for i, d in enumerate(durs):
            if fire_time < acc + d - 1e-9:
                break
            acc += d
        s['fire'] = i
        s['fire_time'] = fire_time
    if extra:
        s.update(extra)
    return s


def even(total, n):
    return [total / n] * n


def windup(fire_time, k, total, n):
    """前 k 帧均分到出手，其余均分到收势"""
    return [fire_time / k] * k + [(total - fire_time) / (n - k)] * (n - k)


def hoshiguma():
    op = 'hoshiguma'
    path = ROOT / f'game/data/characters/{op}.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    sp = data['sprites']
    # 旧 48 画布条的时序（main b1ee9cef；写死，脚本可重跑）
    old = {'attack': {'frames': 5, 'fps': 12, 'fire': 3}, 'skill': {'frames': 7, 'fps': 12, 'fire': 2}, 'throw': {'frames': 6, 'fps': 14, 'fire': 2}}
    T = lambda k: old[k]['frames'] / old[k]['fps']            # 旧条时长
    F = lambda k: (old[k]['fire'] + 0.5) / old[k]['fps']      # 旧出手时刻
    S = {}   # 槽 → (帧, 无盾帧, 时长表, 出手, 槽外字段)
    S['idle'] = (cb_frames(op, 'Idle', range(7)), cb_frames(op, 'Idle', range(7), drop=SHIELD), even(3.0, 7), None)
    S['run'] = (rt_frames(op, 'run'), rt_frames(op, 'run_noshield'), even(0.6, 8), None)
    at = F('attack')
    S['attack'] = (cb_frames(op, 'Attack'), cb_frames(op, 'Attack', drop=SHIELD), windup(at, 2, T('attack'), 8), at)   # 原作出手 = 第 2 帧（t 0.333）
    sk, st = F('skill'), T('skill')
    S['skill'] = (cb_frames(op, 'Attack'), cb_frames(op, 'Attack', drop=SHIELD), windup(sk, 2, st, 8), sk)       # S2 荆棘：盾斧斩落
    s1, s1n = rt_frames(op, 's1'), rt_frames(op, 's1_ns')
    S['s1'] = (s1[:2], s1n[:2], [sk, st - sk], sk)                                                                   # S1 起手：举盾
    S['s1_guard'] = (s1[1:2], s1n[1:2], [0.5], None)                                                                 # 格挡窗口内定格
    S['s1_counter'] = (s1[5:], s1n[5:], [0.12, 0.12, 0.18], None)   # 格挡 / 窗口到点：反手重斩（伤害在格挡瞬间，所以从击中帧起播，不放前摇）
    S['s3_start'] = (cb_frames(op, 'Skill_Begin'), cb_frames(op, 'Skill_Begin', drop=SHIELD), windup(sk, 3, st, 8), sk)
    S['s3_loop'] = (cb_frames(op, 'Skill', range(7)), cb_frames(op, 'Skill', range(7), drop=SHIELD), even(1 / 3, 7), None)
    S['s3_end'] = (cb_frames(op, 'Skill_End'), cb_frames(op, 'Skill_End', drop=SHIELD), even(0.4, 8), None)
    tf, tt = F('throw'), T('throw')
    S['throw'] = (rt_frames(op, 'throw'), rt_frames(op, 'throwns'), [0.06, 0.06, tf - 0.12] + even(tt - tf, 5), tf)
    S['catch'] = (rt_frames(op, 'catch'), rt_frames(op, 'catch_ns'), [0.05, 0.06, 0.06, 0.05, 0.05, 0.05, 0.05, 0.06], None)
    S['death'] = (cb_frames(op, 'Die'), None, [0.141] * 7 + [0.16], None)
    ns_of = {'idle': 'idle_noshield', 'run': 'run_noshield', 'attack': 'attack_noshield', 'throw': 'throw_noshield'}
    for slot, (ims, bare, durs, fire) in S.items():
        size = 128 if fits128(ims) and (bare is None or fits128(bare)) else 192
        save(op, slot, ims, size)
        if slot in ns_of:
            save(op, ns_of[slot], bare, size)
        extra = {'shield': shield_points(ims, bare, size)} if bare is not None else None
        sp[slot] = spec(op, slot, len(ims), size, durs, fire, extra)
        print(op, slot, len(ims), size, round(sum(durs), 4), fire)
    sp['_doc'] = ('10-20 换 64 画布 @2x（docs/108 §5）：待机 / 普攻 / S3 / 死亡取原作动作条（cb_18），跑步 / S1 / 掷盾 / 接盾在原生骨架上出（tools/spine_run_trial），'
                  '打包脚本 tools/probes/package_texas_hoshiguma.py。shield = 每帧盾心（1x 帧内像素，同 foot 口径，null = 盾已离手），格挡闪光 / 反击架势红光锚在这里（fx 的 on_sprite）')
    sp['throw']['_doc'] = '精英二「般若回旋」掷盾：第 3 帧起盾离手（盾由 proj_hoshiguma_sawshield 表现）；盾在外面时本体换无盾画面（noshield），盾回来播 catch（native_motion exits）'
    ns = sp['noshield']
    ns.pop('keep', None)
    ns['_doc'] = '盾在外面（般若回旋）时本体换无盾帧条（art，与有盾条同帧数 / 同画布，原作条去盾部件重组 / 原生骨架隐藏盾牌出图）；fallback 只在缺图时用'
    sp['skills'] = {'_doc': 'S1 举盾 → 窗口内定格 → 格挡（技能随即结束）或窗口到点都收势播反手重斩；S2 盾斧斩落；S3 原作起手 / 持盾切割循环 / 收势',
                    's1': {'start': 's1', 'loop': 's1_guard', 'end': 's1_counter'},
                    's2': {'anim': 'skill'},
                    's3': {'start': 's3_start', 'loop': 's3_loop', 'end': 's3_end'}}
    sp['size'] = 64
    sp['foot'] = [32, 60]
    data['extra_sprites'] = ['death', 's1', 's1_guard', 's1_counter', 's3_start', 's3_loop', 's3_end', 'throw', 'catch']
    data['native_motion'] = {'_doc': '原生动作覆盖层（docs/108 §3.5）：普攻 / S2 / S3 起手按 clips 整条均匀播（击中帧起点 = 伤害时刻）；盾回手（信号 prop 结束）时播接盾',
                             # 出手与画面对齐（协调人 10-21 口径）：原作条按 clip = fire × 帧数 / k 均匀整条播，击中帧起点 = 伤害时刻，收势放慢可越过逻辑窗口
                             'clips': {'catch': round(sum(S['catch'][2]), 6), 'attack': at * 8 / 2, 'skill': sk * 8 / 2, 's3_start': sk * 8 / 3},
                             'exits': [{'on': 'prop', 'slot': 'catch', 'from': 0, 'tail': round(sum(S['catch'][2]), 6)}]}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    for k in ['idle', 'run', 'attack', 'skill', 'throw']:
        (OUT / f'op_{op}_{k}.png').unlink(missing_ok=True)


def texas():
    op = 'texas'
    path = ROOT / f'game/data/characters/{op}.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    sp = data['sprites']
    old = {'attack': {'frames': 5, 'fps': 14, 'fire': 1}, 'skill': {'frames': 7, 'fps': 12, 'fire': 3}}   # 旧条时序（b1ee9cef）
    T = lambda k: old[k]['frames'] / old[k]['fps']
    F = lambda k: (old[k]['fire'] + 0.5) / old[k]['fps']
    at, att, sk, st = F('attack'), T('attack'), F('skill'), T('skill')
    S = {
        'idle': (cb_frames(op, 'Idle', range(7)), even(2.0, 7), None),
        # 跑步：脚本出图时前倾让整身偏右约 6px（1x），整数平移回脚底 x = 32（art_lint 脚底x）
        'run': ([shift(im, -12) for im in rt_frames(op, 'run')], even(0.6, 8), None),
        # 普攻疾行斩：0–1 前摇（到出手），2–7 由冲刺进度驱动（native_motion dash.basic），这里的时长只管动作窗口
        'attack': (rt_frames(op, 'dash'), windup(at, 2, att, 8), at),
        # S1 剑雨（原作 Skill）：举剑 → 插地，出手 = 落剑
        'skill': (cb_frames(op, 'Skill'), [0.06, 0.08, 0.08, sk - 0.22] + even(st - sk, 4), sk),
        'back_native': (rt_frames(op, 'back'), even(0.3, 3) + even(0.44, 5), None),   # 回马剑：0–2 等待段、3–7 反冲（都按信号进度）
        's3_start': (rt_frames(op, 's3start'), windup(sk, 4, st, 8), sk),
        's3_dash': (rt_frames(op, 's3dash'), even(0.44, 8), None),   # S3 每次冲刺：0–3 冲锋、4–7 刹停转向（按信号进度）
        'death': (cb_frames(op, 'Die'), [0.141] * 7 + [0.16], None),
    }
    for slot, (ims, durs, fire) in S.items():
        size = 128 if fits128(ims) else 192
        save(op, slot, ims, size)
        sp[slot] = spec(op, slot, len(ims), size, durs, fire)
        print(op, slot, len(ims), size, round(sum(durs), 4), fire)
    sp['skills'] = {'_doc': 'S1 / S2 原作剑雨；S3 起步（举剑 → 压低蓄势）→ 持续期站立 idle / 移动 run，每次冲刺由 native_motion 换播 s3_dash → 结束落剑雨（skill 后 6 帧）',
                    's1': {'anim': 'skill'}, 's2': {'anim': 'skill'},
                    's3': {'start': 's3_start', 'loop': 'idle', 'run': 'run', 'end': {'anim': 'skill', 'frames': [2, 3, 4, 5, 6, 7]}}}
    sp['size'] = 64
    sp['foot'] = [32, 60]
    data['extra_sprites'] = ['death', 'back_native', 's3_start', 's3_dash']
    data['native_motion'] = {
        '_doc': '原生动作覆盖层（docs/108 §3.5）：信号来自 seg_texas.tx_native_signals；冲刺按进度播（普攻 / 天赋 = attack 2–7、技能 = s3_dash、回马剑 = 等待段 back_native 0–2 + 反冲 3–7）',
        'states': [{'on': 'dash.reverse', 'slot': 'back_native', 'from': 3, 'to': 7, 'rate': 5},
                   {'on': 'wait.reverse', 'slot': 'back_native', 'from': 0, 'to': 2, 'rate': 3},
                   {'on': 'dash.skill', 'slot': 's3_dash', 'from': 0, 'to': 7, 'rate': 8},
                   {'on': 'dash', 'slot': 'attack', 'from': 2, 'to': 7, 'rate': 6}]}
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    for k in ['idle', 'run', 'attack', 'skill']:
        (OUT / f'op_{op}_{k}.png').unlink(missing_ok=True)


if __name__ == '__main__':
    who = sys.argv[1:] or ['hoshiguma', 'texas']
    pv = OUT / 'texas_hoshiguma_native_sources.json'
    if pv.exists():
        provenance.update(json.loads(pv.read_text(encoding='utf-8')))
    if 'hoshiguma' in who:
        hoshiguma()
    if 'texas' in who:
        texas()
    pv.write_text(json.dumps(dict(sorted(provenance.items())), indent=2) + '\n', encoding='utf-8')
