# -*- coding: utf-8 -*-
"""Boss 弹幕东方化第二版（docs/302 §6，用户 11-07「现在设计的不够好看，还是要好看的」「骑士的不要修改」）。

和第一版（tools/concept_danmaku.py 的 A / B）的区别：
  - 画法：每颗弹按解析形状 4×4 超采样，再落回美术像素格；亮度用 5 阶色带（白 → 淡 → 亮 → 主 → 深）+ 色带交界 2×2 有序抖动，
    外沿 1 格暗边，暗边外 1–2 格柔光晕（加色、分 3 档透明度），左上角镜面高光。仍是 1 特效像素 = 1 美术像素。
  - 弹形：小弹全员同一种精修圆弹（成套）；中、大弹换成每个 Boss 的专属弹形（东方弹型里挑和 Boss 身份对得上的）：
      塑路者 菱晶弹 / 接潮主教 水泡环 / 接潮斥亡体 刀弹 / 圣徒伊比利亚 火球 / 圣徒卡门 星弹 / 伊莎玛拉 泪滴 / 偏执泡影 泡弹。
  - 最后的骑士不改（用户 11-07），对比图里骑士保持现状。

  python tools/danmaku_v2.py sheet   --out <目录>
  python tools/danmaku_v2.py compare --cur <GCP 截图目录> --out <目录>
"""
import argparse, colorsys, glob, json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import concept_danmaku as V1

BAYER = np.array([[0.0, 0.5], [0.75, 0.25]])


def _mix(a, b, k):
    return tuple(int(round(a[i] * (1 - k) + b[i] * k)) for i in range(3))


def ramp_from(main, white=(255, 255, 255)):
    """主色 → 5 阶色带 + 暗边。深色调提饱和、压明度，淡色调往白走。"""
    h, s, v = colorsys.rgb_to_hsv(*[c / 255.0 for c in main])
    deep = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, min(1.0, s * 1.15 + 0.1), v * 0.62))
    edge = tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, min(1.0, s * 0.9 + 0.2), v * 0.22))
    return {"white": white, "pale": _mix(main, white, 0.72), "light": _mix(main, white, 0.4), "main": tuple(main), "deep": deep, "edge": edge}


# 每 Boss：色带 + 专属弹形（m / l 档用）；小弹统一 orb
STYLE = {
    "path":     {"ramp": ramp_from((150, 178, 230)), "shape": "diamond", "small": "diamond", "name": "塑路者", "shape_name": "菱晶弹"},
    "bishop":   {"ramp": ramp_from((92, 112, 250)), "shape": "bubble_ring", "small": "orb", "name": "接潮主教", "shape_name": "水泡环"},
    "archon":   {"ramp": ramp_from((92, 230, 118)), "shape": "orb", "small": "orb", "name": "接潮蔑死体", "shape_name": "光玉（无弹幕招）"},
    "immortal": {"ramp": ramp_from((168, 160, 255)), "shape": "knife", "small": "orb", "name": "接潮斥亡体", "shape_name": "刀弹"},
    "iberia":   {"ramp": {"white": (255, 252, 236), "pale": (255, 230, 150), "light": (255, 176, 76), "main": (244, 108, 38), "deep": (178, 50, 20), "edge": (70, 18, 8)},
                 "shape": "fireball", "small": "orb", "name": "圣徒伊比利亚", "shape_name": "火球"},
    "carmen":   {"ramp": {"white": (255, 255, 246), "pale": (255, 244, 200), "light": (255, 220, 128), "main": (238, 178, 66), "deep": (170, 110, 34), "edge": (70, 44, 14)},
                 "shape": "star", "small": "orb", "name": "圣徒卡门", "shape_name": "星弹"},
    "ishar":    {"ramp": ramp_from((64, 240, 160)), "shape": "drop", "small": "orb", "name": "伊莎玛拉", "shape_name": "泪滴"},
    "paranoia": {"ramp": ramp_from((178, 96, 255)), "shape": "bubble", "small": "bubble", "name": "偏执泡影", "shape_name": "泡弹"},
}
TONES = ["white", "pale", "light", "main", "deep"]


# ---------------- 形状：返回 (sdf, e, spec, alpha) ；u 沿飞行方向，v 垂直（屏幕坐标 y 向下）
def f_orb(u, v, R, x, y, ph):
    r = math.hypot(u, v)
    e = 1.0 - min(1.0, r / max(1.0, R - 1.0)) ** 1.5
    sx, sy = x + R * 0.36, y + R * 0.36   # 屏幕左上的高光（x, y 为屏幕相对坐标）
    spec = 1.0 if R >= 5 and math.hypot(sx, sy) < max(0.7, R * 0.16) else 0.0
    return r - R, e, spec, 1.0


def f_bubble(u, v, R, x, y, ph):
    r = math.hypot(u, v)
    t = (R - 1.0) - r   # 到外沿内侧的距离
    if t < 1.6:
        e, a = 0.55 - 0.3 * max(0.0, t) / 1.6, 1.0   # 亮边
    else:
        e, a = 0.45 + 0.3 * (1 - r / R), 0.55   # 半透明泡身（浅色调，中心略亮）
    ang = math.atan2(y, x)
    spec = 0.0
    # 左上弧形高光 + 右下小反光点
    if 0.42 * R < r < 0.74 * R and -2.85 < ang < -1.45:
        spec = 1.0
    if R >= 6 and math.hypot(x - R * 0.38, y - R * 0.38) < 0.75:
        spec = 0.6
    if R < 6 and math.hypot(x + R * 0.3, y + R * 0.3) < 0.8:
        spec = 1.0
    return r - R, e, spec, a


def f_bubble_ring(u, v, R, x, y, ph):
    """水泡环：亮环 + 中间透出地面（主教的潮汐环）。"""
    r = math.hypot(u, v)
    inner = R * 0.42
    sdf = max(r - R, inner - r)
    mid = (R + inner) / 2
    e = 0.9 - min(1.0, abs(r - mid) / ((R - inner) / 2)) * 0.75
    spec = 1.0 if (math.hypot(x + R * 0.5, y + R * 0.5) < 0.9 and R >= 6) else 0.0
    return sdf, e, spec, 1.0


def f_drop(u, v, R, x, y, ph):
    """泪滴：头朝前（+u），尾巴向后收尖。"""
    c = 0.0
    tip = -2.1 * R
    if u >= c:
        sdf = math.hypot(u - c, v) - R
    else:
        k = (u - tip) / (c - tip)
        w = R * max(0.0, k) ** 1.15
        sdf = max(abs(v) - w, tip - u) if k > 0 else math.hypot(u - tip, v)
        sdf = min(sdf, math.hypot(u - c, v) - R)
    e = 1.0 - min(1.0, math.hypot(u - c - R * 0.1, v) / (R * 1.1)) ** 1.3
    if u < c:
        e = min(e, max(0.0, 0.5 * (u - tip) / (c - tip)))
    spec = 1.0 if math.hypot(x + R * 0.3, y + R * 0.3) < max(0.75, R * 0.15) else 0.0
    return sdf, e, spec, 1.0


def f_knife(u, v, R, x, y, ph):
    """刀弹：前尖后平、刃一侧亮一侧暗、尾部护手。R = 半长。"""
    L, W = R, R * 0.3
    front = (L - u) / (L * 0.55)
    w = W * min(1.0, max(0.0, front))
    sdf = max(abs(v) - w, u - L, -L * 0.55 - u)
    # 护手
    if -L * 0.75 <= u <= -L * 0.5:
        sdf = min(sdf, max(abs(v) - W * 1.5, abs(u + L * 0.62) - L * 0.12))
    e = 0.95 if v < -0.2 else (0.5 if v < 0.6 else 0.25)
    if u > L * 0.6:
        e = 1.0
    if u < -L * 0.5:
        e = 0.1
    return sdf, e, 0.0, 1.0


def f_star(u, v, R, x, y, ph):
    """星弹：五角星，按相位自转（屏幕坐标，不随飞行方向）。"""
    r = math.hypot(x, y)
    th = math.atan2(y, x) + ph
    k = abs(((th * 5 / math.tau) % 1.0) - 0.5) * 2
    redge = R * (0.5 + 0.5 * k ** 1.4)
    e = 1.0 - min(1.0, r / (R * 0.85)) ** 1.2
    spec = 1.0 if r < 0.8 else 0.0
    return r - redge, e, spec, 1.0


def f_fireball(u, v, R, x, y, ph):
    """火球：圆头 + 向后的波浪火舌。"""
    head = math.hypot(u, v) - R
    tip = -2.0 * R
    if u < 0:
        k = (u - tip) / (-tip)
        wob = 1.0 + 0.18 * math.sin(u * 1.3 + ph * 3.0)
        w = R * 0.9 * max(0.0, k) ** 0.9 * wob
        tail = max(abs(v + 0.25 * math.sin(u * 0.9 + ph)) - w, tip - u)
        sdf = min(head, tail)
    else:
        sdf = head
    e = 1.0 - min(1.0, math.hypot(u - R * 0.15, v) / (R * 1.05)) ** 1.25
    if u < -R * 0.2:
        e = min(e, 0.55 * max(0.0, (u - tip) / (-tip)))
    return sdf, e, 0.0, 1.0


def f_diamond(u, v, R, x, y, ph):
    """菱晶：沿飞行方向拉长的菱形，四个切面明暗不同 + 前半条白棱。"""
    a, b = R, R * 0.62
    q = abs(u) / a + abs(v) / b - 1.0
    sdf = q * min(a, b) * 0.8
    if u >= 0 and v < 0:
        e = 0.8
    elif u < 0 and v < 0:
        e = 0.6
    elif u >= 0:
        e = 0.42
    else:
        e = 0.22
    if abs(v) < 0.55 and u > -a * 0.2:
        e = 1.0
    return sdf, e, 0.0, 1.0


SHAPES = {"orb": f_orb, "bubble": f_bubble, "bubble_ring": f_bubble_ring, "drop": f_drop, "knife": f_knife, "star": f_star,
          "fireball": f_fireball, "diamond": f_diamond}


def sprite(boss, shape, R, ang=0.0, ph=0.0, glow=2):
    """返回 (body RGBA uint8, glow alpha float, 主色)；画布中心 = 弹心。"""
    st = STYLE[boss]
    ramp = st["ramp"]
    fn = SHAPES[shape]
    ext = R * (2.3 if shape in ("drop", "fireball") else 1.0) + glow + 1.5
    n = int(math.ceil(ext)) * 2 + 1
    c = (n - 1) / 2.0
    ca, sa = math.cos(ang), math.sin(ang)
    body = np.zeros((n, n, 4), np.uint8)
    cov = np.zeros((n, n))
    sdfc = np.zeros((n, n))
    ss = [(-0.375, -0.375), (-0.125, -0.375), (0.125, -0.375), (0.375, -0.375), (-0.375, -0.125), (-0.125, -0.125), (0.125, -0.125), (0.375, -0.125),
          (-0.375, 0.125), (-0.125, 0.125), (0.125, 0.125), (0.375, 0.125), (-0.375, 0.375), (-0.125, 0.375), (0.125, 0.375), (0.375, 0.375)]
    info = {}
    for py in range(n):
        for px in range(n):
            hit = 0
            for ox, oy in ss:
                x, y = px - c + ox, py - c + oy
                u, v = x * ca + y * sa, -x * sa + y * ca
                if fn(u, v, R, x, y, ph)[0] < 0:
                    hit += 1
            x, y = px - c, py - c
            u, v = x * ca + y * sa, -x * sa + y * ca
            sd, e, sp, a = fn(u, v, R, x, y, ph)
            cov[py, px] = hit / 16.0
            sdfc[py, px] = sd
            info[(py, px)] = (sd, e, sp, a)
    inside = cov >= 0.5
    # 暗边 = 内部格里与外部 4 邻接的那一圈
    out = ~inside
    nb = np.zeros_like(inside)
    nb[1:, :] |= out[:-1, :]
    nb[:-1, :] |= out[1:, :]
    nb[:, 1:] |= out[:, :-1]
    nb[:, :-1] |= out[:, 1:]
    edge = inside & nb
    for py in range(n):
        for px in range(n):
            if not inside[py, px]:
                continue
            sd, e, sp, a = info[(py, px)]
            if edge[py, px]:
                col = ramp["edge"]
                al = 255
            else:
                f = (1.0 - max(0.0, min(1.0, e))) * (len(TONES) - 1)
                d = 0.32 + 0.36 * BAYER[py % 2, px % 2]   # 只在色带交界附近抖动
                idx = int(min(len(TONES) - 1, math.floor(f + d)))
                col = ramp[TONES[idx]]
                if sp > 0.8:
                    col = ramp["white"]
                elif sp > 0.3:
                    col = ramp["pale"]
                al = int(255 * a)
            body[py, px] = col + (al,)
    # 柔光晕：暗边外 glow 格，3 档透明度
    g = np.zeros((n, n), np.float32)
    cur = inside.copy()
    levels = [0.5, 0.26, 0.12][:glow]
    for lv in levels:
        grow = cur.copy()
        grow[1:, :] |= cur[:-1, :]
        grow[:-1, :] |= cur[1:, :]
        grow[:, 1:] |= cur[:, :-1]
        grow[:, :-1] |= cur[:, 1:]
        g[grow & ~cur] = lv
        cur = grow
    return body, g, ramp["main"]


def kind_for(boss, b):
    """实机弹 → (弹形, 半径美术像素)。b = eb json 一项。"""
    r = float(b[4])
    st = STYLE[boss]
    tier = int(b[9]) if len(b) > 9 else -1
    if b[5] == "mc" and tier >= 0:
        r = (6.0, 7.0, 11.0)[min(2, tier)]
    if boss == "immortal" or b[5] == "boss_blade":
        return "knife", 7.0 * max(1.0, r / 9.0)
    if r <= 6.0:
        return st["small"], 4.5 if st["small"] != "diamond" else 5.0
    big = {"drop": (5.0, 7.0), "fireball": (5.0, 7.0), "star": (7.5, 10.5)}.get(st["shape"], (6.0, 9.0))   # 星形面积比圆小，放大一档
    return st["shape"], big[0] if r < 10.0 else big[1]


_cache = {}


def draw(canvas, boss, shape, R, cx, cy, vx, vy, scale, ph=0.0, layer="body"):
    ang = math.atan2(vy, vx) if (vx or vy) else 0.0
    if shape != "star":
        ang = round(ang / (math.tau / 16)) * (math.tau / 16)
    phq = round(ph / (math.tau / 10)) % 10 if shape in ("star", "fireball") else 0
    key = (boss, shape, R, round(ang, 3), phq)
    if key not in _cache:
        _cache[key] = sprite(boss, shape, R, ang, phq * math.tau / 10 / 5 if shape == "star" else phq * 0.6, glow=2 if R >= 5 else 1)
    body, g, main = _cache[key]
    if layer == "glow":
        V1.add_glow(canvas, g, 0, main, cx, cy, scale, 1.0)
        return
    if layer == "core":
        top = body.copy()
        ramp = STYLE[boss]["ramp"]
        m = np.zeros(top.shape[:2], bool)
        for t in ("white", "pale"):
            m |= np.all(top[..., :3] == np.array(ramp[t], np.uint8), -1)
        top[~m, 3] = 0
        _alpha_blit(canvas, top, cx, cy, scale)
        return
    _alpha_blit(canvas, body, cx, cy, scale)


def _alpha_blit(canvas, spr, cx, cy, scale):
    big = V1._up(spr, scale)
    x0 = int(round(cx - big.shape[1] / 2.0))
    y0 = int(round(cy - big.shape[0] / 2.0))
    V1._blit(canvas, big, x0, y0)


# ---------------- 瞬间特效 v2：发射 / 消弹 / 命中（4 帧，逐格，主形 + 粒子光）
def fx_v2(boss, what, n=5):
    ramp = STYLE[boss]["ramp"]
    S = 25
    c = S // 2
    out = []
    for f in range(n):
        im = np.zeros((S, S, 4), np.uint8)
        k = f / (n - 1)

        def put(x, y, col, a=255):
            x, y = int(round(x)), int(round(y))
            if 0 <= x < S and 0 <= y < S:
                im[y, x] = col + (a,)
        if what == "fire":
            # 四芒星：长芒白 → 淡，短芒主色；外圈 6 粒火星外飞，最后一帧只剩星点
            L = 9 * (1 - k) + 2
            for i in range(-int(L), int(L) + 1):
                tone = "white" if abs(i) < L * 0.35 else ("pale" if abs(i) < L * 0.7 else "main")
                if f < n - 1:
                    put(c + i, c, ramp[tone])
                    put(c, c + i, ramp[tone])
            for i in range(-int(L * 0.45), int(L * 0.45) + 1):
                if f < n - 2:
                    put(c + i, c + i, ramp["light"])
                    put(c + i, c - i, ramp["light"])
            for j in range(6):
                a = j * math.tau / 6 + 0.3
                d = 3 + f * 2.6
                put(c + math.cos(a) * d, c + math.sin(a) * d, ramp["pale" if f < 2 else "main"])
        elif what == "cancel":
            # 消弹：弹体先胀白，再碎成 6 片菱形亮片外飞旋转，末尾成星点
            if f == 0:
                for y in range(-3, 4):
                    for x in range(-3, 4):
                        if x * x + y * y <= 9:
                            put(c + x, c + y, ramp["white"] if x * x + y * y <= 4 else ramp["light"])
            for j in range(6):
                a = j * math.tau / 6 + f * 0.35
                d = 2 + f * 2.4
                px, py = c + math.cos(a) * d, c + math.sin(a) * d
                if f < n - 1:
                    put(px, py, ramp["white" if f < 2 else "pale"])
                    put(px + math.cos(a + 1.57), py + math.sin(a + 1.57), ramp["light"])
                    put(px - math.cos(a), py - math.sin(a), ramp["main"])
                else:
                    put(px, py, ramp["main"], 200)
        else:
            # 命中：白色压扁闪 → 主色破环 + 八向短芒
            rr = 2 + f * 2.2
            for y in range(-c, c + 1):
                for x in range(-c, c + 1):
                    d = math.hypot(x, y * 1.25)
                    if f == 0 and d <= 3.2:
                        put(c + x, c + y, ramp["white"])
                    elif f > 0 and rr - 1.1 < d <= rr and f < n - 1:
                        put(c + x, c + y, ramp["light" if f < 2 else ("main" if f < 3 else "deep")])
            if 1 <= f <= 2:
                for j in range(8):
                    a = j * math.tau / 8
                    for t in range(2):
                        put(c + math.cos(a) * (rr + 1.5 + t), c + math.sin(a) * (rr + 1.5 + t), ramp["white" if t == 0 else "pale"])
        out.append(im)
    return out


# ---------------- 样板表
def sheet(outdir):
    os.makedirs(outdir, exist_ok=True)
    bosses = ["path", "bishop", "immortal", "iberia", "carmen", "ishar", "paranoia"]
    for dark in (True, False):
        for scale in (2, 4):
            cw = 30 * scale + 10
            rh = 30 * scale + 10
            lw = 150
            cols = ["小弹", "中弹", "大弹", "中弹 · 斜飞"]
            W = lw + len(cols) * cw + 40 + 5 * 3 * (13 * scale + 2) + 40
            H = 70 + len(bosses) * rh + 20
            cv = V1.ground(W, H, dark, 7 + scale)
            img = Image.fromarray(cv, "RGBA")
            dr = ImageDraw.Draw(img)
            tc = (235, 235, 240) if dark else (30, 30, 40)
            dr.text((10, 8), "Boss 弹幕第二版 · %s地面 · %d 倍（1 美术像素 = %d 图像像素；游戏 1080p 约 2.5 倍）· 最后的骑士不改" % ("深色" if dark else "浅色", scale, scale), fill=tc, font=V1.font(16))
            for ci, nm in enumerate(cols):
                dr.text((lw + ci * cw + 4, 40), nm, fill=tc, font=V1.font(13))
            fxx = lw + len(cols) * cw + 40
            dr.text((fxx, 40), "发射（5 帧）　　　　　　消弹（5 帧）　　　　　　命中（5 帧）", fill=tc, font=V1.font(13))
            for bi, b in enumerate(bosses):
                st = STYLE[b]
                dr.text((10, 70 + bi * rh + rh // 2 - 18), st["name"], fill=tc, font=V1.font(14))
                dr.text((10, 70 + bi * rh + rh // 2 + 2), st["shape_name"], fill=tc, font=V1.font(12))
            cv = np.array(img)
            for bi, b in enumerate(bosses):
                y = 70 + bi * rh + rh // 2
                big = {"drop": (5.0, 7.0), "fireball": (5.0, 7.0), "star": (7.5, 10.5)}.get(STYLE[b]["shape"], (6.0, 9.0))
                specs = [(STYLE[b]["small"], 4.5 if STYLE[b]["small"] != "diamond" else 5.0, 0.0),
                         (STYLE[b]["shape"], big[0], 0.0), (STYLE[b]["shape"], big[1], 0.0), (STYLE[b]["shape"], big[0], -0.7)]
                if b == "immortal":
                    specs = [("orb", 4.5, 0.0), ("knife", 7.0, 0.0), ("knife", 9.3, 0.0), ("knife", 7.0, -0.7)]
                for ci, (sh, R, a) in enumerate(specs):
                    x = lw + ci * cw + cw // 2
                    for lay in ("glow", "body"):
                        draw(cv, b, sh, R, x, y, math.cos(a) * 100, math.sin(a) * 100, scale, ph=1.0, layer=lay)
                x = fxx
                for what in ("fire", "cancel", "hit"):
                    for fr in fx_v2(b, what):
                        V1.composite(cv, fr, x + 12 * scale // 2, y, scale // 2 if scale > 2 else 1)
                        x += 13 * scale + 2
                    x += 10
            fn = os.path.join(outdir, "v2_sheet_%s_%dx.png" % ("dark" if dark else "light", scale))
            Image.fromarray(cv, "RGBA").convert("RGB").save(fn)
            print(fn)


# ---------------- 同帧对比：现在 | 第二版
MOVE = {"path": "探路分形", "bishop": "交错潮环", "immortal": "斥亡旋刃", "iberia": "散射", "carmen": "环射", "ishar": "泪雨", "paranoia": "偏执双旋"}
SPEC = {"path": "path", "bishop": "bishop", "immortal": "immortal", "iberia": "iberia", "carmen": "carmen", "ishar2": "ishar", "paranoia": "paranoia"}


def render_v2(bg, js, boss, scale):
    cv = np.array(bg.convert("RGBA"))
    k = js["img"][0] / 1920.0
    items = []
    for i, b in enumerate(js["b"]):
        bb = b[8] if len(b) > 8 and b[8] in STYLE else boss
        if bb == "knight_boss":
            continue
        x, y = V1.world_to_img(js, b[0], b[1] - 16.0)
        sh, R = kind_for(bb, b)
        items.append((bb, sh, R, x * k, y * k, b[2], b[3], i * 1.7 + b[0] * 0.01))
    for lay in ("glow", "body", "core"):   # 分三遍：光晕 → 弹体 → 白芯（叠弹时芯在最上）
        for bb, sh, R, x, y, vx, vy, ph in items:
            draw(cv, bb, sh, R, x, y, vx, vy, scale, ph=ph, layer=lay)
    return Image.fromarray(cv, "RGBA")


def compare(curdir, outdir):
    os.makedirs(outdir, exist_ok=True)
    for spec, boss in SPEC.items():
        cd, hd = os.path.join(curdir, spec + "_cur"), os.path.join(curdir, spec + "_hide")
        best = None
        for f in sorted(glob.glob(os.path.join(cd, "fr_*.png"))):
            i = os.path.basename(f)[3:8]
            jf = os.path.join(hd, "eb_%s.json" % i)
            hf = os.path.join(hd, "fr_%s.png" % i)
            if os.path.exists(jf) and os.path.exists(hf):
                js = json.load(open(jf, encoding="utf-8"))
                if best is None or len(js["b"]) > best[0]:
                    best = (len(js["b"]), i, f, hf, js)
        if best is None:
            continue
        n, i, cf, hf, js = best
        cur = Image.open(cf).convert("RGBA")
        scale = 2 * math.hypot(js["xf"][0], js["xf"][1]) * js["img"][0] / 1920.0
        new = render_v2(Image.open(hf), js, boss, scale)
        k = js["img"][0] / 1920.0
        bx, by = V1.world_to_img(js, js["boss"][0], js["boss"][1])
        px, py = V1.world_to_img(js, js["pp"][0], js["pp"][1])
        mx, my = (bx + px) / 2 * k, (by + py) / 2 * k
        cw, ch = 1240, 820
        x0 = int(min(max(0, mx - cw / 2), cur.width - cw))
        y0 = int(min(max(0, my - ch / 2), cur.height - ch))
        box = (x0, y0, x0 + cw, y0 + ch)
        img = Image.new("RGB", (cw * 2 + 30, ch + 70), (16, 16, 20))
        dr = ImageDraw.Draw(img)
        st = STYLE[boss]
        dr.text((12, 8), "%s · %s · 同一帧（Boss 弹 %d 颗）· 专属弹形：%s · 1 美术像素 = %.2f 屏幕像素（同游戏 1080p）" % (st["name"], MOVE[boss], n, st["shape_name"], scale),
                fill=(235, 235, 240), font=V1.font(18))
        for ti, (nm, t) in enumerate([("现在（实机）", cur), ("第二版", new)]):
            x = 10 + ti * (cw + 10)
            img.paste(t.crop(box).convert("RGB"), (x, 60))
            dr.text((x + 6, 38), nm, fill=(235, 235, 240), font=V1.font(15))
        fn = os.path.join(outdir, "v2_compare_%s.png" % boss)
        img.save(fn)
        # 放大：弹最密处 360×240 → ×3
        pts = [(V1.world_to_img(js, b[0], b[1] - 16)[0] * k, V1.world_to_img(js, b[0], b[1] - 16)[1] * k) for b in js["b"]]
        best_c, best_n = (bx * k, by * k), -1
        for (qx, qy) in pts:
            m = sum(1 for (ax, ay) in pts if abs(ax - qx) < 180 and abs(ay - qy) < 120)
            if m > best_n:
                best_c, best_n = (qx, qy), m
        zx, zy = int(best_c[0]), int(best_c[1])
        zx0 = min(max(0, zx - 180), cur.width - 360)
        zy0 = min(max(0, zy - 120), cur.height - 240)
        zb = (zx0, zy0, zx0 + 360, zy0 + 240)
        z = Image.new("RGB", (1080 * 2 + 30, 720 + 50), (16, 16, 20))
        dz = ImageDraw.Draw(z)
        for ti, (nm, t) in enumerate([("现在", cur), ("第二版", new)]):
            z.paste(t.crop(zb).resize((1080, 720), Image.NEAREST).convert("RGB"), (10 + ti * 1090, 44))
            dz.text((16 + ti * 1090, 12), "%s · %s（弹最密处 ×3 放大）" % (st["name"], nm), fill=(235, 235, 240), font=V1.font(16))
        z.save(os.path.join(outdir, "v2_zoom_%s.png" % boss))
        print(fn, n)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["sheet", "compare"])
    ap.add_argument("--out", required=True)
    ap.add_argument("--cur")
    a = ap.parse_args()
    sheet(a.out) if a.mode == "sheet" else compare(a.cur, a.out)
