# -*- coding: utf-8 -*-
"""标题页 T4「终端首页」概念图（docs/67 §10，2026-10-11 用户：「能不能从明日方舟的游戏主页面设计中获取一点灵感」）。

只是给人看的概念图，不改游戏代码。只借原作主界面的**版式语言**（右侧大小分级的磁贴群、居中偏左的大立绘助理、
四角信息条），不用原作任何素材 / Logo / 图标：底图是本作 keyart 截图，人物是本作像素帧（最近邻放大），
Logo 是本作 logo.png，图标全部是这里用几何线条现画的。

  - T4a：磁贴群整体做轻微透视倾斜（右缘向里退约 5 %，像原作主界面那样「斜着立在屏幕右边」）；
  - T4b：同一套磁贴，不倾斜（像素字 / 1 px 细边保持锐利）；
  - T4b_white：T4b 换近白卡片（测试哪种底在 keyart 上更好读）；
  - T4b_sel2：T4b 选中「图鉴」（看中号磁贴的选中态、和方向键在格子间怎么走）；
  - 手机 740×360：T4b、T4a。

底图：开场 2.2 秒干净 keyart（主仓库 build/title_redesign/shots/，没有就先跑 `python tools/concept_title_ui.py --capture`），
整体左移让巨树落到画面中间、给右侧磁贴群让出暗海面；右侧空出来的一条用原图最左边的暗海面补齐（渐隐接缝，大部分在磁贴后面）。
keyart 里原本的小人先用旁边一段沙滩盖掉，再把封面干员（水月）和博士的 idle 第 0 帧放大画回去。

用法：
    python tools/concept_title_ui_v3.py

输出（不入库）：主仓库 build/title_redesign/v3/
    contact_sheet_v3.png                  总览（先看这张）
    title_T4a.png / title_T4b.png         桌面 1280×720
    title_T4b_white.png / title_T4b_sel2.png
    title_T4b_phone.png / title_T4a_phone.png
"""
import math, os, sys

from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
import concept_title_ui_v2 as c2  # noqa: E402
from concept_title_ui import W, H, PW, PH, YEL, INK, SUB, ART, over, code, logo, emblem, shot, contact_sheet  # noqa: E402
from concept_title_ui_v2 import NAVY, CY, CY_DIM, TXT, TXT2, TEAL, text, frost, cover_switch  # noqa: E402

OUT3 = os.path.join(c1.OUT, "v3")

# ---------------------------------------------------------------- 底图：去掉小人 + 左移 + 镜像补右缘
def stage(phone=False):
    im = shot("intro_phone", (PW, PH)) if phone else shot("intro", (W, H))
    # 原 keyart 里的博士 + 水月（约 4× 像素）用左边一段沙滩盖掉
    if phone:
        box, dx, shift = (470, 228, 602, 338), -128, 190
    else:
        box, dx, shift = (818, 462, 1036, 636), -212, 330
    x0, y0, x1, y1 = box
    patch = im.crop((x0 + dx, y0, x1 + dx, y1))
    m = Image.new("L", patch.size, 255).filter(ImageFilter.GaussianBlur(0))
    # 边缘 10 px 渐变，接缝不那么硬
    md = ImageDraw.Draw(m)
    for i in range(10):
        md.rectangle([i, i, patch.width - 1 - i, patch.height - 1 - i], outline=int(255 * (i + 1) / 10))
    im.paste(patch, (x0, y0), m)
    out = Image.new("RGBA", im.size, (6, 8, 14, 255))
    out.alpha_composite(im.crop((shift, 0, im.width, im.height)), (0, 0))
    # 右侧空出的一条：拿原图最左边那段暗海面 / 星空补上，接缝处 140 px 渐隐（大部分在磁贴后面）
    fade = 140 if not phone else 70
    tail = im.crop((0, 0, shift + fade, im.height))
    a = Image.new("L", tail.size, 255)
    ad = ImageDraw.Draw(a)
    for i in range(fade):
        ad.line([(i, 0), (i, tail.height)], fill=int(255 * i / fade))
    tail.putalpha(a)
    out.alpha_composite(tail, (im.width - shift - fade, 0))
    return out


def sprite(name, scale, k=1.0):
    fr = Image.open(os.path.join(ART, name + "@2x.png")).convert("RGBA").crop((0, 0, 96, 96))
    fr = fr.resize((96 * scale, 96 * scale), Image.NEAREST)
    if k != 1.0:
        dark = Image.new("RGBA", fr.size, (4, 10, 26, int(255 * (1 - k))))
        dark.putalpha(Image.eval(fr.getchannel("A"), lambda a: int(a * (1 - k))))
        fr.alpha_composite(dark)
    return fr


def place(img, name, scale, foot, k=1.0, bbox=None):
    """把 idle 第 0 帧放大到 scale 倍（@2x 帧），脚底中点落在 foot"""
    sp = sprite(name, scale, k)
    bx0, by0, bx1, by1 = bbox
    fx, fy = foot
    ox, oy = int(fx - (bx0 + bx1) / 2 * scale), int(fy - by1 * scale)
    w = (bx1 - bx0) * scale
    over(img, lambda d: d.ellipse([fx - w * 0.62, fy - w * 0.10, fx + w * 0.62, fy + w * 0.12], fill=(0, 2, 10, 120)))
    # 脚下一圈潮光（keyart 里的荧光浪色）
    over(img, lambda d: d.ellipse([fx - w * 0.9, fy - w * 0.05, fx + w * 0.9, fy + w * 0.17], outline=(110, 200, 255, 60), width=2))
    img.alpha_composite(sp, (ox, oy))


BB_MIZ = (30, 27, 78, 93)
BB_DOC = (29, 28, 69, 93)

# ---------------------------------------------------------------- 线条图标（几何现画，不取原作图标）
def icon(d, kind, cx, cy, r, col, w=2):
    if kind == "deploy":      # 三道前进折线
        for i in range(3):
            x = cx - r * 0.9 + i * r * 0.62
            d.line([(x, cy - r * 0.7), (x + r * 0.5, cy), (x, cy + r * 0.7)], fill=col, width=w + (1 if i == 2 else 0))
    elif kind == "gallery":   # 档案册：两页 + 书脊
        d.rectangle([cx - r, cy - r * 0.75, cx + r, cy + r * 0.75], outline=col, width=w)
        d.line([(cx, cy - r * 0.75), (cx, cy + r * 0.75)], fill=col, width=w)
        for k in range(3):
            yy = cy - r * 0.35 + k * r * 0.35
            d.line([(cx - r * 0.7, yy), (cx - r * 0.2, yy)], fill=col, width=1)
            d.line([(cx + r * 0.2, yy), (cx + r * 0.7, yy)], fill=col, width=1)
    elif kind == "boss":      # 准星
        d.ellipse([cx - r * 0.75, cy - r * 0.75, cx + r * 0.75, cy + r * 0.75], outline=col, width=w)
        for a in range(4):
            ang = a * math.pi / 2
            d.line([(cx + math.cos(ang) * r * 0.4, cy + math.sin(ang) * r * 0.4), (cx + math.cos(ang) * r, cy + math.sin(ang) * r)], fill=col, width=w)
        d.rectangle([cx - 1, cy - 1, cx + 1, cy + 1], fill=col)
    elif kind == "guide":     # 手柄轮廓 + 十字键 + 两个键
        d.rounded_rectangle([cx - r, cy - r * 0.55, cx + r, cy + r * 0.55], radius=int(r * 0.45), outline=col, width=w)
        d.line([(cx - r * 0.62, cy), (cx - r * 0.22, cy)], fill=col, width=w)
        d.line([(cx - r * 0.42, cy - r * 0.2), (cx - r * 0.42, cy + r * 0.2)], fill=col, width=w)
        for dx_, dy_ in ((0.35, -0.12), (0.6, 0.12)):
            q = max(1, r * 0.1)
            d.ellipse([cx + r * dx_ - q, cy + r * dy_ - q, cx + r * dx_ + q, cy + r * dy_ + q], fill=col)
    elif kind == "settings":  # 齿轮：圆 + 8 齿
        for a in range(8):
            ang = a * math.pi / 4
            d.line([(cx + math.cos(ang) * r * 0.55, cy + math.sin(ang) * r * 0.55), (cx + math.cos(ang) * r * 0.95, cy + math.sin(ang) * r * 0.95)], fill=col, width=w + 1)
        d.ellipse([cx - r * 0.62, cy - r * 0.62, cx + r * 0.62, cy + r * 0.62], outline=col, width=w)
        d.ellipse([cx - r * 0.24, cy - r * 0.24, cx + r * 0.24, cy + r * 0.24], outline=col, width=w)
    elif kind == "exit":      # 门框 + 外出箭头
        d.line([(cx + r * 0.1, cy - r * 0.8), (cx - r * 0.8, cy - r * 0.8), (cx - r * 0.8, cy + r * 0.8), (cx + r * 0.1, cy + r * 0.8)], fill=col, width=w)
        d.line([(cx - r * 0.3, cy), (cx + r, cy)], fill=col, width=w)
        d.line([(cx + r * 0.55, cy - r * 0.45), (cx + r, cy), (cx + r * 0.55, cy + r * 0.45)], fill=col, width=w)
    elif kind == "info":      # 圆圈 i
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=w)
        d.rectangle([cx - 1, cy - r * 0.15, cx + 1, cy + r * 0.55], fill=col)
        d.rectangle([cx - 1, cy - r * 0.55, cx + 1, cy - r * 0.35], fill=col)
    elif kind == "full":      # 全屏四角
        for sx in (-1, 1):
            for sy in (-1, 1):
                d.line([(cx + sx * r, cy + sy * r * 0.4), (cx + sx * r, cy + sy * r), (cx + sx * r * 0.4, cy + sy * r)], fill=col, width=w)


# ---------------------------------------------------------------- 磁贴
MENU = [("集结出发", "DEPLOY", "deploy"), ("图鉴", "GALLERY", "gallery"), ("Boss 演练", "BOSS TRIAL", "boss"),
        ("操作说明", "GUIDE", "guide"), ("设置", "SETTINGS", "settings"), ("退出", "EXIT", "exit")]
SUBS = ["选择干员与难度，走进深海", "干员、敌人、藏品与结局档案", "直接选择 Boss，检查招式与阶段"]

STYLE = {
    "navy": dict(fill=(12, 24, 44, 196), ol=CY + (70,), txt=TXT, sub=TXT2, idx=CY, ico=(200, 226, 238), tick=CY, frost=True),
    "white": dict(fill=(240, 244, 248, 232), ol=(255, 255, 255, 120), txt=INK, sub=SUB, idx=TEAL, ico=(40, 70, 96), tick=TEAL, frost=False),
}


def tile(L, M, box, i, sel, st, size, s=1.0):
    """一块磁贴：编号 + 线条图标 + 中文 + 宽字距英文；选中 = 整块警示黄（全屏唯一的黄）"""
    x0, y0, x1, y1 = box
    S = STYLE[st]
    cn, en, ic = MENU[i]
    md = ImageDraw.Draw(M)
    md.rectangle(box, fill=255)
    d = ImageDraw.Draw(L)
    if sel:
        over(L, lambda dd: dd.rectangle([x0 + 5 * s, y0 + 5 * s, x1 + 5 * s, y1 + 5 * s], fill=(0, 0, 0, 110)))
        d.rectangle(box, fill=YEL + (255,))
        # 选中外框：2 px 黄色描边外扩 4 px，四角折线（按键导航时远看也能认出）
        g = 5 * s
        for (ax, ay, sx, sy) in ((x0 - g, y0 - g, 1, 1), (x1 + g, y0 - g, -1, 1), (x0 - g, y1 + g, 1, -1), (x1 + g, y1 + g, -1, -1)):
            d.line([(ax, ay + sy * 14 * s), (ax, ay), (ax + sx * 14 * s, ay)], fill=YEL + (255,), width=max(2, int(2 * s)))
        txt, sub, idx, ico, tick = INK, INK, INK, INK, INK
    else:
        over(L, lambda dd: dd.rectangle(box, fill=S["fill"]))
        over(L, lambda dd: dd.rectangle(box, outline=S["ol"], width=1))
        txt, sub, idx, ico, tick = S["txt"], S["sub"], S["idx"], S["ico"], S["tick"]
    # 左上角刻度
    d.line([(x0, y0 + 10 * s), (x0, y0), (x0 + 10 * s, y0)], fill=tick + (255,) if len(tick) == 3 else tick, width=max(2, int(2 * s)))
    if size == "big":
        code(L, (x0 + 24 * s, y0 + 22 * s), "%02d  //  OPERATION" % (i + 1), int(9 * s), idx, 2, "lm")
        text(L, (x0 + 22 * s, y0 + 78 * s), cn, int(44 * s), txt, "lm", bold=True)
        code(L, (x0 + 26 * s, y0 + 118 * s), en, int(12 * s), txt, int(7 * s), "lm")
        text(L, (x0 + 24 * s, y0 + 150 * s), SUBS[0], int(15 * s), sub, "lm")
        # 上次出发小预览（难度 + 编队）
        px0, py0, px1, py1 = x1 - 196 * s, y0 + 18 * s, x1 - 18 * s, y0 + 118 * s
        if sel:
            d.rectangle([px0, py0, px1, py1], outline=INK + (255,), width=1)
        else:
            over(L, lambda dd: dd.rectangle([px0, py0, px1, py1], fill=(4, 10, 22, 150) if st == "navy" else (220, 228, 236, 255)))
            over(L, lambda dd: dd.rectangle([px0, py0, px1, py1], outline=S["ol"], width=1))
        code(L, (px0 + 12 * s, py0 + 16 * s), "LAST  DEPLOY", int(7 * s), sub, 2, "lm")
        text(L, (px0 + 12 * s, py0 + 42 * s), "Ⅳ", int(24 * s), txt, "lm", bold=True)
        text(L, (px0 + 44 * s, py0 + 42 * s), "波涛迭起", int(15 * s), txt, "lm", bold=True)
        # 三格潮位：两格亮
        for k in range(3):
            bx = px0 + 12 * s + k * 24 * s
            fill = (INK if sel else CY) if k < 2 else None
            d.rectangle([bx, py0 + 60 * s, bx + 18 * s, py0 + 66 * s], fill=fill, outline=(INK if sel else (CY_DIM if st == "navy" else TEAL)))
        text(L, (px0 + 12 * s, py0 + 84 * s), "水月 · 三人编队", int(12 * s), sub, "lm")
        icon(d, ic, x1 - 52 * s, y1 - 40 * s, 22 * s, ico, max(2, int(3 * s)))
        code(L, (x1 - 96 * s, y1 - 40 * s), "ENTER  /  PAD A", int(8 * s), sub, 2, "rm")
    elif size == "mid":
        code(L, (x0 + 18 * s, y0 + 20 * s), "%02d" % (i + 1), int(9 * s), idx, 1, "lm")
        icon(d, ic, x1 - 30 * s, y0 + 30 * s, 15 * s, ico, 2)
        text(L, (x0 + 18 * s, y1 - 56 * s), cn, int(24 * s), txt, "lm", bold=True)
        code(L, (x0 + 20 * s, y1 - 32 * s), en, int(8 * s), txt, int(4 * s), "lm")
        if s >= 1:
            text(L, (x0 + 18 * s, y1 - 14 * s), SUBS[i], int(12 * s), sub, "lm")
    else:
        icon(d, ic, x0 + 26 * s, (y0 + y1) / 2, 11 * s, ico, 2)
        text(L, (x0 + 48 * s, (y0 + y1) / 2 - 7 * s), cn, int(17 * s), txt, "lm", bold=True)
        code(L, (x0 + 49 * s, (y0 + y1) / 2 + 13 * s), en, int(7 * s), sub, int(3 * s), "lm")
        code(L, (x1 - 10 * s, y0 + 12 * s), "%02d" % (i + 1), int(7 * s), idx, 1, "rm")


def cluster_boxes(x0, y0, w, s=1.0, n_small=3):
    g = 10 * s
    hb, hm, hs = 206 * s, 128 * s, 70 * s
    mw = (w - g) / 2
    boxes = [(x0, y0, x0 + w, y0 + hb)]
    y = y0 + hb + g
    boxes += [(x0, y, x0 + mw, y + hm), (x0 + mw + g, y, x0 + w, y + hm)]
    y += hm + g
    sw = (w - g * (n_small - 1)) / n_small
    for k in range(n_small):
        boxes.append((x0 + k * (sw + g), y, x0 + k * (sw + g) + sw, y + hs))
    return boxes, y + hs


def find_coeffs(pa, pb):
    """PIL 透视变换系数：输出四边形 pa → 输入四边形 pb"""
    import numpy as np
    A = []
    for (x, y), (X, Y) in zip(pa, pb):
        A.append([x, y, 1, 0, 0, 0, -X * x, -X * y])
        A.append([0, 0, 0, x, y, 1, -Y * x, -Y * y])
    A = np.array(A, dtype=float)
    B = np.array(pb, dtype=float).reshape(8)
    return np.linalg.solve(A, B).tolist()


def cluster(img, x0, y0, w, sel, st="navy", tilt=False, s=1.0, n_small=3, hint=True):
    boxes, yb = cluster_boxes(x0, y0, w, s, n_small)
    L = Image.new("RGBA", img.size, (0, 0, 0, 0))
    M = Image.new("L", img.size, 0)
    sizes = ["big", "mid", "mid"] + ["small"] * n_small
    for i, b in enumerate(boxes):
        tile(L, M, b, i, i == sel, st, sizes[i], s)
    if hint:
        code(L, (x0 + w, yb + 20 * s), "↑ ↓ ← →  SELECT     ENTER  CONFIRM", int(8 * s), TXT2, 2, "rm")
    if tilt:
        # 右缘向里退：右边上下各收 6 %，整块再往右上抬一点（像立在屏幕右侧、朝向人物的一面墙）
        X0, Y0, X1, Y1 = x0 - 12 * s, y0 - 12 * s, x0 + w + 12 * s, yb + 30 * s
        hh = Y1 - Y0
        dst = [(X0, Y0 + hh * 0.015), (X1 - (X1 - X0) * 0.03, Y0 + hh * 0.06 - 14 * s), (X1 - (X1 - X0) * 0.03, Y1 - hh * 0.06 - 14 * s), (X0, Y1 + hh * 0.015)]
        src = [(X0, Y0), (X1, Y0), (X1, Y1), (X0, Y1)]
        co = find_coeffs(dst, src)
        L = L.transform(img.size, Image.PERSPECTIVE, co, Image.BICUBIC)
        M = M.transform(img.size, Image.PERSPECTIVE, co, Image.BICUBIC)
    if STYLE[st]["frost"]:
        img.paste(img.filter(ImageFilter.GaussianBlur(8 * s)), (0, 0), M)
    else:
        # 白卡：背后也先轻模糊，避免星点从卡缝里「跳」出来
        img.paste(img.filter(ImageFilter.GaussianBlur(4 * s)), (0, 0), M)
    img.alpha_composite(L)


# ---------------------------------------------------------------- 四角
def record_strip(img, x, y, s=1.0, compact=False):
    """左上：博士档案条（Logo 下面）"""
    w = (400 if compact else 560) * s
    h = 30 * s
    frost(img, [(x, y), (x + w + 14 * s, y), (x + w, y + h), (x, y + h)], NAVY, 170, 6)
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + 3 * s, y + h], fill=CY)
    cy = y + h / 2
    emblem(img, (x + 20 * s, cy), 7 * s, (200, 220, 230))
    xx = x + 36 * s
    xx += text(img, (xx, cy), "博士", int(14 * s), TXT, "lm", bold=True) + 6 * s
    xx += code(img, (xx, cy), "DR.", int(7 * s), TXT2, 2, "lm") + 12 * s
    items = [("干员", "18/18"), ("最高通关", "Ⅷ"), ("灯火记录", "37 局")] if compact else [("已解锁干员", "18/18"), ("最高通关", "Ⅷ"), ("灯火记录", "37 局")]
    for lab, v in items:
        code(img, (xx, cy), "//", int(8 * s), CY_DIM, 1, "lm")
        xx += 18 * s
        xx += text(img, (xx, cy), lab, int(12 * s), TXT2, "lm") + 6 * s
        xx += text(img, (xx, cy), v, int(14 * s), TXT, "lm", bold=True) + 12 * s


def corner_icons(img, x1, y, s=1.0, keys=True):
    """右上：设置 / 致谢 / 全屏 小图标 + 版本号"""
    d = ImageDraw.Draw(img)
    k = 34 * s
    # 底下一条深海磨砂，避免图标和版本号压在发光巨树上看不清
    gx0 = x1 - 3 * (k + 8 * s) - 54 * s
    frost(img, [(gx0, y - 6 * s), (x1 + 6 * s, y - 6 * s), (x1 + 6 * s, y + k + (22 if keys else 6) * s), (gx0 - 12 * s, y + k + (22 if keys else 6) * s)], NAVY, 150, 6)
    for j, (kind, key) in enumerate((("settings", "ESC"), ("info", "C"), ("full", "F11"))):
        bx = x1 - k - j * (k + 8 * s)
        over(img, lambda dd: dd.rectangle([bx, y, bx + k, y + k], fill=NAVY + (170,)))
        over(img, lambda dd: dd.rectangle([bx, y, bx + k, y + k], outline=CY + (80,), width=1))
        icon(d, kind, bx + k / 2, y + k / 2, 9 * s, TXT, 2)
        if keys:
            code(img, (bx + k / 2, y + k + 10 * s), key, int(6 * s), TXT2, 1, "mm")
    code(img, (x1 - 3 * (k + 8 * s) - 6 * s, y + k / 2), "v2.1", int(9 * s), TXT2, 2, "rm")


def news_card(img, x, y, w, h, s=1.0):
    """左下：本版更新横幅"""
    frost(img, [(x, y), (x + w, y), (x + w, y + h), (x, y + h)], NAVY, 180, 6)
    over(img, lambda d: d.rectangle([x, y, x + w, y + h], outline=CY + (70,), width=1))
    d = ImageDraw.Draw(img)
    d.rectangle([x, y, x + 3 * s, y + h], fill=CY)
    code(img, (x + 16 * s, y + 15 * s), "本版更新  //  UPDATE  v2.1", int(8 * s), CY, 2, "lm")
    text(img, (x + 16 * s, y + 40 * s), "新干员 浊心斯卡蒂 等 5 位", int(16 * s), TXT, "lm", bold=True)
    if h > 60 * s:
        text(img, (x + 16 * s, y + 64 * s), "德克萨斯 · 星熊 · 能天使 · 安洁莉娜", int(12 * s), TXT2, "lm")
    # 翻页点 + 箭头
    for k in range(3):
        cx = x + w - 54 * s + k * 12 * s
        d.rectangle([cx, y + 12 * s, cx + 6 * s, y + 16 * s], fill=CY if k == 0 else CY_DIM)
    text(img, (x + w - 14 * s, y + h / 2 + 4 * s), "》", int(16 * s), CY, "rm")


# ---------------------------------------------------------------- 标题 T4
def title_T4(tilt=False, st="navy", sel=0):
    img = stage()
    # 舞台：博士在后，水月在前（封面干员 = 焦点，@2x 帧 4×，约现版 2×；博士 3×、压暗一点往后推）
    place(img, "doctor_idle", 3, (418, 604), k=0.8, bbox=BB_DOC)
    place(img, "player_idle", 4, (556, 628), bbox=BB_MIZ)
    # 左上 Logo + 档案条
    img.alpha_composite(logo(0.42), (26, 20))
    code(img, (262, 50), "MIZUKI & CAERULA ARBOR", 8, TXT2, 2, "lm")
    text(img, (262, 70), "水月与深蓝之树", 13, TXT, "lm")
    record_strip(img, 24, 96)
    corner_icons(img, 1256, 22)
    # 右侧磁贴群
    cluster(img, 768, 128, 480, sel, st, tilt)
    # 封面干员名牌 + 更换（人物脚下）
    code(img, (452, 650), "COVER  //  ASSISTANT", 7, CY, 2, "lm")
    text(img, (452, 672), "水月", 18, TXT, "lm", bold=True)
    code(img, (496, 672), "MIZUKI", 8, TXT2, 3, "lm")
    cover_switch(img, 740, 636, 0.82, label=False)
    news_card(img, 24, 562, 330, 92)
    text(img, (24, 700), "明日方舟同人作品 · 非商业 · 与鹰角网络无关 · 致谢与声明 C", 11, TXT2, "lm")
    return img


def title_T4_phone(tilt=False, st="navy", sel=0):
    img = stage(phone=True)
    place(img, "doctor_idle", 2, (232, 300), k=0.8, bbox=BB_DOC)
    place(img, "player_idle", 3, (316, 318), bbox=BB_MIZ)
    img.alpha_composite(logo(0.24), (12, 10))
    record_strip(img, 12, 48, 0.62, compact=True)
    corner_icons(img, 730, 10, 0.72, keys=False)
    # 手机：磁贴 0.62 倍；网页 / 手机没有「退出」，底行只有两块
    cluster(img, 404, 62, 326, sel, st, tilt, s=0.62, n_small=2, hint=False)
    news_card(img, 12, 296, 170, 34, 0.62)
    cover_switch(img, 392, 312, 0.62, label=False)
    code(img, (12, 350), "同人作品 · 非商业 · 致谢 C", 6, TXT2, 1, "lm")
    return img


# ---------------------------------------------------------------- 总览
def main():
    os.makedirs(OUT3, exist_ok=True)
    cur = Image.open(os.path.join(c1.OUT, "current_title.png")).convert("RGBA")
    t1p = Image.open(os.path.join(c1.OUT, "v2", "title_T1p_a.png")).convert("RGBA")
    t1p_phone = Image.open(os.path.join(c1.OUT, "v2", "title_T1p_a_phone.png")).convert("RGBA")
    outs = {
        "title_T4a": title_T4(tilt=True),
        "title_T4b": title_T4(tilt=False),
        "title_T4b_white": title_T4(tilt=False, st="white"),
        "title_T4b_sel2": title_T4(tilt=False, sel=1),
        "title_T4b_phone": title_T4_phone(tilt=False),
        "title_T4a_phone": title_T4_phone(tilt=True),
    }
    for k, im in outs.items():
        p = os.path.join(OUT3, k + ".png")
        im.convert("RGB").save(p)
        print("写出", p)
    contact_sheet([
        ("标题", [("现状（方案 A 时间轴菜单）", cur), ("T1'a：左侧深海磨砂竖条（§9 推荐）", t1p),
                ("T4a：终端首页，磁贴群透视倾斜", outs["title_T4a"]), ("T4b：终端首页，磁贴平放（推荐）", outs["title_T4b"])]),
        ("T4 变体", [("T4b 近白卡片（对照：卡片底色测试）", outs["title_T4b_white"]), ("T4b 选中「图鉴」：中号磁贴选中态", outs["title_T4b_sel2"])]),
        ("手机", [("T1'a 手机 740×360", t1p_phone), ("T4b 手机 740×360", outs["title_T4b_phone"]),
                ("T4a 手机 740×360（倾斜）", outs["title_T4a_phone"])]),
    ], "T4 终端首页（版式参考明日方舟主界面，素材全部本作）  docs/67 §10", os.path.join(OUT3, "contact_sheet_v3.png"))


if __name__ == "__main__":
    main()
