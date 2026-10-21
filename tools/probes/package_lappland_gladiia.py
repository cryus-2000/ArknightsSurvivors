# -*- coding: utf-8 -*-
"""拉普兰德 / 歌蕾蒂娅：把 Codex 199d7b73 的原生密采样条（20 fps，25–107 帧）重采样成 8 帧级（docs/108 §9 口径，与其他 18 人一致，用户 10-22），
写回 art/incoming/op_<id>_<slot>@2x.png 并更新 json 的 frames / fps / frame_durations / fire / fire_time（attack 槽另按 logic 旧窗口分段压缩）。

    python tools/probes/package_lappland_gladiia.py <delivery_manifest.json 的目录>   # 源条从 codex/art 199d7b73 临时导出

取帧：有 OnAttack 的条，出手帧 = 事件所在源帧，目标出手帧序号 k = round(7 × t/dur) 夹到 1–6，出手前 k 帧在源 [0, fi) 均匀取（含 0），
出手后 8−k 帧在源 [fi, n) 均匀取（含 fi）；没有事件的条 8 帧均匀取。每目标帧的时长 = 它到下一目标帧之间源帧时长之和（总长 = 源时长）。
"""
import io, json, os, subprocess, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(ROOT)
D = sys.argv[1]
N = 8
m = {(a['operator'], a['action']): a for a in json.load(io.open(os.path.join(D, 'manifest.json'), encoding='utf-8'))['actions']}

SLOTS = {
    'lappland': {'idle': 'Idle', 'attack': 'Combat', 'skill': 'Skill', 'throw': 'Attack', 'death': 'Die'},
    'gladiia': {'idle': 'Idle', 'attack': 'Attack', 'death': 'Die', 's1_begin': 'Skill_1_Begin', 's2_start': 'Skill_2_Startup', 's2_enter': 'Skill_2_Begin',
                's2_loop': 'Skill_2_Idle', 's2_attack': 'Skill_2_Loop', 's2_end': 'Skill_2_End', 's3_start': 'Skill_3_Startup', 's3_enter': 'Skill_3_Begin',
                's3_loop': 'Skill_3_Chant', 's3_attack': 'Skill_3_Loop', 's3_end': 'Skill_3_End'},
}
LOGIC = {('lappland', 'attack'): [5, 14, 2], ('gladiia', 'attack'): [8, 12, 3]}


def even(lo, hi, k):
    """[lo, hi) 里均匀取 k 个整数，含 lo"""
    if k <= 0:
        return []
    if hi - lo < k:
        return list(range(lo, hi))
    return [lo + round(i * (hi - lo) / k) for i in range(k)]   # 每帧占源区间的 1/k（最后一帧也有完整时长，循环条不会闪一帧）


def pick(a):
    n = a['frames']; fd = a['frame_durations']
    ev = [e for e in a.get('source_events', []) if e['name'] == 'OnAttack']
    if not ev:
        idx = even(0, n, N)
        return idx, -1
    t = ev[0]['t']; acc = 0.0; fi = 0
    for i, x in enumerate(fd):
        if acc - 1e-9 <= t < acc + x - 1e-9:
            fi = i; break
        acc += x
    k = max(1, min(N - 2, round((N - 1) * t / a['duration'])))
    pre = even(0, fi, k)
    while len(pre) < k:   # 源出手前帧不够 k 张
        k -= 1
    post = even(fi, n, N - k)
    idx = pre + post
    assert len(idx) == N and idx[k] == fi, (a['action'], idx, k, fi)
    return idx, k


def durations(a, idx):
    fd = a['frame_durations']; out = []
    for j, s in enumerate(idx):
        e = idx[j + 1] if j + 1 < len(idx) else a['frames']
        out.append(sum(fd[s:e]))
    out[-1] += a['duration'] - sum(out)
    return out


for op, slots in SLOTS.items():
    p = 'game/data/characters/%s.json' % op
    d = json.load(io.open(p, encoding='utf-8'))
    for slot, action in slots.items():
        a = m[(op, action)]
        src = Image.open(os.path.join(D, a['file'])).convert('RGBA')
        fw, fh = a['frame_size']
        idx, k = pick(a)
        strip = Image.new('RGBA', (fw * N, fh), (0, 0, 0, 0))
        for j, s in enumerate(idx):
            strip.paste(src.crop((s * fw, 0, (s + 1) * fw, fh)), (j * fw, 0))
        tex = d['sprites'][slot]['tex']
        strip.save('art/incoming/%s@2x.png' % tex)
        fd = durations(a, idx)
        sp = d['sprites'][slot]
        sp['frames'] = N; sp['frame_durations'] = fd; sp['fps'] = N / a['duration']
        sp.pop('logic', None)
        if k >= 0:
            sp['fire'] = k; sp['fire_time'] = round(sum(fd[:k]) + min(0.001, fd[k] / 2), 6)
        if (op, slot) in LOGIC:   # 普攻：逻辑窗口照旧条，frame_durations 分段压到窗口（出手帧前 → fire_time、出手帧起 → 余下）
            lg = LOGIC[(op, slot)]; win = lg[0] / lg[1]; ft = (lg[2] + 0.5) / lg[1]
            pre = sum(fd[:k]); post = a['duration'] - pre
            fd2 = [x * ft / pre for x in fd[:k]] + [x * (win - ft) / post for x in fd[k:]]
            fd2[-1] += win - sum(fd2)
            sp['frame_durations'] = fd2; sp['fire_time'] = ft; sp['fps'] = N / win; sp['logic'] = lg
            d['native_motion']['clips']['attack'] = round(ft * N / k, 6)
        sp['_doc'] = 'Codex 199d7b73 原作 %s %d 帧 %.3f 秒重采样为 8 帧（源帧 %s%s；tools/probes/package_lappland_gladiia.py）' % (
            action, a['frames'], a['duration'], idx, ('，出手帧 = 源第 %d 帧 → 第 %d 帧' % (idx[k], k)) if k >= 0 else '')
        print(op, slot, 'src', idx, 'fire', k, [round(x, 3) for x in sp['frame_durations']])
    io.open(p, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, ensure_ascii=False, indent=1) + '\n')
print('done')
