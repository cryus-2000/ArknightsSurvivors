# -*- coding: utf-8 -*-
"""Boss 弹幕东方化样板（docs/302）：弹型样板表 + 实机对比示意。只出图，不改游戏。

  python tools/concept_danmaku.py sheet  --out <目录>                 # 弹型样板表：深 / 浅地面 × 1 倍 / 2 倍
  python tools/concept_danmaku.py compare --cur <目录> --out <目录>   # 对比图：左实机、中 A、右 B（同一帧）

弹体全部按美术像素格逐格画（1 特效像素 = 1 美术像素，游戏里 1 美术像素 = 2 世界像素），旋转弹（米弹 / 针弹）按角度直接在格上重新栅格化，
不旋转贴图，所以斜着飞也不糊。进游戏时同一套函数改写成 GDScript（16 向预烘到小图集或逐格 draw_rect，二选一见 docs/302 §5）。

compare 读 GCP 实机截图（tools/gcp_render.py 跑带 --ebdump 的临时探针，同一局跑「原样」和「--ebhide 不画 Boss 弹」两遍）：
<cur>/<spec>_cur/fr_*.png 是现在的样子，<spec>_hide/fr_*.png 是同一帧去掉 Boss 弹的底图，eb_*.json 是该帧每颗 Boss 弹的位置 / 速度 / 判定半径。
新样子 = 底图 + 按 json 里的真实弹位重画，所以弹数、速度、扩散角都是游戏里那一帧的。
"""
import argparse, glob, json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------- 配色：每个 Boss 一套，取自 enemies.json bcol / bcol_core / bcol_outline 与本体定稿色
PAL = {
    "knight_boss": {"name": "最后的骑士", "main": (96, 176, 255), "deep": (52, 104, 214), "light": (196, 232, 255), "core": (255, 255, 255), "edge": (12, 26, 60)},
    "ishar":       {"name": "伊莎玛拉",   "main": (64, 255, 153), "deep": (20, 176, 120), "light": (190, 255, 224), "core": (250, 255, 252), "edge": (5, 51, 42)},
    "paranoia":    {"name": "偏执泡影",   "main": (178, 82, 255), "deep": (120, 40, 200), "light": (226, 196, 255), "core": (255, 250, 255), "edge": (51, 20, 77)},
    # 中期 Boss（用户 11-07：重点；朋友反馈「中期 Boss 不明显」）
    "path":     {"name": "塑路者",       "main": (190, 202, 228), "deep": (104, 116, 152), "light": (236, 240, 250), "core": (255, 255, 255), "edge": (24, 28, 42)},
    "bishop":   {"name": "接潮主教",     "main": (88, 108, 244), "deep": (46, 58, 182), "light": (192, 202, 255), "core": (250, 250, 255), "edge": (14, 16, 62)},
    "archon":   {"name": "接潮蔑死体",   "main": (92, 230, 118), "deep": (40, 160, 72), "light": (204, 255, 214), "core": (250, 255, 250), "edge": (10, 52, 22)},
    "immortal": {"name": "接潮斥亡体",   "main": (160, 158, 255), "deep": (100, 92, 222), "light": (222, 222, 255), "core": (255, 255, 255), "edge": (30, 26, 72)},
    "iberia":   {"name": "圣徒伊比利亚", "main": (255, 128, 52), "deep": (204, 84, 26), "light": (255, 202, 150), "core": (255, 250, 236), "edge": (107, 36, 8)},
    "carmen":   {"name": "圣徒卡门",     "main": (255, 216, 140), "deep": (214, 166, 78), "light": (255, 244, 222), "core": (255, 255, 250), "edge": (87, 69, 38)},
}
FINALS = ["knight_boss", "ishar", "paranoia"]
MIDS = ["path", "bishop", "archon", "immortal", "iberia", "carmen"]
BOSSES = MIDS + FINALS

# 圆弹三档：半径（美术像素）与各层外沿（芯 / 浅环 / 彩环 / 暗边）
ROUND = {
    # 画面半径比判定大一圈（东方口径：看着大、判定小）：判定 r6 → 画面 9 世界像素，与现在「r + 3 暗圈」同大
    "s": {"R": 4.5, "core": 1.6, "light": 2.5, "ring": 3.6},
    "m": {"R": 6.5, "core": 2.7, "light": 3.8, "ring": 5.4},
    "l": {"R": 9.5, "core": 4.4, "light": 6.2, "ring": 8.4},
}
# 方向弹：半长轴 a、半短轴 b（美术像素）；e = 椭圆归一距离
SHAPED = {
    "rice":   {"a": 4.6, "b": 2.6, "core": 0.42, "light": 0.62, "ring": 0.8},
    "needle": {"a": 5.8, "b": 1.6, "core": 0.5, "light": 0.5, "ring": 0.72},
}


def _layer(d, spec, pal):
    """按归一 / 实际距离挑层色；返回 RGBA 或 None。"""
    if d <= spec["core"]:
        return pal["core"] + (255,)
    if d <= spec["light"]:
        return pal["light"] + (255,)
    if d <= spec["ring"]:
        return pal["main"] + (255,)
    return pal["edge"] + (255,)


def round_sprite(tier, pal):
    """圆弹：奇数直径方阵，中心在像素中心。"""
    sp = ROUND[tier]
    R = sp["R"]
    n = int(math.ceil(R * 2))
    n += (n + 1) % 2
    c = (n - 1) / 2.0
    im = np.zeros((n, n, 4), np.uint8)
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - c, y - c)
            if d <= R:
                im[y, x] = _layer(d, sp, pal)
    # 彩环外侧 1 格换深色调，环有体积（东方弹的「外沿更饱和」）
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - c, y - c)
            if sp["ring"] - 0.9 < d <= sp["ring"] and tier != "s":
                im[y, x] = pal["deep"] + (255,)
    return im


def shaped_sprite(kind, pal, ang, k=1.0):
    """米弹 / 针弹：按角度直接在格上栅格化（不转贴图）；k = 尺寸档（判定 r / 8，大刃 1.5）。"""
    sp = SHAPED[kind]
    a, b = sp["a"] * k, sp["b"] * k
    n = int(math.ceil(a * 2)) + 1
    n += (n + 1) % 2
    c = (n - 1) / 2.0
    ca, sa = math.cos(ang), math.sin(ang)
    im = np.zeros((n, n, 4), np.uint8)
    for y in range(n):
        for x in range(n):
            dx, dy = x - c, y - c
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            e = math.hypot(u / a, v / b)
            if e <= 1.0:
                if kind == "needle":
                    # 针弹：沿长轴一条白芯（前段更亮），两侧彩色，暗边
                    if abs(v) <= 0.55 and abs(u) <= a - 1.2:
                        im[y, x] = pal["core"] + (255,)
                    elif e <= sp["ring"]:
                        im[y, x] = pal["main"] + (255,)
                    else:
                        im[y, x] = pal["edge"] + (255,)
                else:
                    im[y, x] = _layer(e, sp, pal)
    return im


def bullet_kind(b, boss):
    """把实机弹映射到新弹型（docs/302 §2 表）。b = eb json 一项 [x, y, vx, vy, r, kind, tier, life]。"""
    r = float(b[4])
    tier = int(b[9]) if len(b) > 9 else -1
    if len(b) > 8 and b[8] in PAL:
        boss = b[8]
    if b[5] == "boss_blade":
        return "rice"   # 刃 / 冰屑：有朝向 → 米弹（大小按判定半径，见 shaped_k）
    if b[5] == "mc" and tier >= 0:
        return ("s", "m", "l")[min(2, tier)]
    if boss == "knight_boss":
        return "rice"   # 骑士冰屑 / 雪片 / 冰棱：有朝向的冰片 → 米弹（冰棱弹 knight_prism 进游戏时用针弹）
    if r >= 11.0:
        return "l"
    if r >= 7.0:
        return "m"
    return "s"


# ---------------- 方案 B 附加层：像素光晕 + 拖尾（加色，逐格、棋盘抖动，不糊）
def glow_sprite(base, pal, px=2):
    """在弹体外沿再长 px 格光晕：第一格 α≈0.55、第二格棋盘抖动 α≈0.3。返回加色层（RGB float, A float）。"""
    h, w = base.shape[:2]
    pad = px
    H, W = h + 2 * pad, w + 2 * pad
    m = np.zeros((H, W), bool)
    m[pad:pad + h, pad:pad + w] = base[..., 3] > 0
    out = np.zeros((H, W), np.float32)
    cur = m.copy()
    for k in range(px):
        grow = cur.copy()
        grow[1:, :] |= cur[:-1, :]
        grow[:-1, :] |= cur[1:, :]
        grow[:, 1:] |= cur[:, :-1]
        grow[:, :-1] |= cur[:, 1:]
        ring = grow & ~cur
        a = 0.55 if k == 0 else 0.3
        if k > 0:
            yy, xx = np.mgrid[0:H, 0:W]
            ring &= ((yy + xx) % 2 == 0)
        out[ring] = a
        cur = grow
    return out, pad


def composite(canvas, spr, cx, cy, scale):
    """把美术像素小图按 scale 倍（最近邻）贴到 canvas（RGBA uint8 数组），中心对齐 (cx, cy) 屏幕像素。"""
    h, w = spr.shape[:2]
    big = _up(spr, scale)
    x0 = int(round(cx - big.shape[1] / 2.0))
    y0 = int(round(cy - big.shape[0] / 2.0))
    _blit(canvas, big, x0, y0)


def _up(a, scale):
    """最近邻放大；非整数倍（游戏 1080p 下 1 美术像素 = 2.52 屏幕像素）同游戏低分辨率层放大一样，格宽 2 / 3 交替。"""
    if float(scale).is_integer():
        s = int(scale)
        return np.repeat(np.repeat(a, s, 0), s, 1)
    h, w = a.shape[:2]
    ys = np.minimum((np.arange(int(round(h * scale))) / scale).astype(int), h - 1)
    xs = np.minimum((np.arange(int(round(w * scale))) / scale).astype(int), w - 1)
    return a[ys][:, xs]


def _blit(canvas, big, x0, y0):
    H, W = canvas.shape[:2]
    h, w = big.shape[:2]
    xa, ya = max(0, x0), max(0, y0)
    xb, yb = min(W, x0 + w), min(H, y0 + h)
    if xa >= xb or ya >= yb:
        return
    src = big[ya - y0:yb - y0, xa - x0:xb - x0]
    a = src[..., 3:4].astype(np.float32) / 255.0
    dst = canvas[ya:yb, xa:xb, :3].astype(np.float32)
    canvas[ya:yb, xa:xb, :3] = (src[..., :3] * a + dst * (1 - a)).astype(np.uint8)


def add_glow(canvas, glow, pad, col, cx, cy, scale, k=1.0):
    h, w = glow.shape
    big = _up(glow, scale)
    x0 = int(round(cx - big.shape[1] / 2.0))
    y0 = int(round(cy - big.shape[0] / 2.0))
    H, W = canvas.shape[:2]
    xa, ya = max(0, x0), max(0, y0)
    xb, yb = min(W, x0 + big.shape[1]), min(H, y0 + big.shape[0])
    if xa >= xb or ya >= yb:
        return
    g = big[ya - y0:yb - y0, xa - x0:xb - x0, None] * k
    dst = canvas[ya:yb, xa:xb, :3].astype(np.float32)
    canvas[ya:yb, xa:xb, :3] = np.clip(dst + g * np.array(col, np.float32), 0, 255).astype(np.uint8)


def trail_dots(canvas, pal, cx, cy, vx, vy, scale, tier):
    """B 的拖尾：沿反速度方向 3 个渐隐的彩色格点（每点 1–2 美术像素，加色），越快越长。"""
    sp = math.hypot(vx, vy)
    if sp < 1.0:
        return
    ux, uy = -vx / sp, -vy / sp
    base = {"s": 3.0, "m": 5.0, "l": 8.0, "rice": 4.0, "needle": 5.0}[tier]
    step = (2.0 + sp / 90.0) * scale
    size = 2 if tier in ("m", "l") else 1
    for i in range(1, 4):
        a = 0.5 * (1 - i / 4.0)
        px = cx + ux * (base * scale + step * i)
        py = cy + uy * (base * scale + step * i)
        s = max(1, int(round(size * scale)))
        x0, y0 = int(round(px - s / 2)), int(round(py - s / 2))
        H, W = canvas.shape[:2]
        if 0 <= x0 < W - s and 0 <= y0 < H - s:
            reg = canvas[y0:y0 + s, x0:x0 + s, :3].astype(np.float32)
            canvas[y0:y0 + s, x0:x0 + s, :3] = np.clip(reg + a * np.array(pal["main"], np.float32), 0, 255).astype(np.uint8)


def draw_bullet(canvas, boss, kind, cx, cy, vx, vy, scale, scheme, phase=0.0, layer="all", sk=1.0):
    pal = PAL[boss]
    ang = math.atan2(vy, vx) if (vx or vy) else 0.0
    # 角度量化到 16 向（进游戏时同一做法：每向一张小图）
    ang = round(ang / (math.tau / 16)) * (math.tau / 16)
    spr = round_sprite(kind, pal) if kind in ROUND else shaped_sprite(kind, pal, ang, sk)
    if layer == "core":
        # 第二遍：只补芯与浅环（叠弹时白芯永远在暗边之上；游戏里同样分遍合批画）
        m = np.all(spr[..., :3] == np.array(pal["core"], np.uint8), -1) | np.all(spr[..., :3] == np.array(pal["light"], np.uint8), -1)
        top = spr.copy()
        top[~m, 3] = 0
        composite(canvas, top, cx, cy, scale)
        return
    if scheme == "B":
        trail_dots(canvas, pal, cx, cy, vx, vy, scale, kind)
        g, pad = glow_sprite(spr, pal, 2 if kind != "s" else 1)
        add_glow(canvas, g, pad, pal["main"], cx, cy, scale, 0.9)
    composite(canvas, spr, cx, cy, scale)
    if scheme == "B" and kind in ("m", "l"):
        # 芯上 1 格高光闪烁（相位错开）：东方大弹的「活」
        if math.sin(phase) > 0.3:
            s = int(round(scale))
            canvas[int(cy - s * 1.5):int(cy - s * 0.5), int(cx - s * 1.5):int(cx - s * 0.5), :3] = 255


# ---------------- 瞬间特效：发射闪光 / 消弹碎光 / 命中（逐格；B 多一层 Noita 式粒子光）
def fx_frames(boss, what, scheme, n=4):
    pal = PAL[boss]
    out = []
    S = 21
    c = S // 2
    for f in range(n):
        im = np.zeros((S, S, 4), np.uint8)
        k = f / (n - 1)
        if what == "fire":
            # 发射：十字星芒 + 菱形白闪，2 帧内收
            L = int(round(7 * (1 - k) + 2))
            for i in range(-L, L + 1):
                col = pal["core"] if abs(i) <= L * 0.4 else pal["main"]
                if f < n - 1:
                    im[c, c + i] = col + (255,)
                    im[c + i, c] = col + (255,)
            rr = int(round(3 * (1 - k)))
            for y in range(-rr, rr + 1):
                for x in range(-rr, rr + 1):
                    if abs(x) + abs(y) <= rr:
                        im[c + y, c + x] = pal["core"] + (255,)
            if scheme == "B" and f >= 1:
                for j in range(8):
                    a = j * math.tau / 8 + 0.4
                    d = 3 + f * 2.5
                    x, y = int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d))
                    if 0 <= x < S and 0 <= y < S:
                        im[y, x] = (pal["light"] if f < 3 else pal["main"]) + (255,)
        elif what == "cancel":
            # 消弹：弹体缩成白点 → 4 片菱形碎光外飞 → 星点
            rr = max(0, 3 - f)
            for y in range(-rr, rr + 1):
                for x in range(-rr, rr + 1):
                    if x * x + y * y <= rr * rr:
                        im[c + y, c + x] = (pal["core"] if f > 0 else pal["main"]) + (255,)
            cnt = 4 if scheme == "A" else 8
            for j in range(cnt):
                a = j * math.tau / cnt + 0.785
                d = 2 + f * 2.2
                x, y = int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d))
                if 0 <= x < S - 1 and 0 <= y < S - 1:
                    im[y, x] = (pal["light"] if f < 2 else pal["main"]) + (255,)
                    if f < 2:
                        im[y, x + 1] = pal["main"] + (255,)
            if scheme == "B" and f >= 2:
                for j in range(6):
                    a = j * 1.3 + f
                    d = 4 + f * 2.8
                    x, y = int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d + f))
                    if 0 <= x < S and 0 <= y < S:
                        im[y, x] = pal["light"] + (200,)
        else:
            # 命中：白色压扁圆 → 彩色破环
            rr = 2 + f * 2
            for y in range(-rr, rr + 1):
                for x in range(-rr, rr + 1):
                    d = math.hypot(x, y)
                    if f == 0 and d <= 3:
                        im[c + y, c + x] = pal["core"] + (255,)
                    elif f > 0 and rr - 1.2 < d <= rr and ((math.atan2(y, x) * 4 / math.pi) % 2 < 1.4 or scheme == "B"):
                        im[c + y, c + x] = (pal["main"] if f < 3 else pal["deep"]) + (255,)
            if scheme == "B" and f in (1, 2):
                for j in range(10):
                    a = j * 0.63
                    d = rr + 1.5
                    x, y = int(round(c + math.cos(a) * d)), int(round(c + math.sin(a) * d))
                    if 0 <= x < S and 0 <= y < S:
                        im[y, x] = pal["core"] + (255,)
        out.append(im)
    return out


# ---------------- 字
def font(sz):
    for f in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def ground(w, h, dark, seed=1):
    rng = np.random.default_rng(seed)
    base = np.array((26, 32, 44) if dark else (206, 198, 180), np.float32)
    im = np.ones((h, w, 3), np.float32) * base
    # 低频斑块（像素块 4×4），模拟地面纹理
    blk = rng.normal(0, 6 if dark else 8, (h // 4 + 1, w // 4 + 1, 1))
    im += np.repeat(np.repeat(blk, 4, 0), 4, 1)[:h, :w]
    out = np.zeros((h, w, 4), np.uint8)
    out[..., :3] = np.clip(im, 0, 255)
    out[..., 3] = 255
    return out


def sheet(outdir):
    os.makedirs(outdir, exist_ok=True)
    cols = [("小圆弹", "s"), ("中圆弹", "m"), ("大圆弹", "l"), ("米弹", "rice"), ("针弹", "needle")]
    for dark in (True, False):
        for scale in (1, 2):
            cw, rh = 44 * scale + 8, 34 * scale + 8   # 每格（弹 + B 版）
            lw = 120
            W = lw + len(cols) * cw * 2 + 20
            H = 70 + len(BOSSES) * rh + 30 + rh + len(BOSSES) * (24 * scale + 14) + 40
            cv = ground(W, H, dark, 3 + scale)
            img = Image.fromarray(cv, "RGBA")
            dr = ImageDraw.Draw(img)
            tc = (235, 235, 240) if dark else (30, 30, 40)
            dr.text((10, 8), "Boss 东方弹型样板 · %s地面 · %d 倍（1 美术像素 = %d 图像像素）" % ("深色" if dark else "浅色", scale, scale), fill=tc, font=font(16))
            for ci, (nm, k) in enumerate(cols):
                for si, sc in enumerate(("A", "B")):
                    x = lw + (ci * 2 + si) * cw
                    dr.text((x + 4, 36), "%s %s" % (nm, sc), fill=tc, font=font(12))
            cv = np.array(img)
            for bi, boss in enumerate(BOSSES):
                y = 70 + bi * rh + rh // 2
                for ci, (nm, k) in enumerate(cols):
                    for si, sc in enumerate(("A", "B")):
                        x = lw + (ci * 2 + si) * cw + cw // 2
                        vx, vy = (1.0, -0.6)
                        draw_bullet(cv, boss, k, x, y, vx * 120, vy * 120, scale, sc, phase=1.0)
            # 对照行：普通怪弹（现状，不改）：通用敌弹 ebullet（洋红描边）与浮海飘航者神经弹
            yN = 70 + len(BOSSES) * rh + 6
            root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            eb = np.array(Image.open(os.path.join(root, "game/art/px/ebullet.png")).convert("RGBA"))
            nv = np.array(Image.open(os.path.join(root, "game/art/fx/proj/proj_floater_nerve.png")).convert("RGBA"))[:, :12]
            for j, spr in enumerate((eb, nv)):
                composite(cv, spr, lw + j * cw * 2 + cw // 2, yN, scale)
            # 瞬间特效条：每 Boss 一行，A / B 各「发射 / 消弹 / 命中」4 帧
            y0 = 70 + len(BOSSES) * rh + 30 + rh
            img = Image.fromarray(cv, "RGBA")
            dr = ImageDraw.Draw(img)
            dr.text((10, y0 - 22), "瞬间特效（4 帧，每帧约 0.05 秒）：发射闪光 / 消弹碎光 / 命中 —— 左 A，右 B", fill=tc, font=font(13))
            for bi, boss in enumerate(BOSSES):
                dr.text((10, y0 + bi * (24 * scale + 14) + 6), PAL[boss]["name"], fill=tc, font=font(13))
            cv = np.array(img)
            for bi, boss in enumerate(BOSSES):
                yy = y0 + bi * (24 * scale + 14) + 12 * scale
                x = lw
                for sc in ("A", "B"):
                    for what in ("fire", "cancel", "hit"):
                        for fr in fx_frames(boss, what, sc):
                            composite(cv, fr, x + 11 * scale, yy, scale)
                            x += 22 * scale + 2
                        x += 8
                    x += 16
            img = Image.fromarray(cv, "RGBA")
            dr = ImageDraw.Draw(img)
            for bi, boss in enumerate(BOSSES):
                dr.text((10, 70 + bi * rh + rh // 2 - 8), PAL[boss]["name"], fill=tc, font=font(14))
            dr.text((10, 70 + len(BOSSES) * rh - 2), "普通怪弹 （现状不改）", fill=tc, font=font(12))
            fn = os.path.join(outdir, "sheet_%s_%dx.png" % ("dark" if dark else "light", scale))
            img.convert("RGB").save(fn)
            print(fn, img.size)


# ---------------- 对比图
SPEC_BOSS = {"path": "path", "bishop": "bishop", "archon": "archon", "immortal": "immortal", "iberia": "iberia", "carmen": "carmen",
             "knight_boss": "knight_boss", "ishar2": "ishar", "paranoia": "paranoia"}
MOVE = {"knight_boss": "寒潮回卷（雪片双螺旋）", "ishar": "泪雨（大泪 → 碎成小弹）", "paranoia": "偏执双旋（正反环交织）",
        "path": "探路分形（分裂弹）", "bishop": "交错潮环", "archon": "裂潮", "immortal": "斥亡旋刃", "iberia": "散射", "carmen": "环射"}


def world_to_img(js, x, y):
    a, b, c, d, ox, oy = js["xf"]   # Transform2D: x 轴 (a, b)、y 轴 (c, d)、原点
    sx = js["img"][0] / js["vs"][0] * 0 + 1.0
    return ox + a * x + c * y, oy + b * x + d * y


def render_new(bg, js, boss, scheme, scale):
    cv = np.array(bg.convert("RGBA"))
    k = js["img"][0] / 1920.0   # 截图像素 / 窗口像素
    for i, b in enumerate(js["b"]):
        x, y = world_to_img(js, b[0], b[1] - 16.0)   # 弹飞在离地 16 的高度（world._ebp）
        bb = b[8] if len(b) > 8 and b[8] in PAL else boss
        draw_bullet(cv, bb, bullet_kind(b, bb), x * k, y * k, b[2], b[3], scale, scheme, phase=i * 1.7, sk=max(1.0, float(b[4]) / 8.0))
    for i, b in enumerate(js["b"]):
        x, y = world_to_img(js, b[0], b[1] - 16.0)
        bb = b[8] if len(b) > 8 and b[8] in PAL else boss
        draw_bullet(cv, bb, bullet_kind(b, bb), x * k, y * k, b[2], b[3], scale, scheme, layer="core", sk=max(1.0, float(b[4]) / 8.0))
    return Image.fromarray(cv, "RGBA")


def compare(curdir, outdir, frames=None):
    os.makedirs(outdir, exist_ok=True)
    for spec, boss in SPEC_BOSS.items():
        roots = [r for r in curdir.split(";") if os.path.isdir(os.path.join(r, spec + "_cur"))]
        root = roots[0] if roots else curdir
        cd, hd = os.path.join(root, spec + "_cur"), os.path.join(root, spec + "_hide")
        if not os.path.isdir(cd):
            print("缺", cd)
            continue
        # 挑弹最多的一帧（两遍都有图的帧）
        best = None
        for f in sorted(glob.glob(os.path.join(cd, "fr_*.png"))):
            i = os.path.basename(f)[3:8]
            jf = os.path.join(hd, "eb_%s.json" % i)
            hf = os.path.join(hd, "fr_%s.png" % i)
            if not (os.path.exists(jf) and os.path.exists(hf)):
                continue
            js = json.load(open(jf, encoding="utf-8"))
            if best is None or len(js["b"]) > best[0]:
                best = (len(js["b"]), i, f, hf, js)
        if best is None:
            print("没有可配对的帧", spec)
            continue
        n, i, cf, hf, js = best
        # 两遍同种子：核对同帧弹数（原样那遍的 json）
        jc = os.path.join(cd, "eb_%s.json" % i)
        nc = len(json.load(open(jc, encoding="utf-8"))["b"]) if os.path.exists(jc) else -1
        cur = Image.open(cf).convert("RGBA")
        bg = Image.open(hf).convert("RGBA")
        # 1 美术像素 = 2 世界像素 × 镜头缩放 × 截图比例
        wscale = math.hypot(js["xf"][0], js["xf"][1]) * js["img"][0] / 1920.0
        scale = 2 * wscale
        A = render_new(bg, js, boss, "A", scale)
        B = render_new(bg, js, boss, "B", scale)
        # 以 Boss 为中心裁 1200×800（保持原始像素，不缩放）
        bx, by = world_to_img(js, js["boss"][0], js["boss"][1])
        px, py = world_to_img(js, js["pp"][0], js["pp"][1])
        k = js["img"][0] / 1920.0
        mx, my = (bx + px) / 2 * k, (by + py) / 2 * k
        cw, ch = min(1100, cur.width), min(760, cur.height)
        x0 = int(min(max(0, mx - cw / 2), cur.width - cw))
        y0 = int(min(max(0, my - ch / 2), cur.height - ch))
        box = (x0, y0, x0 + cw, y0 + ch)
        tiles = [("现在（实机）", cur.crop(box)), ("方案 A · 纯东方", A.crop(box)), ("方案 B · 东方 + pixelfx 光晕拖尾", B.crop(box))]
        W = cw * 3 + 40
        img = Image.new("RGB", (W, ch + 70), (16, 16, 20))
        dr = ImageDraw.Draw(img)
        dr.text((12, 8), "%s · %s · 同一帧（游戏时间 %.2f 秒，Boss 弹 %d 颗%s）· 1 美术像素 = %.2f 屏幕像素（同游戏 1080p）" % (
            PAL[boss]["name"], MOVE[boss],
            js["t"], n, "" if nc in (-1, n) else "，原样那遍 %d 颗" % nc, scale), fill=(235, 235, 240), font=font(18))
        for ti, (nm, t) in enumerate(tiles):
            x = 10 + ti * (cw + 10)
            img.paste(t.convert("RGB"), (x, 60))
            dr.text((x + 6, 38), nm, fill=(235, 235, 240), font=font(15))
        fn = os.path.join(outdir, "compare_%s.png" % boss)
        img.save(fn)
        # 局部放大：Boss 附近 300×200 → ×3
        zx, zy = int(bx * k), int(by * k)
        zb = (max(0, zx - 150), max(0, zy - 130), max(0, zx - 150) + 300, max(0, zy - 130) + 200)
        z = Image.new("RGB", (900 * 3 + 40, 600 + 50), (16, 16, 20))
        dz = ImageDraw.Draw(z)
        for ti, (nm, t) in enumerate([("现在", cur), ("A", A), ("B", B)]):
            z.paste(t.crop(zb).resize((900, 600), Image.NEAREST).convert("RGB"), (10 + ti * 910, 44))
            dz.text((16 + ti * 910, 12), "%s · %s（Boss 附近 ×3 放大）" % (PAL[boss]["name"], nm), fill=(235, 235, 240), font=font(16))
        fz = os.path.join(outdir, "zoom_%s.png" % boss)
        z.save(fz)
        print(fn, fz, "frame", i, "bullets", n, nc, "scale", scale)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["sheet", "compare"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--cur")
    a = ap.parse_args()
    if a.mode == "sheet":
        sheet(a.out)
    else:
        compare(a.cur, a.out)
