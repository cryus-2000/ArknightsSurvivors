"""认知塑造树视觉样图（docs/125 §8，10-22 用户反馈 build/ui_ref/meta_tree_feedback_1022.md：①颜色太沉重 ②背景要像素几何慢速流动）。

只出样图、不改游戏代码。结构沿用现稿（build/ui_ref/meta_tree_ref_1022.png）：左栏 认知塑造 / 生机细胞 / 当前节点，右侧「塑造图谱」，底栏 确认塑造。
数据读 game/data/meta_tree.json（31 节点 9 条链 = 8 线，资源线分收藏癖 / 交涉两链）。
  A = 深蓝黑底 + 青白线（最接近现稿、减重）     流动层：像素细网格 + 菱形碎片两层视差
  B = 左白右黑斜切（寻访同款）                   流动层：像素等高线两层视差
  C = 浅灰白底「图纸感」（罗德岛终端）           流动层：蓝图网格 + 尺规刻度两层视差
  D = 中明度石板蓝 + 三角碎片视差               流动层：低多边形三角碎片两层视差
每版另出 3 帧流动示意（0 / 4 / 8 秒，图谱区裁切）与 gif（流速 ×4 方便看）；招牌动效「解锁枝条长亮」出一张 gif + 4 帧条。
用法：python -X utf8 tools/probes/meta_tree_mock.py
输出：主仓库 build/ak_mock/meta_tree_{A,B,C,D}.png、meta_tree_{A..D}_flow.png / .gif、meta_tree_unlock.gif / _unlock.png、总览 meta_tree_sheet.jpg
"""
import json
import math
import os
import re
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_gc = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
COMMON = os.path.dirname(_gc if os.path.isabs(_gc) else os.path.join(ROOT, _gc))
OUT = os.path.join(COMMON, "build", "ak_mock")
FONT = os.path.join(ROOT, "game", "fonts", "ui.ttf")
TREE = json.load(open(os.path.join(ROOT, "game", "data", "meta_tree.json"), encoding="utf8"))
NODES = TREE["nodes"]
W, H = 1280, 720
PX = 3            # 背景几何层的像素粒度（1 像素 = 3 屏幕像素）
GX0, GY0, GX1, GY1 = 372, 64, 1280, 652   # 图谱区

_src = open(os.path.join(ROOT, "game", "scripts", "screens", "tide_ui.gd"), encoding="utf8").read()
GLYPHS = {m.group(1): [int(x, 16) for x in m.group(2).split()] for m in re.finditer(r'"(.)": "([0-9A-F ]{20})"', _src)}

# 每条链：线名、英文、末节质变短句（取自 meta_tree.json 末节 desc 的规则部分，界面上做小标签）
CHAINS = [
    ("disp", "调度", "DISPATCH", "开局藏品"),
    ("shop", "资源", "TRADE", "行商 -15%"),
    ("gold", "资源", "SUPPLY", "源石锭 +10"),
    ("xp", "经验", "INSIGHT", "升级再升"),
    ("sh", "护盾", "SHIELD", "碎盾反震"),
    ("atk", "攻击", "OFFENSE", "处决"),
    ("hp", "生命", "VITALITY", "濒死免死"),
    ("def", "减伤", "GUARD", "久守减伤"),
    ("reg", "回复", "RECOVERY", "低血翻倍"),
]
DONE = set(TREE["order"][:12])       # 样图状态：按推荐点法点了前 12 个
SEL = "hp4"                          # 选中：生存本能Ⅳ（可塑造）
CELLS = 65


def chain_ids(p):
    return sorted([k for k in NODES if re.fullmatch(p + r"\d", k)], key=lambda k: int(k[len(p):]))


from fontTools.ttLib import TTFont
_CMAP = TTFont(FONT).getBestCmap()
FALLBACK = "C:/Windows/Fonts/msyh.ttc"   # ui.ttf 缺「癖」（游戏里同样缺字，见 docs/125 §8.6）；样图用系统雅黑兜底


def font(sz, s=""):
    if any(ord(c) not in _CMAP for c in s) and os.path.exists(FALLBACK):
        return ImageFont.truetype(FALLBACK, sz)
    return ImageFont.truetype(FONT, sz)


def layout():
    """根在图谱区底部中央；九条链各占一列向上生长（相邻列错半格），越靠两侧越向外斜（像枝条）"""
    rx, ry = (GX0 + GX1) / 2, GY1 - 26
    pos = {"root": (rx, ry)}
    n = len(CHAINS)
    gap = 86
    for i, (p, *_r) in enumerate(CHAINS):
        c = i - (n - 1) / 2
        x = rx + c * gap
        y = GY1 - 112 - (i % 2) * 30 - (4 - abs(c)) * 6
        for j, k in enumerate(chain_ids(p)):
            pos[k] = (x + c * 3 * j, y - j * 92)
    return pos


POS = layout()


def state(k):
    if k in DONE:
        return "done"
    req = NODES[k].get("req")
    return "open" if (req is None or req in DONE) else "lock"


# ---------------- 背景几何层（numpy 低分辨率画，再 NEAREST 放大成像素） ----------------
LW, LH = W // PX, H // PX
YY, XX = np.mgrid[0:LH, 0:LW].astype(np.float32)


def lay_grid(t, speed, cell, phase=0.0):
    """细网格：沿右上方向漂移"""
    ox, oy = t * speed / PX, -t * speed * 0.5 / PX
    gx = ((XX - ox + phase) % cell) < 1
    gy = ((YY - oy + phase) % cell) < 1
    return (gx | gy).astype(np.float32)


def lay_diamonds(t, speed, cell, seed):
    """菱形碎片：稀疏格点上的空心小菱形，随种子取舍"""
    ox, oy = t * speed / PX, -t * speed * 0.5 / PX
    u, v = XX - ox, YY - oy
    cx, cy = np.floor(u / cell), np.floor(v / cell)
    h = np.sin(cx * 12.9898 + cy * 78.233 + seed) * 43758.5453
    h = h - np.floor(h)
    lx, ly = u - cx * cell - cell / 2, v - cy * cell - cell / 2
    r = 2 + (h * 4).astype(np.int32)
    d = np.abs(lx) + np.abs(ly)
    return ((h > 0.62) & (np.abs(d - r) < 0.6)).astype(np.float32)


def lay_contour(t, speed, scale, seed, bands=9):
    """等高线：几层正弦叠成的标量场，取分层边界；整体漂移"""
    ox, oy = t * speed / PX, -t * speed * 0.4 / PX
    u, v = (XX - ox) / scale, (YY - oy) / scale
    f = (np.sin(u * 1.3 + seed) + np.sin(v * 1.7 - seed * 0.7) + np.sin((u + v) * 0.9 + seed * 1.9) * 0.8
         + np.sin(math.cos(seed) * u * 2.3 - v * 0.6) * 0.5)
    q = f * bands / 4.0
    fr = q - np.floor(q)
    gy, gx = np.gradient(q)
    g = np.sqrt(gx * gx + gy * gy) + 1e-4
    return (np.minimum(fr, 1 - fr) / g < 0.4).astype(np.float32)


def lay_ruler(t, speed):
    """尺规刻度：横向长线 + 每 8 格短刻度、每 40 格长刻度"""
    ox = t * speed / PX
    u = XX - ox
    m = np.zeros_like(XX)
    rows = (YY % 48) == 0
    m[rows] = 1
    tick = ((u % 8) < 1) & ((YY % 48) < 3)
    tick2 = ((u % 40) < 1) & ((YY % 48) < 7)
    return np.clip(m * 0 + tick + tick2 + ((YY % 48) == 0) * ((u % 4) < 2), 0, 1).astype(np.float32)


def lay_tris(t, speed, cell, seed, fill):
    """三角碎片：斜格三角剖分，少数三角亮起（fill=True 填色、False 只描边）"""
    ox, oy = t * speed / PX, -t * speed * 0.35 / PX
    u, v = XX - ox, YY - oy
    a = u + v * 0.577
    b = v * 1.155
    ca, cb = np.floor(a / cell), np.floor(b / cell)
    fa, fb = a / cell - ca, b / cell - cb
    up = (fa + fb) < 1
    h = np.sin(ca * 12.9898 + cb * 78.233 + up * 3.1 + seed) * 43758.5453
    h = h - np.floor(h)
    on = h > (0.80 if fill else 0.55)
    if fill:
        return (on * (0.5 + 0.5 * h)).astype(np.float32)
    e = np.minimum(np.minimum(fa, fb), np.abs(1 - fa - fb))
    return (on & (e * cell < 0.9)).astype(np.float32)


def sel_boost():
    """选中节点周围的几何线微微提亮（半径约 150 屏幕像素）"""
    sx, sy = POS[SEL]
    d = np.sqrt((XX - sx / PX) ** 2 + (YY - sy / PX) ** 2) * PX
    return 1.0 + 1.3 * np.clip(1 - d / 150, 0, 1)


BOOST = sel_boost()


def compose_bg(base, layers):
    """base = RGB 底色；layers = [(mask, rgb, alpha)]；返回 RGBA 全屏图"""
    arr = np.zeros((LH, LW, 3), np.float32)
    arr[:] = base
    for m, col, a in layers:
        k = np.clip(m * a * BOOST, 0, 1)[..., None]
        arr = arr * (1 - k) + np.array(col, np.float32) * k
    im = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").resize((LW * PX, LH * PX), Image.NEAREST)
    return im.crop((0, 0, W, H)).convert("RGBA")


# ---------------- 版式配置 ----------------
V = {
    "A": dict(base=(14, 26, 44), panel=(22, 38, 60, 235), panel_ink=(236, 242, 248), sub=(140, 162, 186),
              line_done=(226, 246, 255), line_open=(84, 214, 244), line_lock=(70, 98, 128), node_done=(255, 240, 214),
              node_open=(84, 214, 244), node_lock=(78, 104, 134), label=(214, 228, 240), label_lock=(108, 132, 160),
              accent=(96, 226, 255), bar=(10, 18, 32), title_bg=(240, 244, 248), title_ink=(14, 22, 36),
              name="A 深蓝 · 网格菱形", desc="底 #0E1A2C（比现稿抬 2 档）· 青白线 · 流动层：像素细网格 + 菱形碎片"),
    "B": dict(base=(19, 23, 30), panel=None, panel_ink=(17, 19, 24), sub=(96, 102, 112),
              line_done=(232, 246, 255), line_open=(56, 214, 240), line_lock=(70, 84, 100), node_done=(255, 240, 214),
              node_open=(56, 214, 240), node_lock=(80, 92, 108), label=(220, 226, 234), label_lock=(110, 120, 134),
              accent=(24, 150, 214), bar=(12, 14, 18), title_bg=(17, 19, 24), title_ink=(240, 242, 246),
              name="B 斜切 · 等高线", desc="左浅灰右暗场斜切（寻访同款）· 流动层：像素等高线两层"),
    "C": dict(base=(232, 236, 240), panel=(246, 248, 250, 240), panel_ink=(16, 22, 32), sub=(108, 120, 136),
              line_done=(18, 110, 196), line_open=(36, 170, 220), line_lock=(170, 186, 204), node_done=(18, 96, 176),
              node_open=(36, 170, 220), node_lock=(176, 190, 206), label=(24, 40, 60), label_lock=(140, 154, 172),
              accent=(18, 120, 210), bar=(20, 26, 34), title_bg=(16, 22, 32), title_ink=(246, 248, 250),
              name="C 图纸 · 蓝图网格", desc="浅灰白底 · 青蓝线 · 流动层：蓝图网格 + 尺规刻度（罗德岛终端）"),
    "D": dict(base=(34, 52, 74), panel=(240, 243, 246, 245), panel_ink=(17, 22, 30), sub=(104, 114, 128),
              line_done=(236, 248, 255), line_open=(98, 224, 250), line_lock=(92, 120, 150), node_done=(255, 236, 200),
              node_open=(98, 224, 250), node_lock=(100, 126, 156), label=(226, 236, 246), label_lock=(130, 152, 178),
              accent=(24, 130, 214), bar=(16, 22, 32), title_bg=(17, 22, 30), title_ink=(244, 246, 248),
              name="D 石板蓝 · 三角碎片", desc="中明度石板蓝 #22344A · 白面板 · 流动层：三角碎片填色 + 描边两层视差"),
}


def bg_for(v, t):
    if v == "A":
        return compose_bg(V["A"]["base"], [(lay_grid(t, 2, 16), (120, 210, 240), 0.10),
                                           (lay_diamonds(t, 4, 22, 1.7), (200, 240, 255), 0.15)])
    if v == "B":
        return compose_bg(V["B"]["base"], [(lay_contour(t, 2, 26, 0.3, 7), (120, 210, 240), 0.08),
                                           (lay_contour(t, 4, 15, 2.1, 6), (200, 240, 255), 0.11)])
    if v == "C":
        return compose_bg(V["C"]["base"], [(lay_grid(t, 2, 8), (120, 160, 200), 0.12),
                                           (lay_grid(t, 2, 40, 1), (40, 130, 210), 0.15),
                                           (lay_ruler(t, 4), (40, 130, 210), 0.12)])
    return compose_bg(V["D"]["base"], [(lay_tris(t, 2, 34, 0.9, True), (120, 190, 230), 0.12),
                                       (lay_tris(t, 4, 20, 4.2, False), (210, 240, 255), 0.13)])


# ---------------- 文字 / 像素字 ----------------
def text(d, xy, s, sz, col, anchor="la", bold=False):
    f = font(sz, s)
    d.text(xy, s, font=f, fill=col, anchor=anchor, **({"stroke_width": 1, "stroke_fill": col} if bold and sz >= 30 else {}))


def px_text(d, xy, s, k, col):
    x, y0 = xy
    for ch in s.upper():
        g = GLYPHS.get(ch)
        if g:
            for r in range(7):
                for cc in range(5):
                    if g[r] & (1 << (4 - cc)):
                        d.rectangle([x + cc * k, y0 + r * k, x + cc * k + k - 1, y0 + r * k + k - 1], fill=col)
        x += (3 if ch == " " else 6) * k
    return x - xy[0]


def px_line(d, a, b, col, w, dash=0):
    """像素感直线：按 2 px 方块步进（dash>0 时间隔取段）"""
    (x0, y0), (x1, y1) = a, b
    n = max(1, int(math.hypot(x1 - x0, y1 - y0) / 2))
    for i in range(n + 1):
        if dash and (i // dash) % 2:
            continue
        x = round((x0 + (x1 - x0) * i / n) / 2) * 2
        y = round((y0 + (y1 - y0) * i / n) / 2) * 2
        d.rectangle([x - w // 2, y - w // 2, x - w // 2 + w - 1, y - w // 2 + w - 1], fill=col)


# ---------------- 节点图标 ----------------
def icon(d, c, p, col, s=7):
    x, y = c
    if p == "atk":
        d.line([(x - s, y - s), (x + s, y + s)], fill=col, width=2)
        d.line([(x + s, y - s), (x - s, y + s)], fill=col, width=2)
    elif p == "hp":
        d.line([(x - s, y), (x - s / 3, y), (x - s / 6, y - s), (x + s / 6, y + s), (x + s / 3, y), (x + s, y)], fill=col, width=2)
    elif p == "def":
        d.polygon([(x - s, y - s), (x + s, y - s), (x + s, y), (x, y + s), (x - s, y)], outline=col, width=2)
    elif p == "reg":
        d.rectangle([x - 1, y - s, x + 1, y + s], fill=col)
        d.rectangle([x - s, y - 1, x + s, y + 1], fill=col)
    elif p == "sh":
        d.regular_polygon((x, y, s + 1), 6, outline=col, width=2)
    elif p == "xp":
        for o in (-4, 3):
            d.line([(x - s, y + o + 3), (x, y + o - 4), (x + s, y + o + 3)], fill=col, width=2)
    elif p == "gold":
        d.polygon([(x, y - s), (x + s * 0.7, y), (x, y + s), (x - s * 0.7, y)], outline=col, width=2)
    elif p == "shop":
        d.ellipse([x - s, y - s, x + s, y + s], outline=col, width=2)
        d.rectangle([x - 1, y - s + 3, x + 1, y + s - 3], fill=col)
    elif p == "disp":
        for i in range(2):
            for j in range(2):
                d.rectangle([x - s + i * (s + 1), y - s + j * (s + 1), x - 1 + i * (s + 1), y - 1 + j * (s + 1)], outline=col)


def node(d, k, cfg, t=0.0, lit=None):
    """lit = 解锁演出进度（None = 静态）"""
    x, y = POS[k]
    p = re.match(r"[a-z]+", k).group(0)
    st = state(k) if lit is None else ("done" if lit >= 0.55 else "open")
    last = k == chain_ids(p)[-1]
    r = 15 if not last else 17
    pts = ([(x, y - r - 3), (x + r + 3, y), (x, y + r + 3), (x - r - 3, y)] if last
           else [(x - r, y - r * 0.5), (x - r * 0.5, y - r), (x + r * 0.5, y - r), (x + r, y - r * 0.5),
                 (x + r, y + r * 0.5), (x + r * 0.5, y + r), (x - r * 0.5, y + r), (x - r, y + r * 0.5)])
    bgc = cfg["base"]
    if st == "done":
        d.polygon(pts, fill=cfg["node_done"])
        icon(d, (x, y), p, (30, 40, 56) if cfg is not V["C"] else (246, 248, 250))
    elif st == "open":
        breath = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 1.6)
        d.polygon(pts, fill=bgc)
        ring = [(x + (px - x) * (1.25 + 0.12 * breath), y + (py - y) * (1.25 + 0.12 * breath)) for px, py in pts]
        d.polygon(ring, outline=tuple(int(c * (0.45 + 0.3 * breath) + b * (0.55 - 0.3 * breath)) for c, b in zip(cfg["node_open"], bgc)), width=1)
        d.polygon(pts, outline=cfg["node_open"], width=2)
        icon(d, (x, y), p, cfg["node_open"])
    else:
        d.polygon(pts, fill=bgc, outline=cfg["node_lock"], width=1)
        icon(d, (x, y), p, cfg["node_lock"], 6)
    if k == SEL and lit is None:
        q = r + 12
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            d.line([(x + sx * q, y + sy * q), (x + sx * (q - 7), y + sy * q)], fill=cfg["accent"], width=2)
            d.line([(x + sx * q, y + sy * q), (x + sx * q, y + sy * (q - 7))], fill=cfg["accent"], width=2)
    nm = NODES[k]["name"]
    lc = cfg["label"] if st != "lock" else cfg["label_lock"]
    text(d, (x, y + r + 8), nm, 13, lc, "ma", bold=(k == SEL))


def edges(d, cfg, lit=None):
    """lit = (k, 进度)：该节点的进枝条从父节点长亮"""
    rx, ry = POS["root"]
    for p, *_r in CHAINS:
        prev = "root"
        for k in chain_ids(p):
            a, b = POS[prev], POS[k]
            st = state(k)
            if lit and lit[0] == k:
                px_line(d, a, b, cfg["line_lock"], 2, dash=2)
            elif st == "done":
                px_line(d, a, b, cfg["line_done"], 4)
            elif st == "open":
                px_line(d, a, b, cfg["line_open"], 2, dash=3)
            else:
                px_line(d, a, b, cfg["line_lock"], 2, dash=2 if prev == "root" else 0)
            prev = k
    if lit:
        k, f = lit
        a, b = POS[NODES[k].get("req") or "root"], POS[k]
        g = min(1.0, f / 0.55)
        m = (a[0] + (b[0] - a[0]) * g, a[1] + (b[1] - a[1]) * g)
        px_line(d, a, m, cfg["line_done"], 4)
        if g < 1:   # 光头：亮点 + 尾迹
            d.ellipse([m[0] - 7, m[1] - 7, m[0] + 7, m[1] + 7], fill=(255, 255, 255))
        if f > 0.55:   # 解锁后：节点外扩环 + 整条链从根部往上扫一道亮
            e = (f - 0.55) / 0.45
            rr = 18 + 34 * e
            col = tuple(int(c * (1 - e) + bb * e) for c, bb in zip(cfg["line_open"], cfg["base"]))
            d.ellipse([b[0] - rr, b[1] - rr, b[0] + rr, b[1] + rr], outline=col, width=2)
    # 根：认知核心
    d.regular_polygon((rx, ry, 20), 4, rotation=45, fill=cfg["base"], outline=cfg["line_done"], width=2)
    d.regular_polygon((rx, ry, 9), 4, rotation=45, fill=cfg["line_done"])


def chain_labels(d, cfg):
    for p, cn, en, rule in CHAINS:
        ids = chain_ids(p)
        x, y = POS[ids[-1]]
        lx, ly = x, y - 40
        col = cfg["accent"]
        f = font(12, rule)
        tw = ImageDraw.Draw(Image.new("L", (1, 1))).textlength(rule, font=f)
        bx = lx - tw / 2 - 7
        # 质变短句：小斜块标签（末节 = 质变，菱形节点）
        d.polygon([(bx + 4, ly - 10), (bx + tw + 14, ly - 10), (bx + tw + 10, ly + 10), (bx, ly + 10)], outline=col, width=1)
        d.text((bx + 7, ly - 8), rule, font=f, fill=col)
        text(d, (lx, ly - 28), cn, 12, cfg["label_lock"], "ma")


# ---------------- 左栏 / 顶栏 / 底栏 ----------------
def left_panel(img, cfg, v):
    d = ImageDraw.Draw(img)
    if v == "B":
        d.polygon([(0, 0), (400, 0), (340, H), (0, H)], fill=(223, 226, 230))
        d.line([(400, 0), (340, H)], fill=(56, 214, 240), width=2)
    elif v == "C":
        d.rectangle([0, 0, 352, H], fill=(246, 248, 250))
        d.line([(352, 0), (352, H)], fill=(18, 120, 210), width=2)
        for yy in range(0, H, 6):
            d.point((356, yy), fill=(18, 120, 210))
    else:
        ov = Image.new("RGBA", img.size, (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        if v == "D":
            od.polygon([(0, 0), (372, 0), (342, H), (0, H)], fill=cfg["panel"])
        else:
            od.rectangle([0, 0, 352, H], fill=cfg["panel"])
            od.line([(352, 0), (352, H)], fill=(84, 214, 244, 160), width=1)
        img.alpha_composite(ov)
    ink, sub, acc = cfg["panel_ink"], cfg["sub"], cfg["accent"]
    # 标题块：反色斜块（反馈：白底黑字反色；B / C / D 面板是浅色，标题块用黑底白字）
    d.polygon([(28, 70), (300, 70), (288, 124), (16, 124)], fill=cfg["title_bg"])
    text(d, (34, 77), "认知塑造", 36, cfg["title_ink"], bold=True)
    d.rectangle([248, 80, 286, 88], fill=(255, 206, 0))
    px_text(d, (30, 136), "COGNITION SHAPING", 2, sub)
    # 生机细胞
    text(d, (30, 182), "生机细胞", 16, sub)
    big = (18, 120, 210) if v in ("B", "C", "D") else acc
    text(d, (28, 200), str(CELLS), 64, big, bold=True)
    spent = sum(NODES[k]["cost"] for k in DONE)
    text(d, (176, 214), "已塑造  %d / %d" % (len(DONE), len(NODES)), 15, ink)
    text(d, (176, 238), "已投入  %d" % spent, 15, sub)
    d.line([(30, 290), (320, 290)], fill=sub, width=1)
    # 当前节点
    n = NODES[SEL]
    text(d, (30, 306), "当前节点", 16, sub)
    text(d, (30, 330), n["name"], 28, ink, bold=True)
    text(d, (30, 372), "队长最大生命", 16, ink)
    text(d, (28, 392), "+4%", 52, big, bold=True)
    text(d, (30, 462), "下一节  生存本能Ⅴ", 14, sub)
    nxt = NODES["hp5"]["desc"].split("。", 1)[1]
    y = 484
    f = font(13)
    line = ""
    for ch in nxt:
        if d.textlength(line + ch, font=f) > 286:
            d.text((30, y), line, font=f, fill=sub)
            y += 19
            line = ""
        line += ch
    d.text((30, y), line, font=f, fill=sub)
    d.polygon([(30, y + 30), (110, y + 30), (106, y + 50), (26, y + 50)], fill=(255, 206, 0))
    text(d, (38, y + 32), "质变 · 末节", 13, (17, 19, 24))


def top_bottom(img, cfg, v):
    d = ImageDraw.Draw(img)
    light_top = v == "C"
    tc = cfg["label"] if not light_top else (24, 40, 60)
    # 图谱标题
    text(d, (GX0 + 28, 22), "塑造图谱", 24, tc, bold=True)
    px_text(d, (GX0 + 140, 30), "COGNITION MAP", 2, cfg["label_lock"])
    text(d, (W - 28, 26), "返回  Esc", 16, tc, "ra")
    d.line([(GX0 + 28, 58), (W - 28, 58)], fill=cfg["label_lock"], width=1)
    # 底栏
    d.rectangle([0, 672, W, H], fill=cfg["bar"])
    d.rectangle([0, 672, W, 673], fill=(56, 214, 240))
    text(d, (24, 686), "R 推荐    X 重置    鼠标拖动 平移", 15, (150, 160, 172))
    text(d, (W - 300, 686), "消耗 %d 生机细胞" % NODES[SEL]["cost"], 16, (226, 232, 240), "ra")
    d.polygon([(W - 280, 672), (W, 672), (W, H), (W - 292, H)], fill=(56, 214, 240))
    text(d, (W - 140, 682), "确认塑造", 22, (14, 20, 28), "ma", bold=True)


def render(v, t=0.0, lit=None, chrome=True):
    cfg = V[v]
    img = bg_for(v, t)
    d = ImageDraw.Draw(img)
    edges(d, cfg, lit)
    for k in NODES:
        node(d, k, cfg, t, lit[1] if lit and lit[0] == k else None)
    chain_labels(d, cfg)
    if chrome:
        left_panel(img, cfg, v)
        top_bottom(img, cfg, v)
    return img.convert("RGB")


def flow(v):
    """3 帧示意（0 / 4 / 8 秒）：只看背景层 + 一块图谱，标注时间；外加 ×4 速 gif"""
    crop = (700, 300, 1100, 560)
    frames = [render(v, t, chrome=False).crop(crop) for t in (0, 4, 8)]
    fw, fh = frames[0].size
    strip = Image.new("RGB", (fw * 3 + 20, fh + 30), (10, 12, 16))
    d = ImageDraw.Draw(strip)
    for i, fr in enumerate(frames):
        strip.paste(fr, (i * (fw + 10), 30))
        text(d, (i * (fw + 10) + 6, 6), "t = %d 秒" % (i * 4), 15, (220, 226, 234))
    strip.save(os.path.join(OUT, "meta_tree_%s_flow.png" % v))
    gif = [render(v, i * 0.4 * 4, chrome=False).crop((GX0, GY0, GX1, GY1)).resize(((GX1 - GX0) // 2, (GY1 - GY0) // 2), Image.NEAREST)
           for i in range(25)]
    gif[0].save(os.path.join(OUT, "meta_tree_%s_flow.gif" % v), save_all=True, append_images=gif[1:], duration=100, loop=0)


def unlock(v="A"):
    """招牌动效：确认塑造 → 枝条从父节点长亮到新节点（0.55 秒）→ 节点暖白落定 + 外扩环（0.45 秒）"""
    global DONE
    k = SEL
    crop = (int(POS["hp3"][0]) - 150, int(POS["hp3"][1]) - 200, int(POS["hp3"][0]) + 170, int(POS["hp3"][1]) + 80)
    fr = [render(v, i * 0.04, lit=(k, min(1.0, i / 24)), chrome=False).crop(crop) for i in range(31)]
    DONE = DONE | {k}
    fr += [render(v, 1.2 + i * 0.04, chrome=False).crop(crop) for i in range(8)]
    DONE = DONE - {k}
    fr[0].save(os.path.join(OUT, "meta_tree_unlock.gif"), save_all=True, append_images=fr[1:], duration=40, loop=0)
    pick = [0, 8, 16, 24, 30]
    fw, fh = fr[0].size
    strip = Image.new("RGB", (fw * len(pick) + 10 * (len(pick) - 1), fh + 30), (10, 12, 16))
    d = ImageDraw.Draw(strip)
    for i, j in enumerate(pick):
        strip.paste(fr[j], (i * (fw + 10), 30))
        text(d, (i * (fw + 10) + 6, 6), "%.2f 秒" % (j * 0.04), 15, (220, 226, 234))
    strip.save(os.path.join(OUT, "meta_tree_unlock.png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    shots = []
    for v in "ABCD":
        im = render(v)
        im.save(os.path.join(OUT, "meta_tree_%s.png" % v))
        shots.append(im)
        flow(v)
        print(v, "ok", flush=True)
    unlock("A")
    sw, sh = 640, 360
    sheet = Image.new("RGB", (sw * 2 + 30, (sh + 56) * 2 + 10), (12, 14, 18))
    d = ImageDraw.Draw(sheet)
    for i, (v, im) in enumerate(zip("ABCD", shots)):
        x, y = 10 + (i % 2) * (sw + 10), 10 + (i // 2) * (sh + 56)
        text(d, (x, y), V[v]["name"], 18, (240, 242, 246), bold=True)
        text(d, (x, y + 24), V[v]["desc"], 13, (150, 160, 172))
        sheet.paste(im.resize((sw, sh), Image.LANCZOS), (x, y + 46))
    sheet.save(os.path.join(OUT, "meta_tree_sheet.jpg"), quality=90)
    print("out", OUT)


if __name__ == "__main__":
    main()
