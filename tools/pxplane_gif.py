#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面帧条的送审 GIF（协调人 11-05 新流程：上 GCP 前先给用户看 GIF，只用 Python、不开 Godot）。

把 tools/pxplane_bake.py 烘出的帧条（game/art/fx/pxp/pxp_<键>.png + game/data/pxp_<人>.json）按游戏里的摆法拼成每招一张 GIF：
  - E0 / E1 / E2 左右并排（只放实际存在的档）；连携技单独一张；
  - 背景游戏地面色，打在几只怪（深色剪影）上，干员本体用 idle 第 0 帧；
  - 每栏上半 1 倍（= 实机大小：1 美术像素 = 2 屏幕像素），下半 2 倍放大（落点附近）；
  - 15 fps 原速循环（GIF 帧时长 70 / 60 / 70 毫秒交替，平均 66.7）。
贴地层先画；立起层、怪、干员按脚底 y 排序；帧条热芯（emit 点）近似光学发光层加一层柔光。场景压暗 / 受光不模拟（实机会被环境光压暗一些）。

用法：python tools/pxplane_gif.py --op siege [--only atk,s1] [--out 目录]
"""
import argparse, json, math, os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
PX = 2                                   # 1 美术像素 = 2 世界像素
W, H = 400, 250                          # 每栏 1 倍画面（世界像素）
OX, OY = 130, 150                        # 干员脚底在画面里的位置（世界像素）
GROUND = (36, 46, 48)
DIRS = [-90, -45, 0, 45, 90]
SY = 0.72
FONT = "C:/Windows/Fonts/msyh.ttc"


def pick_dir(ang):
    a = (ang + 180) % 360 - 180
    flip = False
    if abs(a) > 90:
        a = (180 - a + 180) % 360 - 180
        flip = True
    best = 0
    for d in DIRS:
        if abs(a - d) < abs(a - best):
            best = d
    return best, flip


class Lib:
    def __init__(self, op):
        self.meta = {}
        for name in ("pxp_%s.json" % op,):
            m = json.load(open(os.path.join(ROOT, "game", "data", name), encoding="utf-8"))
            pre = ""   # 键已带前缀（sg_ / hsg_）
            for k, v in m.items():
                if k != "_doc":
                    self.meta[pre + k] = v
        self.tex = {}

    def frame(self, k, fi, loop=False):
        m = self.meta.get(k)
        if m is None:
            raise KeyError(k)
        n = m["n"]
        if loop:
            fi %= n
        if fi < 0 or fi >= n:
            return None
        if k not in self.tex:
            self.tex[k] = Image.open(os.path.join(ROOT, "game", "art", "fx", "pxp", "pxp_%s.png" % k.replace("_d-", "_dm"))).convert("RGBA")
        w, h = m["w"], m["h"]
        return self.tex[k].crop((fi * w, 0, (fi + 1) * w, h)), m


def sprite_frames(path, n):
    im = Image.open(path).convert("RGBA")
    fw = im.width // n
    return [im.crop((i * fw, 0, (i + 1) * fw, im.height)) for i in range(n)]


class Scene:
    """一个时间轴：items = 帧条件（t0 拍号、地面点（美术像素，相对干员脚底）、层、键、flip）；enemies / op 位置函数。"""

    def __init__(self, lib, n_ticks):
        self.lib = lib
        self.n = n_ticks
        self.items = []
        self.enemies = []      # [x, y, 消失拍（-1 = 不消失）]
        self.op_path = lambda tk: (0.0, 0.0, 0.0)   # 拍 → (x, y, 离地高)
        self.tier = 0

    def add(self, k, tk, gp, flip=False, loop=False, fi=None, until=None):
        self.items.append({"k": k, "t0": tk, "gp": gp, "flip": flip, "loop": loop, "fi": fi, "until": until})

    def pair(self, k, tk, gp, flip=False):
        self.add(k + "_up", tk, gp, flip)
        self.add(k + "_gd", tk, gp, flip)


ENEMY = None
OPSPR = None


def render(scene, tk):
    lib = scene.lib
    img = Image.new("RGBA", (W, H), GROUND + (255,))
    rng = np.random.default_rng(7)   # 地面颗粒（固定）
    g = np.asarray(img).copy()
    noise_ = rng.integers(-5, 6, size=(H // 2, W // 2, 1))
    g[..., :3] = np.clip(g[..., :3].astype(int) + np.repeat(np.repeat(noise_, 2, 0), 2, 1), 0, 255)
    img = Image.fromarray(g.astype(np.uint8), "RGBA")
    emit_layer = Image.new("RGB", (W, H), (0, 0, 0))
    ed = ImageDraw.Draw(emit_layer)
    sortables = []

    def place(it):
        fi = (tk - it["t0"]) if it["fi"] is None else it["fi"](tk)
        if it["until"] is not None and tk >= it["until"]:
            return None
        if tk < it["t0"]:
            return None
        r = lib.frame(it["k"], fi, it["loop"])
        if r is None:
            return None
        fr, m = r
        if it["flip"]:
            fr = fr.transpose(Image.FLIP_LEFT_RIGHT)
        gp = it["gp"](tk) if callable(it["gp"]) else it["gp"]
        gx, gy = OX + gp[0] * PX, OY + gp[1] * PX
        gx, gy = round(gx / 2) * 2, round(gy / 2) * 2
        left = gx - (m["w"] - m["ox"]) * PX if it["flip"] else gx - m["ox"] * PX
        top = gy - m["oy"] * PX
        big = fr.resize((fr.width * PX, fr.height * PX), Image.NEAREST)
        pts = m["emit"][fi % len(m["emit"])] if m["emit"] else []
        return big, (int(left), int(top)), gy, pts, m, it["flip"]

    for it in scene.items:
        if not it["k"].endswith("_gd") and "_gd_" not in it["k"]:
            continue
        p = place(it)
        if p:
            img.alpha_composite(p[0], dest=(max(0, p[1][0]), max(0, p[1][1])), source=(max(0, -p[1][0]), max(0, -p[1][1])))
            for q in p[3]:
                x = q[0] if not p[5] else p[4]["w"] - 1 - q[0]
                ed.rectangle([p[1][0] + x * PX, p[1][1] + q[1] * PX, p[1][0] + x * PX + PX - 1, p[1][1] + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))
    for e in scene.enemies:
        if e[2] >= 0 and tk >= e[2]:
            continue
        sortables.append((OY + e[1] * PX, "enemy", e))
    ox, oy, oh = scene.op_path(tk)
    sortables.append((OY + oy * PX, "op", (ox, oy, oh)))
    for it in scene.items:
        if it["k"].endswith("_gd") or "_gd_" in it["k"]:
            continue
        p = place(it)
        if p:
            sortables.append((p[2] + 1, "fx", p))
    sortables.sort(key=lambda s: s[0])
    for _, kind, v in sortables:
        if kind == "enemy":
            fr = ENEMY
            x, y = OX + v[0] * PX - fr.width // 2, OY + v[1] * PX - fr.height + 6
            img.alpha_composite(fr, dest=(int(x), int(y)))
        elif kind == "op":
            fr = OPSPR
            x, y = OX + v[0] * PX - 32 * PX, OY + v[1] * PX - 60 * PX - v[2] * PX
            img.alpha_composite(fr, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))
        else:
            big, (l, t), _, pts, m, fl = v
            img.alpha_composite(big, dest=(max(0, l), max(0, t)), source=(max(0, -l), max(0, -t)))
            for q in pts:
                x = q[0] if not fl else m["w"] - 1 - q[0]
                ed.rectangle([l + x * PX, t + q[1] * PX, l + x * PX + PX - 1, t + q[1] * PX + PX - 1], fill=tuple(int(q[2][i:i + 2], 16) for i in (0, 2, 4)))
    glow = np.asarray(emit_layer.filter(ImageFilter.GaussianBlur(2))).astype(np.float32) * 0.35
    base = np.asarray(img.convert("RGB")).astype(np.float32)
    out = np.clip(base + glow, 0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGB")


def gif(columns, n_ticks, path, title, zoom_c):
    """columns：[(标签, Scene)]；zoom_c：2 倍放大中心（美术像素，相对干员脚底）"""
    try:
        font = ImageFont.truetype(FONT, 15)
        sfont = ImageFont.truetype(FONT, 12)
    except OSError:
        font = sfont = ImageFont.load_default()
    head = 28
    cw = W
    frames = []
    for tk in range(n_ticks):
        sheet = Image.new("RGB", (cw * len(columns) + 4 * (len(columns) - 1), head + H + 4 + H + 18), (14, 16, 18))
        d = ImageDraw.Draw(sheet)
        for ci, (lab, sc) in enumerate(columns):
            x0 = ci * (cw + 4)
            im = render(sc, tk)
            sheet.paste(im, (x0, head))
            zx, zy = OX + zoom_c[0] * PX, OY + zoom_c[1] * PX
            crop = im.crop((int(zx - W / 4), int(zy - H / 4), int(zx + W / 4), int(zy + H / 4))).resize((W, H), Image.NEAREST)
            sheet.paste(crop, (x0, head + H + 4))
            d.text((x0 + 6, 5), lab, fill=(235, 225, 200), font=font)
            d.text((x0 + 6, head + H + 4 + H + 2), "上：1 倍（实机大小）  下：2 倍放大", fill=(140, 140, 140), font=sfont)
        d.text((sheet.width - 6 - d.textlength(title, font=sfont), 8), title, fill=(150, 150, 150), font=sfont)
        frames.append(sheet)
    # 调色板取全部帧（只取一帧会把没出现的金色映到米色上）
    mos = Image.new("RGB", (frames[0].width, frames[0].height * len(frames)))
    for i, f in enumerate(frames):
        mos.paste(f, (0, i * f.height))
    pal = mos.quantize(colors=255, method=Image.MAXCOVERAGE)
    q = [f.quantize(palette=pal, dither=Image.NONE) for f in frames]
    dur = [70 if i % 3 != 1 else 60 for i in range(len(q))]
    q[0].save(path, save_all=True, append_images=q[1:], duration=dur, loop=0, optimize=False, disposal=1)
    print(path, len(q), "帧")


# ================================================================ 推进之王（docs/264）的摆法：照 game/scripts/render/fx_pxplane.gd 的 _ev_sg

def _land(R, ang):
    a = math.radians(ang)
    return (math.cos(a) * R * 0.7, math.sin(a) * R * 0.7 * SY)


def siege_scenes(lib):
    E_RIGHT = [[30, -6, -1], [40, 6, -1], [50, -12, -1], [58, 4, -1], [46, 16, -1], [70, -4, -1], [36, -18, -1]]
    E_UP = [[26, -30, -1], [34, -40, -1], [16, -44, -1]]

    def base(n, enemies):
        s = Scene(lib, n)
        s.enemies = [list(e) for e in enemies]
        return s

    def hammer(s, tk, t, ang, style="atk", R=46, kill=None, fis=None):
        d, fl = pick_dir(ang)
        if style == "s3":
            s.add("sg_arc_s3_up_d%d" % d, tk, (0, 0), fl)
        elif style == "s1":
            s.add("sg_arc_s1_e%d_up_d%d" % (t, d), tk, (0, 0), fl)
        else:
            s.add("sg_arc_r%d_e%d_up_d%d" % (R, t, d), tk, (0, 0), fl)
        lx, ly = _land(R if style == "atk" else 56 if style != "atk" else R, ang)
        lp = (lx, ly)
        if style == "s3":
            s.add("sg_s3_up", tk, lp)
            s.add("sg_s3_gd_d%d" % d, tk, lp, fl)
        else:
            s.pair("sg_imp_%s_e%d" % (style, t), tk, lp)
        if t >= 1 and kill is not None:   # 精一「粉碎」：击倒处碎石迸开
            e = s.enemies[kill]
            e[2] = tk + 1
            s.pair("sg_crush", tk + 1, (e[0], e[1]))
        if t >= 2:   # 精二「破阵」：落点往前一道地裂 + 岩刺
            s.add("sg_fis_l90_gd_d%d" % d, tk, lp, fl)
            s.add("sg_fis_l90_up_d%d" % d, tk, lp, fl)
        return lp

    out = {}
    # 普攻
    cols = []
    for t in (0, 1, 2):
        s = base(30, E_RIGHT + E_UP)
        hammer(s, 2, t, 0, kill=1)
        hammer(s, 16, t, -50, kill=7)
        cols.append(("普攻「锤击」 精英 %d" % t, s))
    out["atk"] = (cols, 30, (34, -10))
    # S1 冲锋号令
    cols = []
    for t in (0, 1, 2):
        s = base(26, E_RIGHT)
        s.pair("sg_s1cast_e%d" % t, 1, (0, 0))
        hammer(s, 8, t, 0, style="s1", kill=1)
        cols.append(("S1「冲锋号令·γ型」 精英 %d" % t, s))
    out["s1"] = (cols, 26, (24, -10))
    # S1 分支：万兽之王号令波
    s = base(22, E_RIGHT + E_UP)
    s.pair("sg_s1cast_e2", 1, (0, 0))
    s.add("sg_cmd_gd", 1, (0, 0))
    s2 = base(22, E_RIGHT)
    s2.pair("sg_s1cast_e2", 1, (0, 0))
    out["s1_branch"] = ([("S1 分支「万兽之王」号令波（精二）", s), ("对照：不选分支（精二）", s2)], 22, (0, -10))
    # S2 跃空锤
    def leap(s, tk0, a, b, T=6, h=21):
        prev = s.op_path

        def path(tk, prev=prev):
            if tk < tk0:
                return prev(tk)
            u = min(1.0, (tk - tk0) / T)
            return (a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u, 4 * h * u * (1 - u))
        s.op_path = path
        s.add("sg_crash_gd", tk0, a)   # 起跳：脚下一小圈 + 残影弧
        dx, dy = b[0] - a[0], b[1] - a[1]
        d, fl = pick_dir(math.degrees(math.atan2(dy / SY, dx)))
        D = 24 if math.hypot(dx, dy / SY) < 34.5 else 45
        s.add("sg_trail_l%d_e%d_up_d%d" % (D, s.tier, d), tk0, a, fl)
    cols = []
    for t in (1, 2):
        s = base(26, E_RIGHT)
        s.tier = t
        leap(s, 1, (0, 0), (40, 0))
        s.pair("sg_slam_r55_e%d" % t, 7, (40, 0))
        cols.append(("S2「跃空锤」 精英 %d" % t, s))
    out["s2"] = (cols, 26, (34, -16))
    # S2 分支
    s = base(32, E_RIGHT + [[110, 10, -1], [120, 0, -1], [104, 22, -1]])
    s.tier = 2
    leap(s, 1, (0, 0), (34, 0))
    s.pair("sg_slam_r55_e2", 7, (34, 0))
    leap(s, 8, (34, 0), (79, 8), T=6, h=26)
    s.pair("sg_slam_r55_e2", 14, (79, 8))
    s2 = base(32, E_RIGHT + [[110, 10, -1], [120, 0, -1], [104, 22, -1]])
    s2.tier = 2
    leap(s2, 1, (0, 0), (34, 0))
    s2.pair("sg_slam_r55_e2", 7, (34, 0))
    s2.add("sg_crk_l90_gd_d0", 8, (34, 0))
    s3 = base(32, E_RIGHT)
    s3.tier = 2
    leap(s3, 1, (0, 0), (34, 0))
    s3.pair("sg_slam_r55_e2", 7, (34, 0))
    s3.pair("sg_rift_r70_e2", 19, (34, 0))
    out["s2_branch"] = ([("分支「再跃」：落地再跃第二下", s), ("「再跃」她当队长：原地砸出地裂", s2), ("路线「再跃·裂地」：0.8 秒后再震一圈", s3)], 32, (40, -10))
    # S3 碎颅击
    s = base(34, E_RIGHT + E_UP)
    s.pair("sg_s3cast", 1, (0, 0))
    s.add("sg_s3aura_gd", 1, lambda tk: (0, 0), loop=True)
    hammer(s, 6, 2, 0, style="s3", kill=1)
    hammer(s, 24, 2, -50, style="s3", kill=7)
    out["s3"] = ([("S3「碎颅击」 精英 2（只有精二）", s)], 34, (30, -10))
    # 后期剑气（late_shape）= 锤击冲击波：游戏里自己往前推（600·a − 500·a² 世界像素，按 15 fps 跳格），2 道合一取 S24
    cols = []
    for t in (0, 1, 2):
        s = base(26, [[90, -4, -1], [104, 8, -1], [118, -10, -1], [30, -6, -1]])
        hammer(s, 2, t, 0)
        t0, x0 = 2, 32.0

        def gp(tk, t0=t0, x0=x0):
            a = (tk - t0) / 15.0
            return (x0 + (600 * a - 500 * a * a) / PX, 0)
        s.add("sg_wave_s24_e%d_up_d0" % t, t0, gp)
        s.add("sg_wave_s24_e%d_gd_d0" % t, t0, gp)
        cols.append(("后期剑气（锤击冲击波，2 道合一）精英 %d" % t, s))
    out["qi"] = (cols, 26, (70, -6))
    # 成长节点：震地 / 狮吼
    s = base(24, E_RIGHT)
    lp = hammer(s, 2, 0, 0)
    s.add("sg_quake_r35_q_gd", 2, lp)
    s2 = base(24, E_RIGHT)
    lp = hammer(s2, 2, 0, 0)
    s2.add("sg_quake_r35_roar_gd", 2, lp)
    s2.pair("sg_crash", 7, (62, 0))
    out["nodes"] = ([("成长「震地」：落点冲击环", s), ("成长「狮吼」：双环 + 撞击", s2)], 24, (34, -6))
    # 连携技「冲阵」（link/v2）
    s = base(26, [[20, -14, -1], [30, 10, -1], [40, -4, -1], [12, 16, -1], [50, 6, -1]])

    def dash(tk):
        if tk < 1:
            return (-70.0, -26.0, 0.0)
        u = min(1.0, (tk - 1) / 4.0)
        return (-70 + 100 * u, -26 + 26 * u, 0.0)
    s.op_path = dash
    s.pair("sg_link", 5, (30, 0))
    out["link"] = ([("连携技「冲阵」尾锤（link/v2 缺省版）", s)], 26, (30, -10))
    return out


def main():
    global ENEMY, OPSPR
    ap = argparse.ArgumentParser()
    ap.add_argument("--op", default="siege")
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(MAIN, "Claude outputs", "pxplane_siege_1105", "gif"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    lib = Lib(a.op)
    en = sprite_frames(os.path.join(ROOT, "game", "art", "enemies", "offspring", "e_offspring@2x.png"), 4)[0]
    arr = np.asarray(en).astype(np.float32)
    arr[..., :3] = arr[..., :3] * 0.32 + np.array([10, 12, 14])   # 深色剪影（留一点形）
    ENEMY = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")
    OPSPR = sprite_frames(os.path.join(ROOT, "game", "art", "operators", a.op, "op_%s_idle@2x.png" % a.op), 8)[0]
    scenes = siege_scenes(lib)
    only = set(x for x in a.only.split(",") if x)
    for name, (cols, n, zc) in scenes.items():
        if only and name not in only:
            continue
        gif(cols, n, os.path.join(a.out, "%s_%s.gif" % (a.op, name)), "推进之王 · 转平面 · 15 fps 原速", zc)


if __name__ == "__main__":
    main()
