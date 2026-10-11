# -*- coding: utf-8 -*-
"""T5a 精简版「T5s」概念图（docs/67 §12，2026-10-12 用户：「干员不要放大两倍，和背景接不上了，然后现在是不是有点元素太多了，是不是可以精简一下」）。
只是概念图，不改游戏代码。底图 = 现版开场 2.2 秒帧（keyart 不平移、博士与封面干员原尺寸原位置）+ 现版左上 Logo 块；
去掉灯火日志、漂流瓶、右上图标、LAST DEPLOY 小卡、中号磁贴说明、界面层水母 / 光点。
留下：6 块磁贴（大小分级、像素阶梯切角、藏青 Bayer 抖动底）、S4 反白选中 + 细青边、只有选中块有发光潮线 + 涨水 + 涟漪、
小号「更换封面干员」、一行页脚。磁贴群放在左侧（原菜单的位置）：keyart 不平移时右边是巨树主干与人物，放右边会盖住（另出 _right 对照）。
用法：
    python tools/concept_title_ui_v5.py
输出（不入库）：主仓库 build/title_redesign/v5/
    title_T5s.png / title_T5s_sel2.png / title_T5s_phone.png / title_T5s_right.png（对照：磁贴群放右边）
"""
import os, sys

import numpy as np
from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
import concept_title_ui_v4 as v4  # noqa: E402
from concept_title_ui_v4 import snap, stair, edge_of, dith, paint, solid, glow, ripple, ptxt, put_icon, WATER, EDGE, N_TONES  # noqa: E402
from concept_title_ui_v2 import CY, CY_DIM, TXT, TXT2, text  # noqa: E402

OUT5 = os.path.join(c1.OUT, "v5")
NEAR_WHITE = (238, 243, 246)
NAVY_INK = (10, 28, 52)
SEL_EDGE = (60, 200, 228)
SEL_SUB = (70, 92, 112)
SEL_IDX = (24, 130, 160)
TIDE_GLOW = (90, 230, 255)
FOAM_GLOW = (200, 255, 255)
MENU = [("集结出发", "DEPLOY", "deploy"), ("图鉴", "GALLERY", "gallery"), ("Boss 演练", "BOSS TRIAL", "boss"),
        ("操作说明", "GUIDE", "guide"), ("设置", "SETTINGS", "settings"), ("退出", "EXIT", "exit")]
SUB0 = "选择干员与难度，走进深海"


def _mask_img(img, m, x0, y0):
    gm = Image.new("L", img.size, 0)
    gm.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
    return gm


def tile(img, box, i, sel, size, P, s, num=None):
    num = (i + 1) if num is None else num
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    m = stair(w, h, P, 3 if size != "small" else 2)
    crest = None
    if sel:
        glow(img, _mask_img(img, m, x0, y0), (90, 200, 230), 10 * s, (0.08, 0.3, 0.6), (18, 36, 64), cell=P * 2)
        solid(img, x0, y0, m, NEAR_WHITE)
        frac = 0.24 if size == "small" else 0.22
        base = h - max(3 * P, snap(h * frac, P))
        ys, xs = np.mgrid[0:h, 0:w]
        gx = (xs + x0) // P
        wave = (np.round(np.sin(gx * 0.45 + y0 * 0.1) * 0.8 + np.sin(gx * 0.17 + 1.3) * 0.6) * P).astype(int)
        wy = base + wave
        wm = m & (ys >= wy)
        wl = dith(x0, y0, w, h, P, lambda cx, cy: np.clip((cy - base) / max(1.0, h - base) * 2.4, 0, 2))
        wl[~wm] = -1
        paint(img, x0, y0, wm, wl, WATER, 236)
        top = wm & ~np.roll(wm, P, axis=0)
        band = wm & (ys < wy + 3 * P)
        glow(img, _mask_img(img, band, x0, y0), TIDE_GLOW, 4, (0.15, 0.45), (60, 110), cell=P)
        solid(img, x0, y0, top, FOAM_GLOW + (255,))
        crest = y0 + base
        solid(img, x0, y0, edge_of(m, P), SEL_EDGE)
        txt, sub, idx, ico, ico2 = NAVY_INK, SEL_SUB, SEL_IDX, NAVY_INK, (30, 150, 180)
    else:
        lv = dith(x0, y0, w, h, P, lambda cx, cy: np.clip((cy / h * 0.8 + cx / w * 0.2) * 2 * 1.15 - 0.05, 0, 2))
        paint(img, x0, y0, m, lv, N_TONES, 232)
        e = edge_of(m, P)
        solid(img, x0, y0, e, EDGE + (200,))
        tl = e.copy()
        tl[snap(h * 0.28, P):, :] = False
        tl[:, snap(w * 0.18, P):] = False
        solid(img, x0, y0, tl, CY)
        txt, sub, idx, ico, ico2 = TXT, TXT2, CY, (200, 226, 238), CY
    cn, en, ic = MENU[i]
    pk = 2 if P >= 2 else 1
    if size == "big":
        w_ = ptxt(img, (x0 + 18 * s, y0 + 18 * s), "%02d" % num, pk, idx, 1, "lm")
        ptxt(img, (x0 + 18 * s + w_ + 8 * s, y0 + 18 * s), "// OPERATION", 1, sub, 1, "lm")
        text(img, (x0 + 16 * s, y0 + 52 * s), cn, int(34 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 19 * s, y0 + 82 * s), en, pk, txt, 2, "lm")
        if s >= 1:   # 手机不写说明（会被涨起的水盖住）
            text(img, (x0 + 18 * s, y0 + 100 * s), SUB0, int(14 * s), sub, "lm")
        icx = x1 - 46 * s
        if crest:
            ripple(img, icx, crest, P, s * 0.8, m, (x0, y0), col=FOAM_GLOW)
        put_icon(img, ic, icx, (crest - 22 * s) if crest else y0 + h * 0.6, 3 if P >= 2 else 2, ico, ico2)
    elif size == "mid":
        ptxt(img, (x0 + 14 * s, y0 + 16 * s), "%02d" % num, pk, idx, 1, "lm")
        put_icon(img, ic, x1 - 24 * s, y0 + 24 * s, pk, ico, ico2)
        text(img, (x0 + 14 * s, y0 + 44 * s), cn, int(22 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 16 * s, y0 + 64 * s), en, 1, txt, 2, "lm")
        if crest:
            ripple(img, x1 - 40 * s, crest, P, s * 0.6, m, (x0, y0), col=FOAM_GLOW)
    else:
        put_icon(img, ic, x0 + 20 * s, y0 + h / 2 - 4 * s, pk, ico, ico2)
        text(img, (x0 + 38 * s, y0 + h / 2 - 8 * s), cn, int(16 * s), txt, "lm", bold=True)
        ptxt(img, (x0 + 39 * s, y0 + h / 2 + 8 * s), en, 1, sub, 1, "lm")
        ptxt(img, (x1 - 8 * s, y0 + 10 * s), "%02d" % num, 1, idx, 1, "rm")
        if crest:
            ripple(img, x0 + 20 * s, crest, P, s * 0.45, m, (x0, y0), col=FOAM_GLOW)


def cluster(img, x0, y0, w, sel, P, s, ids=(0, 1, 2, 3, 4, 5), hb=146, hm=92, hs=54, g=8):
    """ids：可见菜单项（对外包没有 2 Boss 演练、网页 / 手机没有 5 退出）；某行只剩一块时占满整行，编号按可见顺序连号"""
    hb, hm, hs, g = hb * s, hm * s, hs * s, g * s
    rows = [r for r in ([i for i in grp if i in ids] for grp in ([0], [1, 2], [3, 4, 5])) if r]
    boxes, sizes, nums = {}, {}, {}
    y, n = y0, 1
    for row in rows:
        kind = "big" if 0 in row else ("mid" if (1 in row or 2 in row) else "small")
        h = hb if kind == "big" else (hm if kind == "mid" else hs)
        cw = (w - g * (len(row) - 1)) / len(row)
        for k, i in enumerate(row):
            boxes[i] = (x0 + k * (cw + g), y, x0 + k * (cw + g) + cw, y + h)
            sizes[i], nums[i] = kind, n
            n += 1
        y += h + g
    for i, b in boxes.items():
        if i != sel:
            tile(img, b, i, False, sizes[i], P, s, nums[i])
    tile(img, boxes[sel], sel, True, sizes[sel], P, s, nums[sel])
    return y - g


def base(phone=False):
    """现版开场 2.2 秒帧（干净 keyart + 原位人物）+ 现版标题截图的左上 Logo 块"""
    if phone:
        im = c1.shot("intro_phone", (c1.PW, c1.PH))
        ttl = Image.open(os.path.join(c1.SHOTS, "title_phone", "shot_title.png")).convert("RGBA").resize((c1.PW, c1.PH))
        box = (0, 0, 440, 170)
    else:
        im = c1.shot("intro", (c1.W, c1.H))
        ttl = c1.shot("title", (c1.W, c1.H))
        box = (0, 0, 620, 292)
    im.paste(ttl.crop(box), box[:2])
    return im


def cover_switch(img, x1, y, P, s):
    yy = y
    ptxt(img, (x1, yy), "V", 1, CY, 1, "rm")
    w = text(img, (x1 - 16 * s, yy), "更换封面干员", int(15 * s), TXT, "rm")
    ix = x1 - 16 * s - w - 16 * s
    d = ImageDraw.Draw(img)
    for dx, dy in ((0, -3), (1, -2), (2, -1), (3, 0), (2, 1), (1, 2), (0, 3), (-1, 2), (-2, 1), (-3, 0), (-2, -1), (-1, -2)):
        d.rectangle([ix + dx * P, yy + dy * P, ix + dx * P + P - 1, yy + dy * P + P - 1], fill=TXT)
    c1.over(img, lambda dd: dd.line([(ix - 4 * P, yy + 16 * s), (x1, yy + 16 * s)], fill=TXT2 + (90,), width=1))
    d.rectangle([ix - 4 * P, yy + 15 * s, ix - 4 * P + 22 * s, yy + 15 * s + P - 1], fill=CY)


def title_T5s(sel=0, right=False, ids=(0, 1, 2, 3, 4, 5)):
    img = base()
    P, s = 2, 1.0
    x0 = 846 if right else 90
    yb = cluster(img, x0, 304, 400, sel, P, s, ids)
    ptxt(img, (x0 + 2, yb + 16), "W/S A/D  ↑↓←→ SELECT   ENTER CONFIRM", 1, (90, 104, 120), 1, "lm")
    cover_switch(img, 1236, 668, P, s)
    w = text(img, (90, 700), "明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 C", 12, TXT2, "lm")
    ptxt(img, (90 + w + 14, 700), "V2.0", 1, TXT2, 1, "lm")
    return img


def title_T5s_phone(sel=0, ids=(0, 1, 2, 3, 4)):
    img = base(phone=True)
    P, s = 1, 0.6
    cluster(img, 44, 174, 276, sel, P, s, ids, hb=130, hm=84, hs=58, g=6)
    cover_switch(img, 724, 322, P, 0.75)
    w = text(img, (360, 350), "同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明", 9, TXT2, "lm")
    ptxt(img, (360 + w + 8, 350), "V2.0", 1, TXT2, 1, "lm")
    return img


def main():
    os.makedirs(OUT5, exist_ok=True)
    outs = {"title_T5s": title_T5s(0), "title_T5s_sel2": title_T5s(1), "title_T5s_phone": title_T5s_phone(0),
            "title_T5s_right": title_T5s(0, right=True),
            # 对外包（没有 Boss 演练）：桌面 = 集结出发 / 图鉴（整行）/ 操作说明 + 设置 + 退出；网页 / 手机再去掉退出
            "title_T5s_public": title_T5s(0, ids=(0, 1, 3, 4, 5)), "title_T5s_public_phone": title_T5s_phone(0, ids=(0, 1, 3, 4))}
    for k, im in outs.items():
        p = os.path.join(OUT5, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)


if __name__ == "__main__":
    main()
