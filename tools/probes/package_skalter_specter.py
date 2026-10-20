"""浊心斯卡蒂 / 归溟幽灵鲨：原作动作条 + 新做动作 → 64 画布 @2x 候选（docs/108 §5）。

只读 Codex 工作树（cb_18 原作 8 帧像素部件、dc / dd / de 召唤物替身源）与 build/spine_run_trial 跑步帧；输出到 build/op_skalter_specter/。
不缩放：原作像素部件按 draw_order 原样合成，只做整数平移（对齐 run_trial 的 Idle t=0，鞋底 = 原点 (64,120)）、
整帧水平镜像（回旋转身）与层序调整（锯盘转到身后）。--apply 时写 art/incoming 与 json（用户「过」之后）。

用法：python -X utf8 tools/probes/package_skalter_specter.py [--apply]
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
ART = Path('E:/ArknightsSurvivors/.worktrees/codex-art/art/incoming')
CB = ART / 'cb_18_prts_native_actions_1017'
OUT = ROOT / 'build/op_skalter_specter'
RUN = ROOT / 'build/spine_run_trial'
INC = ROOT / 'art/incoming'
APPLY = '--apply' in sys.argv
WEAPON = {'F_Weapon2', 'B_W_Ring', 'B_W_LineA', 'B_W_LineB', 'B_W_Ribbon', 'B_W_BeltA', 'B_W_BeltB'}


def manifest(op):
    m = json.loads((CB / op / 'manifest.json').read_text(encoding='utf-8'))
    return {a['action']: a for a in m['actions']}


MAN = {op: manifest(op) for op in ('skalter', 'specter_unchained')}


def cb_frame(op, action, i, back=(), front=()):
    """原作 8 帧像素部件按层序合成（192 画布）；back / front 里的槽移到最底 / 最顶。"""
    rec = MAN[op][action]['records'][i]
    parts = sorted(rec['parts'], key=lambda p: p['draw_order'])
    lo = [p for p in parts if p['slot'] in back]
    hi = [p for p in parts if p['slot'] in front]
    mid = [p for p in parts if p['slot'] not in back and p['slot'] not in front]
    im = Image.new('RGBA', tuple(MAN[op][action]['canvas']))
    for p in lo + mid + hi:
        im.alpha_composite(Image.open(CB / op / p['file'].replace('\\', '/')).convert('RGBA'))
    if not back and not front:   # 未调层序的帧必须与 Codex 交付的整帧逐像素一致
        ref = Image.open(CB / op / action / f'{action}_{i:02d}.png').convert('RGBA')
        assert np.array_equal(np.asarray(ref)[:, :, 3] > 0, np.asarray(im)[:, :, 3] > 0), (op, action, i)
    return im


def best_offset(big, small):
    """big（cb 画布）里找与 small（128 @2x）alpha 最吻合的整数平移，返回 big 坐标里 small 原点 (0,0) 的位置。"""
    A = np.asarray(big)[:, :, 3] > 0
    B = np.asarray(small)[:, :, 3] > 0
    best = None
    for dy in range(A.shape[0] - 128 + 1):
        for dx in range(A.shape[1] - 128 + 1):
            s = np.logical_and(A[dy:dy + 128, dx:dx + 128], B).sum() - np.logical_xor(A[dy:dy + 128, dx:dx + 128], B).sum()
            if best is None or s > best[0]:
                best = (s, dx, dy)
    return best


def to_canvas(im, org, flip=False):
    """cb 画布 → 96 画布 @2x（192，原点 (96,152)），org = cb 画布里 64 口径原点的整数位置。"""
    out = Image.new('RGBA', (192, 192))
    out.paste(im, (96 - org[0], 152 - org[1]), im)
    if flip:
        # 回旋转身：绕原点竖线镜像（原点列 96 落在像素 95|96 之间，镜像后脚下位置不变）
        out = out.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return out


def pack(frames):
    """8 帧都在 128 裁窗内 → 64 画布；否则保留 96 画布（docs/108 §5）。"""
    crop = (32, 32, 160, 160)
    compact = all(np.asarray(f)[:, :, 3].sum() == np.asarray(f.crop(crop))[:, :, 3].sum() for f in frames)
    if compact:
        frames = [f.crop(crop) for f in frames]
    s = frames[0].width
    strip = Image.new('RGBA', (s * len(frames), s))
    for i, f in enumerate(frames):
        strip.paste(f, (s * i, 0))
    return strip, (64 if compact else 96)


def run_frames(op, action=None, n=8):
    d = RUN / op / (action + '/frames' if action else 'frames')
    fr = [Image.open(d / f'f{i:02d}.png').convert('RGBA') for i in range(n)]
    out = []
    for f in fr:
        c = Image.new('RGBA', (192, 192)); c.paste(f, (32, 32), f); out.append(c)
    return out


# ---- 替身（召唤物原生源，按 dg export_doll.py 同法：dd 修订尺度 + de 风格 + 嘴线），动作 Start_B / Die_B ----
def doll_frames(action, idx):
    sys.path.insert(0, str(ART / 'de_summon_style_alignment_1020'))
    from style import pixel_part
    spec = importlib.util.spec_from_file_location('clean', ART / 'cz_skadi_actions_1020/cleanup.py')
    cl = importlib.util.module_from_spec(spec); spec.loader.exec_module(cl)
    SRC = ART / 'dc_summon_native_actions_1020/specter_substitute'
    BASE = ART / 'db_summon_native_pixels_1020/specter_substitute'
    REV = ART / 'dd_summon_pixel_alignment_1020/specter_substitute'
    m = json.loads((SRC / action / 'manifest.json').read_text())
    sc = json.loads((REV / 'manifest.json').read_text())['global_transform']['scale']
    b = json.loads((BASE / 'manifest.json').read_text())
    ox, oy = m['source_origin']
    matrix = (1 / sc, 0, ox - 64 / sc, 0, 1 / sc, oy - 120 / sc)
    ox0, oy0 = b['global_transform']['source_origin']
    bm = (1 / sc, 0, ox0 - 64 / sc, 0, 1 / sc, oy0 - 120 / sc)
    cols = []
    for p in b['parts']:
        a = np.array(Image.open(BASE / 'original' / (p['id'] + '.png')).convert('RGBA').transform((128, 128), Image.Transform.AFFINE, bm, Image.Resampling.BICUBIC))
        if (a[:, :, 3] >= 64).any():
            cols.append(a[:, :, :3][a[:, :, 3] >= 64])
    palette = Image.fromarray(np.concatenate(cols).reshape(1, -1, 3)).quantize(colors=96, method=Image.Quantize.MEDIANCUT)
    out = []
    for index in idx:
        full = Image.new('RGBA', (128, 128))
        for row in m['parts'][index]:
            raw = Image.open(SRC / 'native' / (row['id'] + '.png')).convert('RGBA')
            im = raw.transform((128, 128), Image.Transform.AFFINE, matrix, Image.Resampling.BICUBIC)
            q, _ = pixel_part(im, palette); q = cl.clean_part(q, row['slot'])
            if row['slot'] == 'F_Mouth_T':
                a = np.array(im)[:, :, 3]; ys, xs = np.where(a > 0)
                if len(xs):
                    w = a[ys, xs].astype(float); cx = int(round(np.average(xs, weights=w))); cy = int(round(np.average(ys, weights=w)))
                    q = Image.new('RGBA', (128, 128)); q.putpixel((cx, cy), (104, 78, 75, 255)); q.putpixel((cx + 1, cy), (104, 78, 75, 255))
            full.alpha_composite(q)
        c = Image.new('RGBA', (192, 192)); c.paste(full, (32, 32), full); out.append(c)
    return out, m


def even(dur, fire=None):
    """旧口径时序保持不变：8 帧均分旧动作秒数，fire_time = 旧 (fire+0.5)/fps，fire = 所在帧（V7）。"""
    d = {'frames': 8, 'fps': 8 / dur, 'frame_durations': [dur / 8] * 8}
    if fire is not None:
        d['fire_time'] = fire
        d['fire'] = min(7, int(fire / (dur / 8) + 1e-9))
    return d


def hit(dur, fire, k, n=8):
    """出手与画面对齐（10-20 用户要求）：逻辑时序不变（总长 dur、出手 fire 秒，伤害在出手帧起点），前 k 帧均分 fire、其余均分收势，出手帧 = k；
    画面整条播放 clip = fire × n / k 秒（json native_motion.clips，均匀播放，纯显示、收势可越过逻辑窗口，docs/108 §3.5），
    所以出手帧的画面起点正好 = fire。"""
    return {'frames': n, 'fps': n / dur, 'frame_durations': [fire / k] * k + [(dur - fire) / (n - k)] * (n - k),
            'fire_time': fire, 'fire': k, 'clip': fire * n / k}


def build():
    OUT.mkdir(parents=True, exist_ok=True)
    ref = {}
    for op in ('skalter', 'specter_unchained'):
        idle0 = Image.open(RUN / op / 'frames' / 'idle_t0.png').convert('RGBA')
        s, dx, dy = best_offset(cb_frame(op, 'Idle', 0), idle0)
        ref[op] = (dx + 64, dy + 120)
        print(op, 'cb 原点 → 64 口径原点', ref[op], 'score', s, 'cb anchor', MAN[op]['Idle']['anchor'])
    res = {}

    def cb(op, action, i, **kw):
        flip = kw.pop('flip', False)
        a, ia = MAN[op][action]['anchor'], MAN[op]['Idle']['anchor']   # 动作画布加大时（如 196）原点随之平移
        org = (ref[op][0] + round(a[0] - ia[0]), ref[op][1] + round(a[1] - ia[1]))
        return to_canvas(cb_frame(op, action, i, **kw), org, flip)

    def native(op, action):
        return [cb(op, action, i) for i in range(8)], MAN[op][action]['frame_durations']

    # ---------------- 浊心斯卡蒂 ----------------
    op = 'skalter'
    # 待机：原作 Idle 全长 8.77 秒按 36 帧加密采样（cb 只有 8 个关键姿势、每帧约 1.1 秒，10-20 用户要求补帧）
    n = 36; dur = MAN[op]['Idle']['source_duration']
    res[(op, 'idle')] = (run_frames(op, 'idle_dense', n), {'frames': n, 'fps': n / dur, 'frame_durations': [dur / n] * n})
    res[(op, 'run')] = (run_frames(op), {'frames': 8, 'fps': 40 / 3, 'frame_durations': [0.075] * 8})
    # 普攻「海潮低吟」：原作无 Attack；10-20 用户定不做出手姿势，只原地漂浮（声浪是特效）。旧 5 帧 12fps、出手 2 的时序不变
    res[(op, 'attack')] = (run_frames(op, 'hover'), dict(even(5 / 12, 2.5 / 12), clip=0.8))
    # 技能：原作起手取 8 帧重排，关键姿势（举杖 / 挥下）放在出手帧 2，画面 1.17 秒；旧 skill 7 帧 12fps、出手 3 的逻辑时序不变
    for slot, act, idx in (('skill', 'Skill_1_Begin', [0, 4, 5, 6, 6, 6, 7, 7]), ('skill_s2', 'Skill_2_Begin', [2, 4, 5, 6, 6, 7, 7, 7]),
                           ('skill_s3', 'Skill_3_Begin', [3, 4, 5, 6, 6, 6, 7, 7])):
        res[(op, slot)] = ([cb(op, act, i) for i in idx], hit(7 / 12, 3.5 / 12, 2))
    fr, du = native(op, 'Die'); res[(op, 'death')] = (fr, {'frames': 8, 'fps': 8 / sum(du), 'frame_durations': du})

    # ---------------- 归溟幽灵鲨 ----------------
    op = 'specter_unchained'
    fr, du = native(op, 'Idle'); res[(op, 'idle')] = (fr, {'frames': 8, 'fps': 8 / sum(du), 'frame_durations': du})
    res[(op, 'run')] = (run_frames(op), {'frames': 8, 'fps': 40 / 3, 'frame_durations': [0.075] * 8})
    # 普攻 360° 环斩：前 4 帧蓄锯（原作 Attack 拉锯），出手帧锯盘甩到身前，随后转身（整帧镜像）、锯盘转到身后（层序置底），再转回身前收势。
    # 旧 5 帧 12fps、出手 2 → 出手时刻 0.2083 秒 = 第 4 帧起点
    # 12 帧、画面 0.833 秒（每帧 69 ms）：前摇 3 帧到伤害时刻 0.208 秒 → 出手帧 3 锯盘甩到身前 → 转身锯盘过背 → 低位扫过 → 转回身前（帧 3–6 共 0.28 秒，
    # 与锯环特效 0.24–0.3 秒同步转完一圈）→ 收势 5 帧
    spin = [cb(op, 'Attack', 1), cb(op, 'Attack_Down', 1), cb(op, 'Attack_Down', 2),
            cb(op, 'Attack', 3),
            cb(op, 'Attack', 4, flip=True, back=WEAPON),
            cb(op, 'Attack_Down', 4, flip=True),
            cb(op, 'Attack', 4),
            cb(op, 'Attack', 5), cb(op, 'Attack', 6), cb(op, 'Attack', 6), cb(op, 'Attack', 7), cb(op, 'Attack', 7)]
    res[(op, 'attack')] = (spin, hit(5 / 12, 2.5 / 12, 3, 12))
    # 技能：关键姿势放在出手帧 2（S1 抬手蓄力、S3 锯盘举过头），画面 1.5 秒；旧 skill 7 帧 12fps、出手 4 的逻辑时序不变
    res[(op, 'skill')] = ([cb(op, 'Skill_1', i) for i in [1, 2, 3, 4, 5, 6, 7, 7]], hit(7 / 12, 4.5 / 12, 2))
    res[(op, 'skill_s3')] = ([cb(op, 'Skill_3_Begin', i) for i in [2, 3, 4, 5, 6, 7, 7, 7]], hit(7 / 12, 4.5 / 12, 2))
    # S3 持续期（纯显示，seg_specter.h3_anim_state 在 s_t[2] > 0 时换条）：待机 = 原作举锯待机 Skill_3_Idle；
    # 普攻 = 重锯环斩：原作 Skill_3_Attack 举锯→下砸（出手帧）后接转身锯盘过背、转回，收在举锯姿势。帧号与普攻同步（同 8 帧、同出手帧 4）
    fr, du = native(op, 'Skill_3_Idle'); res[(op, 'idle_s3')] = (fr, {'frames': 8, 'fps': 8 / sum(du), 'frame_durations': du})
    heavy = [cb(op, 'Skill_3_Attack', 0), cb(op, 'Skill_3_Attack', 1), cb(op, 'Skill_3_Attack_Down', 2),
             cb(op, 'Skill_3_Attack', 3),
             cb(op, 'Skill_3_Attack', 4, flip=True, back=WEAPON),
             cb(op, 'Skill_3_Attack_Down', 4, flip=True),
             cb(op, 'Skill_3_Attack', 4),
             cb(op, 'Skill_3_Attack', 5), cb(op, 'Skill_3_Attack', 6), cb(op, 'Skill_3_Attack', 6), cb(op, 'Skill_3_Attack', 7), cb(op, 'Skill_3_Attack', 7)]
    res[(op, 'attack_s3')] = (heavy, hit(5 / 12, 2.5 / 12, 3, 12))   # 与普攻同帧号（h3_anim_state 直接换条）
    fr, _ = native(op, 'Die')
    res[(op, 'fall')] = (fr, even(0.5, 0.45))                                      # 旧 fall 5 帧 10fps、fire 4（倒下时长 0.5 秒）
    fr, du = native(op, 'Die'); res[(op, 'death')] = (fr, {'frames': 8, 'fps': 8 / sum(du), 'frame_durations': du})
    # 替身：现身（Start_B 12 帧采样取 8）、连斩旋身（Start_B 张袍姿势 + 镜像交替）、消散（Die_B）
    ap, _ = doll_frames('Start_B', [1, 2, 3, 4, 5, 6, 8, 11])
    res[(op, 'doll_appear')] = (ap, {'frames': 8, 'fps': 32, 'frame_durations': [0.25 / 8] * 8})
    sp_, _ = doll_frames('Start_B', [4, 5, 6, 5])
    flipx = lambda im: im.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    # 整个连斩段（spin 秒）只播一遍（10-21 原每圈一遍、0.15 秒内两次镜像读成抽搐）：三斩 hit_at + k × gap 落在帧 1 / 4 / 6，
    # 张袍姿势正 → 反 → 正与锯环转向交替一致，全程只转两次身
    res[(op, 'doll_spin')] = ([sp_[0], sp_[1], sp_[2], flipx(sp_[1]), flipx(sp_[0]), flipx(sp_[2]), sp_[0], sp_[3]], {'frames': 8, 'fps': 8 / 0.45, 'fire': 1})
    va, _ = doll_frames('Die_B', [0, 1, 3, 5, 7, 8, 10, 11])
    res[(op, 'doll_vanish')] = (va, {'frames': 8, 'fps': 8 / 0.3, 'frame_durations': [0.3 / 8] * 8})

    meta = {}
    for (op, slot), (frames, spec) in res.items():
        strip, size = pack(frames)
        name = f'op_{op}_{slot}'
        strip.save(OUT / f'{name}@2x.png')
        foot = [32, 60] if size == 64 else [48, 76]
        meta[f'{op}.{slot}'] = dict(spec, tex=name, foot=foot, canvas=size, sha256=hashlib.sha256((OUT / f'{name}@2x.png').read_bytes()).hexdigest())
        print(op, slot, 'canvas', size, 'frames', len(frames))
    (OUT / 'meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    return meta


SKILLS = {'skalter': {'s1': 'skill', 's2': 'skill_s2', 's3': 'skill_s3'},
          'specter_unchained': {'s1': 'skill', 's2': 'skill', 's3': 'skill_s3'}}
DOC = {
    'skalter.attack': '原作无普攻动作：10-20 用户定只原地漂浮（声浪是特效）；逻辑时序同旧 5 帧 12fps、出手 2',
    'specter_unchained.attack': '360° 环斩：前摇 3 帧到伤害时刻，出手帧 3 起 0.28 秒转完一圈（与锯环特效同步）再收势；画面按 native_motion.clips 播 0.833 秒，出手帧画面起点 = fire_time',
    'specter_unchained.attack_s3': 'S3 期间普攻画面（seg_specter.h3_anim_state 换条，帧号同 attack）：原作 Skill_3_Attack 举锯下砸 + 转身锯盘过背',
    'specter_unchained.idle_s3': 'S3 期间待机画面（h3_anim_state 换条）：原作 Skill_3_Idle',
    'specter_unchained.doll_appear': '替身闪现的现身段（_e3_flash_draw，按 appear 秒数整条播）：原作 Start_B',
    'specter_unchained.doll_vanish': '替身闪现的消散段（_e3_flash_draw，按 burst 秒数整条播）：原作 Die_B',
    'specter_unchained.doll_spin': '替身连斩旋身（原作无此动作）：Start_B 张袍姿势 + 镜像；整个连斩段播一遍，三斩落在帧 1 / 4 / 6（正 / 反 / 正，与锯环转向一致）',
}


def apply(meta):
    """用户「过」后落盘：@2x 帧条写 art/incoming（不交 1x），删同名旧 1x；json 改 64 口径（docs/108 §4–§5）。"""
    for op in ('skalter', 'specter_unchained'):
        path = ROOT / f'game/data/characters/{op}.json'
        data = json.loads(path.read_text(encoding='utf-8'))
        sp = data['sprites']
        sp['size'] = 64
        sp['foot'] = [32, 60]
        extras = data.get('extra_sprites', [])
        clips = {}
        for key, m in meta.items():
            o, slot = key.split('.')
            if o != op:
                continue
            (INC / f"{m['tex']}@2x.png").write_bytes((OUT / f"{m['tex']}@2x.png").read_bytes())
            (INC / f"{m['tex']}.png").unlink(missing_ok=True)
            (INC / f"{m['tex']}.png.import").unlink(missing_ok=True)
            spec = {'tex': m['tex'], 'frames': m['frames'], 'fps': m['fps'], 'foot': m['foot']}
            for k in ('frame_durations', 'fire', 'fire_time'):
                if k in m:
                    spec[k] = m[k]
            if key in DOC:
                spec['_doc'] = DOC[key]
            sp[slot] = spec
            if m.get('clip'):
                clips[slot] = round(m['clip'], 6)
            if slot not in ('idle', 'run', 'attack', 'skill', 'hurt', 'death') and slot not in extras:
                extras.append(slot)
        data['extra_sprites'] = extras
        sp['skills'] = {k: {'anim': v} for k, v in SKILLS[op].items()}
        data['native_motion'] = {'_doc': '出手帧对齐（10-20 用户）：画面整条播 clip 秒，出手帧画面起点 = fire_time，收势越过逻辑窗口、下一动作打断（docs/108 §3.5）',
                                 'clips': clips}
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
        print('json', path.name, 'clips', clips)
    (INC / 'skalter_specter_native_sources.json').write_text(json.dumps(
        {k: {'tex': v['tex'], 'sha256': v['sha256'], 'canvas': v['canvas']} for k, v in meta.items()}, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')


if __name__ == '__main__':
    meta = build()
    if APPLY:
        apply(meta)
