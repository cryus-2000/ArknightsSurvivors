#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""凯尔希转平面送审 GIF（docs/265；协调人 11-05 流程：上 GCP 前先给用户看 GIF，只用 Python、不开 Godot）。

拼 tools/pxplane_kal_art.py 烘出的帧条（game/art/fx/pxp/pxp_ka_<键>.png + game/data/pxp_kaltsit.json），摆法照 fx_pxplane_kal.gd：
  - E0 / E1 / E2 并排（只放实际存在的档）；连携单独一张；
  - 游戏地面色背景 + 几只怪（深色剪影）；凯尔希、Mon3tr 用 idle 第 0 帧；
  - 上半 1 倍（实机大小：1 美术像素 = 2 屏幕像素），下半 2 倍放大；15 fps 原速。
贴地层先画；立起层、怪、干员按脚底 y 排序；热芯（emit 点）近似光学发光层加一层柔光。Noita 颗粒、照地光、场景压暗不模拟。

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


class Scene:
    def __init__(self, lib, n):
        self.lib, self.n = lib, n
        self.items = []
        self.enemies = []          # [x, y, 消失拍]
        self.kal = lambda tk: (0.0, 0.0)
        self.m3 = lambda tk: (M3[0], M3[1], 0.0)
        self.m3_face = 1

    def add(self, k, tk, gp, flip=False, loop=False, until=None, sk=0.0):
        self.items.append({"k": k, "t0": tk, "gp": gp, "flip": flip, "loop": loop, "until": until, "sk": sk})


ENEMY = KAL = MON = None


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
            spr = MON if sc.m3_face > 0 else MON.transpose(Image.FLIP_LEFT_RIGHT)
            x, y = OX + v[0] * PX - 64, OY + v[1] * PX - 120 - HOV - v[2] * PX
            # 影子
            ImageDraw.Draw(img).ellipse([OX + v[0] * PX - 16, OY + v[1] * PX - 5, OX + v[0] * PX + 16, OY + v[1] * PX + 5], fill=(18, 24, 24, 255))
            img.alpha_composite(spr, dest=(int(round(x / 2) * 2), int(round(y / 2) * 2)))
        else:
            img.alpha_composite(v[0], dest=(max(0, v[1][0]), max(0, v[1][1])), source=(max(0, -v[1][0]), max(0, -v[1][1])))
            emit(v)
    glow = np.asarray(em.filter(ImageFilter.GaussianBlur(2))).astype(np.float32) * 0.35
    base = np.asarray(img.convert("RGB")).astype(np.float32)
    return Image.fromarray(np.clip(base + glow, 0, 255).astype(np.uint8), "RGB")


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
    sc.add("%s_r%d_s%d_up" % (pre, Rw, sw), tk, at, flip)
    sc.add("%s_r%d_s%d_%s" % (pre, Rw, sw, "gd1" if (tier >= 1 and not melt) else "gd"), tk, at, flip)
    if tier >= 2 and not melt:
        for e in hits[:3]:
            sc.add("spike_up", tk + 1, (e[0], e[1]))
            sc.add("spike_gd", tk + 1, (e[0], e[1]))


def heal(sc, tk, tgt, tier):
    sc.add("heal_gd", tk, tgt)
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
    out["guard"] = ([("精二「回防」/「护主」落地（半径 100）", s)], 22, (60, -8))
    # S1 结构加固（队长身上）：骨肋合拢 + 治疗（E1 + 六角板，E2 + 头顶结扣）
    cols = []
    for t in (0, 1, 2):
        s = base(20, [])
        s.add("s1rib_bk_up", 2, (0, 0), sk=-3)
        s.add("s1rib_fr2_up" if t >= 2 else "s1rib_fr_up", 2, (0, 0), sk=1)
        if t >= 1:
            s.add("s1hex_gd", 2, (0, 0))
        s.add("heal_gd", 4, (0, 0))   # 技能治疗只出地环（同招元素 ≤ 3：骨肋 + 地面件 + 结扣）
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
        if t >= 2:
            s.add("s2str_up", 3, M3, sk=1)
        cols.append(("S2「战术协同」精英 %d" % t, s))
    out["s2"] = (cols, 18, (22, -18))
    # S3 熔毁：起手爆柱 → 持续热流 + 熔毁爪 → 结束一枚大结晶炸开（半径 130）
    s = base(46, E_FRONT)
    s.add("s3cast_up", 1, M3, sk=2)
    s.add("s3cast_gd", 1, M3)
    s.add("s3aura_up", 3, lambda tk: M3, loop=True, until=26, sk=1)
    s.add("s3aura_gd", 3, lambda tk: M3, loop=True, until=26)
    claw(s, 8, M3, 2, 161, 0, melt=True)
    claw(s, 17, M3, 2, 161, 1, melt=True)
    s.add("melt_r130_up", 27, M3, sk=3)
    s.add("melt_r130_gd", 27, M3)
    out["s3"] = ([("S3「熔毁」精英 2（红：起手 → 熔毁爪 → 结束熔毁爆）", s)], 46, (30, -8))
    # 连携「Mon3tr 掩护」（link/v2 缺省版）：落到队长前方，朝敌一侧骨刺墙 + 推波；凯尔希给队长回复
    s = base(20, [[60, -4, -1], [70, 8, -1], [64, -14, -1]])
    s.m3 = lambda tk: (25, 0, 0.0)
    s.add("link_up_d0", 2, (25, 0), sk=1)
    s.add("link_gd_d0", 2, (25, 0))
    heal(s, 3, (0, 0), 2)
    out["link"] = ([("连携技「Mon3tr 掩护」（link/v2 缺省版）", s)], 20, (30, -6))
    return out


def main():
    global ENEMY, KAL, MON
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
    MON = sprite_frames(os.path.join(ROOT, "game", "art", "operators", "kaltsit", "op_mon3tr_idle@2x.png"), 4)[0]
    only = set(x for x in a.only.split(",") if x)
    for name, (cols, n, zc) in scenes(lib).items():
        if only and name not in only:
            continue
        gif(cols, n, os.path.join(a.out, "kaltsit_%s.gif" % name), "凯尔希 · 转平面 · 15 fps 原速", zc)


if __name__ == "__main__":
    main()
