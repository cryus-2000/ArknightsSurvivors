#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""水月转平面（docs/261）交审前预览：只用 Python 把烘焙好的帧条（game/art/fx/pxp/pxp_mz_*.png + data/pxp_mizuki.json）拼成 GIF，不开 Godot。

11-05 新流程：上 GCP 出实机图之前先给用户看 GIF。每招一张，E0 / E1 / E2 左右并排（只放该招实际存在的档位），连携技单独一张；
背景用游戏地面色（深海地形贴图平铺），打在几只怪的剪影上；1 倍尺寸（1 特效像素 = 2 屏幕像素，同游戏）另附 _x2 两倍放大；15 fps 原速循环。
摆放规则照 fx_pxplane.gd 的水月段：伞面挂在人身上、命中水母原点 = 命中点、触手在目标脚边离水月远的一侧钻出、缠绕分前后半圈、
立起件和单位按脚底 y 排序、贴地件在最下层；热芯 emit 点加一层柔光（近似光学层发光，实机还会被场景压暗 / 受光）。

用法（仓库根目录）：python tools/pxplane_gif_mizuki.py [--out 目录] [--only atk,s1,...]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2
FPS = 15
PW, PH = 380, 270            # 每格（世界像素 = 1 倍屏幕像素）
META = json.load(open(os.path.join(ROOT, "game", "data", "pxp_mizuki.json"), encoding="utf-8"))
_cache = {}


def strip(k):
    if k not in _cache:
        m = META[k]
        im = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        _cache[k] = [im.crop((i * w, 0, (i + 1) * w, h)).resize((w * PX, h * PX), Image.NEAREST) for i in range(m["n"])]
    return _cache[k]


def snap(x, y):
    return (round(x / 2) * 2, round(y / 2) * 2)


def font(sz):
    for f in ("C:/Windows/Fonts/msyhl.ttc", "C:/Windows/Fonts/msyh.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


# ---------------------------------------------------------------- 背景与单位
def ground():
    t = Image.open(os.path.join(ROOT, "game", "art", "world", "terrain", "terrain_regions.png")).convert("RGBA")
    tile = t.crop((0, 0, 32, 32)).resize((64, 64), Image.NEAREST)
    bg = Image.new("RGBA", (PW, PH), (24, 45, 55, 255))
    for y in range(0, PH, 64):
        for x in range(0, PW, 64):
            bg.alpha_composite(tile, (x, y))
    return bg


def _frames(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


MZ_IDLE = _frames(os.path.join(ROOT, "game/art/operators/mizuki/mizuki_runtime_idle@2x.png"), 36)
MZ_ATK = _frames(os.path.join(ROOT, "game/art/operators/mizuki/mizuki_runtime_attack@2x.png"), 8)
MZ_SK = _frames(os.path.join(ROOT, "game/art/operators/mizuki/mizuki_runtime_skill_start@2x.png"), 8)
EN = {
    "runner": (_frames(os.path.join(ROOT, "game/art/enemies/runner/e_runner@2x.png"), 4)[0], (0.56, 0.875)),
    "slider": (_frames(os.path.join(ROOT, "game/art/enemies/slider/e_slider@2x.png"), 4)[0], (0.5, 0.85)),
}


def silhouette(im):
    a = np.asarray(im)[..., 3]
    out = np.zeros((im.height, im.width, 4), np.uint8)
    out[..., 0], out[..., 1], out[..., 2] = 9, 14, 20
    out[..., 3] = (a > 40) * 235
    return Image.fromarray(out, "RGBA")


EN_S = {k: (silhouette(v[0]).resize((v[0].width * 3 // 4, v[0].height * 3 // 4), Image.NEAREST), v[1]) for k, v in EN.items()}   # @2x → 世界 × 体型缺省 1.5（docs 密度定案）


def mz_sprite(t, swings, casts, face):
    im = MZ_IDLE[int(t * 6.75) % 36]
    for c in casts:
        if c <= t < c + 0.5:
            im = MZ_SK[min(7, int((t - c) * 16))]
    for s in swings:
        if s - 0.27 <= t < s + 0.45:
            im = MZ_ATK[min(7, int((t - s + 0.27) / 0.09))]
    sc = 0.45
    im = im.resize((int(im.width * sc), int(im.height * sc)), Image.NEAREST)
    if face < 0:
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
    return im, (im.width * 0.5, 151 * sc)


# ---------------------------------------------------------------- 场景：一格 = 一个档位
class Panel:
    def __init__(self, label, mz=(130, 150), face=1):
        self.label, self.mz, self.face = label, mz, face
        self.items, self.enemies, self.swings, self.casts, self.jel = [], [], [], [], []

    def en(self, x, y, kind="runner", r=20):
        e = {"pos": (x, y), "kind": kind, "r": r}
        self.enemies.append(e)
        return e

    def add(self, k, t0, gp, ly="up", flip=False, gy=None, loop=False, life=None):
        if k not in META:
            raise KeyError(k)
        self.items.append({"k": k, "t0": t0, "gp": snap(*gp), "ly": ly, "flip": flip, "gy": gp[1] + 1 if gy is None else gy, "loop": loop, "life": life})

    def pair(self, k, t0, gp, flip=False, gy=None, **kw):
        self.add(k + "_up", t0, gp, "up", flip, gy, **kw)
        self.add(k + "_gd", t0, gp, "gd", flip, gy, **kw)

    # 下面几样照 fx_pxplane.gd 水月段的摆法
    def slash(self, key, t0, ang=0.0, spin=False):
        self.swings.append(t0)
        if spin:
            self.pair(key, t0, self.mz)
            return
        d, flip = pick_dir(ang)
        self.add("%s_up_d%d" % (key, d), t0, self.mz, "up", flip)
        self.add("%s_gd_d%d" % (key, d), t0, self.mz, "gd", flip)

    def bloom(self, key, t0, e):
        x, y = e["pos"]
        self.add(key, t0, (x, y - e["r"] * 0.55), "up", gy=y + 2)

    def tent(self, key, t0, e, bind=0.0, tier=1):
        x, y = e["pos"]
        side = 1 if x >= self.mz[0] else -1
        bx, by = x + side * e["r"] * 0.55, y + 3
        self.add(key + "_up", t0, (bx, by), "up", side > 0, gy=by + 0.5)
        self.add(key + "_gd", t0, (bx, by), "gd", side > 0)
        if bind >= 0.45:
            rx = min([6, 9, 13, 18], key=lambda v: abs(v - e["r"] * 0.5))
            for half, so in (("back", -1.5), ("front", 1.5)):
                self.add("mz_coil_r%d_e%d_%s_up" % (rx, max(1, min(2, tier)), half), t0, (x, y), "up", gy=y + 1 + so, loop=True, life=min(bind, 1.2))


def pick_dir(ang):
    a = (math.degrees(ang) + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = min([-90, -45, 0, 45, 90], key=lambda d: abs(a - d))
    return best, flip


def jelly_home(mz, k, n, t):
    ang = t * 0.6 + k * math.tau / max(1, n)
    ph = t * 1.3 + k * 2.1
    return (mz[0] + math.cos(ang) * 34, mz[1] - 34 + math.sin(ang) * 12 + math.sin(ph * 1.7) * 3)


def comp(img, fr, x, y):
    """alpha_composite，超出画布的部分裁掉（不整张丢）"""
    x0, y0 = max(0, -x), max(0, -y)
    x1, y1 = min(fr.width, img.width - x), min(fr.height, img.height - y)
    if x1 <= x0 or y1 <= y0:
        return
    img.alpha_composite(fr.crop((x0, y0, x1, y1)), (x + x0, y + y0))


def render_panel(P, t):
    img = ground()
    glow = np.zeros((PH, PW, 3), np.float32)

    def draw_item(it):
        fi = int(math.floor(t * FPS + 1e-6)) - int(math.floor(it["t0"] * FPS + 1e-6))
        frs = strip(it["k"])
        m = META[it["k"]]
        if it["loop"]:
            if t < it["t0"] or t > it["t0"] + (it["life"] or 99):
                return
            fi = int(math.floor(t * FPS + 1e-6)) % len(frs)
        elif fi < 0 or fi >= len(frs):
            return
        fr = frs[fi]
        gx, gy = it["gp"]
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
            left = gx - (m["w"] - m["ox"]) * PX
        else:
            left = gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        comp(img, fr, int(left), int(top))
        for q in (m["emit"][fi] if fi < len(m["emit"]) else []):
            x = q[0] if not it["flip"] else m["w"] - 1 - q[0]
            X, Y = int(left + x * PX), int(top + q[1] * PX)
            if 0 <= X < PW - 1 and 0 <= Y < PH - 1:
                c = int(q[2], 16)
                glow[Y:Y + 2, X:X + 2] += np.array([(c >> 16) & 255, (c >> 8) & 255, c & 255], np.float32) / 255.0 * 0.8

    def safe(fn):
        def w(*a):
            try:
                fn(*a)
            except ValueError:
                pass
        return w

    for it in P.items:
        if it["ly"] == "gd":
            safe(draw_item)(it)
    draws = []
    for it in P.items:
        if it["ly"] == "up":
            draws.append((it["gy"], lambda it=it: safe(draw_item)(it)))
    for e in P.enemies:
        sil, (ax, ay) = EN_S[e["kind"]]
        x, y = e["pos"]
        draws.append((y, lambda sil=sil, ax=ax, ay=ay, x=x, y=y: comp(img, sil, int(x - sil.width * ax), int(y - sil.height * ay))))
    mzim, (fx, fy) = mz_sprite(t, P.swings, P.casts, P.face)
    draws.append((P.mz[1], lambda: comp(img, mzim, int(P.mz[0] - fx), int(P.mz[1] - fy))))
    for jf in P.jel:   # 深蓝之籽：jf(t) → [(位置, 速度)]
        for (p, v) in jf(t):
            def dj(p=p, v=v):
                if math.hypot(*v) > 1:
                    L = math.hypot(*v)
                    for i, col in enumerate([(154, 168, 255), (90, 124, 240), (49, 80, 200)]):
                        q = snap(p[0] - v[0] / L * (6 + 6 * i), p[1] - v[1] / L * (6 + 6 * i))
                        ImageDraw.Draw(img).rectangle([q[0], q[1], q[0] + 1, q[1] + 1], fill=col + (255,))
                safe(draw_item)({"k": "mz_jelly_up", "t0": 0, "gp": snap(p[0], p[1] + 6), "flip": False, "loop": True, "life": 99})
            draws.append((p[1] + 34, dj))
    for _, fn in sorted(draws, key=lambda d: d[0]):
        fn()
    g = Image.fromarray(np.clip(glow * 255, 0, 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(3))
    a = np.asarray(img).astype(np.float32)
    a[..., :3] = np.clip(a[..., :3] + np.asarray(g).astype(np.float32) * 0.9, 0, 255)
    img = Image.fromarray(a.astype(np.uint8), "RGBA")
    ImageDraw.Draw(img).text((8, 6), P.label, fill=(205, 214, 255, 255), font=font(14))
    return img


def make_gif(panels, L, path, title):
    n = int(round(L * FPS))
    frames1, frames2 = [], []
    for i in range(n):
        t = i / FPS
        row = Image.new("RGBA", (PW * len(panels) + 4 * (len(panels) - 1), PH + 24), (10, 12, 18, 255))
        ImageDraw.Draw(row).text((8, 3), title, fill=(220, 225, 240, 255), font=font(14))
        for j, P in enumerate(panels):
            row.alpha_composite(render_panel(P, t), (j * (PW + 4), 24))
        rgb = row.convert("RGB")
        frames1.append(rgb)
        frames2.append(rgb.resize((rgb.width * 2, rgb.height * 2), Image.NEAREST))
    for fr, p in ((frames1, path), (frames2, path.replace(".gif", "_x2.gif"))):
        q = [f.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE) for f in fr]
        q[0].save(p, save_all=True, append_images=q[1:], duration=int(1000 / FPS), loop=0, disposal=1, optimize=False)
    print(path, n, "帧")


# ---------------------------------------------------------------- 每招的时间线
def cone_enemies(P):
    es = [P.en(205, 128, "runner", 20), P.en(222, 168, "slider", 22), P.en(190, 196, "runner", 20), P.en(178, 112, "slider", 22), P.en(238, 144, "runner", 20)]
    return es


def jel_fn(P, n, out=None):
    """n 只身后水母；out = (第几只, 起飞时刻, 目标) → 0.3 秒飞到、蛰中、0.45 秒飘回"""
    def f(t):
        r = []
        for k in range(n):
            home = jelly_home(P.mz, k, n, t)
            if out and out[0] == k and out[1] <= t < out[1] + 0.75:
                e = out[2]
                tgt = (e["pos"][0], e["pos"][1] - e["r"] * 0.5)
                u = t - out[1]
                if u < 0.3:
                    s = u / 0.3
                    r.append(((home[0] + (tgt[0] - home[0]) * s, home[1] + (tgt[1] - home[1]) * s), (tgt[0] - home[0], tgt[1] - home[1])))
                else:
                    s = (u - 0.3) / 0.45
                    r.append(((tgt[0] + (home[0] - tgt[0]) * s, tgt[1] + (home[1] - tgt[1]) * s), (home[0] - tgt[0], home[1] - tgt[1])))
            else:
                r.append((home, (0, 0)))
        return r
    return f


def mv_atk():
    ps = []
    for t in (0, 1, 2):
        P = Panel(["E0  伞面 + 水母（无触手）", "E1  + 触手（精一新元素）", "E2  + 荧光紫 / 双触手 / 深蓝之籽"][t])
        es = cone_enemies(P)
        for sw in (0.35, 1.25):
            P.slash("mz_atk_r56_e%d" % t, sw)
            P.bloom("mz_bloom_e%d_up" % t, sw, es[0])
            P.bloom("mz_bloom_e%d_up" % t, sw, es[3])
            if t == 0:
                P.bloom("mz_bloom_e0_up", sw, es[1] if sw < 1 else es[4])
            else:
                P.tent("mz_tent_e%d" % t, sw, es[1] if sw < 1 else es[4])
        if t == 2:
            P.jel.append(jel_fn(P, 2, (0, 0.8, es[2])))
            P.bloom("mz_sting_up", 1.1, es[2])
        ps.append(P)
    return ps, 1.8, "普攻「伞击」：每升一档多一个新元素（E0 伞面 + 水母 → E1 触手 → E2 荧光紫 + 深蓝之籽）"


def mv_s1():
    ps = []
    for t in (0, 1, 2):
        P = Panel(["E0  唤醒：大水母 ×3", "E1  + 每团下面钻出触手", "E2  + 荧光紫 / 四瓣纹 / 双触手"][t])
        es = cone_enemies(P)
        P.add("mz_ready_gd", 0, (P.mz[0], P.mz[1] + 4), "gd", loop=True, life=0.42)
        sw = 0.45
        P.slash("mz_s1_r73_e%d" % t, sw)
        P.bloom("mz_bloom_e%d_up" % t, sw, es[0])
        for k, e in enumerate([es[0], es[3], es[1]]):
            x, y = e["pos"]
            P.add("mz_burst_e%d_up" % t, sw + 0.06 * k, (x, y - 16), "up", gy=y + 3)
            P.add("mz_burst_e%d_gd" % t, sw + 0.06 * k, (x, y), "gd")
            if t >= 1:
                P.tent("mz_tent_e%d" % t, sw + 0.06 * k, {"pos": (x, y), "r": 10})
        if t == 0:
            P.bloom("mz_bloom_e0_up", sw, es[2])
        else:
            P.tent("mz_tent_e%d" % t, sw, es[2])
        if t == 2:
            P.jel.append(jel_fn(P, 2))
        ps.append(P)
    return ps, 1.6, "S1「唤醒」：更大更白的伞面 + 三团大水母（创伤扩散），精一起水母下钻出触手"


def mv_s2():
    ps = []
    for t in (1, 2):
        P = Panel(["", "E1  囚徒困境：触手缠一股", "E2  双触手 + 两股交叉对缠"][t])
        es = cone_enemies(P)
        P.casts.append(0.1)
        P.add("mz_s2cast_e%d_up" % t, 0.1, P.mz, "up")
        P.add("mz_s2cast_e%d_gd" % t, 0.1, P.mz, "gd")
        for i, sw in enumerate((0.75, 1.2, 1.65)):
            P.slash("mz_s2_r56_e%d" % t, sw)
            a, b = [(es[0], es[1]), (es[3], es[2]), (es[4], es[0])][i]
            P.bloom("mz_bloom_e%d_up" % t, sw, a)
            P.tent("mz_tent_e%d" % t, sw, a, bind=1.0, tier=t)
            P.tent("mz_tent_e%d" % t, sw, b, bind=1.0, tier=t)
        if t == 2:
            P.jel.append(jel_fn(P, 3))
        ps.append(P)
    return ps, 2.2, "S2「囚徒困境」：起手一圈触手 + 冰蓝尖晶；伞击更快更薄（幻影残弧），触手缠住 1 秒"


def mv_s3():
    P = Panel("E2  镜花水月（精二解锁）", mz=(190, 140))
    es = [P.en(260, 120, "runner", 20), P.en(250, 185, "slider", 22), P.en(120, 170, "runner", 20), P.en(130, 105, "slider", 22), P.en(200, 210, "runner", 20), P.en(290, 160, "runner", 20)]
    P.casts.append(0.1)
    P.add("mz_moon_up", 0.1, P.mz, "up")
    P.add("mz_moon_gd", 0.1, P.mz, "gd")
    P.add("mz_pool_r81_gd", 0.1, (P.mz[0], P.mz[1] + 2), "gd", loop=True, life=9)
    for i, sw in enumerate((0.9, 1.75)):
        P.slash("mz_spin3_r81", sw, spin=True)
        tg = [es[0], es[2], es[4]] if i == 0 else [es[1], es[3], es[5]]
        for e in tg:
            P.bloom("mz_bloom_e2_up", sw, e)
            P.tent("mz_tentbig", sw, e, bind=0.6, tier=2)
    P.jel.append(jel_fn(P, 3))
    return [P], 2.6, "S3「镜花水月」：大水母浮起 + 水镜；旋斩 + 粗触手"


def mv_link():
    P = Panel("link/v2 缺省版，不分档", mz=(90, 150))
    es = [P.en(200, 120), P.en(240, 150, "slider", 22), P.en(210, 185), P.en(280, 120, "slider", 22), P.en(290, 190), P.en(170, 155)]
    P.casts.append(0.15)
    for e in es:
        P.tent("mz_tentlink", 0.2, e, bind=1.0, tier=2)
    return [P], 1.6, "连携「小触手」：6 名敌人脚下高触手，缠住 1 秒"


def mv_extra():
    P1 = Panel("后期 / 分支：藏品剑气 → 小水母游过去；扩散 → 细水纹", mz=(90, 150))
    es = [P1.en(260, 140), P1.en(300, 175, "slider", 22), P1.en(230, 190)]
    P1.jel.append(lambda t: [(((90 + 300 * min(1, t / 0.9)), 128), (300, 0))] if t < 0.95 else [])
    P1.add("mz_ripple_gd", 0.6, es[0]["pos"], "gd")
    P1.add("mz_ripple_gd", 1.0, es[2]["pos"], "gd")
    P2 = Panel("惊跳反射·余悸：身边一圈触手；触手桩", mz=(160, 140))
    P2.en(230, 120); P2.en(100, 170, "slider", 22); P2.en(220, 190)
    P2.pair("mz_awk2", 0.2, P2.mz)
    P2.tent("mz_tent_e1", 1.0, {"pos": (280, 200), "r": 8})
    return [P1, P2], 1.6, "额外攻击（late_shape 召唤流派只加范围 / 伤害；藏品剑气、扩散卡、分支招）"


MOVES = {"atk": mv_atk, "s1": mv_s1, "s2": mv_s2, "s3": mv_s3, "link": mv_link, "extra": mv_extra}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_mizuki_1105", "gif"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for k, fn in MOVES.items():
        if a.only and k not in a.only.split(","):
            continue
        ps, L, title = fn()
        make_gif(ps, L, os.path.join(a.out, "mizuki_%s.gif" % k), title)


if __name__ == "__main__":
    main()
