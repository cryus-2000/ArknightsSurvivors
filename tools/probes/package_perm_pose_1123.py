"""永续技能换动作补齐（11-23 docs/407 F17 / docs/408）：安洁莉娜 / 浊心斯卡蒂 / 乌尔比安 / 铃兰 四人新帧条 + json。

全部取原作 Spine 对应轨，不自编动作；只换画面（逻辑窗口、出手时刻、帧数照旧槽），同 seed 不变。
  · 安洁莉娜 S2 微粒模式（原作 Skill1_*）：skill_s2 = Skill1_Begin 整条 8 帧（时序抄 skill 槽）；
    attack_s2 = Skill1_Loop 8 帧（OnAttack 帧对到 attack 的出手帧 3，时序抄 attack 槽），perm_pose 永续后普攻换播。
  · 浊心斯卡蒂 S2 同葬无光之愿：idle_s2 = Skill_2_Loop 全长 3.33 秒 14 帧（run_trial，与现有 36 帧待机同一 cfg，重渲 Idle 逐像素一致），
    永续后待机与普攻（原地漂浮）都换播。
  · 乌尔比安 S2 必须维系的界限：idle_s2 = Skill_2_Idle 6 秒 8 帧；@1x 走 make_op_1x 同一 cfg（重渲 Idle 与现有 @1x alpha 一致），
    @2x 同 cfg 两倍 scaleMul。普攻 attack_s2（Codex S2Attack）已在 native_motion.variants，不动。
  · 铃兰 S2 儿时的舞乐（施法一次，原作无常驻轨）：intro / hold 的贴图换成原作 Skill2 f0 / f1（槽规格不动 → 逻辑窗口不变），
    定格后接 tail = Skill2 f2–f7（纯画面 vis_anim）。
@1x：除乌尔比安外按 make_op_1x ② 2×2 合并（与各人其他技能条同口径），之后跑 eye_fix 瞳色保护。

用法：python -X utf8 tools/probes/package_perm_pose_1123.py [--apply]
需要：codex-art 工作树 cb_18_prts_native_actions_1017（只读）、主仓库 build/prts_ref（Spine + node 依赖）、build/op_1x/ulpianus/_cfg。
中间件在主仓库 build/op_backfill/。
"""
import json, os, subprocess, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools')); sys.path.insert(0, str(ROOT / 'tools/op_1x'))
import asset_paths
import make_op_1x as M
import native_extra as N
import eye_fix

CB = Path('E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming/cb_18_prts_native_actions_1017')
BUILD = Path(M.COMMON) / 'build' / 'op_backfill'
CHARS = ROOT / 'game/data/characters'
APPLY = '--apply' in sys.argv


def cb(op, action, i):
    im = Image.open(CB / op / action / f'{action}_{i:02d}.png').convert('RGBA'); assert im.size == (192, 192)
    return im


def cb_durs(op, action):
    m = json.loads((CB / op / 'manifest.json').read_text(encoding='utf-8'))
    return next(a for a in m['actions'] if a['action'] == action)['frame_durations']


def strip(frames, canvas):
    """192 舞台帧（原点 (96,152)）→ 64 画布裁 (32,32,160,160)；96 画布原样"""
    if canvas == 64:
        for f in frames:
            assert np.asarray(f)[:, :, 3].sum() == np.asarray(f.crop((32, 32, 160, 160)))[:, :, 3].sum(), '帧出了 128 裁窗'
        frames = [f.crop((32, 32, 160, 160)) for f in frames]
    w = frames[0].width; out = Image.new('RGBA', (w * len(frames), frames[0].height))
    for i, f in enumerate(frames): out.paste(f, (w * i, 0))
    return out


def spec_like(sp, slot, tex, **over):
    s = {k: v for k, v in sp[slot].items() if k not in ('_doc', 'tex')}
    s = {'tex': tex, **s, **over}
    return s


def run_node(cfg, out_dir):
    env = dict(os.environ, NODE_PATH=str(Path(M.COMMON) / 'build/prts_ref/_node/node_modules'))
    subprocess.run(['node', str(ROOT / 'tools/spine_run_trial/run_trial.js'), str(cfg), '--out', str(out_dir)], check=True, env=env,
                   stdout=subprocess.DEVNULL)


res = {}   # (op, tex) -> (@2x Image, @1x Image or None, frames)
js = {op: json.loads((CHARS / f'{op}.json').read_text(encoding='utf-8')) for op in ('angelina', 'skalter', 'ulpianus', 'suzuran')}

# ---------------- 安洁莉娜 ----------------
op = 'angelina'; sp = js[op]['sprites']
d = cb_durs(op, 'Skill1_Loop'); acc = np.cumsum([0] + d)
ev = 0.23333333   # Skill1_Loop OnAttack
k_fire = int(np.searchsorted(acc, ev + 1e-6) - 1)          # OnAttack 落在的源帧
pre = [0, 1, 2] if k_fire >= 3 else list(range(k_fire)) + [k_fire - 1] * (3 - k_fire)
post = list(range(k_fire, 8)); post = (post + [7] * 5)[:5]
idx = pre + post
assert sp['attack']['frames'] == 8 and sp['attack']['fire'] == 3
res[(op, 'op_angelina_attack_s2')] = (strip([cb(op, 'Skill1_Loop', i) for i in idx], 96), None, 8)
print(op, 'Skill1_Loop OnAttack 源帧', k_fire, '取帧', idx)
res[(op, 'op_angelina_skill_s2')] = (strip([cb(op, 'Skill1_Begin', i) for i in range(8)], 64), None, 8)

# ---------------- 浊心斯卡蒂 ----------------
op = 'skalter'
run_node(ROOT / 'tools/spine_run_trial/cfg/skalter_idle_s2.json', BUILD / 'skalter_idle_s2')
fr = [Image.open(BUILD / 'skalter_idle_s2' / f'f{i:02d}.png').convert('RGBA') for i in range(14)]
assert all(np.asarray(f)[0, :, 3].sum() == 0 and np.asarray(f)[:, 0, 3].sum() == 0 and np.asarray(f)[:, -1, 3].sum() == 0 for f in fr), '贴边可能被裁'
res[(op, 'op_skalter_idle_s2')] = (strip(fr, 128), None, 14)

# ---------------- 乌尔比安 ----------------
op = 'ulpianus'
T = [0.0, 0.75, 1.5, 2.25, 3.0, 3.75, 4.5, 5.25]
d1, anc = N.render(op, 'idle_stand.json', 'idle_s2', 'Skill_2_Idle', T)
x1 = M.compose(d1, 8, 64, 64, [32, 60], anc); assert x1.size == (512, 64), x1.size
c = json.load(open(os.path.join(M.OUT, op, '_cfg', 'idle_stand.json'), encoding='utf-8'))
c['scaleMul'] = c['scaleMul'] * 2; c['canvas'] = c.get('canvas', 128) * 2; c['sample'] = {'anim': 'Skill_2_Idle', 'times': T}
d2 = os.path.join(M.OUT, op, 'idle_s2_x2'); M.run_node(M.write_cfg(op, 'idle_s2_x2', c), d2)
x2 = M.compose(d2, 8, 128, 128, [64, 120], M.anchor_of(c)); assert x2.size == (1024, 128), x2.size
res[(op, 'op_ulpianus_idle_s2')] = (x2, x1, 8)

# ---------------- 铃兰 ----------------
op = 'suzuran'
sk = [cb(op, 'Skill2', i) for i in range(8)]
res[(op, 'op_suzuran_skill_s2_intro')] = (strip([sk[0]] * 8, 64), None, 8)
res[(op, 'op_suzuran_skill_s2_hold')] = (strip([sk[1]], 64), None, 1)
res[(op, 'op_suzuran_skill_s2')] = (strip(sk[2:], 64), None, 6)
sz_durs = cb_durs(op, 'Skill2')[2:]

BUILD.mkdir(parents=True, exist_ok=True)
for (op, tex), (x2, x1, n) in res.items():
    if x1 is None:
        x1 = M.downsample(x2, n)
    x2.save(BUILD / f'{tex}@2x.png'); x1.save(BUILD / f'{tex}@1x.png')
    print(tex, x2.size, x1.size)
    if APPLY:
        x2.save(asset_paths.out_png(tex + '@2x')); x1.save(asset_paths.out_png(tex + '@1x'))

def patch_text(op, slots, extra, after=()):
    """手排版 json（CRLF、行内数组）不整体重写：新槽 / perm_pose 插在 "sprites": { 的下一行，extra_sprites 插在开头，after = [(锚点行正则, 插入行)]"""
    import re
    p = CHARS / f'{op}.json'
    raw = p.read_bytes().decode('utf-8'); nl = '\r\n' if '\r\n' in raw else '\n'
    lines = raw.split(nl)
    i = next(k for k, l in enumerate(lines) if re.match(r'\s*"sprites": \{\s*$', l))
    ind = re.match(r'\s*', lines[i + 1]).group(0)
    ins = [ind + json.dumps(k, ensure_ascii=False) + ': ' + json.dumps(v, ensure_ascii=False) + ',' for k, v in slots.items()]
    lines[i + 1:i + 1] = ins
    for pat, text in after:
        k = next(k for k, l in enumerate(lines) if re.search(pat, l))
        ind = re.match(r'\s*', lines[k + 1]).group(0)
        lines.insert(k + 1, ind + text)
    j = next(k for k, l in enumerate(lines) if '"extra_sprites": [' in l)
    l = lines[j]; c = l.index('[') + 1
    lines[j] = l[:c] + ''.join(json.dumps(x, ensure_ascii=False) + ', ' for x in extra) + l[c:]
    out = nl.join(lines)
    json.loads(out)
    p.write_bytes(out.encode('utf-8'))


if APPLY:
    M.write_index()
    sp = js['angelina']['sprites']
    patch_text('angelina', {
        'attack_s2': spec_like(sp, 'attack', 'op_angelina_attack_s2', _doc='11-23 docs/408：S2 永续后的普攻（原作 Skill1_Loop，OnAttack 源帧对到出手帧 3；时序同 attack，sprites.perm_pose 换贴图）'),
        'skill_s2': spec_like(sp, 'skill', 'op_angelina_skill_s2', _doc='11-23 docs/408：S2 施法 = 原作 Skill1_Begin 整条（时序同 skill 槽，逻辑窗口不变）'),
        'perm_pose': {'s2': {'attack': 'attack_s2'}}}, ['attack_s2', 'skill_s2'],
        [(r'"name": "秘杖·微粒模式"', '"anim": "skill_s2",')])
    sp = js['skalter']['sprites']
    patch_text('skalter', {
        'idle_s2': {'tex': 'op_skalter_idle_s2', 'frames': 14, 'fps': 14 / 3.3333333, 'foot': [32, 60], 'frame_durations': [3.3333333 / 14] * 14,
                    '_doc': '11-23 docs/408：S2 永续后的待机 / 原地漂浮普攻 = 原作 Skill_2_Loop 全长（run_trial cfg/skalter_idle_s2.json）'},
        'perm_pose': {'s2': {'idle': 'idle_s2', 'attack': 'idle_s2'}}}, ['idle_s2'])
    sp = js['ulpianus']['sprites']
    patch_text('ulpianus', {
        'idle_s2': spec_like(sp, 'idle', 'op_ulpianus_idle_s2', _doc='11-23 docs/408：S2 永续后的待机 = 原作 Skill_2_Idle（6 秒 8 帧，make_op_1x 同一 cfg）'),
        'perm_pose': {'s2': {'idle': 'idle_s2'}}}, ['idle_s2'])
    sp = js['suzuran']['sprites']
    patch_text('suzuran', {
        'skill_s2': {'tex': 'op_suzuran_skill_s2', 'frames': 6, 'fps': 6 / sum(sz_durs), 'foot': sp['idle']['foot'], 'frame_durations': sz_durs,
                     '_doc': '11-23 docs/408：S2 施法余段 = 原作 Skill2 f2–f7（skills.s2.tail，纯画面）；intro / hold 贴图 = Skill2 f0 / f1'}}, ['skill_s2'],
        [(r'^\s*"s2": \{\s*$', '"tail": "skill_s2",')])
    for op in js:
        print('eye_fix', op, [x for x in eye_fix.fix_op(op) if x[2]])
