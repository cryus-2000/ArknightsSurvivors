#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""凯尔希转平面送审 GIF（docs/265；协调人 11-05 流程：上 GCP 前先给用户看 GIF，只用 Python、不开 Godot）。

拼 tools/pxplane_kal_art.py 烘出的帧条（game/art/fx/pxp/pxp_ka_<键>.png + game/data/pxp_kaltsit.json），摆法照 fx_pxplane_kal.gd：
  - E0 / E1 / E2 并排（只放实际存在的档）；连携单独一张；
  - 游戏地面色背景 + 几只怪（深色剪影）；凯尔希、Mon3tr 用 idle 第 0 帧；
  - 上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素），下半 2 倍放大；15 fps 原速。
贴地层先画；立起层、怪、干员按脚底 y 排序；热芯（emit 点）近似光学发光层加一层柔光。
照地光近似成压扁的柔光椭圆（叠加）；Noita 颗粒用和游戏同一套材质参数（fx_recipe.MATS）做简易模拟；场景压暗不模拟。

用法：python tools/pxplane_gif_kaltsit.py [--only claw,heal] [--out 目录]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
W, H = 440, 260
OX, OY = 110, 160          # 凯尔希脚底（世界像素）
GROUND = (36, 46, 48)
SY = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"
M3 = (22, 9)               # Mon3tr 待命位（美术像素，相对凯尔希脚底；rest [44, 18] 世界）
HOV = 4                    # Mon3tr 悬浮（美术像素约 2，取 4 世界）


class Lib:
    def __init__(self):
        m = json.load(open(os.path.join(ROOT, "game", "data", "pxp_kaltsit.json"), encoding="utf-8"))
        self.meta = {k: v for k, v in m.items() if k != "_doc"}
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta[k]
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ka_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite_frames(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


# fx_recipe.MATS 的子集（世界像素 / 秒）
MATS = {
    "ember": {"grav": 900.0, "rest": 0.38, "bounce": 1, "land": 0.3, "sz": [2, 4], "spd": [60.0, 170.0], "up": [80.0, 210.0], "life": 0.8},
    "rise": {"grav": -55.0, "rest": 0.0, "bounce": 0, "land": 0.0, "sz": [2, 2], "spd": [4.0, 16.0], "up": [18.0, 40.0], "life": 1.0},
    "dust": {"grav": 420.0, "rest": 0.0, "bounce": 0, "land": 0.25, "sz": [2, 2], "spd": [40.0, 110.0], "up": [30.0, 80.0], "life": 0.5},
}
GR = ((170, 242, 62), (30, 62, 34))
HEAL = ((238, 246, 228), (70, 168, 124))
MELT = ((255, 108, 46), (92, 16, 13))
DUST = ((132, 138, 120), (58, 64, 56))
LG = (156, 240, 58)          # 照地光：荧光绿
LH = (168, 240, 207)         # 治疗薄荷
LM = (255, 108, 46)          # 熔毁橙红
LMF = (148, 28, 18)          # 熔毁期间脚下暗红


def _lerp(a, b, u):
    return tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3))


class Scene:
    def __init__(self, lib, n):
        self.lib, self.n = lib, n
        self.items = []
        self.enemies = []          # [x, y, 消失拍]
        self.kal = lambda tk: (0.0, 0.0)
        self.m3 = lambda tk: (M3[0], M3[1], 0.0)
        self.m3_face = 1
        self.m3_dye = lambda tk: False   # S3 熔毁期间本体换熔毁红换色贴图
        self.lights = []      # [拍, 地面点（美术像素）, 抬高（世界）, 半径（世界）, 强度, 颜色, 持续拍]
        self.pts = None
        self._spawn = []      # [拍, 地面点（美术像素）, 出生高度（世界）, 材质, 数量, (c0, c1), 方向]
        self.seed = 5

    def light(self, tk, at, r, inten, col, life=2, lift=10):
        self.lights.append([tk, at, lift, r, inten, col, life])

    def pp(self, tk, at, h, mat, n, cols, d=None):
        self._spawn.append([tk, at, h, mat, min(n, 10), cols, d])

    def particles(self, tk):
        """逐拍模拟（4 个子步），结果缓存"""
        if self.pts is None:
            rnd = np.random.default_rng(self.seed)
            hist = []
            live = []
            dt = 1.0 / 60.0
            for t in range(self.n):
                for sp in self._spawn:
                    if sp[0] != t:
                        continue
                    mt = MATS[sp[3]]
                    for _ in range(sp[4]):
                        a = rnd.uniform(0, 2 * math.pi) if sp[6] is None else math.atan2(sp[6][1], sp[6][0]) + rnd.uniform(-0.9, 0.9)
                        v = rnd.uniform(*mt["spd"])
                        live.append({"m": sp[3], "x": OX + sp[1][0] * PX, "y": OY + sp[1][1] * PX, "h": sp[2], "vx": math.cos(a) * v, "vy": math.sin(a) * v * SY,
                                     "vh": rnd.uniform(*mt["up"]), "age": 0.0, "life": mt["life"] * rnd.uniform(0.8, 1.2), "landed": -1.0, "nb": 0,
                                     "sz": mt["sz"][0] if rnd.random() < 0.5 else mt["sz"][1], "c": sp[5]})
                for _ in range(4):
                    keep = []
                    for q in live:
                        mt = MATS[q["m"]]
                        q["age"] += dt
                        if q["landed"] >= 0:
                            q["landed"] += dt
                            if q["landed"] < mt["land"]:
                                keep.append(q)
                            continue
                        q["x"] += q["vx"] * dt
                        q["y"] += q["vy"] * dt
                        q["vx"] *= max(0.0, 1 - 1.2 * dt)
                        q["vy"] *= max(0.0, 1 - 1.2 * dt)
                        q["vh"] -= mt["grav"] * dt
                        q["h"] += q["vh"] * dt
                        if q["h"] <= 0:
                            q["h"] = 0
                            if q["nb"] < mt["bounce"] and abs(q["vh"]) > 60:
                                q["nb"] += 1
                                q["vh"] = -q["vh"] * mt["rest"]
                                q["vx"] *= 0.55
                                q["vy"] *= 0.55
                            elif mt["land"] > 0:
                                q["landed"] = 0.0
                        if q["age"] < q["life"] + mt["land"]:
                            keep.append(q)
                    live = keep
                snap = []
                for q in live:
                    u = min(1.0, q["age"] / max(0.001, q["life"]))
                    c = _lerp(q["c"][0], q["c"][1], min(1.0, u * 1.4))
                    if q["landed"] >= 0:
                        c = _lerp(c, (0, 0, 0), 0.35)
                    snap.append((round(q["x"] / 2) * 2, round((q["y"] - q["h"]) / 2) * 2, q["sz"], c, q["landed"] < 0 and u < 0.35))
                hist.append(snap)
            self.pts = hist
        return self.pts[tk]

    def add(self, k, tk, gp, flip=False, loop=False, until=None, sk=0.0):
        self.items.append({"k": k, "t0": tk, "gp": gp, "flip": flip, "loop": loop, "until": until, "sk": sk})


ENEMY = KAL = MON = MOND = None


def _isgd(k):
    return k.endswith("_gd") or "_gd_" in k or k.endswith("_gd1")


def render(sc, tk):
    lib = sc.lib
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)
    g = np.asarray(img).copy()
    nz = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(nz, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    em = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(em)

    def place(it):
        if tk < it["t0"] or (it["until"] is not None and tk >= it["until"]):
            return None
        r = lib.frame(it["k"], tk - it["t0"] if not it["loop"] else tk, it["loop"])
        if r is None:
            return None
        fr, m = r
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gp = it["gp"](tk) if callable(it["gp"]) else it["gp"]
        gx, gy = round((OX + gp[0] * PX) / 2) * 2, round((OY + gp[1] * PX) / 2) * 2
        left = gx - (m["w"] - m["ox"]) * PX if it["flip"] else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        fi = (tk - it["t0"]) if not it["loop"] else tk % m["n"]
        return big, (int(left), int(top)), gy + it["sk"] * PX, m["emit"][fi], m, it["flip"]

    def emit(p):
        big, (l, t), _, pts, m, fl = p
        for q in pts:
            x = q[0] if not fl else m["w"] - 1 - q[0]
            ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))

    for it in sc.items:
        if _isgd(it["k"]):
            p = place(it)
            if p:
                img.alpha_composite(p[0], dest=(max(0, p[1][0]), max(0, p[1][1])), source=(max(0, -p[1][0]), max(0, -p[1][1])))
                emit(p)
    srt = []
    for e in sc.enemies:
        if e[2] >= 0 and tk >= e[2]:
            continue
        srt.append((OY + e[1] * PX, "e", e))
    kx, ky = sc.kal(tk)
    srt.append((OY + ky * PX, "k", (kx, ky)))
    mx, my, mh = sc.m3(tk)
    if mx is not None:
        srt.append((OY + my * PX, "m", (mx, my, mh)))
    for it in sc.items:
        if not _isgd(it["k"]):
            p = place(it)
            if p:
                srt.append((p[2] + 1, "fx", p))
    srt.sort(key=lambda s: s[0])
    for _, kind, v in srt:
        if kind == "e":
            x, y = OX + v[0] * PX - ENEMY.width // 2, OY + v[1] * PX - ENEMY.height + 6
            img.alpha_composite(ENEMY, dest=(int(x), int(y)))
        elif kind == "k":
            x, y = OX + v[0] * PX - 64, OY + v[1] * PX - 120
            img.alpha_composite(KAL, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))
        elif kind == "m":
            if sc.m3_dye(tk):   # 熔毁期间：本体一点暖色 + 红粒子轮廓叠层（A / B 按拍交替）
                spr = MOND[0].copy()
                spr.alpha_composite(MOND[1][tk % 2])
            else:
                spr = MON
            spr = spr if sc.m3_face > 0 else spr.transpose(Image.FLIP_LEFT_RIGHT)
            x, y = OX + v[0] * PX - 128, OY + v[1] * PX - 184 - HOV - v[2] * PX
            # 影子
            ImageDraw.Draw(img).ellipse([OX + v[0] * PX - 16, OY + v[1] * PX - 5, OX + v[0] * PX + 16, OY + v[1] * PX + 5], fill=(18, 24, 24, 255))
            img.alpha_composite(spr, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))
        else:
            img.alpha_composite(v[0], dest=(max(0, v[1][0]), max(0, v[1][1])), source=(max(0, -v[1][0]), max(0, -v[1][1])))
            emit(v)
    dr = ImageDraw.Draw(img)
    for (x, y, sz, c, hot) in sc.particles(tk):
        dr.rectangle([x, y, x + sz - 1, y + sz - 1], fill=c + (255,))
        if hot:
            ed.rectangle([x, y, x + sz - 1, y + sz - 1], fill=c)
    glow = np.asarray(em.filter(ImageFilter.GaussianBlur(2))).astype(np.float32) * 0.45
    base = np.asarray(img.convert("RGB")).astype(np.float32)
    # 照地光：压扁的柔光椭圆，强度随寿命线性衰减（近似光学层点光）
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lit = np.zeros((H, W, 3), np.float32)
    for (t0, at, lift, r, inten, col, life) in sc.lights:
        if not (t0 <= tk < t0 + life):
            continue
        k = inten * (1.0 - (tk - t0) / life)
        cx, cy = OX + at[0] * PX, OY + at[1] * PX
        d = np.sqrt(((xx - cx) / r) ** 2 + ((yy - cy) / (r * SY)) ** 2)
        fall = np.clip(1.0 - d, 0, 1) ** 2 * k
        lit += fall[..., None] * np.array(col, np.float32)[None, None, :] * 0.55
    return Image.fromarray(np.clip(base + glow + lit, 0, 255).astype(np.uint8), "RGB")


def gif(cols, n, path, title, zc):
    try:
        font = ImageFont.truetype(FONT, 15)
        sfont = ImageFont.truetype(FONT, 12)
    except OSError:
        font = sfont = ImageFont.load_default()
    head = 28
    frames = []
    for tk in range(n):
        sheet = Image.new("RGB", (W * len(cols) + 4 * (len(cols) - 1), head + H + 4 + H + 18), (14, 16, 18))
        d = ImageDraw.Draw(sheet)
        for ci, (lab, sc) in enumerate(cols):
            x0 = ci * (W + 4)
            im = render(sc, tk)
            sheet.paste(im, (x0, head))
            zx, zy = OX + zc[0] * PX, OY + zc[1] * PX
            crop = im.crop((int(zx - W / 4), int(zy - H / 4), int(zx + W / 4), int(zy + H / 4))).resize((W, H), Image.NEAREST)
            sheet.paste(crop, (x0, head + H + 4))
            d.text((x0 + 6, 5), lab, fill=(235, 225, 200), font=font)
            d.text((x0 + 6, head + H + 4 + H + 2), "上：1 倍（实机大小）  下：2 倍放大", fill=(140, 140, 140), font=sfont)
        d.text((sheet.width - 6 - d.textlength(title, font=sfont), head + H + 4 + H + 2), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    mos = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        mos.paste(f, (0, i * f.height))
    pal = mos.quantize(colors=255, method=Image.MAXCOVERAGE)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(os.path.basename(path), len(q), "帧")


# ================================================================ 摆法（照 fx_pxplane_kal.gd）

E_FRONT = [[52, -6, -1], [60, 6, -1], [70, -12, -1], [66, 14, -1], [80, 0, -1], [92, -8, -1]]


def claw(sc, tk, at, tier, Rw, sw, flip=False, melt=False, hits=()):
    pre = "mclaw" if melt else "claw"
    if hits:
        e = hits[0]
        hp = (e[0], e[1] - 6)
        d = (e[0] - at[0], e[1] - at[1])
        sc.pp(tk, (e[0], e[1]), 12, "ember", 3 if melt else 2 + tier, MELT if melt else GR, d)
        sc.light(tk, (e[0], e[1]), 110 if melt else 90, 0.5 if melt else 0.35, LM if melt else LG)
    sc.add("%s_r%d_s%d_up" % (pre, Rw, sw), tk, at, flip)
    sc.add("%s_r%d_s%d_%s" % (pre, Rw, sw, "gd1" if (tier >= 1 and not melt) else "gd"), tk, at, flip)
    if tier >= 2 and not melt:
        for e in hits[:3]:
            sc.add("spike_up", tk + 1, (e[0], e[1]))
            sc.add("spike_gd", tk + 1, (e[0], e[1]))


def heal(sc, tk, tgt, tier, power=False):
    sc.add("heal_gd", tk, tgt)
    sc.pp(tk, tgt, 4, "rise", 3 if power else 4, HEAL)
    sc.light(tk, tgt, 90 if power else 70, 0.35 if power else 0.3, LH, lift=20)
    if power:
        return
    if tier >= 1:
        sc.add("heal_cross_up", tk, tgt, sk=1)
    if tier >= 2:
        sc.add("heal_col_up", tk, tgt, sk=-2)


def scenes(lib):
    out = {}

    def base(n, en=E_FRONT):
        s = Scene(lib, n)
        s.enemies = [list(e) for e in en]
        return s

    # 普攻 · Mon3tr 爪击（E0 109 / E1 128 / E2 161：精二按「战术协同」已开，范围 × 1.3）
    cols = []
    for t, Rw in ((0, 109), (1, 128), (2, 161)):
        s = base(26)
        claw(s, 2, M3, t, Rw, 0, hits=[E_FRONT[0], E_FRONT[1], E_FRONT[3]])
        claw(s, 14, M3, t, Rw, 1, hits=[E_FRONT[2], E_FRONT[4]])
        cols.append(("普攻 Mon3tr 爪击 精英 %d（外沿 %d）" % (t, Rw), s))
    out["claw"] = (cols, 26, (50, -6))
    # 节点「骨爪增生」双爪 + 精二身后一爪（mirror）
    s = base(22, E_FRONT + [[-14, 6, -1], [-6, -6, -1]])
    claw(s, 2, M3, 2, 161, 0, hits=[E_FRONT[0], E_FRONT[1]])
    s.add("claw_r161_s1_up", 3, M3)   # 0.08 秒后第二爪（另一向挥，交叉）
    s.add("claw_r161_s1_gd1", 3, M3)
    claw(s, 2, M3, 2, 161, 0, flip=True, hits=[[-14, 6, -1]])
    out["claw_nodes"] = ([("节点「骨爪增生」第二爪 + 精二身后一爪", s)], 22, (24, -6))
    # 治疗（普攻）：E0 缝合环；E1 + 十字；E2 + 下针光柱。目标 = 队长（这里凯尔希自己当队长）
    cols = []
    for t in (0, 1, 2):
        s = base(18, [])
        s.m3 = lambda tk: (None, 0, 0)
        heal(s, 2, (0, 0), t)
        cols.append(("普攻 治疗 精英 %d" % t, s))
    out["heal"] = (cols, 18, (0, -14))
    # 精一扑击
    cols = []
    for t in (1, 2):
        s = base(20, [[66, -2, -1], [72, 8, -1], [60, 12, -1]])

        def mp(tk):
            if tk < 2:
                return (M3[0], M3[1], 0.0)
            u = min(1.0, (tk - 2) / 2.0)
            return (M3[0] + (56 - M3[0]) * (1 - (1 - u) ** 2), M3[1] + (2 - M3[1]) * u, 0.0)
        s.m3 = mp
        s.add("pounce_up", 4, (56, 2))
        s.add("pounce_gd", 4, (56, 2))
        s.light(4, (56, 2), 90, 0.35, LG, lift=8)
        s.pp(4, (56, 2), 2, "dust", 6, DUST)
        claw(s, 7, (56, 2), t, 128, 0, hits=[[66, -2], [72, 8]])
        cols.append(("精一「扑击」落地（半径 40）精英 %d" % t, s))
    out["lunge"] = (cols, 20, (56, -4))
    # 精二回防 / 护主（技能响应）
    s = base(22, [[-30, -10, -1], [-40, 8, -1], [-24, 20, -1], [-50, -2, -1]])

    def leap(tk):
        if tk < 2:
            return (M3[0], M3[1], 0.0)
        u = min(1.0, (tk - 2) / 4.0)
        return (M3[0] + (60 - M3[0]) * u, M3[1] + (2 - M3[1]) * u, 23 * math.sin(math.pi * u))
    s.enemies = [[60 + e[0] + 30, e[1], -1] for e in [[-30, -10], [-40, 8], [-24, 20], [-50, -2], [-8, -16], [20, 4]]]
    s.m3 = leap
    s.add("guard_gd", 6, (60, 2))
    s.add("guard_bk_up", 6, (60, 2), sk=-3)
    s.add("guard_fr_up", 6, (60, 2))
    s.light(6, (60, 2), 160, 0.5, LG)
    s.pp(6, (60, 2), 2, "dust", 8, DUST)
    out["guard"] = ([("精二「回防」/「护主」落地（半径 100）", s)], 22, (60, -8))
    # S1 结构加固（队长身上）：骨肋合拢 + 治疗（E1 + 六角板，E2 + 头顶结扣）
    cols = []
    for t in (0, 1, 2):
        s = base(20, [])
        s.add("s1rib_bk_up", 2, (0, 0), sk=-3)
        s.add("s1rib_fr2_up" if t >= 2 else "s1rib_fr_up", 2, (0, 0), sk=1)
        if t >= 1:
            s.add("s1hex_gd", 2, (0, 0))
        heal(s, 4, (0, 0), t, power=True)   # 技能治疗只出地环 + 光点（同招元素 ≤ 3：骨肋 + 地面件 + 结扣）
        s.light(2, (0, 0), 120, 0.45, LH, lift=30)
        cols.append(("S1「结构加固」精英 %d" % t, s))
    out["s1"] = (cols, 20, (0, -16))
    # S1 分支「不毁重构」：Mon3tr 处三连爆（70 结晶 → 87 / 105 回响环）
    s = base(42, [[30, -10, -1], [40, 14, -1], [10, 18, -1], [50, 0, -1]])
    s.add("melt_r70_up", 2, M3, sk=3)
    s.add("melt_r70_gd", 2, M3)
    s.add("echo_r87_gd", 2 + 3, M3)
    s.add("echo_up", 2 + 3, M3, sk=3)
    s.add("echo_r105_gd", 2 + 6, M3)
    s.add("echo_up", 2 + 6, M3, sk=3)
    s.add("rebuild_up", 2 + 7, M3, sk=2)   # 三连爆之后：碎片回收 + 骨架一段段亮起合拢
    s.light(2, M3, 160, 0.65, LM, lift=20)
    s.pp(4, M3, 30, "ember", 6, MELT)
    s.pp(5, M3, 16, "ember", 4, MELT)
    s.pp(8, M3, 16, "ember", 4, MELT)
    s.light(9 + 11, M3, 150, 0.7, LM, lift=22)
    s.add("rebuild_gd", 2 + 7, M3)
    for k in range(3):   # 余焰（节点 5）：每 0.5 秒一圈淡边
        s.add("smol_r105_gd", 24 + k * 7 + 0, M3)
    out["s1_rebuild"] = ([("S1 分支「不毁重构」三连爆 → 重构 + 余焰", s)], 42, (22, -14))
    # S2 战术协同（Mon3tr 身上）
    cols = []
    for t in (1, 2):
        s = base(18, [])
        s.add("s2hex_gd", 2, M3)
        s.add("s2cmd_up", 2, M3, sk=1)
        s.light(2, M3, 100, 0.45, LG, lift=30)
        if t >= 2:
            s.add("s2str_up", 3, M3, sk=1)
        cols.append(("S2「战术协同」精英 %d" % t, s))
    out["s2"] = (cols, 18, (22, -18))
    # S3 熔毁：起手爆柱 → 持续热流 + 熔毁爪 → 结束一枚大结晶炸开（半径 130）
    s = base(46, E_FRONT)
    s.m3_dye = lambda tk: 1 <= tk < 27
    s.add("s3cast_up", 1, M3, sk=2)
    s.add("s3cast_gd", 1, M3)
    s.add("s3aura_up", 3, lambda tk: M3, loop=True, until=26, sk=1)
    s.add("s3aura_gd", 3, lambda tk: M3, loop=True, until=26)
    claw(s, 8, M3, 2, 161, 0, melt=True, hits=[E_FRONT[0], E_FRONT[1]])
    claw(s, 17, M3, 2, 161, 1, melt=True, hits=[E_FRONT[2]])
    for k in range(1, 27):   # 熔毁期间：脚下常驻暗红照地光 + 火星从本体轮廓往上飘
        if k % 2 == 0:
            s.light(k, M3, 110, 0.35, LMF, life=2, lift=6)
        else:
            s.pp(k, (M3[0] + ((k * 37) % 36 - 18) / 2.0, M3[1]), 30 + (k * 23) % 66, "rise", 1, MELT)
    s.light(1, M3, 130, 0.6, LM, lift=40)
    s.light(27, M3, 240, 1.0, LM, lift=20)
    s.pp(29, M3, 30, "ember", 10, MELT)
    s.pp(29, M3, 20, "rise", 4, MELT)
    s.add("melt_r130_up", 27, M3, sk=3)
    s.add("melt_r130_gd", 27, M3)
    out["s3"] = ([("S3「熔毁」精英 2（红：起手 → 熔毁爪 → 结束熔毁爆）", s)], 46, (30, -8))
    # 连携「Mon3tr 掩护」（link/v2 缺省版）：落到队长前方，朝敌一侧骨刺墙 + 推波；凯尔希给队长回复
    s = base(20, [[60, -4, -1], [70, 8, -1], [64, -14, -1]])
    s.m3 = lambda tk: (25, 0, 0.0)
    s.add("link_up_d0", 2, (25, 0), sk=1)
    s.add("link_gd_d0", 2, (25, 0))
    s.light(2, (25, 0), 150, 0.55, LG, lift=16)
    s.pp(2, (40, 0), 2, "dust", 7, DUST, (1, 0))
    heal(s, 3, (0, 0), 2)
    out["link"] = ([("连携技「Mon3tr 掩护」（link/v2 缺省版）", s)], 20, (30, -6))
    return out


def main():
    global ENEMY, KAL, MON, MOND
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_kaltsit_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib()
    en = sprite_frames(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)[0]
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    KAL = sprite_frames(os.path.join(ROOT, "game", "art", "operators", "kaltsit", "op_kaltsit_idle@2x.png"), 8)[0]
    # Mon3tr 用游戏里实际画的 native 帧条（sprites.m_idle.visual → native_m_idle，17 帧，@2x 每帧 256×256，脚底 (128, 184)）
    MON = sprite_frames(os.path.join(ROOT, "game", "art", "operators", "kaltsit", "op_mon3tr_native_idle@2x.png"), 17)[0]
    RIM = [sprite_frames(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_ka_rim%s_op_mon3tr_native_idle_2x.png" % v), 17)[0] for v in "ab"]
    warm = np.asarray(MON).astype(np.float32)
    warm[..., 0] *= 1.1
    warm[..., 1] *= 0.92
    warm[..., 2] *= 0.9
    MW = Image.fromarray(np.clip(warm, 0, 255).astype(np.uint8), "RGBA")
    MOND = (MW, RIM)
    only = set(x for x in a.only.split(",") if x)
    for name, (cols, n, zc) in scenes(lib).items():
        if only and name not in only:
            continue
        gif(cols, n, os.path.join(a.out, "kaltsit_%s.gif" % name), "凯尔希 · 转平面 · 15 fps 原速", zc)


if __name__ == "__main__":
    main()
