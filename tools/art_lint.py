# -*- coding: utf-8 -*-
"""干员帧条自动检查（docs/87 统一美术规格的机检部分）。只读 art/incoming 与 game/data，不改任何文件。

用法：
    python tools/art_lint.py                       # 18 名干员 + 博士全部
    python tools/art_lint.py --ops texas,siege     # 只查这几人（id 同 game/data/characters/<id>.json；博士 = doctor，水月 = mizuki）
    python tools/art_lint.py --json qa.json        # 另外写一份机器可读结果（Codex 交付时写进 qa.json）
    python tools/art_lint.py --no-images           # 不出对照图（快检用）
    python tools/art_lint.py --art <目录>          # 查别的目录里的帧条（例如 Codex 工作树的 art/incoming）
    python tools/art_lint.py --base <提交>         # hue 项改与这个提交里的同名帧条比（缺省：每个文件的上一个提交版本）
    python tools/art_lint.py --changed             # hue 项只比相对 main 分叉点改过的帧条（快检 check.py 用这个）

输出：终端表格；build/art_lint/report.md；build/art_lint/compare_<id>.png（本人四动作 + 参考干员待机并排）。
退出码：有未豁免的 FAIL = 1，否则 0（WARN 不影响退出码）。

判定三档：PASS / WARN / FAIL。阈值全部来自 docs/87，改阈值先改文档。
豁免（WAIVERS）：已开返修单、尚未交付的 FAIL 显式列在下面，标注返修单号；交付合入后删掉对应条目。
已豁免的 FAIL 显示为 FAIL*，不计入退出码；豁免项如果已经通过，会提示「豁免可删」。

检查项（id → 说明）：
    files    帧条齐全（1x 与 @2x 都在）
    size     单帧 48×48 / 96×96，宽 = 帧数 × 高，帧数与角色 json sprites 一致，出手帧在范围内
    pair     1x 与 @2x 逐帧对应（@2x 缩到 1x 后剪影差 / 帧序）
    alpha    二值透明（只有 0 / 255）
    outline  外描边：与透明区四邻接的像素全部是 #080E18；@2x 第二圈也是（2px）
    colors   每人全部帧条合计色数 ≤ 24（1x、@2x 各算）
    magenta  洋红抠图残留 = 0
    skill_end  skill 末帧 = idle f0（逐像素，1x 与 @2x）
    facing   待机与动作同向（朝右）：idle f0 头部与「本该同一张图」的 skill 末帧 / 动作帧比对，原样 vs 镜像
    frontal  待机不得正面朝前：idle 头部左右对称度 / 本人跑步帧头部对称度
    idle     待机呼吸：身体起伏、剪影变化、几乎相同的相邻帧
    run      跑步循环：剪影 / 腿部 / 上半身变化、头部起伏、停顿帧、前倾角（tools/run_cycle_review.py 同一口径）
    ground   脚底贴第 46 行（@2x 92）：待机每帧贴地，其他动作至少一帧贴地（FAIL）；跑步某帧离地 > 3px（WARN）
    foot     脚底中心 x（最低 2 行）与 json foot 偏差 > 2px 报 WARN
    tone     明度：非描边 HSL 明度均值、近黑 / 亮部占比、L4 受光变亮占比（只报 WARN）
    hue      与上一版比色调（docs/87 §4.3，只报 WARN）：本人身体的每组动作（1x、@2x 各算）与「上一版」逐像素比，
             在两版都不透明、都不是描边的像素上取平均：色相差（度，按两版彩度 max−min 的较小者加权，彩度 < 0.08 的
             灰 / 近黑像素不算——它们的色相是噪声）、HSL 饱和差、HSL 明度差（逐像素绝对差）；任一项超线
             （5° / 0.05 / 0.03）报 WARN 并打印数值，同时给出带符号的平均偏移（看是整体变灰 / 变暗还是局部换色）。
             上一版 = git 里这个文件上一个提交的版本（工作区有未提交改动时 = HEAD 版本），或 --base <提交>；
             --changed（快检用）= 只比相对 main 分叉点改过的帧条、上一版取分叉点。没有上一版就跳过（列里显示 —）。
             两版重合像素 < 60% 时改比整条帧条的统计量（彩度加权平均色相、平均饱和、平均明度），注明「统计」；
             亮度对得上的像素（|ΔY| < 40）不到 70% 时注明「像是重画了姿势」——这时逐像素差不代表调色，要看对照图
"""
import argparse, glob, io, json, math, os, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)

ART = os.path.join(ROOT, "art", "incoming")
DATA = os.path.join(ROOT, "game", "data")
OUT = os.path.join(ROOT, "build", "art_lint")
OUTLINE = (8, 14, 24)   # #080E18
MAIN_ACTS = ["idle", "run", "attack", "skill"]
REF_OPS = ["skadi", "skalter", "lumen"]   # docs/87 §2 朝右 3/4 侧身参考
NAMES = {"angelina": "安洁莉娜", "exusiai": "能天使", "eyjafjalla": "艾雅法拉", "hoshiguma": "星熊", "irene": "艾丽妮",
         "kaltsit": "凯尔希", "logos": "逻各斯", "lumen": "流明", "mizuki": "水月", "saria": "塞雷娅", "siege": "推进之王",
         "skadi": "斯卡蒂", "skalter": "浊心斯卡蒂", "specter_unchained": "归溟幽灵鲨", "suzuran": "铃兰", "texas": "德克萨斯",
         "ulpianus": "乌尔比安", "wisadel": "维什戴尔", "doctor": "博士"}

# ---------------------------------------------------------------- 阈值（docs/87，改这里先改文档）
T = {
    "pair_sil_warn": 0.10, "pair_sil_fail": 0.20,        # @2x 缩到 1x 后与 1x 的剪影异或 / 并集（逐帧最大）
    "colors_max": 24,
    "facing_fail": 0.0, "facing_warn": 1.5,              # 头部比对：镜像距离 − 原样距离（正 = 同向）
    "frontal_fail": 0.76, "frontal_warn": 0.82,          # 待机头部对称差 / 跑步头部对称差（越小越对称）
    "idle_bob": (1.0, 3.0), "idle_sil": 0.03, "idle_static_pairs": 1, "static_eps": 0.005,
    "run_move": 0.035, "run_leg": 0.10, "run_head_bob": (1.0, 2.5), "run_upper": 0.004, "run_static_pairs": 1,
    "run_lean": (0.0, 25.0), "run_lean_slack": 5.0,       # 前倾（度，正 = 朝右前倾）；超出区间 WARN，再超 5° FAIL
    "foot_tol": 2.0,
    "tone_hsl": (0.30, 0.50), "tone_dark_min": 0.10, "tone_bright": (0.08, 0.35), "tone_gain_max": 0.12,
    "hue_deg": 5.0, "hue_sat": 0.05, "hue_light": 0.03,   # docs/87 §4.3：与上一版比，超线 WARN
    "hue_min_chroma": 0.08, "hue_overlap": 0.60, "hue_redraw": 0.70,   # 色相只算彩度 ≥ 0.08 的像素；重合 < 60% 改统计口径；亮度对上 < 70% 注明像重画
}
# 逐人覆盖（docs/69 A/B、docs/87 §4.3）
TONE_OVERRIDE = {
    "texas": {"tone_dark_min": 0.35, "tone_bright": (0.08, 0.35), "tone_hsl": (0.20, 0.50)},
    "hoshiguma": {"tone_dark_min": 0.25, "tone_bright": (0.18, 0.30), "tone_hsl": (0.33, 0.40)},
}
# 存量（第三批 docs/63 之前交付的 12 名干员（含水月）+ 博士）：色数 > 24、skill 末帧 ≠ idle f0 只报 WARN（这两条是第三批起才定的硬规格）；
# 重画哪条帧条，哪条就按 docs/87 全部达标
LEGACY = {"eyjafjalla", "irene", "kaltsit", "logos", "lumen", "mizuki", "saria", "siege", "skadi", "suzuran",
                 "ulpianus", "wisadel", "doctor"}

# ---------------------------------------------------------------- 豁免：已开返修单、未交付的 FAIL（交付合入后删条目）
WAIVERS = {
    ("suzuran", "facing"): "docs/86 交付后 idle 已朝右侧身；机检误判源于 attack 帧条偏正面 / 朝左，用户 10-13 定暂不重画 attack",
    ("skadi", "run"): "docs/85 交付 928b8a35 后腿部 / 前倾已达标，仅剩停顿帧 2 对（线为 ≤ 1），协调人 10-13 接受",
    # 以下为 docs/87 附录 B 基线新发现，待协调人 / 用户定是否开返修单（开单后把说明改成返修单号）
    ("skalter", "run"): "设计例外（用户 10-13 定）：浊心斯卡蒂跑步是悬浮飘行，腿不交替属造型，长期豁免",
    ("skalter", "ground"): "设计例外（用户 10-13 定）：浊心斯卡蒂悬浮飘行，离地 4–6px 属造型，长期豁免",
    ("exusiai", "run"): "用户 10-13 认可现版（fafe6f1e 连续性修复后）；机检上半身变化 0.000、头部起伏 0.8px 仍低于线，暂不返修",
    ("texas", "run"): "用户 10-13 认可现版（1a761c8e 连续性修复后）；机检头部起伏 0.5px 仍低于线，暂不返修",
    ("specter_unchained", "run"): "用户 10-13 认可现版：归溟幽灵鲨跑步前倾 35°、停顿帧 2 对，不返修",
    # 单条帧条豁免（op, check, 动作）：只豁免这条帧条的这一项，同一干员其他帧条照常检查
    ("angelina", "ground", "float_in"): "设计例外（docs/92）：S3 起飞，f2–f3 离地属造型",
    ("angelina", "ground", "float"): "设计例外（docs/92）：S3 浮空待机，最低行 38±1 离地属造型",
    ("angelina", "ground", "float_move"): "设计例外（docs/92）：S3 浮空移动，离地属造型",
    ("angelina", "ground", "float_attack"): "设计例外（docs/92）：S3 浮空普攻，离地属造型",
}


# ---------------------------------------------------------------- 名单与配置

def roster(data=DATA):
    """{id: {act: {tex, frames, fps, foot, fire}}}；水月用 player_* 缺省帧条（world.gd），博士读 data/doctor.json"""
    out = {}
    for p in sorted(glob.glob(os.path.join(data, "characters", "*.json"))):
        d = json.load(open(p, encoding="utf-8"))
        cid = d.get("id") or os.path.splitext(os.path.basename(p))[0]
        sp = d.get("sprites") or {}
        foot = sp.get("foot", [24, 46])
        acts = {k: dict(v) for k, v in sp.items() if isinstance(v, dict) and "tex" in v}
        # 技能期间换动作组（sprites.skill_pose，docs/92）引用的帧条是本人身体：和 MAIN_ACTS 一样查描边 / 色数 / 贴地
        pz = sp.get("skill_pose") if isinstance(sp.get("skill_pose"), dict) else {}
        for k in [pz.get("in"), pz.get("out")] + list((pz.get("map") or {}).values()):
            if k in acts:
                acts[k]["_body"] = True
        if cid == "mizuki":   # idle / run / attack 仍是字符串槽（world.gd 缺省帧条）；skill 自 docs/97 B 起是带 fps / fire 的字典槽，两者合并
            for k, v in {"idle": {"tex": "player_idle", "frames": 4, "fps": 6, "foot": foot},
                         "run": {"tex": "player_run", "frames": 6, "fps": 12, "foot": foot},
                         "attack": {"tex": "player_attack_48", "frames": 4, "fps": 12, "foot": foot}}.items():
                acts.setdefault(k, v)
        for v in acts.values():
            v.setdefault("foot", foot)
        out[cid] = acts
    dp = os.path.join(data, "doctor.json")
    if os.path.exists(dp):
        sp = json.load(open(dp, encoding="utf-8")).get("sprites", {})
        foot = sp.get("foot", [24, 46])
        out["doctor"] = {k: {"tex": sp[k], "frames": None, "foot": foot} for k in ("idle", "run") if isinstance(sp.get(k), str)}
    return out


def load_strip(art, tex, hi):
    p = os.path.join(art, tex + ("@2x" if hi else "") + ".png")
    if not os.path.exists(p):
        return None
    a = np.array(Image.open(p).convert("RGBA"))
    return a


def split(a):
    s = a.shape[0]
    return [a[:, i * s:(i + 1) * s] for i in range(a.shape[1] // s)]


# ---------------------------------------------------------------- 基础量

def _ring(m):
    p = np.pad(m, 1, constant_values=False)
    t = ~p
    return m & (t[:-2, 1:-1] | t[2:, 1:-1] | t[1:-1, :-2] | t[1:-1, 2:])


def _is_outline(a):
    return np.all(a[..., :3] == OUTLINE, axis=-1) & (a[..., 3] > 0)


def _luma(rgb):
    return 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]


def _dilate(m, r):
    o = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            o |= np.roll(np.roll(m, dy, 0), dx, 1)
    return o


def _move(a, b, r=2):
    u = (a | b).sum()
    return ((a & ~_dilate(b, r)).sum() + (b & ~_dilate(a, r)).sum()) / max(1, u)


# ---------------------------------------------------------------- 朝向 / 正面

def _prep(f, k):
    m = f[..., 3] > 0
    g = np.zeros(f.shape, np.float32)
    g[..., :3] = f[..., :3] * m[..., None]
    g[..., 3] = m * 255
    ch = [np.array(Image.fromarray(g[..., i].astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8 * k))).astype(np.float32) for i in range(4)]
    return np.stack(ch, -1), m


def _headrows(m, frac=0.3):
    ys = np.nonzero(m.any(axis=1))[0]
    top, bot = ys.min(), ys.max()
    return top, top + int(round((bot - top + 1) * frac))


def _best_dist(A, cxa, rr, mr, k):
    t1, b1 = _headrows(mr)
    xs = np.nonzero(mr[t1:b1])[1]
    cxb = xs.mean()
    H = A.shape[0]
    best = 1e9
    for dy in range(-3 * k, 3 * k + 1):
        y0 = t1 + dy
        if y0 < 0 or y0 + H > rr.shape[0]:
            continue
        B = rr[y0:y0 + H]
        for dx in range(-6 * k, 6 * k + 1):
            Bs = np.roll(B, int(round(cxa - cxb)) + dx, 1)
            u = (A[..., 3] > 20) | (Bs[..., 3] > 20)
            if u.any():
                best = min(best, float(np.abs(A - Bs)[u].mean()))
    return best


def facing_margin(idle0, ref, k=2):
    """idle f0 头部（外框顶往下 30%）与参考帧头部的距离：镜像参考 − 原样参考（对齐搜索 ±6×±3 px@1x）。正 = 同向"""
    i0, m0 = _prep(idle0, k)
    t0, b0 = _headrows(m0)
    A = i0[t0:b0]
    cxa = np.nonzero(m0[t0:b0])[1].mean()
    r, mr = _prep(ref, k)
    return _best_dist(A, cxa, r[:, ::-1], mr[:, ::-1], k) - _best_dist(A, cxa, r, mr, k)


def _headsym(f, hw, y0f, y1f, k=2):
    m = f[..., 3] > 0
    ys = np.nonzero(m.any(axis=1))[0]
    top, bot = ys.min(), ys.max()
    h = bot - top + 1
    y0, y1 = top + int(h * y0f), top + int(h * y1f)
    bx = np.nonzero(m[y0:y1])[1]
    cx = bx.mean()
    best = 9.0
    for c2 in range(int(2 * cx) - 16 * k, int(2 * cx) + 16 * k + 1):   # 对称轴在 c2 / 2，±16px@1x 内搜
        w = hw * k
        cols = np.arange(int(np.floor(c2 / 2)) - w + 1, int(np.floor(c2 / 2)) + 1)
        mir = c2 - cols
        ok = (cols >= 0) & (mir < f.shape[1]) & (mir > cols)
        A = f[y0:y1][:, cols[ok]].astype(np.float32)
        B = f[y0:y1][:, mir[ok]].astype(np.float32)
        ma, mb = A[..., 3] > 0, B[..., 3] > 0
        if (ma & mb).sum() < 0.6 * ma.size:   # 窗口要基本填满（是头，不是边缘）
            continue
        u = ma | mb
        d = (np.abs(A[..., :3] - B[..., :3]).max(-1) * (ma & mb) + 255 * (ma ^ mb))[u].mean() / 255
        best = min(best, float(d))
    return best


SYM_CFG = [(5, 0.15, 0.4), (6, 0.15, 0.4), (7, 0.15, 0.4), (6, 0.1, 0.35), (7, 0.1, 0.35)]


def frontal_ratio(idle, run, k=2):
    """待机头部左右对称差 / 本人跑步帧头部对称差 的几何平均（5 组窗口）。正面朝前的头部左右对称 → 比值小"""
    rs = []
    for c in SYM_CFG:
        i = np.mean([_headsym(f, *c, k=k) for f in idle])
        r = np.median([_headsym(f, *c, k=k) for f in run])
        rs.append(i / max(1e-6, r))
    return float(np.exp(np.mean(np.log(rs))))


# ---------------------------------------------------------------- 动作指标

def idle_metrics(fr, k=2):
    n = len(fr)
    masks = [f[..., 3] > 0 for f in fr]
    sil = [(masks[i] ^ masks[(i + 1) % n]).sum() / max(1, (masks[i] | masks[(i + 1) % n]).sum()) for i in range(n)]
    tops, heads = [], []
    for m in masks:
        ys, xs = np.nonzero(m)
        top, bot = ys.min(), ys.max()
        tops.append(top / k)
        hb = m[top: top + (bot - top + 1) // 3]
        heads.append((np.nonzero(hb)[0].mean() + top) / k)
    bob = max(max(tops) - min(tops), max(heads) - min(heads))
    return {"bob": float(bob), "sil": float(np.mean(sil)), "static_pairs": int(sum(1 for s in sil if s < T["static_eps"]))}


def run_metrics(art, tex_run, tex_idle):
    """复用 tools/run_cycle_review.py 的 metrics（同一口径）。它按 strip_path(op) 找跑步条，
    待机条用 strip_path(op).replace("_run@2x", "_idle@2x")，所以只要换掉 strip_path 即可（待机条名 = 跑步条名把 run 换成 idle）"""
    import run_cycle_review as rcr
    assert tex_idle == tex_run.replace("_run", "_idle"), (tex_run, tex_idle)
    rcr.ART = art
    rcr.strip_path = lambda op, hi=True: os.path.join(art, tex_run + ("@2x" if hi else "") + ".png")
    m = rcr.metrics("__run__")
    fr = rcr.load("__run__", True)
    masks = [f[..., 3] > 0 for f in fr]
    n = len(masks)
    m["static_pairs"] = int(sum(1 for i in range(n) if _move(masks[i], masks[(i + 1) % n]) < T["static_eps"]))
    return m


def foot_est(fr, k):
    """最低不透明行（1x 像素）与最低 2 行（1x）不透明像素的横向中心"""
    ys_all, xs_all = [], []
    for f in fr:
        m = f[..., 3] > 0
        ys = np.nonzero(m.any(axis=1))[0]
        bot = ys.max()
        xs = np.nonzero(m[bot - 2 * k + 1: bot + 1].any(axis=0))[0]
        ys_all.append(bot / k)
        xs_all.append((xs.min() + xs.max() + 1) / 2 / k)
    return float(np.mean(xs_all)), float(max(ys_all))


def tone_metrics(frs):
    px = []
    for f in frs:
        a = f[(f[..., 3] > 0) & ~_is_outline(f)][:, :3].astype(np.float32)
        px.append(a)
    a = np.concatenate(px)
    y = _luma(a)
    hsl = (a.max(1) + a.min(1)) / 510
    gain = ((y >= 40) & (y < 160) & (_luma(np.clip(a * 1.12, 0, 255)) >= 160)).mean()   # L4：角色受光封顶 ×1.12
    return {"hsl": float(hsl.mean()), "dark": float((y < 40).mean()), "bright": float((y >= 160).mean()), "gain": float(gain)}


# ---------------------------------------------------------------- 色调与上一版比（hue，docs/87 §4.3）

def _git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True)
    except OSError:
        return None
    return r.stdout if r.returncode == 0 else None


class PrevVersions:
    """按文件名给出「上一版」帧条：base 给了就取 <base>:<路径>；否则取该文件上一个提交的版本
    （工作区有未提交改动时取 HEAD 版本）。art 目录不在 git 里时，按本仓库的 art/incoming/ 路径解析（只在给了 base 时有用）"""

    def __init__(self, art, base=None, changed=False):
        self.base = base
        self.only = None    # --changed：只比这些文件名
        self.cache = {}
        art = os.path.abspath(art)
        top = _git(["rev-parse", "--show-toplevel"], art) if os.path.isdir(art) else None
        if top:
            self.repo = top.decode().strip()
            self.prefix = (_git(["rev-parse", "--show-prefix"], art) or b"").decode().strip()
            self.in_git = True
        else:
            self.repo, self.prefix, self.in_git = ROOT, "art/incoming/", False
        self.prev = {}      # 文件名 -> 上一版的取法（<提交>:<路径>）
        self.label = {}     # 文件名 -> 说明（哪个提交）
        if changed:
            mb = _git(["merge-base", "HEAD", "main"], self.repo) if self.in_git else None
            self.only = set()
            if mb:
                self.base = mb.decode().strip()
                names = (_git(["diff", "--name-only", self.base, "--", self.prefix or "."], self.repo) or b"").decode("utf-8", "replace").split()
                self.only = {n[len(self.prefix):] if n.startswith(self.prefix) else n for n in names}
            return
        if base:
            return
        if not self.in_git:
            return
        dirty = set((_git(["diff", "--name-only", "HEAD", "--", self.prefix or "."], self.repo) or b"").decode("utf-8", "replace").split())
        log = (_git(["log", "--format=>%H", "--name-only", "--", self.prefix or "."], self.repo) or b"").decode("utf-8", "replace")
        hist, cur = {}, None
        for line in log.splitlines():
            if line.startswith(">"):
                cur = line[1:]
            elif line.strip() and cur:
                hist.setdefault(line.strip(), []).append(cur)
        for path, commits in hist.items():
            fn = path[len(self.prefix):] if path.startswith(self.prefix) else path
            if path in dirty:
                self.prev[fn] = "HEAD:" + path
                self.label[fn] = "HEAD"
            elif len(commits) >= 2:
                self.prev[fn] = commits[1] + ":" + path
                self.label[fn] = commits[1][:8]

    def get(self, fname):
        """返回 (RGBA 数组, 说明) 或 (None, 原因)"""
        if self.only is not None and fname not in self.only:
            return None, "相对 main 未改动"
        if self.base:
            spec, lab = "%s:%s%s" % (self.base, self.prefix, fname), self.base[:8]
        else:
            if fname not in self.prev:
                return None, "没有上一版"
            spec, lab = self.prev[fname], self.label[fname]
        if spec not in self.cache:
            blob = _git(["cat-file", "-p", spec], self.repo)
            self.cache[spec] = np.array(Image.open(io.BytesIO(blob)).convert("RGBA")) if blob else None
        a = self.cache[spec]
        return (a, lab) if a is not None else (None, "%s 里没有这个文件" % lab)


def _hsl(rgb):
    c = rgb.astype(np.float32) / 255.0
    mx, mn = c.max(-1), c.min(-1)
    l = (mx + mn) / 2
    d = mx - mn
    s = np.where(d == 0, 0.0, d / np.maximum(1e-6, 1 - np.abs(2 * l - 1)))
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    h = np.where(mx == r, ((g - b) / np.maximum(d, 1e-6)) % 6, np.where(mx == g, (b - r) / np.maximum(d, 1e-6) + 2, (r - g) / np.maximum(d, 1e-6) + 4)) * 60.0
    return h, np.clip(s, 0, 1), l, d


def hue_shift(new, old):
    """new / old：同一条帧条的两版 RGBA。返回 {mode, n, overlap, match, dh, ds, dl, ds_mean, dl_mean} 或 None（高度对不上）。
    逐像素口径：dh = 彩度加权的平均色相差（度），ds / dl = 饱和 / 明度逐像素绝对差的平均，ds_mean / dl_mean = 带符号平均（新 − 旧）"""
    if new.shape[0] != old.shape[0]:
        return None
    w = min(new.shape[1], old.shape[1])
    a, b = new[:, :w], old[:, :w]
    ma = (a[..., 3] > 0) & ~_is_outline(a)
    mb = (b[..., 3] > 0) & ~_is_outline(b)
    both = ma & mb
    overlap = both.sum() / max(1, max(ma.sum(), mb.sum()))
    if overlap >= T["hue_overlap"]:
        pa, pb = a[both][:, :3], b[both][:, :3]
        h1, s1, l1, c1 = _hsl(pa)
        h0, s0, l0, c0 = _hsl(pb)
        wch = np.minimum(c1, c0) * ((c1 >= T["hue_min_chroma"]) & (c0 >= T["hue_min_chroma"]))
        dh = np.abs((h1 - h0 + 180.0) % 360.0 - 180.0)
        match = float((np.abs(_luma(pa.astype(np.float32)) - _luma(pb.astype(np.float32))) < 40).mean())
        return {"mode": "逐像素", "n": int(both.sum()), "overlap": float(overlap), "match": match,
                "dh": float((dh * wch).sum() / wch.sum()) if wch.sum() > 0 else 0.0,
                "ds": float(np.abs(s1 - s0).mean()), "dl": float(np.abs(l1 - l0).mean()),
                "ds_mean": float((s1 - s0).mean()), "dl_mean": float((l1 - l0).mean())}

    def stat(x, m):   # 姿势重画：整条帧条的统计量
        h, s_, l, c = _hsl(x[m][:, :3])
        wgt = c * (c >= T["hue_min_chroma"])
        ang = np.deg2rad(h)
        mh = math.degrees(math.atan2((np.sin(ang) * wgt).sum(), (np.cos(ang) * wgt).sum())) if wgt.sum() > 0 else 0.0
        return mh, float(s_.mean()), float(l.mean())
    (h1, s1, l1), (h0, s0, l0) = stat(a, ma), stat(b, mb)
    return {"mode": "统计", "n": int(ma.sum()), "overlap": float(overlap), "match": None,
            "dh": abs((h1 - h0 + 180.0) % 360.0 - 180.0), "ds": abs(s1 - s0), "dl": abs(l1 - l0), "ds_mean": s1 - s0, "dl_mean": l1 - l0}


# ---------------------------------------------------------------- 主检查

def _lead(probs, warns):
    if probs:
        return "不达标：" + "、".join(probs + warns) + "；"
    return ("注意：" + "、".join(warns) + "；") if warns else ""


def _body(act, cfg):
    return act in MAIN_ACTS or bool(cfg.get("_body"))


def lint_op(op, acts, art=ART, prev=None):
    R = []

    def add(check, level, value, detail, waiver=None):
        w = WAIVERS.get((op, check)) or waiver
        R.append({"op": op, "check": check, "level": level, "value": value, "detail": detail,
                  "waiver": w if (w and level == "FAIL") else None, "stale_waiver": bool(w and level != "FAIL")})

    strips = {}
    missing = []
    for act, cfg in acts.items():
        lo, hi = load_strip(art, cfg["tex"], False), load_strip(art, cfg["tex"], True)
        if lo is None or hi is None:
            missing.append(cfg["tex"] + ("" if lo is not None else ".png ") + ("" if hi is not None else "@2x.png"))
            continue
        strips[act] = (lo, hi)
    add("files", "FAIL" if missing else "PASS", len(strips), "缺：" + "、".join(missing) if missing else "%d 组 × 1x/@2x" % len(strips))

    # size / frames
    bad = []
    for act, (lo, hi) in strips.items():
        cfg = acts[act]
        h1, h2 = lo.shape[0], hi.shape[0]
        n1, n2 = lo.shape[1] / h1, hi.shape[1] / h2
        if _body(act, cfg) and (h1, h2) != (48, 96):
            bad.append("%s 单帧高 %d/%d（应 48/96）" % (act, h1, h2))
        if h2 != 2 * h1 or n1 != int(n1) or n2 != n1:
            bad.append("%s 尺寸 %dx%d / %dx%d 不成帧条" % (act, lo.shape[1], h1, hi.shape[1], h2))
        if cfg.get("frames") and cfg["frames"] != n1:
            bad.append("%s 帧数 %d ≠ json %d" % (act, n1, cfg["frames"]))
        if cfg.get("fire") is not None and not (0 <= cfg["fire"] < n1):
            bad.append("%s 出手帧 %d 超出 %d 帧" % (act, cfg["fire"], n1))
    add("size", "FAIL" if bad else "PASS", None, "；".join(bad) if bad else "尺寸 / 帧数与 json 一致")

    # pair 1x / @2x
    worst, order_bad = 0.0, []
    for act, (lo, hi) in strips.items():
        f1, f2 = split(lo), split(hi)
        if len(f1) != len(f2):
            continue
        dm = []
        for b in f2:
            mb = (b[..., 3] > 0).reshape(b.shape[0] // 2, 2, b.shape[1] // 2, 2).sum((1, 3)) >= 2
            dm.append([((mb ^ (a[..., 3] > 0)).sum() / max(1, (mb | (a[..., 3] > 0)).sum())) for a in f1])
        dm = np.array(dm)
        worst = max(worst, float(dm.diagonal().max()))
        for i in range(len(f1)):
            if len(f1) > 1 and dm[i].argmin() != i and dm[i].min() < dm[i, i] - 0.02:
                order_bad.append("%s f%d" % (act, i))
    lvl = "FAIL" if worst > T["pair_sil_fail"] else ("WARN" if worst > T["pair_sil_warn"] or order_bad else "PASS")
    add("pair", lvl, round(worst, 3), "@2x 缩到 1x 剪影差最大 %.3f%s" % (worst, ("；帧序对不上：" + "、".join(order_bad)) if order_bad else ""))

    # alpha / outline / colors / magenta
    semi, ring_n, ring_ok, r2_n, r2_ok, mag = 0, 0, 0, 0, 0, 0
    cols = {False: set(), True: set()}
    for act, pair in strips.items():
        if not _body(act, acts[act]):   # 召唤物 / 道具帧条（Mon3tr、人偶等）不算进本人的色数与描边
            continue
        for hi, a in zip((False, True), pair):
            al = a[..., 3]
            semi += int(((al > 0) & (al < 255)).sum())
            m = al > 0
            r = _ring(m)
            ol = _is_outline(a)
            ring_n += int(r.sum())
            ring_ok += int((ol & r).sum())
            if hi:
                r2 = _ring(m & ~r)
                r2_n += int(r2.sum())
                r2_ok += int((ol & r2).sum())
            c = a[m][:, :3]
            cols[hi] |= set(map(tuple, c))
            R_, G_, B_ = (a[..., i].astype(int) for i in range(3))
            # 抠图洋红：R≈B 的紫红（|R−B| < 40）且 G 很低；艾丽妮 (224,56,128) 这类设计用粉红不算
            mag += int((m & (R_ > 90) & (B_ > 90) & (np.abs(R_ - B_) < 40) & (G_ < 0.4 * np.minimum(R_, B_))).sum())
    add("alpha", "FAIL" if semi else "PASS", semi, "半透明像素 %d" % semi)
    r1 = ring_ok / max(1, ring_n)
    r2 = r2_ok / max(1, r2_n)
    lvl = "FAIL" if r1 < 0.99 else ("WARN" if r1 < 1.0 or r2 < 0.98 else "PASS")
    add("outline", lvl, round(r1, 4), "外圈 #080E18 占比 %.4f；@2x 第二圈 %.3f" % (r1, r2))
    nc = max(len(cols[False]), len(cols[True]))
    if nc <= T["colors_max"]:
        lvl = "PASS"
    else:
        lvl = "WARN" if op in LEGACY else "FAIL"
    add("colors", lvl, nc, "1x %d 色 / @2x %d 色%s" % (len(cols[False]), len(cols[True]), "（存量，不卡）" if lvl == "WARN" else ""))
    add("magenta", ("WARN" if op in LEGACY else "FAIL") if mag else "PASS", mag, "洋红残留 %d 像素" % mag)

    idle = strips.get("idle")
    if idle is None:
        return R
    idle1, idle2 = split(idle[0]), split(idle[1])

    # skill_end
    if "skill" in strips:
        s1, s2 = split(strips["skill"][0])[-1], split(strips["skill"][1])[-1]
        e1, e2 = np.array_equal(s1, idle1[0]), np.array_equal(s2, idle2[0])
        d2 = float(np.any(s2 != idle2[0], -1).mean())
        if e1 and e2:
            lvl, det = "PASS", "skill 末帧 = idle f0（1x 与 @2x）"
        elif e2:   # 游戏读 @2x；1x 备用版不同只报 WARN
            lvl, det = "WARN", "@2x 相同，1x 备用版 skill 末帧 ≠ idle f0"
        else:
            lvl = "WARN" if op in LEGACY else "FAIL"
            det = "skill 末帧 ≠ idle f0（@2x 不同像素 %.1f%%%s）" % (d2 * 100, "；存量，重画 idle / skill 时对齐" if lvl == "WARN" else "")
        add("skill_end", lvl, round(d2, 3), det)

    # facing
    comps = {}
    sk_last = split(strips["skill"][1])[-1] if "skill" in strips else None
    if sk_last is not None and not np.array_equal(sk_last, idle2[0]):
        comps["skill 末帧"] = facing_margin(idle2[0], sk_last)
        score, basis = comps["skill 末帧"], "skill 末帧"
    else:
        refs = []
        for act in ("attack", "run"):
            if act in strips:
                refs += [f for f in split(strips[act][1]) if not np.array_equal(f, idle2[0])]
        vals = [facing_margin(idle2[0], f) for f in refs]
        score = float(np.median(vals)) if vals else float("nan")
        basis = "attack + run 帧中位数" + ("（skill 末帧 = idle f0）" if sk_last is not None else "")
    if math.isnan(score):
        add("facing", "WARN", None, "没有可比对的动作帧")
    else:
        lvl = "FAIL" if score < T["facing_fail"] else ("WARN" if score < T["facing_warn"] else "PASS")
        add("facing", lvl, round(score, 2), "头部同向分 %+.2f（依据 %s；< 0 = 待机与动作朝向相反）" % (score, basis))

    # frontal
    if "run" in strips:
        fr = frontal_ratio(idle2, split(strips["run"][1]))
        lvl = "FAIL" if fr < T["frontal_fail"] else ("WARN" if fr < T["frontal_warn"] else "PASS")
        add("frontal", lvl, round(fr, 3), "待机 / 跑步头部对称差比 %.3f（< %.2f = 正面朝前）" % (fr, T["frontal_fail"]))

    # idle breathing
    im = idle_metrics(idle2)
    probs, warns = [], []
    lo_, hi_ = T["idle_bob"]
    if im["sil"] < T["idle_sil"]:          # 定格（docs/73 的问题）：FAIL
        probs.append("剪影变化 %.3f" % im["sil"])
    if im["static_pairs"] > T["idle_static_pairs"]:
        probs.append("几乎相同的相邻帧 %d 对" % im["static_pairs"])
    if not (lo_ <= im["bob"] <= hi_):      # 起伏不在 1–3px：只 WARN（存量里不少靠发梢 / 衣摆呼吸，身体不动）
        warns.append("身体起伏 %.1fpx" % im["bob"])
    add("idle", "FAIL" if probs else ("WARN" if warns else "PASS"), im,
        _lead(probs, warns) + "起伏 %.1fpx 剪影变化 %.3f 停顿对 %d" % (im["bob"], im["sil"], im["static_pairs"]))

    # run
    if "run" in strips:
        rm = run_metrics(art, acts["run"]["tex"], acts["idle"]["tex"])
        probs, warns = [], []
        if rm["move"] < T["run_move"]:
            probs.append("剪影变化 %.3f" % rm["move"])
        if rm["leg_move"] < T["run_leg"]:
            probs.append("腿部变化 %.3f" % rm["leg_move"])
        hb0, hb1 = T["run_head_bob"]
        if not (hb0 <= rm["head_bob"] <= hb1):
            probs.append("头部起伏 %.1fpx" % rm["head_bob"])
        if rm["upper_move"] < T["run_upper"]:
            probs.append("上半身变化 %.3f" % rm["upper_move"])
        if rm["static_pairs"] > T["run_static_pairs"]:
            probs.append("停顿帧 %d 对" % rm["static_pairs"])
        l0, l1 = T["run_lean"]
        sl = T["run_lean_slack"]
        if rm["lean"] < l0 - sl or rm["lean"] > l1 + sl:
            probs.append("前倾 %+.0f°" % rm["lean"])
        elif rm["lean"] < l0 or rm["lean"] > l1:
            warns.append("前倾 %+.0f°" % rm["lean"])
        val = {k: round(rm[k], 4) for k in ("move", "leg_move", "upper_move", "head_bob", "lean", "foot_dx", "static_pairs")}
        add("run", "FAIL" if probs else ("WARN" if warns else "PASS"), val,
            _lead(probs, warns) +
            "剪影 %.3f 腿 %.3f 上身 %.3f 头起伏 %.1fpx 前倾 %+.0f° 停顿 %d" % (rm["move"], rm["leg_move"], rm["upper_move"], rm["head_bob"], rm["lean"], rm["static_pairs"]))

    # ground：脚底贴第 46 行（@2x 92）。待机每帧贴地；其他动作至少一帧贴地，跑步每帧离地 ≤ 3px
    gf, gw, gv, gwv = [], [], {}, []
    for act, (lo, hi) in strips.items():
        if not _body(act, acts[act]):
            continue
        sw = WAIVERS.get((op, "ground", act))
        jy = acts[act]["foot"][1]
        bots = [int(np.nonzero((f[..., 3] > 0).any(axis=1))[0].max()) // 2 for f in split(hi)]
        gv[act] = "".join(str(b - 40) if 0 <= b - 40 <= 9 else "?" for b in bots)
        if act == "idle" and any(b != jy for b in bots):
            gf.append("idle 最低行 %s（应每帧 = %d）" % (bots, jy))
        elif max(bots) != jy:
            if sw:
                gwv.append(act)
            else:
                gf.append("%s 没有一帧贴地（最低行 %s，应有 = %d）" % (act, bots, jy))
        elif act == "run" and min(bots) < jy - 3:
            gw.append("run 有帧离地 %dpx" % (jy - min(bots)))
    det = "；".join(gf + gw) if (gf or gw) else "脚底贴第 46 行（每帧最低行 − 40：%s）" % " ".join("%s %s" % (k, v) for k, v in gv.items())
    if gwv:
        det += "；单条豁免离地：" + "、".join(gwv)
    if gf or not gwv:
        add("ground", "FAIL" if gf else ("WARN" if gw else "PASS"), gv, det)
    else:   # 只有单条豁免的帧条离地：记 FAIL*（其余帧条全部贴地）
        add("ground", "FAIL", gv, det, "；".join("%s：%s" % (a, WAIVERS[(op, "ground", a)]) for a in gwv))

    # foot：脚底中心 x 与 json foot 偏差（只 WARN：json 的 foot 是接入时为站跑衔接手调的）
    fw = []
    fv = {}
    for act, (lo, hi) in strips.items():
        if act not in ("idle", "run"):
            continue
        fx, fy = foot_est(split(hi), 2)
        jx, jy = acts[act]["foot"]
        fv[act] = [round(fx, 1), round(fy, 1)]
        if abs(fx - jx) > T["foot_tol"]:
            fw.append("%s 量得 x %.1f vs json %d" % (act, fx, jx))
    add("foot", "WARN" if fw else "PASS", fv, "；".join(fw) if fw else "脚底中心与 json 偏差 ≤ %.0fpx" % T["foot_tol"])

    # tone
    tm = tone_metrics(idle2)
    t = dict(T)
    t.update(TONE_OVERRIDE.get(op, {}))
    tw = []
    if not (t["tone_hsl"][0] <= tm["hsl"] <= t["tone_hsl"][1]):
        tw.append("HSL 明度 %.3f" % tm["hsl"])
    if tm["dark"] < t["tone_dark_min"]:
        tw.append("近黑 %.0f%%" % (tm["dark"] * 100))
    if not (t["tone_bright"][0] <= tm["bright"] <= t["tone_bright"][1]):
        tw.append("亮部 %.0f%%" % (tm["bright"] * 100))
    if tm["gain"] > t["tone_gain_max"]:
        tw.append("受光变亮 %.0f%%" % (tm["gain"] * 100))
    add("tone", "WARN" if tw else "PASS", {k: round(v, 3) for k, v in tm.items()},
        ("超出通用范围：" + "、".join(tw) + "；") * bool(tw) +
        "HSL %.3f 近黑 %.0f%% 亮部 %.0f%% 受光变亮 %.0f%%" % (tm["hsl"], tm["dark"] * 100, tm["bright"] * 100, tm["gain"] * 100))

    # hue：与上一版比色调（docs/87 §4.3）；只查本人身体的帧条（四组动作 + 技能动作组）
    if prev is not None:
        hv, hw, skipped, labs = {}, [], 0, set()
        for act, (lo, hi) in strips.items():
            if not _body(act, acts[act]):
                continue
            for arr, suf in ((lo, ""), (hi, "@2x")):
                old, lab = prev.get(acts[act]["tex"] + suf + ".png")
                if old is None:
                    skipped += 1
                    continue
                m = hue_shift(arr, old)
                if m is None:
                    hw.append("%s%s 尺寸与上一版（%s）不同，未比" % (act, suf, lab))
                    continue
                labs.add(lab)
                key = act + suf
                hv[key] = {k: (round(v, 3) if isinstance(v, float) else v) for k, v in m.items()}
                over = []
                if m["dh"] > T["hue_deg"]:
                    over.append("色相 %.1f°" % m["dh"])
                if m["ds"] > T["hue_sat"]:
                    over.append("饱和 %.3f（平均 %+.3f）" % (m["ds"], m["ds_mean"]))
                if m["dl"] > T["hue_light"]:
                    over.append("明度 %.3f（平均 %+.3f）" % (m["dl"], m["dl_mean"]))
                if over:
                    how = "统计，重合 %.0f%%" % (m["overlap"] * 100) if m["mode"] == "统计" else (
                        "逐像素" + ("，亮度对上仅 %.0f%%，像是重画了姿势" % (m["match"] * 100) if m["match"] < T["hue_redraw"] else ""))
                    hw.append("%s（%s）%s" % (key, how, " ".join(over)))
        if not hv and not hw:
            add("hue", "SKIP", None, "没有上一版，跳过")
        else:
            worst = max(hv.values(), key=lambda m: max(m["dh"] / T["hue_deg"], m["ds"] / T["hue_sat"], m["dl"] / T["hue_light"])) if hv else None
            base = "与 %s 比" % "、".join(sorted(labs)) if labs else ""
            summ = ("最大：色相 %.1f° 饱和 %.3f 明度 %.3f（%s）" % (worst["dh"], worst["ds"], worst["dl"], worst["mode"])) if worst else ""
            add("hue", "WARN" if hw else "PASS", hv,
                ("色调偏移超线（色相 > %.0f° / 饱和 > %.2f / 明度 > %.2f）：" % (T["hue_deg"], T["hue_sat"], T["hue_light"]) + "；".join(hw) + "。") * bool(hw) +
                base + ("，" if base and summ else "") + summ + ("（%d 条帧条没有上一版，未比）" % skipped if skipped else ""))
    return R


# ---------------------------------------------------------------- 对照图

def _font(sz):
    for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def compare_image(op, acts, art, path, sc=2):
    BG = (38, 52, 66, 255)
    f14 = _font(13)
    cells = []

    def cell(arr, label, mark=None):
        im = Image.fromarray(arr).resize((arr.shape[1] * sc, arr.shape[0] * sc), Image.NEAREST)
        c = Image.new("RGBA", (im.width, im.height + 18), BG)
        c.alpha_composite(im, (0, 18))
        d = ImageDraw.Draw(c)
        d.text((3, 1), label, fill=(235, 240, 245, 255) if not mark else (255, 120, 120, 255), font=f14)
        d.line([(0, 18 + 93 * sc - 1), (c.width, 18 + 93 * sc - 1)], fill=(0, 200, 200, 255))
        return c

    def strip(o, act):
        cfg = roster().get(o, {}).get(act) if o != op else acts.get(act)
        if not cfg:
            return None
        a = load_strip(art, cfg["tex"], True)
        return split(a) if a is not None else None

    row1 = []
    for act in MAIN_ACTS:
        fr = strip(op, act)
        if not fr:
            continue
        i = len(fr) - 1 if act == "skill" else (acts[act].get("fire", 0) if act == "attack" else 0)
        row1.append(cell(fr[i], "%s %s f%d" % (NAMES.get(op, op), act, i)))
    for r in REF_OPS:
        if r == op:
            continue
        fr = strip(r, "idle")
        if fr:
            row1.append(cell(fr[0], "参考 %s idle" % NAMES.get(r, r)))
    row2 = []
    for act in ("idle", "run"):
        fr = strip(op, act) or []
        row2 += [cell(f, "%s f%d" % (act, i)) for i, f in enumerate(fr)]
    rows = [row1, row2]
    W = max(sum(c.width + 4 for c in r) for r in rows if r)
    H = sum((r[0].height + 6) for r in rows if r)
    can = Image.new("RGBA", (W, H), (20, 24, 30, 255))
    y = 0
    for r in rows:
        if not r:
            continue
        x = 0
        for c in r:
            can.alpha_composite(c, (x, y))
            x += c.width + 4
        y += r[0].height + 6
    can.convert("RGB").save(path)


# ---------------------------------------------------------------- 输出

ORDER = ["files", "size", "pair", "alpha", "outline", "colors", "magenta", "skill_end", "facing", "frontal", "idle", "run", "ground", "foot", "tone", "hue"]
CN = {"files": "齐全", "size": "尺寸帧数", "pair": "1x/@2x", "alpha": "透明", "outline": "描边", "colors": "色数", "magenta": "洋红",
      "skill_end": "技末=待机", "facing": "朝向", "frontal": "非正面", "idle": "待机呼吸", "run": "跑步", "ground": "贴地", "foot": "脚底x", "tone": "明度", "hue": "色调"}


def _mark(r):
    if r is None or r["level"] == "SKIP":
        return "—"
    if r["level"] == "FAIL" and r["waiver"]:
        return "FAIL*"
    return r["level"]


def run(ops=None, art=ART, images=True, quiet=False, base=None, hue=True, changed=False):
    ro = roster()
    ids = ops or list(ro)
    res = []
    prev = PrevVersions(art, base, changed) if hue else None
    for op in ids:
        if op not in ro:
            res.append({"op": op, "check": "files", "level": "FAIL", "value": None, "detail": "名单里没有这个 id", "waiver": None, "stale_waiver": False})
            continue
        res += lint_op(op, ro[op], art, prev)
    if images:
        os.makedirs(OUT, exist_ok=True)
        for op in ids:
            if op in ro:
                try:
                    compare_image(op, ro[op], art, os.path.join(OUT, "compare_%s.png" % op))
                except Exception as e:  # 对照图失败不影响判定
                    if not quiet:
                        print("对照图 %s 失败：%s" % (op, e))
    return ids, res


def summarize(ids, res):
    by = {(r["op"], r["check"]): r for r in res}
    fails = [r for r in res if r["level"] == "FAIL" and not r["waiver"]]
    waived = [r for r in res if r["level"] == "FAIL" and r["waiver"]]
    warns = [r for r in res if r["level"] == "WARN"]
    stale = [r for r in res if r["stale_waiver"]]
    return by, fails, waived, warns, stale


def table(ids, by):
    head = "| 干员 | " + " | ".join(CN[c] for c in ORDER) + " |"
    lines = [head, "|---|" + "---|" * len(ORDER)]
    for op in ids:
        lines.append("| %s | " % NAMES.get(op, op) + " | ".join(_mark(by.get((op, c))) for c in ORDER) + " |")
    return "\n".join(lines)


def report_md(ids, res):
    by, fails, waived, warns, stale = summarize(ids, res)
    out = ["# art_lint 报告", "", "规格：docs/87。FAIL* = 已豁免（WAIVERS：有返修单未交付，或已登记待定的新发现）。", "", table(ids, by), ""]
    for title, rows in (("未豁免 FAIL", fails), ("已豁免 FAIL", waived), ("WARN", warns)):
        out.append("## %s（%d）" % (title, len(rows)))
        out.append("")
        for r in rows:
            out.append("- %s · %s：%s%s" % (NAMES.get(r["op"], r["op"]), CN[r["check"]], r["detail"], ("　〔豁免：%s〕" % r["waiver"]) if r["waiver"] else ""))
        out.append("")
    if stale:
        out.append("## 豁免可删（已通过）")
        out.append("")
        for r in stale:
            out.append("- %s · %s：%s" % (NAMES.get(r["op"], r["op"]), CN[r["check"]], WAIVERS[(r["op"], r["check"])]))
        out.append("")
    out.append("## 明细")
    out.append("")
    for op in ids:
        out.append("### %s `%s`" % (NAMES.get(op, op), op))
        out.append("")
        for c in ORDER:
            r = by.get((op, c))
            if r:
                out.append("- %s **%s**：%s" % (CN[c], _mark(r), r["detail"]))
        out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ops", help="逗号分隔的 id；缺省全部")
    ap.add_argument("--art", default=ART, help="帧条目录（缺省 art/incoming）")
    ap.add_argument("--json", help="另写一份 JSON 结果到这个路径")
    ap.add_argument("--no-images", action="store_true", help="不出对照图")
    ap.add_argument("--base", help="hue 项与这个提交里的同名帧条比（缺省：每个文件在 git 里的上一个版本）")
    ap.add_argument("--changed", action="store_true", help="hue 项只比相对 main 分叉点改过的帧条（上一版取分叉点）")
    a = ap.parse_args()
    ids, res = run(a.ops.split(",") if a.ops else None, a.art, not a.no_images, base=a.base, changed=a.changed)
    by, fails, waived, warns, stale = summarize(ids, res)
    print(table(ids, by))
    print()
    for r in fails:
        print("FAIL  %s · %s：%s" % (NAMES.get(r["op"], r["op"]), CN[r["check"]], r["detail"]))
    for r in waived:
        print("FAIL* %s · %s：%s〔豁免：%s〕" % (NAMES.get(r["op"], r["op"]), CN[r["check"]], r["detail"], r["waiver"]))
    for r in warns:
        print("WARN  %s · %s：%s" % (NAMES.get(r["op"], r["op"]), CN[r["check"]], r["detail"]))
    for r in stale:
        print("豁免可删 %s · %s" % (NAMES.get(r["op"], r["op"]), CN[r["check"]]))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "report.md"), "w", encoding="utf-8").write(report_md(ids, res))
    if a.json:
        json.dump({"spec": "docs/87", "ok": not fails, "results": res}, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1, default=str)
    print("\n%s：%d 人，未豁免 FAIL %d、已豁免 FAIL %d、WARN %d。报告 %s" % ("通过" if not fails else "不通过", len(ids), len(fails), len(waived), len(warns), os.path.join(OUT, "report.md")))
    return 1 if fails else 0


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
