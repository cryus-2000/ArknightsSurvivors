# -*- coding: utf-8 -*-
"""干员寻访（局外解锁）概念样张（docs/124，2026-10-22）。只是静态样张，不改游戏代码。

风格：局外 T5s（docs/37 §8：藏青三阶 Bayer 抖动、像素阶梯切角、青细边、选中反白、5×7 像素字）；
干员像用游戏里的 @2x 待机帧（art/incoming），未解锁画剪影；特效（扫描线、星屑、信号缝）用程序画法占位，正式素材见 docs/124 §6 特效单。
主动作「信号解码」：一道横向扫描线自上而下扫过剪影，扫过的行由剪影解码成彩色像素（docs/62 §2.8：全游戏不复用）。

用法：python -X utf8 tools/concept_headhunt.py
输出（不入库）：主仓库 build/headhunt_design/
"""
import json
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
from concept_title_ui_v4 import stair, edge_of, dith, paint, solid, ptxt, N_TONES, EDGE  # noqa: E402

ROOT = os.path.dirname(TOOLS)
ART = os.path.join(ROOT, "art", "incoming")
DATA = os.path.join(ROOT, "game", "data", "characters")
OUT = os.path.join(c1.gr.common_root(ROOT), "build", "headhunt_design")
W, H = 1280, 720
PW, PH = 740, 360

CY = (96, 224, 232)
CY_HI = (200, 255, 255)
ACC = (60, 200, 228)
TXT = (228, 236, 244)
SUB = (138, 160, 182)
DIM = (70, 92, 116)
NEAR_WHITE = (238, 243, 246)
NAVY_INK = (10, 28, 52)
SIL = (14, 30, 52)
SIL_RIM = (60, 120, 150)
BG = [(12, 26, 46), (8, 18, 34), (5, 11, 24)]
CLS_COL = {"先锋": (255, 199, 89), "近卫": (140, 191, 255), "重装": (255, 184, 97), "狙击": (255, 107, 97),
           "术师": (255, 128, 56), "医疗": (140, 255, 153), "辅助": (255, 217, 128), "特种": (191, 153, 255)}
CLASSES = ["先锋", "近卫", "重装", "狙击", "术师", "医疗", "辅助", "特种"]
CLS_EN = {"先锋": "VANGUARD", "近卫": "GUARD", "重装": "DEFENDER", "狙击": "SNIPER", "术师": "CASTER",
          "医疗": "MEDIC", "辅助": "SUPPORTER", "特种": "SPECIALIST"}
START5 = ["texas", "hoshiguma", "eyjafjalla", "suzuran", "exusiai"]


def text(img, xy, s, size, col=TXT, anchor="la", bold=False):
    """逐字选字体（ui.ttf 缺字的单字才用后备字体，整串换后备会把其他字画成方框）"""
    if c1._UI_CMAP is None or all(ord(ch) in c1._UI_CMAP or ch.isspace() for ch in s):
        return c1.text(img, xy, s, size, col, anchor, bold and size >= 22)
    d = ImageDraw.Draw(img)
    fonts = [c1.F(size, ch) for ch in s]
    wsum = sum(d.textlength(ch, font=f) for ch, f in zip(s, fonts))
    x, y = xy
    if anchor[0] == "m":
        x -= wsum / 2
    elif anchor[0] == "r":
        x -= wsum
    for ch, f in zip(s, fonts):
        d.text((x, y), ch, font=f, fill=col, anchor="l" + anchor[1], stroke_width=1 if (bold and size >= 22) else 0, stroke_fill=col)
        x += d.textlength(ch, font=f)
    return wsum


def load_ops():
    ops = {}
    lore = json.load(open(os.path.join(ROOT, "game", "data", "lore.json"), encoding="utf-8"))
    for f in sorted(os.listdir(DATA)):
        if not f.endswith(".json"):
            continue
        d = json.load(open(os.path.join(DATA, f), encoding="utf-8"))
        if not d.get("recruitable", True):
            continue
        cid = f[:-5]
        ops[cid] = {"id": cid, "name": d["name"], "en": str(d.get("en", cid.upper())), "cls": d.get("class", ""),
                    "idle": d["sprites"]["idle"], "ds": float(d["sprites"].get("draw_scale", 1.0)),
                    "skills": [s.get("name", "") for s in d.get("skills", [])],
                    "line": str(lore.get(cid, {}).get("lore", "")).split("。")[0].strip("「」") + "。"}
    return ops


def frame0(op, k=1):
    """待机 f0（@2x 贴图像素），按 k 最近邻放大；返回 (图, 脚底点)"""
    sp = op["idle"]
    im = Image.open(os.path.join(ART, sp["tex"] + "@2x.png")).convert("RGBA")
    n = int(sp["frames"])
    fw = im.width // n
    f = im.crop((0, 0, fw, im.height))
    c = fw // 2
    foot_y = (46 if fw <= 96 else 60 + (fw / 2 - 64) / 2) * 2
    bb = f.getbbox()
    f = f.crop(bb)
    foot = (c - bb[0], foot_y - bb[1])
    kk = k * op["ds"]
    f = f.resize((max(1, round(f.width * kk)), max(1, round(f.height * kk))), Image.NEAREST)
    return f, (foot[0] * kk, foot[1] * kk)


def silhouette(im, col=SIL, rim=SIL_RIM):
    a = np.array(im.split()[-1]) > 0
    out = np.zeros(a.shape + (4,), np.uint8)
    out[a] = col + (255,)
    e = a & ~(np.roll(a, 1, 0) & np.roll(a, -1, 0) & np.roll(a, 1, 1) & np.roll(a, -1, 1))
    out[e] = rim + (255,)
    return Image.fromarray(out, "RGBA")


def paste_at_foot(img, spr, foot, x, y, a=255):
    if a < 255:
        spr = spr.copy()
        spr.putalpha(spr.split()[-1].point(lambda v: v * a // 255))
    img.alpha_composite(spr, (int(round(x - foot[0])), int(round(y - foot[1]))))


# ---------------------------------------------------------------- 底与面板
def bg(w, h, seed=3, stars=True):
    img = Image.new("RGBA", (w, h), BG[2] + (255,))
    m = np.ones((h, w), bool)
    lv = dith(0, 0, w, h, 2, lambda cx, cy: np.clip(cy / h * 2.2, 0, 2))
    paint(img, 0, 0, m, lv, BG)
    if stars:
        rnd = random.Random(seed)
        d = ImageDraw.Draw(img)
        for _ in range(w * h // 9000):
            x, y = rnd.randrange(w), rnd.randrange(h)
            c = rnd.choice([(40, 70, 96), (52, 92, 120), (30, 54, 80)])
            d.rectangle([x, y, x + 1, y + 1], fill=c)
    return img


def panel(img, box, P=2, n=3, tones=None, a=235, edge=EDGE):
    x0, y0, x1, y1 = [int(v) // P * P for v in box]
    m = stair(x1 - x0, y1 - y0, P, n)
    t = tones or N_TONES
    lv = dith(x0, y0, x1 - x0, y1 - y0, P, lambda cx, cy: np.clip(cy / (y1 - y0) * 2.2, 0, 2))
    paint(img, x0, y0, m, lv, t, a)
    solid(img, x0, y0, edge_of(m, P), edge + (220,))
    return (x0, y0, x1, y1)


def sel_panel(img, box, P=2, n=3):
    x0, y0, x1, y1 = [int(v) // P * P for v in box]
    m = stair(x1 - x0, y1 - y0, P, n)
    solid(img, x0, y0, m, NEAR_WHITE)
    solid(img, x0, y0, edge_of(m, P), ACC)
    return (x0, y0, x1, y1)


def btn(img, box, label, en, sel=False, key=None):
    x0, y0, x1, y1 = box
    if sel:
        sel_panel(img, box)
        tc, sc = NAVY_INK, (24, 130, 160)
    else:
        panel(img, box)
        tc, sc = TXT, SUB
    cy = (y0 + y1) // 2
    fs = max(10, min(16, int((y1 - y0) * 0.38)))
    pad = max(8, int(fs))
    text(img, (x0 + pad, cy), label, fs, tc, "lm")
    if c1.F(fs).getlength(label) + ptxt(Image.new("RGBA", (1, 1)), (0, 0), en, 1) + pad * 3 < x1 - x0:
        ptxt(img, (x1 - pad, cy), en, 1, sc, 1, "rm")


def cls_glyph(img, cls, cx, cy, r, col, w=2):
    d = ImageDraw.Draw(img)
    x, y = cx, cy
    if cls == "近卫":
        d.line([x - r, y + r, x + r, y - r], fill=col, width=w); d.line([x - r + 4, y + r, x + r, y - r + 4], fill=col, width=w)
    elif cls == "重装":
        d.polygon([(x - r, y - r), (x + r, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=w)
    elif cls == "狙击":
        d.ellipse([x - r, y - r, x + r, y + r], outline=col, width=w); d.line([x - r - 2, y, x + r + 2, y], fill=col, width=w); d.line([x, y - r - 2, x, y + r + 2], fill=col, width=w)
    elif cls == "术师":
        d.polygon([(x, y - r), (x + r, y + r), (x - r, y + r)], outline=col, width=w); d.ellipse([x - 2, y, x + 2, y + 4], fill=col)
    elif cls == "医疗":
        d.rectangle([x - w * 2, y - r, x + w * 2, y + r], fill=col); d.rectangle([x - r, y - w * 2, x + r, y + w * 2], fill=col)
    elif cls == "辅助":
        for i in range(3):
            xx = x - r + i * r
            d.line([xx, y + r, xx, y - r + 2], fill=col, width=w)
        d.line([x - r, y - r + 2, x + r, y - r + 2], fill=col, width=w)
    elif cls == "特种":
        d.polygon([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], outline=col, width=w)
    else:  # 先锋
        d.line([x - r + 2, y - r, x - r + 2, y + r], fill=col, width=w); d.polygon([(x - r + 2, y - r), (x + r, y - r + 4), (x - r + 2, y)], fill=col)


def lock_glyph(img, cx, cy, s, col):
    d = ImageDraw.Draw(img)
    d.rectangle([cx - 4 * s, cy - s, cx + 4 * s, cy + 5 * s], fill=col)
    d.rectangle([cx - 3 * s, cy - 5 * s, cx + 3 * s, cy - s], outline=col, width=max(1, s))
    d.rectangle([cx - s // 2, cy + s, cx + s // 2, cy + 3 * s], fill=BG[2])


def header(img, s, code, title, sub=None):
    ptxt(img, (int(28 * s), int(30 * s)), code, max(1, int(round(2 * s))), CY, 1, "lm")
    text(img, (int(28 * s), int(46 * s)), title, int(26 * s), TXT, "la", True)
    if sub:
        text(img, (int(28 * s), int(88 * s)), sub, int(14 * s), SUB, "la")


def hint(img, s, items, w):
    x = w - int(24 * s)
    for k, lab in reversed(items):
        lw = c1.F(int(13 * s)).getlength(lab)
        text(img, (x, img.height - int(22 * s)), lab, int(13 * s), SUB, "rm")
        x -= lw + 6
        kw = ptxt(img, (x, img.height - int(22 * s)), k, max(1, int(round(s))), CY, 1, "rm")
        x -= kw + int(22 * s)


# ---------------------------------------------------------------- 特效占位（程序画法）
def stardust(img, cx, cy, rad, n, seed, col=CY_HI, toward=0.0):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(img)
    for _ in range(n):
        an = rnd.random() * 6.283
        r = rad * (rnd.random() ** 0.6) * (1 - toward)
        x, y = cx + np.cos(an) * r, cy + np.sin(an) * r * 0.55
        s = rnd.choice([1, 1, 2, 2, 3])
        a = rnd.randint(90, 255)
        d.rectangle([x, y, x + s, y + s], fill=col + (a,))


def slit(img, cy, x0, x1, th, col=CY_HI, glow_col=CY):
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k, a in ((10, 26), (6, 50), (3, 90)):
        d.rectangle([x0, cy - th - k * 2, x1, cy + th + k * 2], fill=glow_col + (a,))
    d.rectangle([x0, cy - th, x1, cy + th], fill=col + (255,))
    img.alpha_composite(lay)


def decode(spr, frac, seed=7):
    """解码到 frac（0–1，自上而下）：已扫过的行彩色，未扫的剪影；扫描线附近 3 行噪点格（按 4 像素块）"""
    sil = silhouette(spr)
    h = spr.height
    yline = int(h * frac)
    out = sil.copy()
    out.paste(spr.crop((0, 0, spr.width, yline)), (0, 0))
    a = np.array(out)
    al = np.array(spr.split()[-1]) > 0
    rnd = np.random.default_rng(seed)
    band = slice(max(0, yline - 10), min(h, yline + 6))
    blk = 4
    for y in range(band.start, band.stop, blk):
        for x in range(0, spr.width, blk):
            if al[y:y + blk, x:x + blk].any() and rnd.random() < 0.45:
                c = rnd.choice([0, 1, 2])
                col = [CY_HI, CY, (40, 90, 120)][c]
                sub = al[y:y + blk, x:x + blk]
                a[y:y + blk, x:x + blk][sub] = col + (255,)
    return Image.fromarray(a, "RGBA"), yline


# ---------------------------------------------------------------- 寻访揭示（主动作：信号解码）
def stage_box(w, h, s):
    return (int(w * 0.5 - 200 * s), int(110 * s), int(w * 0.5 + 200 * s), int(h - 120 * s))


def voucher_card(img, cx, cy, s, a=1.0, kind="寻访凭证", sub="HEADHUNTING PERMIT"):
    w, h = int(150 * s), int(96 * s)
    box = (cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2)
    panel(img, box, 2, 3, tones=[(26, 56, 88), (16, 36, 62), (8, 20, 38)])
    x0, y0, x1, y1 = box
    ImageDraw.Draw(img).rectangle([x0 + 8, y0 + 8, x0 + 8 + int(4 * s), y1 - 8], fill=CY)
    text(img, (x0 + int(22 * s), y0 + int(18 * s)), kind, int(18 * s), TXT, "la", True)
    ptxt(img, (x0 + int(22 * s), y0 + int(50 * s)), sub, 1, SUB, 1, "lm")
    ptxt(img, (x0 + int(22 * s), y1 - int(16 * s)), "R.I. PERSONNEL", 1, DIM, 1, "lm")
    # 右侧菱形 + 一道浪（本作徽记）
    d = ImageDraw.Draw(img)
    ex, ey, r = x1 - int(26 * s), y0 + int(30 * s), int(10 * s)
    d.polygon([(ex, ey - r), (ex + r, ey), (ex, ey + r), (ex - r, ey)], outline=CY, width=2)
    d.line([ex - r + 3, ey + 2, ex - 2, ey - 1, ex + 2, ey + 2, ex + r - 3, ey - 1], fill=CY, width=1)


def name_block(img, op, x, y, s, extra=None, fresh=True):
    col = CLS_COL[op["cls"]]
    ptxt(img, (x, y), "NO.%02d // %s" % (ORDER.index(op["id"]) + 1, CLS_EN[op["cls"]]), max(1, int(round(2 * s))), CY, 1, "lm")
    text(img, (x, y + int(14 * s)), op["name"], int(40 * s), NEAR_WHITE, "la", True)
    ptxt(img, (x, y + int(78 * s)), op["en"], max(1, int(round(2 * s))), SUB, 2, "lm")
    cy = y + int(100 * s)
    chip = (x, cy, x + int(96 * s), cy + int(26 * s))
    panel(img, chip, 2, 2, tones=[(26, 46, 70), (20, 38, 60), (14, 30, 50)], edge=tuple(int(v * 0.7) for v in col))
    cls_glyph(img, op["cls"], x + int(14 * s), cy + int(13 * s), int(6 * s), col, max(1, int(2 * s)))
    text(img, (x + int(28 * s), cy + int(13 * s)), op["cls"] + "干员", int(14 * s), TXT, "lm")
    if fresh:
        text(img, (x, cy + int(40 * s)), "已加入名册", int(15 * s), CY, "la")
    if extra:
        ex = x + int(110 * s)
        panel(img, (ex, cy, ex + int(128 * s), cy + int(26 * s)), 2, 2, tones=[(60, 50, 110), (48, 40, 92), (36, 30, 74)], edge=(124, 107, 255))
        text(img, (ex + int(10 * s), cy + int(13 * s)), extra, int(13 * s), TXT, "lm")


def reveal(op, phase, s=1.0, w=W, h=H, pity=None):
    img = bg(w, h, 5)
    st = stage_box(w, h, s)
    cx = (st[0] + st[2]) // 2
    foot_y = st[3]
    spr, foot = frame0(op, 4 if s >= 1 else 2)
    # 舞台底的投影台
    d = ImageDraw.Draw(img)
    for i, a in enumerate((30, 50, 80)):
        rr = int((150 - i * 40) * s)
        d.ellipse([cx - rr, foot_y - rr * 0.18, cx + rr, foot_y + rr * 0.18], outline=CY + (a,), width=1)
    header(img, s, "HEADHUNT // 01", "寻访", None)
    if phase == "wait":
        voucher_card(img, cx, int(h * 0.48), s)
        stardust(img, cx, int(h * 0.48), 220 * s, 60, 1, toward=0.2)
        text(img, (cx, int(h * 0.48) + int(80 * s)), "寻访凭证 ×1", int(16 * s), TXT, "mm")
    elif phase == "signal":
        slit(img, int(h * 0.48), cx - int(230 * s), cx + int(230 * s), max(1, int(2 * s)))
        stardust(img, cx, int(h * 0.48), 260 * s, 140, 2, toward=0.55)
        ptxt(img, (cx, int(h * 0.48) + int(34 * s)), "SIGNAL  03/13", max(1, int(round(2 * s))), CY, 2, "mm")
        cls_glyph(img, op["cls"], cx, int(h * 0.48) - int(40 * s), int(10 * s), CLS_COL[op["cls"]], max(1, int(2 * s)))
    elif phase in ("decode", "name", "line", "pity"):
        frac = 0.55 if phase == "decode" else 1.0
        dec, yl = decode(spr, frac)
        x0, y0 = int(cx - foot[0]), int(foot_y - foot[1])
        img.alpha_composite(dec, (x0, y0))
        if phase == "decode":
            slit(img, y0 + yl, cx - int(170 * s), cx + int(170 * s), 1)
            stardust(img, cx, y0 + yl, 180 * s, 60, 3, toward=0.3)
        else:
            stardust(img, cx, foot_y - int(120 * s), 260 * s, 26, 4)
            name_block(img, op, int(70 * s), int(h * 0.42), s, extra=("意向干员 · 第 3 张必出" if phase == "pity" else None))
        if phase in ("line", "pity"):
            by = h - int(96 * s)
            panel(img, (int(60 * s), by, w - int(60 * s), by + int(54 * s)), 2, 3, a=220)
            text(img, (int(84 * s), by + int(27 * s)), "「" + op["line"].rstrip("。") + "。」", int(16 * s), TXT, "lm")
            ptxt(img, (w - int(84 * s), by + int(27 * s)), "R.I. RECRUITMENT FILE", 1, DIM, 1, "rm")
    if pity is not None and phase in ("wait", "signal"):
        text(img, (w - int(28 * s), int(40 * s)), "意向 %s · 保底 %d/3" % pity, int(14 * s), SUB, "ra")
    hint(img, s, [("ENTER", "继续"), ("ESC", "跳过全部")] if phase != "wait" else [("ENTER", "寻访"), ("ESC", "跳过全部")], w)
    return img


def summary(ops, s=1.0, w=W, h=H):
    img = bg(w, h, 6)
    header(img, s, "HEADHUNT // RESULT", "本次寻访", "3 名干员已加入名册 · 前往干员名册查看")
    n = len(ops)
    cw, ch = int(220 * s), int(300 * s)
    gap = int(28 * s)
    x = (w - (n * cw + (n - 1) * gap)) // 2
    y = int(150 * s)
    srcs = ["寻访凭证", "招募券 · 特种", "人事调度函"]
    for i, op in enumerate(ops):
        box = (x, y, x + cw, y + ch)
        panel(img, box)
        col = CLS_COL[op["cls"]]
        ImageDraw.Draw(img).rectangle([x + 6, y + 4, x + cw - 6, y + 7], fill=col)
        spr, foot = frame0(op, 2 if s >= 1 else 1)
        paste_at_foot(img, spr, foot, x + cw // 2, y + ch - int(84 * s))
        text(img, (x + cw // 2, y + ch - int(62 * s)), op["name"], int(20 * s), NEAR_WHITE, "mm", True)
        text(img, (x + cw // 2, y + ch - int(36 * s)), op["cls"] + " · " + srcs[i % 3], int(13 * s), SUB, "mm")
        x += cw + gap
    bw = int(200 * s)
    btn(img, (w // 2 - bw - 10, h - int(80 * s), w // 2 - 10, h - int(36 * s)), "前往干员名册", "ROSTER", True)
    btn(img, (w // 2 + 10, h - int(80 * s), w // 2 + bw + 10, h - int(36 * s)), "返回", "BACK")
    return img


# ---------------------------------------------------------------- 定向：招募券（选职业）/ 人事调度函（指定）
def class_pick(ops, unlocked, s=1.0, w=W, h=H, sel="近卫"):
    img = bg(w, h, 7)
    header(img, s, "RECRUIT // CLASS", "招募券", "选择职业：从该职业未解锁的干员里寻访 1 名")
    cols = 4
    cw, ch = int(260 * s), int(150 * s)
    gx, gy = int(18 * s), int(18 * s)
    x0 = (w - (cols * cw + (cols - 1) * gx)) // 2
    y0 = int(130 * s)
    owned = {ops[i]["cls"] for i in unlocked}
    for i, cls in enumerate(CLASSES):
        x, y = x0 + (i % cols) * (cw + gx), y0 + (i // cols) * (ch + gy)
        left = [o for o in ops.values() if o["cls"] == cls and o["id"] not in unlocked]
        box = (x, y, x + cw, y + ch)
        done = not left
        if cls == sel:
            sel_panel(img, box)
            tc, sc = NAVY_INK, (40, 80, 110)
        else:
            panel(img, box, a=150 if done else 235)
            tc, sc = (DIM if done else TXT), (DIM if done else SUB)
        col = CLS_COL[cls] if not done else DIM
        cls_glyph(img, cls, x + int(34 * s), y + int(40 * s), int(12 * s), col if cls != sel else tuple(int(v * 0.6) for v in col), max(1, int(3 * s)))
        text(img, (x + int(62 * s), y + int(26 * s)), cls, int(24 * s), tc, "la", True)
        ptxt(img, (x + int(62 * s), y + int(66 * s)), CLS_EN[cls], 1, sc, 1, "lm")
        if done:
            text(img, (x + int(20 * s), y + ch - int(30 * s)), "已全部解锁", int(14 * s), DIM, "la")
        else:
            text(img, (x + int(20 * s), y + ch - int(30 * s)), "未解锁 %d 名" % len(left), int(14 * s), tc, "la")
            for j, o in enumerate(left):
                sp, ft = frame0(o, s)
                sil = silhouette(sp, (40, 70, 100) if cls != sel else (150, 170, 190), (80, 130, 160) if cls != sel else (120, 140, 160))
                paste_at_foot(img, sil, ft, x + cw - int(36 * s) - j * int(44 * s), y + ch - int(18 * s))
        if cls not in owned:
            tag = (x + cw - int(76 * s), y + int(12 * s), x + cw - int(12 * s), y + int(36 * s))
            panel(img, tag, 2, 2, tones=[(60, 50, 110), (48, 40, 92), (36, 30, 74)], edge=(124, 107, 255))
            text(img, ((tag[0] + tag[2]) // 2, (tag[1] + tag[3]) // 2), "新职业", int(12 * s), TXT, "mm")
    bw = int(260 * s)
    btn(img, (w - bw - int(40 * s), h - int(84 * s), w - int(40 * s), h - int(40 * s)), "使用招募券 · " + sel, "OK", True)
    text(img, (int(40 * s), h - int(62 * s)), "持有：招募券 ×1　人事调度函 ×1　寻访凭证 ×0", int(14 * s), SUB, "lm")
    return img


def letter_pick(ops, unlocked, s=1.0, w=W, h=H, sel="kaltsit", wish="mizuki"):
    img = bg(w, h, 8)
    header(img, s, "TRANSFER // ASSIGN", "人事调度函", "指定 1 名未解锁干员直接加入名册")
    locked = [o for o in ops.values() if o["id"] not in unlocked]
    cols = 5
    cw, ch = int(108 * s), int(132 * s)
    g = int(10 * s)
    x0, y0 = int(28 * s), int(124 * s)
    for i, o in enumerate(locked):
        x, y = x0 + (i % cols) * (cw + g), y0 + (i // cols) * (ch + g)
        box = (x, y, x + cw, y + ch)
        if o["id"] == sel:
            sel_panel(img, box)
            tc = NAVY_INK
        else:
            panel(img, box)
            tc = TXT
        col = CLS_COL[o["cls"]]
        ImageDraw.Draw(img).rectangle([x + 5, y + 3, x + cw - 5, y + 5], fill=col)
        sp, ft = frame0(o, 1)
        sil = silhouette(sp, (150, 166, 186) if o["id"] == sel else SIL, (110, 130, 150) if o["id"] == sel else SIL_RIM)
        paste_at_foot(img, sil, ft, x + cw // 2, y + ch - int(30 * s))
        text(img, (x + cw // 2, y + ch - int(16 * s)), o["name"], int(12 * s), tc, "mm")
        cls_glyph(img, o["cls"], x + int(14 * s), y + int(18 * s), int(5 * s), col, 2)
        if o["id"] == wish:
            text(img, (x + cw - int(8 * s), y + int(18 * s)), "意向", int(11 * s), (124, 107, 255) if o["id"] != sel else (90, 70, 200), "rm")
    # 右栏：选中干员
    o = ops[sel]
    px0 = x0 + cols * (cw + g) + int(20 * s)
    pb = panel(img, (px0, y0, w - int(28 * s), h - int(100 * s)))
    sp, ft = frame0(o, 2)
    paste_at_foot(img, silhouette(sp), ft, (pb[0] + pb[2]) // 2, pb[1] + int(230 * s))
    text(img, (pb[0] + int(20 * s), pb[1] + int(250 * s)), o["name"], int(26 * s), NEAR_WHITE, "la", True)
    ptxt(img, (pb[0] + int(20 * s), pb[1] + int(292 * s)), o["en"] + " // " + CLS_EN[o["cls"]], 1, SUB, 1, "lm")
    for j, sk in enumerate(o["skills"]):
        text(img, (pb[0] + int(20 * s), pb[1] + int(312 * s) + j * int(22 * s)), "S%d　%s" % (j + 1, sk), int(14 * s), TXT, "la")
    text(img, (pb[0] + int(20 * s), pb[3] - int(28 * s)), "立绘在解锁后显示", int(12 * s), SUB, "la")
    bw = int(240 * s)
    btn(img, (w - bw - int(28 * s), h - int(84 * s), w - int(28 * s), h - int(40 * s)), "使用人事调度函", "CONFIRM", True)
    text(img, (int(28 * s), h - int(62 * s)), "持有：人事调度函 ×1", int(14 * s), SUB, "lm")
    return img


# ---------------------------------------------------------------- 锁定态（选人 B+ 名册 / 图鉴 C4′ 格子 / 封面干员）
def roster_strip(img, ops, ids, unlocked, x, y, s, fresh=(), sel=None, cover=False):
    cw, ch = int(82 * s), int(112 * s)
    for i, cid in enumerate(ids):
        o = ops[cid]
        bx = x + i * int(90 * s)
        box = (bx, y, bx + cw, y + ch)
        lk = cid not in unlocked
        if cid == sel:
            panel(img, (bx - 3, y - 3, bx + cw + 3, y + ch + 3), 2, 3, tones=[(40, 34, 90)] * 3, edge=(124, 107, 255))
        panel(img, box, 2, 3, a=170 if (lk and cover) else 235)
        col = CLS_COL[o["cls"]] if not lk else tuple(int(v * 0.45) for v in CLS_COL[o["cls"]])
        ImageDraw.Draw(img).rectangle([bx + 4, y + 2, bx + cw - 4, y + 4], fill=col)
        sp, ft = frame0(o, s)
        if lk:
            sp = silhouette(sp)
        k = 0.8
        sp = sp.resize((round(sp.width * k), round(sp.height * k)), Image.NEAREST)
        paste_at_foot(img, sp, (ft[0] * k, ft[1] * k), bx + cw // 2, y + ch - int(30 * s), 120 if (lk and cover) else 255)
        cls_glyph(img, o["cls"], bx + int(12 * s), y + int(16 * s), int(5 * s), col, 2)
        ImageDraw.Draw(img).rectangle([bx + 2, y + ch - int(22 * s), bx + cw - 2, y + ch - 2], fill=(4, 8, 16, 200))
        text(img, (bx + cw // 2, y + ch - int(12 * s)), o["name"] if not lk else o["name"], int(11 * s), TXT if not lk else DIM, "mm")
        if lk:
            lock_glyph(img, bx + cw - int(14 * s), y + int(16 * s), max(1, int(round(s))), DIM)
        if cid in fresh:
            d = ImageDraw.Draw(img)
            for k2, a in ((6, 40), (3, 90), (0, 255)):
                d.rectangle([bx - k2, y - k2, bx + cw + k2, y + ch + k2], outline=CY + (a,), width=2 if k2 == 0 else 1)
            tag = (bx + cw - int(44 * s), y - int(10 * s), bx + cw + int(4 * s), y + int(8 * s))
            sel_panel(img, tag, 2, 2)
            text(img, ((tag[0] + tag[2]) // 2, (tag[1] + tag[3]) // 2), "新加入", int(10 * s), NAVY_INK, "mm")


def oppick_locked(ops, unlocked, s=1.0, w=W, h=H, focus="mizuki", fresh=("lumen",)):
    img = bg(w, h, 9)
    header(img, s, "OPERATOR SELECT", "选择开局干员", "队长 1 名；未解锁干员仍可能以「临时招募」出现在局内")
    # 舞台：未解锁 → 剪影 + 说明 + 设为意向 + 保底
    o = ops[focus]
    cx, fy = int(w * 0.56), h - int(176 * s)
    sp, ft = frame0(o, 3 * s)
    paste_at_foot(img, silhouette(sp), ft, cx, fy)
    ptxt(img, (int(70 * s), int(220 * s)), "NO.%02d // %s" % (ORDER.index(focus) + 1, CLS_EN[o["cls"]]), max(1, int(round(2 * s))), CY, 1, "lm")
    text(img, (int(70 * s), int(236 * s)), o["name"], int(40 * s), NEAR_WHITE, "la", True)
    ptxt(img, (int(70 * s), int(300 * s)), o["en"], max(1, int(round(2 * s))), SUB, 2, "lm")
    lk = (int(70 * s), int(316 * s), int(70 * s) + int(330 * s), int(346 * s))
    panel(img, lk, 2, 2, tones=[(30, 34, 50)] * 3, edge=DIM)
    lock_glyph(img, lk[0] + int(16 * s), lk[1] + int(14 * s), max(1, int(round(s))), SUB)
    text(img, (lk[0] + int(32 * s), (lk[1] + lk[3]) // 2), "未解锁 · 使用寻访凭证、招募券或人事调度函", int(13 * s), SUB, "lm")
    btn(img, (int(70 * s), int(360 * s), int(70 * s) + int(170 * s), int(398 * s)), "设为意向", "WISH", True)
    text(img, (int(70 * s) + int(184 * s), int(379 * s)), "寻访凭证保底", int(13 * s), SUB, "lm")
    for j in range(3):
        px = int(70 * s) + int(272 * s) + j * int(16 * s)
        d = ImageDraw.Draw(img)
        if j < 2:
            d.rectangle([px, int(373 * s), px + int(10 * s), int(385 * s)], fill=CY)
        else:
            d.rectangle([px, int(373 * s), px + int(10 * s), int(385 * s)], outline=CY, width=1)
    text(img, (int(70 * s) + int(326 * s), int(379 * s)), "2/3", int(13 * s), CY, "lm")
    # 右侧信息面板（技能可翻看）
    pb = panel(img, (int(w * 0.76), int(110 * s), w - int(24 * s), h - int(176 * s)))
    text(img, (pb[0] + 16, pb[1] + 14), "技能（可翻看）", int(14 * s), SUB, "la")
    for j, sk in enumerate(o["skills"]):
        yy = pb[1] + int(44 * s) + j * int(56 * s)
        panel(img, (pb[0] + 12, yy, pb[2] - 12, yy + int(46 * s)), 2, 2)
        text(img, (pb[0] + 24, yy + int(23 * s)), "S%d　%s" % (j + 1, sk), int(15 * s), TXT, "lm")
    ImageDraw.Draw(img).rectangle([0, h - int(160 * s), w, h], fill=(4, 9, 18, 255))
    ptxt(img, (int(30 * s), h - int(146 * s)), "ROSTER 6 / 18 // SORT: CLASS", 1, SUB, 2, "lm")
    ids = ["texas", "siege", "hoshiguma", "saria", "exusiai", "wisadel", "eyjafjalla", "lumen", "mizuki", "suzuran", "skalter", "irene"]
    roster_strip(img, ops, ids, unlocked | {"lumen"}, int(30 * s), h - int(128 * s), s, fresh=fresh, sel=focus)
    return img


def cover_locked(ops, unlocked, s=1.0, w=W, h=H):
    img = bg(w, h, 10)
    header(img, s, "COVER OPERATOR", "更换封面干员", "只能选已解锁的干员")
    ids = ["texas", "siege", "hoshiguma", "saria", "exusiai", "wisadel", "eyjafjalla", "lumen", "mizuki", "suzuran", "skalter", "irene"]
    roster_strip(img, ops, ids, unlocked | {"lumen"}, int(30 * s), int(330 * s), s, sel="eyjafjalla", cover=True)
    text(img, (int(30 * s), int(470 * s)), "暗色卡 = 未解锁，不能设为封面；点按会提示「未解锁」。", int(14 * s), SUB, "la")
    return img


def codex_locked(ops, unlocked, s=1.0, w=W, h=H):
    """图鉴 C4′ 格子：浅黄强调保留（docs/37：图鉴留黄），未解锁 = 深灰剪影 + 锁 + 名字照写"""
    img = Image.new("RGBA", (w, h), (24, 22, 30, 255))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, w, 50], fill=(232, 232, 228))
    d.rectangle([150, 8, 250, 44], fill=(255, 206, 0))
    text(img, (200, 26), "干员", 18, (16, 16, 20), "mm", True)
    text(img, (24, 26), "图鉴", 20, (16, 16, 20), "lm", True)
    ids = ORDER[:16]
    cw, ch = 80, 110
    for i, cid in enumerate(ids):
        o = ops[cid]
        x, y = 76 + (i % 4) * 88, 86 + (i // 4) * 120
        lk = cid not in unlocked
        d.rectangle([x, y, x + cw, y + ch], fill=(30, 32, 40))
        d.rectangle([x + 1, y + 1, x + cw - 1, y + 5], fill=(60, 60, 66) if lk else CLS_COL[o["cls"]])
        sp, ft = frame0(o, 1)
        if lk:
            sp = silhouette(sp, (52, 54, 64), (72, 74, 86))
        sp = sp.resize((round(sp.width * 0.8), round(sp.height * 0.8)), Image.NEAREST)
        paste_at_foot(img, sp, (ft[0] * 0.8, ft[1] * 0.8), x + cw // 2, y + ch - 28)
        d.rectangle([x + 1, y + ch - 22, x + cw - 1, y + ch - 1], fill=(238, 238, 236) if not lk else (90, 90, 96))
        text(img, (x + cw // 2, y + ch - 11), o["name"], 12, (16, 16, 20), "mm")
        if lk:
            lock_glyph(img, x + cw - 12, y + 18, 1, (120, 120, 130))
        d.rectangle([x, y, x + cw, y + ch], outline=(10, 10, 14), width=1)
    # 舞台：未解锁不剧透立绘
    o = ops["mizuki"]
    sp, ft = frame0(o, 3)
    paste_at_foot(img, silhouette(sp, (40, 40, 50), (70, 70, 84)), ft, 660, 440)
    text(img, (450, 470), "水月", 44, (240, 240, 236), "la", True)
    text(img, (452, 526), "未解锁 · 档案与技能可翻看，立绘在解锁后显示", 14, (170, 170, 176), "la")
    return img


def unlock_flash(ops, unlocked, s=1.0, w=W, h=H):
    """解锁瞬间（揭示结束回到名册时，「新加入」卡的高亮：青边 + 外圈两档光 + 角标，看过一次后清除）"""
    img = bg(w, h, 11)
    header(img, s, "ROSTER // NEW", "名册：解锁高亮", "刚解锁的干员卡外圈青光 + 「新加入」角标；进过一次选人 / 图鉴后不再显示")
    ids = ["texas", "hoshiguma", "exusiai", "eyjafjalla", "lumen", "suzuran", "skadi", "specter_unchained", "kaltsit"]
    roster_strip(img, ops, ids, unlocked | {"lumen", "skadi", "specter_unchained", "kaltsit"}, int(60 * s), int(300 * s), s,
                 fresh=("skadi", "specter_unchained", "kaltsit"))
    return img


# ---------------------------------------------------------------- 流程图 / 分镜条 / 拼图
def storyboard(frames, labels, out, cell=(426, 240)):
    n = len(frames)
    sheet = Image.new("RGB", (cell[0] * n + 8 * (n - 1), cell[1] + 40), (10, 14, 22))
    for i, (f, lab) in enumerate(zip(frames, labels)):
        t = f.convert("RGB").resize(cell, Image.LANCZOS)
        sheet.paste(t, (i * (cell[0] + 8), 40))
        text(sheet, (i * (cell[0] + 8) + 6, 20), lab, 16, (230, 236, 244), "lm")
    sheet.save(out)


def main():
    os.makedirs(OUT, exist_ok=True)
    global ORDER
    ops = load_ops()
    ORDER = list(ops)
    unlocked = set(START5)
    op = ops["mizuki"]
    seq = [("wait", "1 等待 0–0.6 秒"), ("signal", "2 信号 0.6–1.4 秒"), ("decode", "3 解码 1.4–2.6 秒"), ("name", "4 定格 2.6–3.6 秒"), ("line", "5 台词 3.6–5.0 秒")]
    frames = []
    for ph, lab in seq:
        im = reveal(op, ph, 1.0, pity=("水月", 2))
        im.convert("RGB").save(os.path.join(OUT, "reveal_%s.png" % ph))
        frames.append(im)
    storyboard(frames, [l for _, l in seq], os.path.join(OUT, "reveal_storyboard.png"))
    reveal(op, "pity", 1.0).convert("RGB").save(os.path.join(OUT, "reveal_pity.png"))
    summary([ops["skadi"], ops["specter_unchained"], ops["kaltsit"]]).convert("RGB").save(os.path.join(OUT, "summary.png"))
    class_pick(ops, unlocked | {"lumen"}).convert("RGB").save(os.path.join(OUT, "pick_class.png"))
    letter_pick(ops, unlocked | {"lumen"}).convert("RGB").save(os.path.join(OUT, "pick_letter.png"))
    oppick_locked(ops, unlocked).convert("RGB").save(os.path.join(OUT, "locked_oppick.png"))
    codex_locked(ops, unlocked | {"lumen"}).convert("RGB").save(os.path.join(OUT, "locked_codex.png"))
    cover_locked(ops, unlocked).convert("RGB").save(os.path.join(OUT, "locked_cover.png"))
    unlock_flash(ops, unlocked).convert("RGB").save(os.path.join(OUT, "unlock_highlight.png"))
    # 手机（设计尺寸 740 × 360，界面层按 Cfg.ui_k 放大；样张按 2 倍出图便于看）
    sp = 0.62
    for ph in ("decode", "line"):
        im = reveal(op, ph, sp, PW, PH)
        im.convert("RGB").resize((PW * 2, PH * 2), Image.NEAREST).save(os.path.join(OUT, "phone_reveal_%s.png" % ph))
    class_pick(ops, unlocked | {"lumen"}, sp, PW, PH).convert("RGB").resize((PW * 2, PH * 2), Image.NEAREST).save(os.path.join(OUT, "phone_pick_class.png"))
    oppick_locked(ops, unlocked, sp, PW, PH).convert("RGB").resize((PW * 2, PH * 2), Image.NEAREST).save(os.path.join(OUT, "phone_locked_oppick.png"))
    # 竖屏（游戏本体横屏；竖持时演出居中放大到宽度，信息排在立绘下方）
    im = portrait_line(op)
    im.convert("RGB").resize((im.width * 2, im.height * 2), Image.NEAREST).save(os.path.join(OUT, "portrait_reveal_line.png"))
    print("ok", OUT)


def portrait_line(op, w=360, h=740):
    img = bg(w, h, 12)
    s = 0.62
    header(img, s, "HEADHUNT // 01", "寻访")
    spr, foot = frame0(op, 2)
    paste_at_foot(img, spr, foot, w // 2, int(h * 0.48))
    stardust(img, w // 2, int(h * 0.36), 150, 24, 4)
    name_block(img, op, 24, int(h * 0.53), s)
    by = h - 120
    panel(img, (16, by, w - 16, by + 60), 2, 3, a=220)
    for i, ln in enumerate(c1.wrap(op["line"], 11, w - 52) if hasattr(c1, "wrap") else [op["line"]]):
        text(img, (28, by + 18 + i * 16), ln, 11, TXT, "lm")
    hint(img, s, [("TAP", "继续")], w)
    return img


ORDER = []

if __name__ == "__main__":
    main()
