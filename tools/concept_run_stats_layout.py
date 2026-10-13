# -*- coding: utf-8 -*-
"""作战记录 v3 版式三案（docs/77 §3.1，2026-10-12 用户「现在的结算布局也有点奇怪」）。只是概念图，不改游戏代码。
同一份数据画三种版式，各出两种情况：失败 + 5 件藏品、胜利 + 30 件藏品；推荐案另出手机版。
规则：面板按内容定高、不留大空面板；藏品说明改成选中 / 悬停时贴着图标弹出；统一栏距与基线；结果最先读到；T5s 风格。
用法：python tools/concept_run_stats_layout.py → 主仓库 build/run_stats/layout/
"""
import os, sys

from PIL import Image, ImageDraw

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import concept_run_stats as R  # noqa: E402
from concept_run_stats import block, text, ptxt, pbar, sprite, hints, rgb, num, mmss, SEL_INK, SEL_SUB, RED, CY, CY_DIM, TXT, TXT2, EDGE  # noqa: E402

OUT = os.path.join(R.OUT, "layout")
ART = R.ART
GREEN = (47, 211, 160)
VIOLET = (124, 107, 255)

OPS = [("水月", "player_idle", (0.62, 0.55, 1.0), "主控 · 开局", 46, 176002), ("斯卡蒂", "op_skadi_idle", (0.35, 0.55, 0.95), "01:17 加入", 21, 81000),
       ("星熊", "op_hoshiguma_idle", (0.95, 0.75, 0.3), "02:40 加入", 18, 69000), ("维什戴尔", "op_wisadel_idle", (0.95, 0.22, 0.2), "05:12 加入", 9, 34000),
       ("藏品与支援", "", (0.55, 0.62, 0.72), "全程", 6, 23000)]


def stats(win):
    s = [("探索时间", "12:22" if win else "05:00", ""), ("击杀", "3,512" if win else "1,789", ""), ("精英击杀", "23" if win else "6", ""),
         ("Boss 击破", "3" if win else "1", ""), ("造成伤害", "383,002", "每秒 517"), ("最高单次伤害", "18,412", "迅捷打击·γ型（斯卡蒂）"),
         ("受到伤害", "1,240", ""), ("生命回复", "1,118", ""), ("获得经验", "9,420", "Lv.38"), ("获得源石锭", "148", "花费 120"),
         ("打开补给箱", "8", ""), ("海嗣祭坛", "2", ""), ("点亮引航灯标", "4", ""), ("灯火通明", "71%", ""), ("冲刺", "214", ""),
         ("技能发动", "276", ""), ("藏品", "30" if win else "5", "")]
    if win:
        s.append(("源石锭熔铸", "全队伤害 +6%", ""))
    return s


def relic_ids(n):
    ids = [str(i) for i in (4, 13, 42, 96, 7, 21, 33, 58, 61, 70, 75, 80, 88, 99, 102, 110, 111, 115, 120, 121, 125, 130, 1, 8, 10, 11, 12, 14, 16, 18)]
    return [i for i in ids if os.path.exists(os.path.join(ART, "relic_%s.png" % i))][:n]


def base(W, H):
    im = R.base(W, H, 1.0)
    block(im, (14, 14, W - 14, H - 14), 2, 3, alpha=140, acc=False)
    return im


def enemy(img, cx, by, k=2):
    sh = Image.open(os.path.join(ART, "e_bone.png")).convert("RGBA")
    fr = sh.crop((0, 0, sh.height, sh.height)).resize((sh.height * k, sh.height * k), Image.NEAREST)
    img.alpha_composite(fr, (int(cx - fr.width / 2), int(by - fr.height)))


def banner(img, box, win, compact=False):
    """结果横幅：结果大字 + 结局 / 击倒者 + 难度 · 时间 + 主控像"""
    x0, y0, x1, y1 = block(img, box, 2, 3)
    d = ImageDraw.Draw(img)
    col = CY if win else RED
    d.rectangle([x0 + 4, y0 + 10, x0 + 7, y1 - 10], fill=col)
    ptxt(img, (x0 + 24, y0 + 20), "RUN REPORT", 1, CY_DIM, 2, "lm")
    text(img, (x0 + 22, y0 + 52), "探索完成" if win else "探索终止", 34 if not compact else 26, col, "lm", bold=True)
    sub = "结局一 · 平凡即是喜乐" if win else "被 骨海漂流体 击倒 · 侵蚀"
    text(img, (x0 + 22, y0 + 88), sub, 16, TXT, "lm")
    return x0, y0, x1, y1


def banner_right(img, x1, y0, win, show_leader=True):
    # 难度 / 时间 / 主控（右对齐）
    xr = x1 - 22
    if show_leader:
        sprite(img, "player_idle", xr - 36, y0 + 104, 2)
        text(img, (xr - 80, y0 + 40), "水月", 18, TXT, "rm", bold=True)
        text(img, (xr - 80, y0 + 64), "Lv.38 · 精英二", 13, TXT2, "rm")
        xr -= 210
    ptxt(img, (xr, y0 + 52), "12:22" if win else "05:00", 4, TXT, 1, "rm")
    text(img, (xr, y0 + 88), "波涛迭起 · IV  探索时间", 13, TXT2, "rm")
    if not win:
        enemy(img, xr - 220, y0 + 112, 2)


def relic_grid(img, box, ids, cell=44, sel=None, title=True):
    x0, y0, x1, _ = box
    if title:
        text(img, (x0, y0 + 10), "藏品", 16, TXT, "lm", bold=True)
        ptxt(img, (x0 + 44, y0 + 10), str(len(ids)), 2, CY, 1, "lm")
        y0 += 26
    per = max(1, int((x1 - x0) // cell))
    for i, rid in enumerate(ids):
        cx, cy = x0 + (i % per) * cell, y0 + (i // per) * cell
        on = sel == i
        block(img, (cx, cy, cx + cell - 6, cy + cell - 6), 2, 1, sel=on)
        ic = Image.open(os.path.join(ART, "relic_%s.png" % rid)).convert("RGBA")
        img.alpha_composite(ic, (int(cx + (cell - 6) / 2 - 16), int(cy + (cell - 6) / 2 - 16)))
        if i % 7 == 2:
            d = ImageDraw.Draw(img)
            for q in range(3):
                d.rectangle([cx + 4 + q * 6, cy + cell - 13, cx + 7 + q * 6, cy + cell - 11], fill=(150, 240, 230))
    rows = (len(ids) + per - 1) // per
    return y0 + rows * cell - 6, per


def popup(img, ax, ay, w=300):
    """选中藏品时贴着图标弹出的说明"""
    x0, y0 = ax, ay + 6
    block(img, (x0, y0, x0 + w, y0 + 70), 2, 2, alpha=250)
    d = ImageDraw.Draw(img)
    d.polygon([(x0 + 18, y0), (x0 + 26, y0 - 7), (x0 + 34, y0)], fill=(18, 40, 68))
    text(img, (x0 + 12, y0 + 18), "咖啡平原咖啡糖", 15, TXT, "lm", bold=False)
    text(img, (x0 + 140, y0 + 18), "Lv.3 / 3 · 基础 · 攻击与输出", 11, CY_DIM, "lm")
    text(img, (x0 + 12, y0 + 42), "全队攻击速度 +12%；精英与 Boss 在场时再 +8%。", 12, TXT2, "lm")


def stat_list(img, box, rows, cols=1, rh=22):
    x0, y0, x1, y1 = box
    text(img, (x0, y0 + 10), "数据", 16, TXT, "lm", bold=True)
    ptxt(img, (x0 + 44, y0 + 10), "STATS", 1, CY_DIM, 2, "lm")
    y0 += 28
    gap = 24
    cw = (x1 - x0 - gap * (cols - 1)) / cols
    per = (len(rows) + cols - 1) // cols
    d = ImageDraw.Draw(img)
    for i, (k, v, sub) in enumerate(rows):
        c, r = i // per, i % per
        cx, cy = x0 + c * (cw + gap), y0 + r * rh + rh / 2
        d.line([(cx, cy + rh / 2 - 1), (cx + cw, cy + rh / 2 - 1)], fill=(40, 56, 76))
        text(img, (cx, cy), k, 13, TXT2, "lm")
        vw = text(img, (cx + cw, cy), v, 14, TXT, "rm")
        if sub:
            text(img, (cx + cw - vw - 10, cy), sub, 11, CY_DIM, "rm")
    return y0 + per * rh


def squad_strip(img, box, cw=None):
    x0, y0, x1, y1 = box
    text(img, (x0, y0 + 10), "编队", 16, TXT, "lm", bold=True)
    text(img, (x0 + 50, y0 + 10), "全队伤害 383,002 · 每秒 517", 13, TXT2, "lm")
    segs = [(o[4] / 100.0, rgb(o[2])) for o in OPS]
    pbar(img, x0, y0 + 24, x1 - x0, 8, 2, segs)
    y = y0 + 42
    n = len(OPS)
    cw = cw or min(150, (x1 - x0 - 8 * (n - 1)) / n)
    for i, (nm, tex, col, jt, pct, dmg) in enumerate(OPS):
        cx = x0 + i * (cw + 8)
        bx0, by0, bx1, by1 = block(img, (cx, y, cx + cw, y1), 2, 2, sel=(i == 0))
        ink, sub = (SEL_INK, SEL_SUB) if i == 0 else (TXT, TXT2)
        ImageDraw.Draw(img).rectangle([bx0 + 6, by0 + 4, bx1 - 6, by0 + 5], fill=rgb(col))
        if tex:
            sprite(img, tex, (bx0 + bx1) / 2, by0 + 60, 1)
        text(img, (bx0 + 10, by0 + 74), nm, 13, ink, "lm", bold=False)
        text(img, (bx0 + 10, by0 + 92), jt, 11, sub, "lm")
        ptxt(img, (bx0 + 10, by1 - 14), "%d%%" % pct, 2, ink, 1, "lm")
        text(img, (bx1 - 8, by1 - 14), num(dmg), 11, sub, "rm")


def squad_list(img, box):
    """竖排编队行：像、名字、入队、占比条、百分比"""
    x0, y0, x1, y1 = box
    text(img, (x0, y0 + 10), "编队", 16, TXT, "lm", bold=True)
    text(img, (x0 + 50, y0 + 10), "全队伤害 383,002", 13, TXT2, "lm")
    y = y0 + 28
    rh = (y1 - y) / len(OPS)
    for i, (nm, tex, col, jt, pct, dmg) in enumerate(OPS):
        bx0, by0, bx1, by1 = block(img, (x0, y, x1, y + rh - 6), 2, 1, sel=(i == 0))
        ink, sub = (SEL_INK, SEL_SUB) if i == 0 else (TXT, TXT2)
        if tex:
            sprite(img, tex, bx0 + 30, by1 - 2, 1)
        text(img, (bx0 + 62, by0 + 16), nm, 14, ink, "lm")
        text(img, (bx0 + 62, by0 + 34), jt, 11, sub, "lm")
        pbar(img, bx0 + 150, by0 + 22, bx1 - bx0 - 230, 8, 2, [(1.0, rgb(col))], pct / 46.0, track=True)
        ptxt(img, (bx1 - 12, (by0 + by1) / 2), "%d%%" % pct, 2, ink, 1, "rm")
        y += rh


def footer(img, W, H):
    block(img, (W - 192, H - 52, W - 32, H - 18), 2, 2)
    text(img, (W - 178, H - 35), "返回结算", 15, TXT, "lm")
    ptxt(img, (W - 46, H - 35), "ESC", 1, CY, 1, "rm")
    hints(img, 32, H - 35, [("↑ ↓ ← →", "藏品 / 编队"), ("ENTER", "干员详情"), ("PGUP PGDN", "滚动数据")])


def v1(win, W=1280, H=720):
    """横幅 + 两行：顶部全宽结果横幅；中间 藏品格（自适应高）| 数据；底部全宽编队条"""
    im = base(W, H)
    ids = relic_ids(30 if win else 5)
    banner(im, (32, 28, W - 32, 150), win)
    banner_right(im, W - 32, 28, win)
    top = 166
    sq_h = 150
    mid_b = H - 64 - sq_h - 12
    split = 0.6
    xs = 32 + (W - 64) * split
    gb, per = relic_grid(im, (32, top, xs - 12, mid_b), ids, cell=44 if win else 52, sel=2)
    popup(im, 32 + 2 * (44 if win else 52), top + 26 + (44 if win else 52) - 6)
    stat_list(im, (xs + 12, top, W - 32, mid_b), stats(win), cols=2 if not win else 2, rh=22)
    squad_strip(im, (32, H - 64 - sq_h, W - 32, H - 64), cw=200)
    footer(im, W, H)
    return im


def v2(win, W=1280, H=720):
    """左档案右数据（推荐）：左 40% 结果横幅 + 主控 / 击倒者卡 + 竖排编队（行高撑满）；
    右 60% 藏品格在上（按件数定高）+ 数据（行高撑满剩余高度，单列放不下才分两列）。两栏同顶同底，没有空面板"""
    im = base(W, H)
    ids = relic_ids(30 if win else 5)
    lw = (W - 64) * 0.4
    bot = H - 64
    banner(im, (32, 28, 32 + lw, 140), win, compact=True)
    x0, y0, x1, y1 = block(im, (32, 152, 32 + lw, 252), 2, 2)
    sprite(im, "player_idle", x0 + 50, y1 - 4, 2)
    text(im, (x0 + 100, y0 + 26), "水月", 16, TXT, "lm", bold=False)
    text(im, (x0 + 100, y0 + 48), "Lv.38 · 精英二 · 波涛迭起 IV", 12, TXT2, "lm")
    ptxt(im, (x1 - 16, y0 + 26), "12:22" if win else "05:00", 2, TXT, 1, "rm")
    # 击倒者 / 最终 Boss：卡片下半一行
    d = ImageDraw.Draw(im)
    d.line([(x0 + 100, y0 + 64), (x1 - 16, y0 + 64)], fill=(40, 56, 76))
    if not win:
        enemy(im, x0 + 116, y1 - 6, 1)
        text(im, (x0 + 140, y0 + 80), "击倒者  骨海漂流体", 13, TXT, "lm")
        text(im, (x1 - 16, y0 + 80), "侵蚀", 12, (217, 153, 255), "rm")
    else:
        text(im, (x0 + 100, y0 + 80), "击破最终 Boss  偏执泡影", 13, TXT, "lm")
        ptxt(im, (x1 - 16, y0 + 80), "12:22", 1, TXT2, 1, "rm")
    squad_list(im, (32, 264, 32 + lw, bot))
    rx = 32 + lw + 24
    gb, per = relic_grid(im, (rx, 28, W - 32, 400), ids, cell=46, sel=2)
    st = stats(win)
    avail = bot - (gb + 16) - 28
    rh = min(30, avail / len(st))
    cols = 1 if rh >= 20 else 2
    if cols == 2:
        rh = min(30, avail / ((len(st) + 1) // 2))
    stat_list(im, (rx, gb + 16, W - 32, bot), st, cols=cols, rh=rh)
    popup(im, rx + 2 * 46, 28 + 26 + 40)
    footer(im, W, H)
    return im


def v2_phone(win, page):
    """推荐案手机（UI 逻辑 1044×481，放大到 1560×720 看）：结果横幅 + 主控 / 击倒者一行常驻，下面三页 编队 / 藏品 / 数据"""
    W, H = 1044, 481
    im = base(W, H)
    ids = relic_ids(30 if win else 5)
    banner(im, (20, 20, 520, 116), win, compact=True)
    x0, y0, x1, y1 = block(im, (532, 20, W - 20, 116), 2, 2)
    sprite(im, "player_idle", x0 + 40, y1 - 4, 2)
    text(im, (x0 + 84, y0 + 24), "水月 · Lv.38 精英二", 14, TXT, "lm")
    ptxt(im, (x1 - 12, y0 + 24), "12:22" if win else "05:00", 2, TXT, 1, "rm")
    if not win:
        enemy(im, x0 + 100, y1 - 6, 1)
        text(im, (x0 + 122, y0 + 66), "击倒者  骨海漂流体 · 侵蚀", 13, TXT2, "lm")
    for i, nm in enumerate(["编队", "藏品", "数据"]):
        x = 20 + i * 100
        block(im, (x, 128, x + 92, 162), 2, 2, sel=(i == page))
        text(im, (x + 46, 145), nm, 15, SEL_INK if i == page else TXT2, "mm")
    if page == 0:
        squad_strip(im, (20, 168, W - 20, H - 60), cw=190)
    elif page == 1:
        relic_grid(im, (20, 168, W - 20, H - 60), ids, cell=48, sel=2, title=False)
        popup(im, 20 + 2 * 48, 168 + 42)
    else:
        stat_list(im, (20, 166, W - 20, H - 60), stats(win), cols=2, rh=26)
    block(im, (W - 170, H - 52, W - 20, H - 12), 2, 2)
    text(im, (W - 156, H - 32), "返回结算", 15, TXT, "lm")
    return im.resize((1560, 720), Image.NEAREST)


def v3(win, W=1280, H=720, phone=False):
    """推荐：横幅（结果 + 结局 / 击倒者 + 主控 + 难度时间）；下面左 62%：藏品格（按内容定高）紧跟编队条；右 38%：数据（单列，和左栏同顶同底）"""
    im = base(W, H)
    ids = relic_ids(30 if win else 5)
    banner(im, (32, 28, W - 32, 140), win)
    banner_right(im, W - 32, 22, win)
    top = 156
    bot = H - 64
    xs = 32 + (W - 64) * 0.62
    cell = 44 if len(ids) > 20 else 52
    gb, per = relic_grid(im, (32, top, xs - 12, bot), ids, cell=cell, sel=2)
    popup(im, 32 + 2 * cell, top + 26 + cell - 6)
    squad_strip(im, (32, max(gb + 20, bot - 190), xs - 12, bot))
    stat_list(im, (xs + 12, top, W - 32, bot), stats(win), cols=1, rh=min(24, (bot - top - 28) / len(stats(win))))
    footer(im, W, H)
    return im


def v3_phone(win, page):
    """手机（UI 逻辑 1044×481，放大到 1560×720 看）：横幅常驻，下面三页 概况 / 藏品 / 数据"""
    W, H = 1044, 481
    im = base(W, H)
    ids = relic_ids(30 if win else 5)
    banner(im, (20, 20, W - 20, 120), win, compact=True)
    banner_right(im, W - 20, 10, win, show_leader=False)
    for i, nm in enumerate(["概况", "藏品", "数据"]):
        x = 20 + i * 100
        block(im, (x, 130, x + 92, 164), 2, 2, sel=(i == page))
        text(im, (x + 46, 147), nm, 15, SEL_INK if i == page else TXT2, "mm")
    if page == 0:
        squad_strip(im, (20, 176, W - 20, H - 60), cw=190)
    elif page == 1:
        relic_grid(im, (20, 176, W - 20, H - 60), ids, cell=48, sel=2, title=False)
        popup(im, 20 + 2 * 48, 176 + 42)
    else:
        stat_list(im, (20, 170, W - 20, H - 60), stats(win), cols=2, rh=26)
    block(im, (W - 170, H - 52, W - 20, H - 12), 2, 2)
    text(im, (W - 156, H - 32), "返回结算", 15, TXT, "lm")
    return im.resize((1560, 720), Image.NEAREST)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("V1", v1), ("V2", v2), ("V3", v3)):
        for win in (False, True):
            fn(win).convert("RGB").save(os.path.join(OUT, "layout_%s_%s.png" % (name, "win30" if win else "defeat5")))
    for page in range(3):
        v2_phone(False, page).convert("RGB").save(os.path.join(OUT, "layout_V2_phone_%d.png" % page))
    print("写到", OUT)


if __name__ == "__main__":
    main()
