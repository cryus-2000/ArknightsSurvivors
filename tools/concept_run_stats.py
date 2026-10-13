# -*- coding: utf-8 -*-
"""作战记录（局终统计）概念图（docs/77，2026-10-12 用户：「最后可以加一个统一界面，各个干员伤害统计之类的，你看着进行指标设计和UI设计」）。

只是概念图，不改游戏代码。风格按局外 T5s（docs/37 §8、docs/67 §12）：像素阶梯切角、藏青三阶 Bayer 抖动底、
S4 近白选中 + 细青边、5×7 像素字画数字 / 英文，中文用 ui.ttf；不用琥珀、不用警示黄。数据是编的示例局（数值量级按 BALANCE 记录）。

用法：
    python tools/concept_run_stats.py
输出（不入库）：主仓库 build/run_stats/
    concept_overview.png        总览 1280×720（结局结算之后按「作战记录」进来）
    concept_detail_leader.png   主控详情（伤害来源 + 承伤 / 回复 / 灯火）
    concept_detail_ally.png     队友详情
    concept_overview_phone.png  手机 1560×720（UI 逻辑约 1044×481，界面层放大 1.494）
    concept_motion.png          招牌动效分镜：伤害分段拼合
"""
import os, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import concept_title_ui as c1  # noqa: E402
from concept_title_ui_v4 import snap, stair, edge_of, dith, paint, solid, glow, ptxt, N_TONES, WATER, EDGE  # noqa: E402
from concept_title_ui_v2 import CY, CY_DIM, TXT, TXT2  # noqa: E402
import concept_title_ui_v4 as v4  # noqa: E402

v4.GLYPH[","] = [0x00, 0x00, 0x00, 0x00, 0x0C, 0x04, 0x08]   # 千分位逗号（游戏内 TUI 同步加了这个字形）


def text(img, xy, s, size, col=TXT, anchor="la", bold=False):
    """ui.ttf 缺字（如「娅」）的字逐段换 ui_fallback.otf（它是缺字子集，不能整句换）"""
    from PIL import ImageFont
    d = ImageDraw.Draw(img)
    cm = c1._UI_CMAP or {}
    runs, cur, fb = [], "", None
    for ch in s:
        f = (ord(ch) not in cm) and not ch.isspace() and bool(cm)
        if fb is None or f == fb:
            cur += ch
        else:
            runs.append((cur, fb))
            cur = ch
        fb = f
    if cur:
        runs.append((cur, fb))
    fonts = [(r, ImageFont.truetype(c1.FONT_FB if f else c1.FONT_UI, size)) for r, f in runs]
    w = sum(d.textlength(r, font=fo) for r, fo in fonts)
    x, y = xy
    if anchor[0] == "m":
        x -= w / 2
    elif anchor[0] == "r":
        x -= w
    sw = 1 if (bold and size >= 22) else 0
    for r, fo in fonts:
        d.text((x, y), r, font=fo, fill=col, anchor="l" + anchor[1], stroke_width=sw, stroke_fill=col)
        x += d.textlength(r, font=fo)
    return w

OUT = os.path.join(c1.gr.common_root(ROOT), "build", "run_stats")
ART = os.path.join(ROOT, "art", "incoming")
SEL = (238, 243, 246)
SEL_EDGE = (60, 200, 228)
SEL_INK = (10, 28, 52)
SEL_SUB = (70, 92, 112)
RED = (255, 61, 139)
LAMP = [(150, 220, 236), (96, 160, 190), (52, 84, 118), (30, 36, 52)]   # 通明 / 摇曳 / 暗淡 / 寂灭：冷色明度阶（局外不用琥珀）

# ---------------------------------------------------------------- 示例局（量级按 BALANCE 记录：全队整局约 1365 / 秒）
T_END = 742
OPS = [
    dict(id="mizuki", name="水月", en="MIZUKI", col=(0.62, 0.55, 1.0), tex="player_idle", join=0, leader=True, kills=1412, casts=31, heal=0,
         src=[("伞击", "普攻", 268000), ("技能", "技能", 172000), ("触手", "天赋", 96000), ("触须阵", "分支", 61000), ("水刃", "分支", 22000)]),
    dict(id="skadi", name="斯卡蒂", en="SKADI", col=(0.35, 0.55, 0.95), tex="op_skadi_idle", join=192, kills=903, casts=14, heal=0,
         src=[("大剑", "普攻", 154000), ("迅捷打击·γ型", "技能", 121000), ("跃浪", "技能", 48000), ("反手斩", "天赋", 20000)]),
    dict(id="saria", name="塞雷娅", en="SARIA", col=(1.0, 0.72, 0.38), tex="op_saria_idle", join=400, kills=211, casts=9, heal=1840,
         src=[("拳击", "普攻", 52000), ("碎晶", "技能", 39000), ("阻挡", "天赋", 6000)]),
    dict(id="kaltsit", name="凯尔希", en="KAL'TSIT", col=(0.55, 1.0, 0.5), tex="op_kaltsit_idle", join=485, kills=344, casts=6, heal=2310,
         src=[("Mon3tr", "普攻", 88000), ("Mon3tr · 熔毁", "技能", 61000)]),
]
OTHER = dict(id="_other", name="藏品与支援", en="RELICS", col=(0.55, 0.62, 0.72), join=0, kills=187, casts=0, heal=0,
             src=[("援护", "支援", 41000), ("藏品", "藏品", 30000), ("地雷", "藏品", 12000)])
BOSSES = [("塑路者", 210, 262), ("接潮主教", 420, 497), ("「偏执泡影」", 600, 742)]
LAMP_S = [402, 231, 96, 13]
HEAL_SRC = [("凯尔希", 2310), ("塞雷娅", 1840), ("自身回复", 1210), ("吸血", 640), ("击杀回复", 380), ("拾取", 300)]
TAKEN_SRC = [("接潮主教", 2140), ("侵蚀", 1180), ("黑潮", 760), ("裂片掠食者", 540)]


def rgb(c):
    return tuple(int(round(v * 255)) for v in c)


def total(o):
    return sum(v for _, _, v in o["src"])


ALL = OPS + [OTHER]
SUM = sum(total(o) for o in ALL)


def pct_ints(vals):
    """最大余数法：整数百分比合计恰好 100"""
    s = float(sum(vals)) or 1.0
    raw = [v * 100.0 / s for v in vals]
    fl = [int(r) for r in raw]
    rest = 100 - sum(fl)
    order = sorted(range(len(vals)), key=lambda i: raw[i] - fl[i], reverse=True)
    for i in order[:rest]:
        fl[i] += 1
    return fl


PCT = pct_ints([total(o) for o in ALL])


def mmss(t):
    return "%02d:%02d" % (t // 60, t % 60)


def num(v):
    return "{:,}".format(int(round(v)))


# ---------------------------------------------------------------- 绘制件
def base(W, H, s):
    """背景：现版对局截图压暗（结算之后，世界仍在后面）"""
    p = os.path.join(c1.gr.common_root(ROOT), "build", "motion", "shots", "play", "shot_200.png")
    if os.path.exists(p):
        im = Image.open(p).convert("RGBA").resize((W, H), Image.LANCZOS)
    else:
        im = Image.new("RGBA", (W, H), (8, 16, 30, 255))
    im = im.filter(ImageFilter.GaussianBlur(2))
    im.alpha_composite(Image.new("RGBA", (W, H), (2, 8, 18, 214)))
    return im


def block(img, box, P, n=2, sel=False, alpha=232, acc=True):
    x0, y0, x1, y1 = [snap(v, P) for v in box]
    w, h = x1 - x0, y1 - y0
    m = stair(w, h, P, n)
    if sel:
        glow(img, _mask(img, m, x0, y0), (90, 200, 230), 8, (0.08, 0.3, 0.6), (18, 36, 64), cell=P * 2)
        solid(img, x0, y0, m, SEL)
        solid(img, x0, y0, edge_of(m, P), SEL_EDGE)
    else:
        lv = dith(x0, y0, w, h, P, lambda cx, cy: np.clip((cy / h * 0.8 + cx / w * 0.2) * 2 * 1.15 - 0.05, 0, 2))
        paint(img, x0, y0, m, lv, N_TONES, alpha)
        e = edge_of(m, P)
        solid(img, x0, y0, e, EDGE + (200,))
        if acc:
            tl = e.copy()
            tl[max(P * 3, int(h * 0.28)):, :] = False
            tl[:, max(P * 3, int(w * 0.18)):] = False
            solid(img, x0, y0, tl, CY)
    return x0, y0, x1, y1


def _mask(img, m, x0, y0):
    gm = Image.new("L", img.size, 0)
    gm.paste(Image.fromarray((m * 255).astype(np.uint8), "L"), (x0, y0))
    return gm


def pbar(img, x, y, w, h, P, segs, frac=1.0, track=True):
    """像素条：segs = [(占比, 颜色)]，段间 1 格暗缝；frac = 整条展开到多少（动效分镜用）"""
    d = ImageDraw.Draw(img)
    x, y, w, h = snap(x, P), snap(y, P), snap(w, P), snap(h, P)
    if track:
        d.rectangle([x, y, x + w - 1, y + h - 1], fill=(6, 14, 30))
        d.rectangle([x, y + h - P, x + w - 1, y + h - 1], fill=(20, 44, 70))
    cx = x
    lim = x + int(w * frac)
    for i, (f, col) in enumerate(segs):
        sw = snap(w * f, P)
        if i == len(segs) - 1 and frac >= 1.0:
            sw = x + w - cx
        x1 = min(cx + sw, lim)
        if x1 - cx > P:
            d.rectangle([cx, y, x1 - 1 - P, y + h - 1], fill=col)
            d.rectangle([cx, y, x1 - 1 - P, y + P - 1], fill=tuple(min(255, int(c * 1.25 + 30)) for c in col))
        cx += sw
    return x, y, w, h


def sprite(img, tex, cx, by, k, sel=False):
    p = os.path.join(ART, tex + ".png")
    if not os.path.exists(p):
        return
    sh = Image.open(p).convert("RGBA")
    fw = sh.height
    fr = sh.crop((0, 0, fw, sh.height)).resize((fw * k, sh.height * k), Image.NEAREST)
    img.alpha_composite(fr, (int(cx - fw * k / 2), int(by - sh.height * k)))


def tag(img, xy, s_, col, fs, P, ink=SEL_INK):
    """小标签：实色底 + 深字（来源类别：普攻 / 技能 / 天赋 / 分支 / 支援 / 藏品）"""
    d = ImageDraw.Draw(img)
    w = d.textlength(s_, font=c1.F(fs, s_)) + 8
    x, y = xy
    d.rectangle([x, y - fs // 2 - 3, x + w, y + fs // 2 + 3], fill=col)
    text(img, (x + 4, y), s_, fs, ink, "lm")
    return w


ORIGIN_COL = {"普攻": (120, 150, 180), "技能": (60, 200, 228), "天赋": (124, 107, 255), "分支": (47, 211, 160), "支援": (126, 152, 184), "藏品": (150, 160, 200)}


def header(img, W, s, P, title_cn, sub_en, right_hint, result=("结局一 · 平凡即是喜乐", "探索完成", CY)):
    x = 32 * s
    ptxt(img, (x + 2, 34 * s), sub_en, max(1, round(1 * s)), CY, 2, "lm")
    tw = text(img, (x, 60 * s), title_cn, int(28 * s), TXT, "lm", bold=True)
    rx = x + tw + 20 * s
    d = ImageDraw.Draw(img)
    rn, rs, rc = result
    w1 = d.textlength(rn, font=c1.F(int(15 * s), rn))
    block(img, (rx, 44 * s, rx + w1 + 24 * s + 70 * s, 76 * s), P, 2, acc=False)
    d.rectangle([rx + P * 2, 50 * s, rx + P * 3, 70 * s], fill=rc)
    text(img, (rx + 12 * s, 60 * s), rn, int(15 * s), TXT, "lm")
    text(img, (rx + 18 * s + w1, 60 * s), rs, int(13 * s), rc, "lm")
    ptxt(img, (W - 32 * s, 40 * s), right_hint, 1, TXT2, 1, "rm")


def kpis(img, x0, y0, w, h, s, P, items, phone=False):
    g = 8 * s
    n = len(items)
    cw = (w - g * (n - 1)) / n
    for i, (cn, val, sub) in enumerate(items):
        bx = x0 + i * (cw + g)
        block(img, (bx, y0, bx + cw, y0 + h), P, 2)
        text(img, (bx + 12 * s, y0 + 16 * s), cn, int(13 * s), TXT2, "lm")
        ptxt(img, (bx + 12 * s, y0 + h * 0.62), val, max(2, round(3 * s)) if not phone else 2, TXT, 1, "lm")
        if sub and not phone:
            text(img, (bx + cw - 10 * s, y0 + 16 * s), sub, int(11 * s), CY_DIM, "rm")


def squad_bar(img, x0, y0, w, s, P, frac=1.0, labels=True):
    text(img, (x0, y0 + 8 * s), "全队伤害", int(14 * s), TXT2, "lm")
    ww = ptxt(img, (x0 + 70 * s, y0 + 8 * s), num(SUM), 2, TXT, 1, "lm")
    text(img, (x0 + 70 * s + ww + 12 * s, y0 + 8 * s), "平均 %s / 秒" % num(SUM / T_END), int(13 * s), TXT2, "lm")
    ptxt(img, (x0 + w, y0 + 8 * s), "SQUAD DAMAGE SHARE", 1, CY_DIM, 2, "rm")
    segs = [(total(o) / SUM, rgb(o["col"])) for o in ALL]
    bx, by, bw, bh = pbar(img, x0, y0 + 22 * s, w, 20 * s, P, segs, frac)
    if labels and frac >= 1.0:
        cx = bx
        for o, p in zip(ALL, PCT):
            sw = bw * total(o) / SUM
            if sw > 44 * s:
                ptxt(img, (cx + 6 * s, by + bh / 2), "%d%%" % p, 1, SEL_INK, 1, "lm")
            cx += sw


def op_card(img, box, o, pct, s, P, sel=False, fill=1.0, phone=False):
    x0, y0, x1, y1 = block(img, box, P, 3, sel)
    w, h = x1 - x0, y1 - y0
    ink, sub, acc = (SEL_INK, SEL_SUB, (24, 130, 160)) if sel else (TXT, TXT2, CY)
    oc = rgb(o["col"])
    d = ImageDraw.Draw(img)
    # 干员色竖条（左缘）
    d.rectangle([x0 + P * 2, y0 + 14 * s, x0 + P * 3 + 1, y0 + 46 * s], fill=oc)
    text(img, (x0 + 16 * s, y0 + 22 * s), o["name"], int((17 if not phone else 15) * s), ink, "lm", bold=True)
    if o["id"] == "_other":
        jt = "全程"
    elif o.get("leader"):
        jt = "主控 · 开局"
    else:
        jt = mmss(o["join"]) + " 加入"
    text(img, (x0 + 16 * s, y0 + 42 * s), jt, int(12 * s), sub, "lm")
    if o.get("tex"):
        sprite(img, o["tex"], x1 - 40 * s, y0 + 66 * s, 2 if not phone else 2)
    # 占比（大像素字）+ 伤害
    ptxt(img, (x0 + 16 * s, y0 + 86 * s), "%d%%" % pct, 4 if not phone else 3, ink, 1, "lm")
    ptxt(img, (x0 + 16 * s, y0 + 116 * s), num(total(o)), 2, ink, 1, "lm")
    pbar(img, x0 + 16 * s, y0 + 130 * s, w - 32 * s, 8 * s, P, [(1.0, oc)], fill * total(o) / max(total(x) for x in ALL))
    if phone:
        return
    rows = [("每秒", num(total(o) / max(1, T_END - o["join"]))), ("击杀", num(o["kills"]))]
    if o["casts"]:
        rows.append(("技能", "%d 次" % o["casts"]))
    if o["heal"]:
        rows.append(("治疗", num(o["heal"])))
    yy = y0 + 156 * s
    for k, v in rows[:4]:
        text(img, (x0 + 16 * s, yy), k, int(12 * s), sub, "lm")
        text(img, (x1 - 14 * s, yy), v, int(13 * s), ink, "rm")
        yy += 19 * s
    top = sorted(o["src"], key=lambda r: -r[2])[0]
    d.line([(x0 + 16 * s, y1 - 32 * s), (x1 - 16 * s, y1 - 32 * s)], fill=(SEL_SUB if sel else EDGE), width=1)
    text(img, (x0 + 16 * s, y1 - 18 * s), "主要  " + top[0], int(12 * s), sub, "lm")
    text(img, (x1 - 14 * s, y1 - 18 * s), "%d%%" % round(top[2] * 100 / total(o)), int(12 * s), acc, "rm")


def timeline(img, box, s, P, frac=1.0):
    x0, y0, x1, y1 = block(img, box, P, 2)
    text(img, (x0 + 14 * s, y0 + 18 * s), "全队每秒伤害", int(14 * s), TXT, "lm")
    ptxt(img, (x0 + 120 * s, y0 + 18 * s), "DPS / 10S", 1, CY_DIM, 2, "lm")
    gx0, gy0, gx1, gy1 = x0 + 44 * s, y0 + 40 * s, x1 - 16 * s, y1 - 26 * s
    d = ImageDraw.Draw(img)
    for m in range(0, T_END // 60 + 1, 2):
        xx = gx0 + (gx1 - gx0) * m * 60 / T_END
        ptxt(img, (xx, gy1 + 12 * s), "%d:00" % m, 1, TXT2, 1, "mm")
    # 堆叠柱（每 10 秒一根，像素块）：干员按入队时间叠
    n = T_END // 10
    bw = max(P, snap((gx1 - gx0) / n, 1))
    rs = np.random.RandomState(3)
    cols = []
    for i in range(n):
        t = i * 10
        ramp = 0.35 + 0.65 * min(1.0, t / 500.0)
        col_ = []
        for o in ALL:
            if t < o["join"]:
                continue
            v = total(o) / max(1, T_END - o["join"]) * ramp * (0.75 + 0.5 * rs.rand())
            if any(b0 <= t <= b1 for _, b0, b1 in BOSSES):
                v *= 1.25
            col_.append((v, rgb(o["col"])))
        cols.append(col_)
    vmax = max(sum(v for v, _ in c) for c in cols)
    top = float(np.ceil(vmax / 1000.0) * 1000.0)
    for i in range(int(n * frac)):
        y = gy1
        for v, cc in cols[i]:
            hgt = snap((gy1 - gy0) * v / top, P)
            xx = gx0 + (gx1 - gx0) * i / n
            d.rectangle([xx, y - hgt, xx + bw - 2, y - 1], fill=cc)
            y -= hgt
    for k in range(3):
        yy = gy1 - (gy1 - gy0) * k / 2
        d.line([(gx0, yy), (gx1, yy)], fill=(24, 52, 80), width=1)
        ptxt(img, (gx0 - 6 * s, yy), "%gK" % (top * k / 2000.0) if k else "0", 1, TXT2, 1, "rm")
    for name, b0, b1 in BOSSES:
        for t, solid_ in ((b0, False), (b1, True)):
            xx = gx0 + (gx1 - gx0) * t / T_END
            for yy in range(int(gy0), int(gy1), 6):
                d.line([(xx, yy), (xx, yy + 2)], fill=RED if solid_ else (150, 60, 100), width=1)
        xx = gx0 + (gx1 - gx0) * b1 / T_END
        d.polygon([(xx, gy0 - 8 * s), (xx + 5 * s, gy0 - 3 * s), (xx, gy0 + 2 * s), (xx - 5 * s, gy0 - 3 * s)], fill=RED)
        text(img, (xx - 8 * s, gy0 - 3 * s), name, int(11 * s), (240, 170, 200), "rm")


def summary(img, box, s, P):
    x0, y0, x1, y1 = block(img, box, P, 2)
    text(img, (x0 + 14 * s, y0 + 18 * s), "探索记录", int(14 * s), TXT, "lm")
    ptxt(img, (x0 + 86 * s, y0 + 18 * s), "LOG", 1, CY_DIM, 2, "lm")
    yy = y0 + 46 * s
    for name, b0, b1 in BOSSES:
        d = ImageDraw.Draw(img)
        d.polygon([(x0 + 18 * s, yy - 4 * s), (x0 + 22 * s, yy), (x0 + 18 * s, yy + 4 * s), (x0 + 14 * s, yy)], fill=RED)
        text(img, (x0 + 30 * s, yy), name, int(13 * s), TXT, "lm")
        ptxt(img, (x1 - 16 * s, yy), "%s  +%s" % (mmss(b1), mmss(b1 - b0)), 1, TXT2, 1, "rm")
        yy += 22 * s
    yy += 4 * s
    for k, v in (("引航灯标", "点燃 4 / 5"), ("源石锭熔铸", "全队伤害 +6%"), ("精英击杀", "23")):
        text(img, (x0 + 14 * s, yy), k, int(13 * s), TXT2, "lm")
        text(img, (x1 - 16 * s, yy), v, int(13 * s), TXT, "rm")
        yy += 21 * s


def buttons(img, W, H, s, P, phone=False):
    y = H - 46 * s
    bw = 168 * s
    x1 = W - 32 * s
    block(img, (x1 - bw, y, x1, y + 34 * s), P, 2, sel=False)
    text(img, (x1 - bw + 14 * s, y + 17 * s), "返回结算", int(15 * s), TXT, "lm")
    if not phone:
        ptxt(img, (x1 - 14 * s, y + 17 * s), "ESC", 1, CY, 1, "rm")
    if not phone:
        hints(img, 32 * s, y + 17 * s, [("← →", "选择干员"), ("ENTER", "详情"), ("ESC", "返回结算")])


def hints(img, x, y, pairs):
    """操作提示：像素字键名 + 中文说明"""
    for k, v in pairs:
        x += ptxt(img, (x, y), k, 1, CY, 1, "lm") + 6
        x += text(img, (x, y), v, 12, TXT2, "lm") + 18


# ---------------------------------------------------------------- 画面
def overview(W=1280, H=720, s=1.0, sel=0, frac_bar=1.0, frac_fill=1.0, frac_tl=1.0, phone=False):
    img = base(W, H, s)
    P = max(1, round(2 * s)) if not phone else 2
    block(img, (14 * s, 14 * s, W - 14 * s, H - 14 * s), P, 3, alpha=150, acc=False)
    header(img, W, s, P, "作战记录", "RUN RECORD", "" if phone else "01 / 02")
    m = 32 * s
    kh = 58 * s
    items = [("探索时间", mmss(T_END), None), ("难度", "IV", "波涛迭起"), ("击杀", num(3057), None), ("等级", "LV 41", "精英二"),
             ("藏品", "19", None), ("最高单次", num(18412), "迅捷打击·γ型")]
    if phone:
        items = items[:4] + [items[5]]
    kpis(img, m, 92 * s, W - 2 * m, kh, s, P, items, phone)
    squad_bar(img, m, (92 + 58 + 14) * s, W - 2 * m, s, P, frac_bar)
    cy0 = (92 + 58 + 14 + 54) * s
    ch = (250 if not phone else 158) * s
    n = len(ALL)
    g = 10 * s
    widths = [1.0] * len(OPS) + [0.82]
    tw = sum(widths)
    cx = m
    for i, o in enumerate(ALL):
        cw = (W - 2 * m - g * (n - 1)) * widths[i] / tw
        op_card(img, (cx, cy0, cx + cw, cy0 + ch), o, PCT[i], s, P, sel == i, frac_fill, phone)
        cx += cw + g
    if not phone:
        by0 = cy0 + ch + 12 * s
        timeline(img, (m, by0, m + (W - 2 * m) * 0.64, H - 58 * s), s, P, frac_tl)
        summary(img, (m + (W - 2 * m) * 0.64 + 10 * s, by0, W - m, H - 58 * s), s, P)
    buttons(img, W, H, s, P, phone)
    return img


def detail(o_idx=0, W=1280, H=720, s=1.0):
    img = base(W, H, s)
    P = 2
    o = ALL[o_idx]
    block(img, (14, 14, W - 14, H - 14), P, 3, alpha=150, acc=False)
    header(img, W, s, P, "作战记录 · " + o["name"], "RUN RECORD // " + o["en"], "< %02d / %02d >" % (o_idx + 1, len(ALL)))
    m = 32
    # 左：干员身份卡（近白选中：从总览带过来的焦点）
    lx0, ly0, lx1, ly1 = block(img, (m, 92, m + 300, H - 58), P, 3, sel=True)
    sprite(img, o.get("tex", ""), (lx0 + lx1) / 2, ly0 + 168, 3)
    d = ImageDraw.Draw(img)
    d.rectangle([lx0 + 14, ly0 + 184, lx1 - 14, ly0 + 186], fill=rgb(o["col"]))
    text(img, (lx0 + 20, ly0 + 210), o["name"], 24, SEL_INK, "lm", bold=True)
    ptxt(img, (lx0 + 22, ly0 + 234), o["en"], 1, SEL_SUB, 2, "lm")
    jt = "主控 · 开局" if o.get("leader") else mmss(o["join"]) + " 加入编队"
    text(img, (lx1 - 18, ly0 + 210), jt, 13, SEL_SUB, "rm")
    rows = [("造成伤害", num(total(o))), ("全队占比", "%d%%" % PCT[o_idx]), ("在队每秒", num(total(o) / max(1, T_END - o["join"]))),
            ("在队时长", mmss(T_END - o["join"])), ("击杀", num(o["kills"])), ("技能发动", "%d 次" % o["casts"])]
    if o["heal"]:
        rows.append(("治疗主控", num(o["heal"])))
    yy = ly0 + 266
    for k, v in rows:
        text(img, (lx0 + 20, yy), k, 14, SEL_SUB, "lm")
        ptxt(img, (lx1 - 18, yy), v.replace(" 次", ""), 2, SEL_INK, 1, "rm")
        yy += 30
    # 中：伤害来源
    mx0 = m + 312
    mx1 = (W - m) if not o.get("leader") else 862
    x0, y0, x1, y1 = block(img, (mx0, 92, mx1, H - 58), P, 2)
    text(img, (x0 + 16, y0 + 22), "伤害来源", 16, TXT, "lm", bold=True)
    ptxt(img, (x0 + 96, y0 + 22), "DAMAGE BY SOURCE", 1, CY_DIM, 2, "lm")
    srcs = sorted(o["src"], key=lambda r: -r[2])
    vmax = srcs[0][2]
    yy = y0 + 62
    for name, ori, v in srcs:
        tw_ = tag(img, (x0 + 16, yy), ori, ORIGIN_COL.get(ori, CY), 11, P)
        text(img, (x0 + 26 + tw_, yy), name, 15, TXT, "lm")
        ptxt(img, (x1 - 18, yy), "%d%%" % round(v * 100 / total(o)), 2, CY, 1, "rm")
        ptxt(img, (x1 - 80, yy), num(v), 1, TXT2, 1, "rm")
        pbar(img, x0 + 16, yy + 14, x1 - x0 - 32, 8, P, [(1.0, rgb(o["col"]))], v / vmax)
        yy += 50
    if o.get("leader"):
        # 右：主控专属（受击体）
        rx0, ry0, rx1, ry1 = block(img, (874, 92, W - m, H - 58), P, 2)
        text(img, (rx0 + 16, ry0 + 22), "生存", 16, TXT, "lm", bold=True)
        ptxt(img, (rx0 + 56, ry0 + 22), "SURVIVAL", 1, CY_DIM, 2, "lm")
        yy = ry0 + 52
        text(img, (rx0 + 16, yy), "受到伤害", 13, TXT2, "lm")
        ptxt(img, (rx1 - 16, yy), num(sum(v for _, v in TAKEN_SRC)) + " / 412 HITS", 1, TXT, 1, "rm")
        yy += 20
        tmax = TAKEN_SRC[0][1]
        for n_, v in TAKEN_SRC:
            text(img, (rx0 + 16, yy + 4), n_, 12, TXT2, "lm")
            pbar(img, rx0 + 120, yy, rx1 - rx0 - 190, 8, P, [(1.0, RED)], v / tmax)
            ptxt(img, (rx1 - 16, yy + 4), num(v), 1, TXT2, 1, "rm")
            yy += 18
        yy += 12
        text(img, (rx0 + 16, yy), "生命回复", 13, TXT2, "lm")
        ptxt(img, (rx1 - 16, yy), num(sum(v for _, v in HEAL_SRC)), 1, TXT, 1, "rm")
        yy += 20
        hmax = HEAL_SRC[0][1]
        for n_, v in HEAL_SRC:
            text(img, (rx0 + 16, yy + 4), n_, 12, TXT2, "lm")
            pbar(img, rx0 + 120, yy, rx1 - rx0 - 190, 8, P, [(1.0, (47, 211, 160))], v / hmax)
            ptxt(img, (rx1 - 16, yy + 4), num(v), 1, TXT2, 1, "rm")
            yy += 18
        yy += 14
        text(img, (rx0 + 16, yy), "灯火", 13, TXT2, "lm")
        yy += 18
        segs = [(v / T_END, LAMP[i]) for i, v in enumerate(LAMP_S)]
        pbar(img, rx0 + 16, yy, rx1 - rx0 - 32, 12, P, segs)
        yy += 26
        for i, (nm, v) in enumerate(zip(["通明", "摇曳", "暗淡", "寂灭"], LAMP_S)):
            xx = rx0 + 16 + i * (rx1 - rx0 - 32) / 4
            d.rectangle([xx, yy - 4, xx + 7, yy + 3], fill=LAMP[i])
            text(img, (xx + 12, yy), nm, 12, TXT2, "lm")
            ptxt(img, (xx + 12, yy + 16), mmss(v), 1, TXT, 1, "lm")
        yy += 40
        for k, v in (("闪避", "38"), ("冲刺", "214"), ("护盾抵挡", "12"), ("生命低于 35%", "01:12")):
            text(img, (rx0 + 16, yy), k, 13, TXT2, "lm")
            ptxt(img, (rx1 - 16, yy), v, 1, TXT, 1, "rm")
            yy += 19
    img2 = img
    y = H - 46
    bw = 168
    x1 = W - 32
    block(img2, (x1 - bw, y, x1, y + 34), P, 2)
    text(img2, (x1 - bw + 14, y + 17), "返回总览", 15, TXT, "lm")
    ptxt(img2, (x1 - 14, y + 17), "ESC", 1, CY, 1, "rm")
    hints(img2, 32, y + 17, [("← →", "换干员"), ("↑ ↓", "滚动来源"), ("ESC", "返回总览")])
    return img


def motion_board():
    """招牌动效分镜：伤害分段拼合（四帧，0 / 0.18 / 0.42 / 0.9 秒）"""
    frames = [(0.0, 0.0, 0.0), (0.35, 0.15, 0.0), (0.75, 0.6, 0.2), (1.0, 1.0, 1.0)]
    labels = ["0.00 s  面板 T1 淡入", "0.18 s  分段依次落位", "0.42 s  卡片条随之注满", "0.90 s  时间线扫出 · 终态"]
    tiles = []
    for (fb, ff, ft), lb in zip(frames, labels):
        im = overview(frac_bar=fb, frac_fill=ff, frac_tl=ft)
        im = im.resize((640, 360), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, 330, 640, 360], fill=(0, 0, 0, 200))
        text(im, (12, 345), lb, 15, TXT, "lm")
        tiles.append(im)
    sheet = Image.new("RGBA", (1290, 730), (4, 10, 20, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, ((i % 2) * 650, (i // 2) * 370))
    return sheet


def main():
    os.makedirs(OUT, exist_ok=True)
    overview().convert("RGB").save(os.path.join(OUT, "concept_overview.png"))
    detail(0).convert("RGB").save(os.path.join(OUT, "concept_detail_leader.png"))
    detail(1).convert("RGB").save(os.path.join(OUT, "concept_detail_ally.png"))
    overview(1560, 720, 1.494, phone=True).convert("RGB").save(os.path.join(OUT, "concept_overview_phone.png"))
    motion_board().convert("RGB").save(os.path.join(OUT, "concept_motion.png"))
    print("写到", OUT)


if __name__ == "__main__":
    main()
