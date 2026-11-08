# 蚀刻章重设计示意图（docs/328）：程序画像素章面 + 陈列页 + 获得提示，电脑 / 手机各一份，A / B 两套。
# 只出示意图，不进游戏。用法：python tools/mock/medal_redesign_1108.py [输出目录，缺省 docs/img/medal_1108]
import math, os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "img", "medal_1108")
os.makedirs(OUT, exist_ok=True)
FONT_UI = os.path.join(ROOT, "game", "fonts", "ui.ttf")
FONT_SERIF = os.path.join(ROOT, "game", "fonts", "serif.ttf")
SHOT = os.path.join(ROOT, "..", "..", "..", "build", "eyes", "ingame", "texas", "shot.png")
if not os.path.exists(SHOT):
    SHOT = r"E:\ArknightsSurvivors\build\eyes\ingame\texas\shot.png"


def F(sz, serif=False):
    return ImageFont.truetype(FONT_SERIF if serif else FONT_UI, sz)


def hx(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


CYAN = hx("36e2dc"); TEXT = hx("e6edf5"); SUB = hx("8796ab"); DIM = hx("4a5a72")
SILVER = [hx(c) for c in ("1a2232", "3a4658", "6b7a90", "a9b6c8", "dfe7f0", "ffffff")]
COPPER = [hx(c) for c in ("2a1814", "5a3226", "8a5038", "c98a62", "f0c49a", "fff0dc")]
TIDEPL = [hx(c) for c in ("102030", "2a5068", "4f8fa8", "8fd6e0", "d8fbff", "ffffff")]   # 镀层：潮光
FACE = [hx(c) for c in ("07142c", "0b1d3a", "123160", "1d4a8a", "2f6bb8")]
PALE = [hx(c) for c in ("7f9cc4", "a8c2e2", "cfe0f2", "eef5fc")]
NAVY = [hx(c) for c in ("0a1a3a", "163a7a", "2a5cae", "4b86d0")]

# ------------------------------------------------------------------ 章面
TIER_SIZE_A = {3: (35, 40), 2: (25, 28), 1: (17, 19)}   # 原作三档按尺寸区分（约 2.2 : 1.6 : 1）
SIZE_B = (27, 31)                                       # B 版统一尺寸，稀有度看框


N8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))


def hex_mask(w, h):
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    q = h / 4.0
    d.polygon([(w / 2 - 0.5, 0), (w - 1, q), (w - 1, h - 1 - q), (w / 2 - 0.5, h - 1), (0, h - 1 - q), (0, q)], fill=255)
    return m


def erode(m, n):
    """按八邻域收缩 n 格（图边外当作空，否则贴边的竖边不收）"""
    w, h = m.size
    p = Image.new("L", (w + 2, h + 2), 0)
    p.paste(m, (1, 1))
    for _ in range(n):
        a = p.load()
        q = p.copy(); b = q.load()
        for y in range(1, h + 1):
            for x in range(1, w + 1):
                if a[x, y] > 127 and min(a[x - 1, y], a[x + 1, y], a[x, y - 1], a[x, y + 1], a[x - 1, y - 1], a[x + 1, y - 1], a[x - 1, y + 1], a[x + 1, y + 1]) < 128:
                    b[x, y] = 0
        p = q
    return p.crop((1, 1, w + 1, h + 1))


def px(m):
    return m.load()


def em_canvas(w, h):
    m = Image.new("L", (w, h), 0)
    return m, ImageDraw.Draw(m)


# 纹样（对称、徽记式，参照原作「抽象纹章」的路子，不照搬原作图案）
def em_set(w, h):           # 深蓝之下：水母伞 + 下垂触须化作树根，四角星点
    m, d = em_canvas(w, h)
    cx = w // 2
    bw = int(w * 0.62); bh = int(h * 0.30); top = int(h * 0.20)
    d.pieslice([cx - bw // 2, top, cx + bw // 2, top + bh * 2], 180, 360, fill=255)
    d.line([cx - bw // 2, top + bh, cx + bw // 2, top + bh], fill=255)
    for i, dx in enumerate((-bw // 4, 0, bw // 4)):
        y0 = top + bh + 1
        x = cx + dx
        for y in range(y0, int(h * 0.82)):
            off = int(round(math.sin((y - y0) * 0.55 + i) * 1.0))
            d.point((x + off, y), fill=255)
        yb = int(h * 0.70)
        d.line([x, yb, x - 2 - (1 if dx < 0 else 0), yb + 4], fill=255)
        d.line([x, yb, x + 2 + (1 if dx > 0 else 0), yb + 4], fill=255)
    d.rectangle([cx - bw // 2 + 2, top + bh - 3, cx + bw // 2 - 2, top + bh - 3], fill=0)
    for sx, sy in ((0.16, 0.24), (0.84, 0.24), (0.16, 0.74), (0.84, 0.74)):
        x, y = int(w * sx), int(h * sy)
        d.point([(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)], fill=255)
    return m


def em_tree(w, h):          # 深蓝之树：主干 + 三层对称枝 + 顶上星
    m, d = em_canvas(w, h)
    cx = w // 2
    y0, y1 = int(h * 0.30), int(h * 0.80)
    d.line([cx, y0, cx, y1], fill=255)
    d.line([cx - 1, y1 - 3, cx - 1, y1], fill=255); d.line([cx + 1, y1 - 3, cx + 1, y1], fill=255)
    for k, yy in enumerate((0.40, 0.52, 0.64)):
        y = int(h * yy); L = int(w * (0.16 + 0.07 * k))
        d.line([cx, y + 2, cx - L, y - 2], fill=255); d.line([cx, y + 2, cx + L, y - 2], fill=255)
        d.point([(cx - L, y - 3), (cx + L, y - 3)], fill=255)
    y = int(h * 0.20)
    d.point([(cx, y - 2), (cx, y - 1), (cx, y), (cx, y + 1), (cx, y + 2), (cx - 1, y), (cx + 1, y), (cx - 2, y), (cx + 2, y)], fill=255)
    return m


def em_lance(w, h):         # 骑士归潮：竖立的长枪 + 护手 + 底部双弧浪
    m, d = em_canvas(w, h)
    cx = w // 2
    d.polygon([(cx, int(h * 0.14)), (cx - 2, int(h * 0.28)), (cx + 2, int(h * 0.28))], fill=255)
    d.line([cx, int(h * 0.28), cx, int(h * 0.72)], fill=255)
    d.line([cx - int(w * 0.18), int(h * 0.36), cx + int(w * 0.18), int(h * 0.36)], fill=255)
    for r, yy in ((int(w * 0.22), 0.78), (int(w * 0.33), 0.86)):
        y = int(h * yy)
        d.arc([cx - r, y - r // 2, cx + r, y + r // 2], 200, 340, fill=255)
    return m


def em_bubbles(w, h):       # 泡影散尽：三只泡 + 两粒碎点
    m, d = em_canvas(w, h)
    for sx, sy, r in ((0.42, 0.56, 0.20), (0.66, 0.36, 0.12), (0.30, 0.30, 0.08)):
        x, y, rr = w * sx, h * sy, w * r
        d.ellipse([x - rr, y - rr, x + rr, y + rr], outline=255)
    d.point([(int(w * 0.70), int(h * 0.66)), (int(w * 0.62), int(h * 0.76))], fill=255)
    return m


def em_drop(w, h):
    m, d = em_canvas(w, h)
    cx, cy, r = w / 2, h * 0.58, w * 0.20
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    d.polygon([(cx, h * 0.22), (cx - r * 0.85, cy - r * 0.5), (cx + r * 0.85, cy - r * 0.5)], fill=255)
    return m


def em_rings(w, h):
    m, d = em_canvas(w, h)
    cx, cy = w / 2, h / 2
    for r in (0.30, 0.18):
        d.ellipse([cx - w * r, cy - w * r, cx + w * r, cy + w * r], outline=255)
    d.point((int(cx), int(cy)), fill=255)
    return m


def em_chev(w, h):
    m, d = em_canvas(w, h)
    cx = w / 2
    for yy in (0.34, 0.50, 0.66):
        y = h * yy
        d.line([cx - w * 0.24, y + 3, cx, y - 1, cx + w * 0.24, y + 3], fill=255)
    return m


def em_shell(w, h):
    m, d = em_canvas(w, h)
    cx = w / 2
    d.pieslice([cx - w * 0.28, h * 0.30, cx + w * 0.28, h * 0.86], 180, 360, fill=255)
    for k in (-2, 0, 2):
        d.line([cx, h * 0.62, cx + k * w * 0.1, h * 0.36], fill=0)
    d.rectangle([cx - 2, h * 0.58, cx + 2, h * 0.68], fill=255)
    return m


def em_wave(w, h):
    m, d = em_canvas(w, h)
    for yy in (0.40, 0.58):
        pts = [(x, h * yy + math.sin(x / w * 2 * math.pi * 1.5) * 2) for x in range(int(w * 0.18), int(w * 0.83))]
        d.line(pts, fill=255)
    return m


def em_anchor(w, h):
    m, d = em_canvas(w, h)
    cx = w / 2
    d.ellipse([cx - 2, h * 0.20, cx + 2, h * 0.20 + 4], outline=255)
    d.line([cx, h * 0.30, cx, h * 0.76], fill=255)
    d.line([cx - w * 0.16, h * 0.38, cx + w * 0.16, h * 0.38], fill=255)
    d.arc([cx - w * 0.26, h * 0.50, cx + w * 0.26, h * 0.80], 20, 160, fill=255)
    return m


def em_trio(w, h):
    m, d = em_canvas(w, h)
    for sx, sy in ((0.5, 0.34), (0.34, 0.62), (0.66, 0.62)):
        x, y, r = w * sx, h * sy, w * 0.10
        d.regular_polygon((x, y, r + 1), 6, rotation=30, fill=255)
    return m


EMBLEMS = {"set": em_set, "tree": em_tree, "lance": em_lance, "bubbles": em_bubbles, "drop": em_drop, "rings": em_rings,
           "chev": em_chev, "shell": em_shell, "wave": em_wave, "anchor": em_anchor, "trio": em_trio}


def bevel(mask, x, y, w, h):
    """浮雕：左上缘受光，右下缘背光"""
    p = mask
    def on(a, b):
        return 0 <= a < w and 0 <= b < h and p[a, b] > 127
    if not on(x - 1, y - 1) or not on(x, y - 1) and not on(x - 1, y):
        return 2
    if not on(x + 1, y + 1) or not on(x, y + 1) and not on(x + 1, y):
        return 0
    return 1


def render_medal(emblem, tier, style="A", state="got", plated=False):
    w, h = (TIER_SIZE_A[tier] if style == "A" else SIZE_B)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    o = out.load()
    outer = hex_mask(w, h)
    ft = {3: 3, 2: 2, 1: 2}[tier]
    if style == "B":
        ft = {3: 4, 2: 3, 1: 2}[tier]
    inner = erode(outer, ft)
    face = erode(inner, 1)
    po, pi, pf = px(outer), px(inner), px(face)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    metal = COPPER if tier == 3 else SILVER
    if plated:
        metal = TIDEPL
    em_fn = EMBLEMS[emblem]
    ew, eh = w - 2 * ft - 2, h - 2 * ft - 2
    em = Image.new("L", (w, h), 0)
    em.paste(em_fn(ew, eh), (ft + 1, ft + 1))
    em = ImageChops.multiply(em, face)
    pe = px(em)
    if state == "locked":
        for y in range(h):
            for x in range(w):
                if po[x, y] < 128:
                    continue
                if pi[x, y] < 128:
                    o[x, y] = (*hx("2a3a55"), 255) if (pf[x, y] < 128) else (*hx("0d1628"), 255)
                    # 外描边 1 格，其余框内暗
                    edge = any(not (0 <= x + a < w and 0 <= y + b < h and po[x + a, y + b] > 127) for a, b in N8)
                    o[x, y] = (*hx("34476a"), 255) if edge else (*hx("111c30"), 255)
                elif style == "A" and pe[x, y] > 127:
                    o[x, y] = (*hx("1c2a44"), 255)          # A：剪影（看得出纹样轮廓，看不出细节）
                else:
                    o[x, y] = (*hx("0b1424"), 255)
        if style == "B":   # B：问号
            q = ["0110", "1001", "0001", "0010", "0100", "0000", "0100"]
            sx, sy = int(cx) - 1, int(cy) - 3
            for j, row in enumerate(q):
                for i, ch in enumerate(row):
                    if ch == "1":
                        o[sx + i, sy + j] = (*hx("3c4e6a"), 255)
        return out
    for y in range(h):
        for x in range(w):
            if po[x, y] < 128:
                continue
            if pi[x, y] < 128:      # 框
                edge = any(not (0 <= x + a < w and 0 <= y + b < h and po[x + a, y + b] > 127) for a, b in N8)
                # 按所在的边定明暗（光从左上来）：六条边各一档，不逐格算法线，斜边不出棋盘格
                ang = math.degrees(math.atan2((y - cy) / h * w, x - cx)) % 360
                side = int(((ang + 30) % 360) // 60)   # 0 右 1 右下 2 左下 3 左 4 左上 5 右上
                k = {0: 2, 1: 1, 2: 2, 3: 3, 4: 4, 5: 4}[side]
                inner_edge = any(0 <= x + a < w and 0 <= y + b < h and pi[x + a, y + b] > 127 for a, b in N8)
                if edge:
                    k = 0 if side in (0, 1, 2) else 1
                elif inner_edge and side in (3, 4, 5):
                    k = 5 if side in (4, 5) else 4
                o[x, y] = (*metal[k], 255)
            elif pf[x, y] < 128:    # 槽
                o[x, y] = (*hx("060b16"), 255)
            else:                   # 面
                t = y / h
                if style == "A" and tier < 3:
                    k = 2 if t < 0.35 else 1 if t < 0.75 else 0
                    s = (x + y) % 11
                    if 2 <= (x + y - int(w * 0.4)) <= 4 and (x + y) % 2 == 0:
                        k = min(4, k + 1)       # 斜向流光（抖动两档）
                    col = FACE[k + 1] if (x * 7 + y * 3) % 5 == 0 and k < 3 else FACE[k]
                elif style == "A":          # 三星：浅色面 + 深蓝浮雕（原作三星是亮面）
                    k = 3 if t < 0.3 else 2 if t < 0.7 else 1
                    col = PALE[k]
                else:                       # B：银 / 铜板，纹样刻进去
                    k = 4 if t < 0.25 else 3 if t < 0.8 else 2
                    if 2 <= (x + y - int(w * 0.45)) <= 3:
                        k = 5
                    col = (metal if tier == 3 else SILVER)[k]
                    if plated:
                        col = TIDEPL[k]
                o[x, y] = (*col, 255)
                if pe[x, y] > 127:
                    b = bevel(pe, x, y, w, h)
                    if style == "A" and tier < 3:
                        o[x, y] = (*SILVER[[2, 3, 5][b]], 255)
                    elif style == "A":
                        o[x, y] = (*NAVY[[0, 2, 3][b]], 255)
                    else:   # 蚀刻：刻槽深色，右下缘受光（凹进去）
                        o[x, y] = (*NAVY[[1, 0, 0][b]], 255)
                        if tier == 3:
                            o[x, y] = (*hx("1d4a8a"), 255) if b != 0 else (*NAVY[0], 255)
                elif style == "B":
                    # 刻槽外沿：左上邻是刻槽 → 这一格是背光坡
                    if 0 < x and 0 < y and pe[x - 1, y - 1] > 127:
                        o[x, y] = (*(metal if tier == 3 else SILVER)[1], 255) if not plated else (*TIDEPL[1], 255)
    # A 二星：浮雕外环
    if style == "A" and tier == 2 and state != "locked":
        r = (w - 2 * ft - 2) / 2 - 1.5
        for a in range(0, 360, 3):
            x = int(round(cx + math.cos(math.radians(a)) * r)); y = int(round(cy + 1 + math.sin(math.radians(a)) * r))
            if 0 <= x < w and 0 <= y < h and pf[x, y] > 127 and pe[x, y] < 128:
                k = 4 if math.sin(math.radians(a)) < -0.3 else 3 if math.cos(math.radians(a)) < 0.3 else 2
                o[x, y] = (*SILVER[k], 255)
    # A 三星：环形刻痕（四周短刻度）
    if style == "A" and tier == 3:
        r = (w - 2 * ft - 2) / 2 - 1
        for a in range(0, 360, 15):
            x = int(round(cx + math.cos(math.radians(a)) * r)); y = int(round(cy + math.sin(math.radians(a)) * r * 1.1))
            if 0 <= x < w and 0 <= y < h and pf[x, y] > 127 and pe[x, y] < 128:
                o[x, y] = (*NAVY[1], 255)
    # B 双框暗缝（二、三星）
    if style == "B" and tier >= 2:
        ring = ImageChops.subtract(erode(outer, ft // 2), erode(outer, ft // 2 + 1))
        pr = px(ring)
        for y in range(h):
            for x in range(w):
                if pr[x, y] > 127:
                    o[x, y] = (*hx("0a1020"), 255)
    # B 三星：六角铆钉
    if style == "B" and tier == 3:
        q = h / 4.0
        for vx, vy in ((w / 2, 1.5), (w - 2.5, q + 0.5), (w - 2.5, h - 1.5 - q), (w / 2, h - 2.5), (1.5, h - 1.5 - q), (1.5, q + 0.5)):
            o[int(vx), int(vy)] = (*COPPER[5], 255)
    # 镀层：框上闪点
    if plated:
        for (sx, sy) in ((0.5, 0.02), (0.92, 0.3), (0.1, 0.72)):
            x, y = int(w * sx), int(h * sy)
            if 0 <= x < w and 0 <= y < h and po[x, y] > 127:
                o[x, y] = (255, 255, 255, 255)
    return out


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def sheen(im, phase=0.45, width=4, k=1):
    """获得演出的扫光帧：斜向白带叠在不透明像素上"""
    im = im.copy()
    p = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = p[x, y]
            if a == 0:
                continue
            d = (x + y * 0.6) / k - phase * (w + h * 0.6) / k
            if 0 <= d < width:
                p[x, y] = (min(255, r + 90), min(255, g + 90), min(255, b + 90), a)
    return im


# ------------------------------------------------------------------ 章表（12 枚；前 9 枚沿用现有存档键）
MEDALS = [
    # key, 名称, 星, 纹样, 已获得, 镀层
    ("set_complete", "深蓝之下", 3, "set", False, None),
    ("ending_standard", "泡影散尽", 1, "bubbles", True, False),
    ("ending_knight", "骑士归潮", 2, "lance", True, True),
    ("ending_deep", "潮声止息", 2, "wave", False, None),
    ("ending_resolve", "深蓝之树", 2, "tree", True, False),
    ("elite_three", "协同晋升", 2, "chev", False, None),
    ("relic_fifty", "海中拾遗", 1, "shell", True, None),
    ("cognition_complete", "认知深化", 2, "rings", False, None),
    ("cognition_first", "初识深蓝", 1, "drop", True, None),
    ("roster_twelve", "编队扩充", 1, "trio", False, None),
    ("events_thirty", "见闻留档", 1, "anchor", False, None),
    ("clears_ten", "归航", 2, "anchor", False, None),
]
MEDALS[10] = ("events_thirty", "见闻留档", 1, "wave", False, None)
STARS = {3: "★★★", 2: "★★", 1: "★"}


# ------------------------------------------------------------------ 背景
def sea_bg(W, H, grid=3, seed=1):
    gw, gh = W // grid + 1, H // grid + 1
    im = Image.new("RGB", (gw, gh))
    p = im.load()
    bay = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(gh):
        for x in range(gw):
            t = y / gh
            base = [5 + 6 * t, 10 + 14 * t, 22 + 30 * t]
            ray = 0.0
            for k, (x0, wd) in enumerate(((0.78, 0.07), (0.88, 0.04), (0.66, 0.05))):
                c = x0 * gw - (y * 0.55)
                dd = abs(x - c) / (wd * gw)
                if dd < 1:
                    ray += (1 - dd) * (1 - t) * (0.9 - 0.2 * k)
            v = ray * 18 + bay[y % 4][x % 4] / 16 * 6 - 3
            q = int(v / 6) * 6
            p[x, y] = (int(base[0] + q * 0.4), int(base[1] + q * 0.8), int(base[2] + q * 1.3))
    import random
    rnd = random.Random(seed)
    for _ in range(gw * gh // 260):
        x, y = rnd.randrange(gw), rnd.randrange(gh)
        p[x, y] = (60, 110, 150) if rnd.random() < 0.7 else (120, 180, 210)
    return im.resize((gw * grid, gh * grid), Image.NEAREST).crop((0, 0, W, H))


def text(d, xy, s, sz, col=TEXT, serif=False, anchor="la", spacing=0):
    f = F(sz, serif)
    if spacing:
        x, y = xy
        if anchor[0] == "m":
            tw = sum(d.textlength(ch, font=f) + spacing for ch in s) - spacing
            x -= tw / 2
            anchor = "l" + anchor[1]
        elif anchor[0] == "r":
            tw = sum(d.textlength(ch, font=f) + spacing for ch in s) - spacing
            x -= tw
            anchor = "l" + anchor[1]
        for ch in s:
            d.text((x, y), ch, font=f, fill=col, anchor=anchor)
            x += d.textlength(ch, font=f) + spacing
        return
    d.text(xy, s, font=f, fill=col, anchor=anchor)


def wrap(d, s, sz, maxw):
    f = F(sz); lines = []; cur = ""
    for ch in s:
        if d.textlength(cur + ch, font=f) > maxw:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur:
        lines.append(cur)
    return lines


def back_btn(d, x, y, s=1.0):
    w, h = int(118 * s), int(40 * s)
    d.rectangle([x - w, y, x, y + h], outline=hx("5a6c86"), width=max(1, int(s)))
    text(d, (x - w + 16 * s, y + h / 2), "返回", int(18 * s), TEXT, anchor="lm")
    kx = x - 14 * s
    d.rectangle([kx - 38 * s, y + 10 * s, kx, y + h - 10 * s], outline=hx("8796ab"), width=1)
    text(d, (kx - 19 * s, y + h / 2), "ESC", int(11 * s), SUB, anchor="mm")


def paste(canvas, im, cx, cy):
    canvas.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))


def sel_box(d, cx, cy, w, h, pad=6, col=CYAN, L=10):
    x0, y0, x1, y1 = cx - w / 2 - pad, cy - h / 2 - pad, cx + w / 2 + pad, cy + h / 2 + pad
    for (ax, ay, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line([ax, ay, ax + L * sx, ay], fill=col, width=2)
        d.line([ax, ay, ax, ay + L * sy], fill=col, width=2)


DETAIL = {
    "ending_knight": dict(rec="为在「静谧时代」结局后返航的小队颁发的蚀刻章。", how="达成结局「静谧时代」。",
                          plate="在潮位 4 及以上达成结局「静谧时代」。", date="2026-11-03 获得 · 11-06 镀层", prog=None),
    "relic_fifty": dict(rec="为在海中拾回大量藏品的小队颁发的蚀刻章。", how="累计获得 50 种不同的藏品。", plate=None,
                        date="2026-11-01 获得", prog=(50, 50)),
    "elite_three": dict(rec="为一次探索中让三名干员同时完成精英二的小队颁发的蚀刻章。", how="在一次探索中，使编队内 3 名干员同时达到精英二。",
                        plate=None, date=None, prog=(2, 3)),
}


def detail_panel(cv, d, x, y, w, key, k_big, s=1.0, style="A"):
    m = next(mm for mm in MEDALS if mm[0] == key)
    _, name, tier, em, got, plated = m
    D = DETAIL[key]
    img = render_medal(em, tier, style, "got" if got else "locked", plated=bool(plated))
    big = up(img, k_big)
    paste(cv, big, x + w / 2, y + big.height / 2)
    yy = y + big.height + 18 * s
    text(d, (x + w / 2, yy), name, int(30 * s), TEXT, serif=True, anchor="mt")
    yy += 42 * s
    text(d, (x + w / 2, yy), STARS[tier], int(18 * s), COPPER[4] if tier == 3 else SILVER[4], anchor="mt")
    if plated:
        text(d, (x + w / 2 + 44 * s, yy + 2 * s), "已镀层", int(13 * s), TIDEPL[3], anchor="lt")
    yy += 34 * s
    d.line([x, yy, x + w, yy], fill=hx("26344a"), width=1)
    yy += 14 * s
    for ln in wrap(d, D["rec"], int(16 * s), w):
        text(d, (x, yy), ln, int(16 * s), hx("b9c4d4")); yy += 24 * s
    yy += 10 * s
    text(d, (x, yy), "获得方式", int(13 * s), SUB); yy += 22 * s
    for ln in wrap(d, D["how"], int(17 * s), w):
        text(d, (x, yy), ln, int(17 * s), TEXT); yy += 25 * s
    if D["prog"]:
        a, b = D["prog"]
        yy += 4 * s
        segw = (w - 60 * s) / b
        for i in range(b):
            x0 = x + i * segw
            d.rectangle([x0, yy, x0 + segw - 4 * s, yy + 8 * s], fill=TEXT if i < a else hx("1f2a3c"))
        text(d, (x + w, yy + 4 * s), f"{a} / {b}", int(14 * s), SUB, anchor="rm")
        yy += 22 * s
    if D["plate"]:
        yy += 8 * s
        text(d, (x, yy), "镀层方式", int(13 * s), SUB); yy += 22 * s
        for ln in wrap(d, D["plate"], int(17 * s), w):
            text(d, (x, yy), ln, int(17 * s), TIDEPL[3] if plated else TEXT); yy += 25 * s
    yy += 12 * s
    text(d, (x, yy), D["date"] or "未获得", int(13 * s), SUB)


# ------------------------------------------------------------------ 方案 A：浮雕蜂巢套组板
A_LAYOUT = {  # key -> (cx, cy) 1280×720 下；三星大章在左，二星组成蜂巢，一星小章另成一簇（原作套组板的组织方式）
    "set_complete": (478, 345),
    "ending_knight": (562, 282), "ending_resolve": (562, 408), "ending_deep": (642, 345),
    "elite_three": (722, 282), "cognition_complete": (722, 408), "clears_ten": (802, 345),
    "ending_standard": (668, 210), "relic_fifty": (722, 186), "cognition_first": (776, 210),
    "roster_twelve": (668, 480), "events_thirty": (722, 504),
}


def scheme_a_page(W=1280, H=720, scale=1.0, phone=False, sel="ending_knight"):
    cv = sea_bg(W, H, grid=max(3, int(3 * scale))).convert("RGBA")
    d = ImageDraw.Draw(cv)
    s = scale
    k = max(3, int(round(3 * s)))
    safeL = 118 if phone else 0
    safeR = 118 if phone else 0
    if not phone:
        x0 = 70
        text(d, (x0, 236), "蚀刻章套组", 16, SUB, spacing=4)
        text(d, (x0 - 4, 262), "深蓝之下", 60, TEXT, serif=True)
        text(d, (x0, 352), "BENEATH THE BLUE", 12, SUB, spacing=5)
        d.line([x0, 380, x0 + 60, 380], fill=hx("5a6c86"))
        text(d, (x0, 388), "05", 34, TEXT); text(d, (x0 + 50, 400), "/ 12", 18, SUB)
        yy = 446
        for t, a, b in ((3, 0, 1), (2, 2, 6), (1, 3, 5)):
            text(d, (x0, yy), STARS[t], 14, COPPER[4] if t == 3 else SILVER[4]); text(d, (x0 + 64, yy), f"{a} / {b}", 14, SUB); yy += 24
        text(d, (x0, yy + 6), "镀层  1 / 4", 14, TIDEPL[3])
        ox, oy, kk = 0, 0, 3
        pos = A_LAYOUT
    else:
        x0 = safeL + 20
        text(d, (x0, 40), "深蓝之下", 56, TEXT, serif=True)
        text(d, (x0 + 250, 50), "蚀刻章套组", 26, SUB, spacing=4)
        text(d, (x0 + 250, 88), "05 / 12   镀层 1 / 4", 26, SUB)
        ox, oy, kk = -150, 70, 4
        pos = {kk_: ((cx - 640) * 1.333 + 600, (cy - 345) * 1.333 + 440) for kk_, (cx, cy) in A_LAYOUT.items()}
        k = 4
    for key, name, tier, em, got, plated in MEDALS:
        img = render_medal(em, tier, "A", "got" if got else "locked", plated=bool(plated))
        big = up(img, k)
        cx, cy = pos[key]
        paste(cv, big, cx, cy)
        if key == sel:
            sel_box(d, cx, cy, big.width, big.height, pad=6 * s, L=12 * s)
    if not phone:
        d.line([930, 150, 930, 610], fill=hx("26344a"))
        detail_panel(cv, d, 965, 150, 260, sel, 5)
        back_btn(d, 1240, 26)
        text(d, (1240, 690), "点选蚀刻章查看记录", 13, SUB, anchor="rs")
    else:
        d.line([W - safeR - 530, 150, W - safeR - 530, H - 60], fill=hx("26344a"))
        detail_panel(cv, d, W - safeR - 500, 130, 480, sel, 4, s=1.3)
        back_btn(d, W - safeR - 10, 26, s=2.0)
    return cv


def scheme_b_page(W=1280, H=720, phone=False, sel="elite_three", flt=0):
    cv = sea_bg(W, H, grid=4 if phone else 3, seed=2).convert("RGBA")
    d = ImageDraw.Draw(cv)
    s = 1.6 if phone else 1.0
    safeL = 118 if phone else 0
    safeR = 118 if phone else 0
    x0 = safeL + (24 if phone else 56)
    # 页头：页名 + 套组页签（只有一套也保留，后续套组往右加）+ 筛选
    text(d, (x0, 30 * s), "蚀刻章", int(30 * s), TEXT, serif=True)
    tx = x0 + 130 * s
    text(d, (tx, 40 * s), "深蓝之下", int(19 * s), TEXT)
    text(d, (tx + 92 * s, 43 * s), "05/12", int(14 * s), SUB)
    d.rectangle([tx, 68 * s, tx + 140 * s, 70 * s], fill=CYAN)
    fx = tx + 190 * s
    for i, lab in enumerate(("全部", "已获得", "未获得")):
        wdt = d.textlength(lab, font=F(int(15 * s))) + 24 * s
        if i == flt:
            d.rectangle([fx, 36 * s, fx + wdt, 64 * s], outline=CYAN, width=1)
        text(d, (fx + wdt / 2, 50 * s), lab, int(15 * s), TEXT if i == flt else SUB, anchor="mm")
        fx += wdt + 8 * s
    back_btn(d, W - safeR - 16 * s, 26 * s, s=1.6 if phone else 1.0)
    # 网格：按稀有度排（三星 → 二星 → 一星），统一尺寸，稀有度看框
    order = sorted(MEDALS, key=lambda m: -m[2])
    cols = 4
    cw, ch = (150, 172) if not phone else (190, 196)
    gx, gy = x0, 100 if not phone else 100
    k = 3 if not phone else 4
    for i, (key, name, tier, em, got, plated) in enumerate(order):
        c, r = i % cols, i // cols
        cx = gx + c * cw + cw / 2
        cy = gy + r * ch + 58 * (1.3 if phone else 1)
        if key == sel:
            d.rectangle([cx - cw / 2 + 4, cy - 64 * (1.3 if phone else 1), cx + cw / 2 - 4, cy + 100 * (1.3 if phone else 1)], fill=(16, 36, 52), outline=CYAN)
        img = render_medal(em, tier, "B", "got" if got else "locked", plated=bool(plated))
        paste(cv, up(img, k), cx, cy)
        ny = cy + (60 if not phone else 78)
        text(d, (cx, ny), name if got else name, int(16 * s * (0.85 if phone else 1)), TEXT if got else DIM, anchor="mt")
        text(d, (cx, ny + (22 if not phone else 32)), STARS[tier], int(12 * s * (0.85 if phone else 1)),
             (COPPER[4] if tier == 3 else SILVER[3]) if got else DIM, anchor="mt")
        if plated:
            text(d, (cx + 40 * (1.3 if phone else 1), cy - 40 * (1.3 if phone else 1)), "镀层", int(13 * s), TIDEPL[3], anchor="lm")
    # 右侧详情卡
    px0 = gx + cols * cw + (30 if not phone else 20)
    pw = W - safeR - px0 - (40 if not phone else 20)
    d.rectangle([px0, 100 * s if not phone else 120, px0 + pw, H - (130 if not phone else 50)], fill=(9, 16, 30), outline=hx("26344a"))
    detail_panel(cv, d, px0 + 24 * (1.3 if phone else 1), (124 if not phone else 150), pw - 48 * (1.3 if phone else 1), sel, 5 if not phone else 5, s=1.0 if not phone else 1.45, style="B")
    return cv


# ------------------------------------------------------------------ 获得提示
def toast_a(scene, phone=False):
    cv = scene.copy().convert("RGBA")
    d = ImageDraw.Draw(cv, "RGBA")
    s = 1.6 if phone else 1.0
    k = 3 if not phone else 4
    m = render_medal("lance", 2, "A", "got")
    big = up(sheen(m, 0.42, 3), k)
    # 左侧、增益行下方：暗带从左缘展开，章「压入」定格的一帧（第 0.35 秒）
    x0 = (150 if phone else 0); y0 = 132 if not phone else 150
    bw, bh = 330 * s, 64 * s
    for i in range(int(bw)):
        a = int(220 * (1 - max(0, i - bw * 0.7) / (bw * 0.3)))
        d.line([x0 + i, y0, x0 + i, y0 + bh], fill=(6, 12, 24, a))
    d.line([x0, y0, x0 + bw * 0.85, y0], fill=(*SILVER[3], 160))
    paste(cv, big, x0 + 18 * s + big.width / 2, y0 + bh / 2)
    tx = x0 + 32 * s + big.width
    text(d, (tx, y0 + 10 * s), "获得蚀刻章", int(13 * s), SUB, spacing=2)
    text(d, (tx, y0 + 28 * s), "骑士归潮", int(22 * s), TEXT, serif=True)
    text(d, (tx + 100 * s, y0 + 34 * s), "★★", int(14 * s), SILVER[4])
    return cv


def toast_b(scene, phone=False):
    cv = scene.copy().convert("RGBA")
    d = ImageDraw.Draw(cv, "RGBA")
    s = 1.35 if phone else 1.0
    k = 3 if not phone else 4
    m = render_medal("tree", 2, "B", "got")
    W = cv.width
    safeR = 118 if phone else 0
    bw, bh = 300 * s, 96 * s
    x1 = W - safeR - 70 if not phone else 1495   # 右侧：避开右上的暂停 / 倍速列
    x0, y0 = x1 - bw, 92 if not phone else 200
    d.rectangle([x0, y0, x1, y0 + bh], fill=(8, 14, 26, 228), outline=(*SILVER[2], 255))
    # 章在翻面（第 2 / 3 帧：横向压扁 → 正面 + 扫光）
    img = up(sheen(m, 0.55, 3), k)
    paste(cv, img, x0 + 18 * s + img.width / 2, y0 + bh / 2)
    tx = x0 + 34 * s + img.width
    text(d, (tx, y0 + 12 * s), "获得蚀刻章", int(13 * s), SUB, spacing=2)
    text(d, (tx, y0 + 30 * s), "深蓝之树", int(22 * s), TEXT, serif=True)
    text(d, (tx + 96 * s, y0 + 36 * s), "★★", int(14 * s), SILVER[4])
    # 套组进度：12 格，新得的一格亮
    gx, gyy = tx, y0 + 70 * s
    for i in range(12):
        c = TEXT if i < 5 else (CYAN if i == 5 else hx("26344a"))
        d.rectangle([gx + i * 12 * s, gyy, gx + i * 12 * s + 8 * s, gyy + 6 * s], fill=c)
    text(d, (gx + 12 * 12 * s + 4 * s, gyy + 3 * s), "6/12", int(11 * s), SUB, anchor="lm")
    return cv


# ------------------------------------------------------------------ 手机外框（横屏 844×390 点 @2x，左侧灵动岛 + 安全区标线）
def phone_frame(screen, label):
    W, H = screen.size
    pad = 40
    out = Image.new("RGBA", (W + pad * 2, H + pad * 2 + 50), (24, 26, 30, 255))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([pad - 16, pad - 16, pad + W + 16, pad + H + 16], 110, fill=(8, 8, 10), outline=(70, 72, 80), width=4)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], 96, fill=255)
    out.paste(screen, (pad, pad), mask)
    d.rounded_rectangle([pad + 22, pad + H / 2 - 120, pad + 22 + 70, pad + H / 2 + 120], 35, fill=(0, 0, 0))
    ov = Image.new("RGBA", out.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    for x in (pad + 118, pad + W - 118):
        for y in range(pad, pad + H, 16):
            od.line([x, y, x, y + 8], fill=(255, 80, 120, 120), width=2)
    od.line([pad, pad + H - 42, pad + W, pad + H - 42], fill=(255, 80, 120, 90), width=2)
    out.alpha_composite(ov)
    text(d, (pad, pad + H + 30), label + "    （红虚线 = 安全区边：左侧灵动岛 / 右侧圆角 / 底部横条）", 22, SUB)
    return out


def label_bar(im, s):
    out = Image.new("RGBA", (im.width, im.height + 44), (14, 16, 22, 255))
    out.alpha_composite(im, (0, 44))
    text(ImageDraw.Draw(out), (16, 10), s, 20, TEXT)
    return out


def phone_scene():
    """电脑版局内截图按高铺满放中间，两侧用边缘拉伸 + 压暗补齐（示意，手机 HUD 的实际排布以触屏版为准）"""
    sc = Image.open(SHOT).convert("RGBA")
    W, H = 1688, 780
    k = H / sc.height
    mid = sc.resize((int(sc.width * k), H), Image.LANCZOS)
    out = Image.new("RGBA", (W, H))
    side = (W - mid.width) // 2
    l = mid.crop((0, 0, 4, H)).resize((side, H)); r = mid.crop((mid.width - 4, 0, mid.width, H)).resize((W - side - mid.width, H))
    out.paste(l, (0, 0)); out.paste(r, (side + mid.width, 0)); out.paste(mid, (side, 0))
    dk = Image.new("RGBA", (W, H), (0, 0, 0, 0)); dd = ImageDraw.Draw(dk)
    dd.rectangle([0, 0, side, H], fill=(0, 0, 0, 120)); dd.rectangle([side + mid.width, 0, W, H], fill=(0, 0, 0, 120))
    out.alpha_composite(dk)
    return out


def samples(style):
    keys = [("set", 3, "深蓝之下"), ("tree", 2, "深蓝之树"), ("lance", 2, "骑士归潮"), ("bubbles", 1, "泡影散尽")]
    W, H = 1280, 520
    cv = Image.new("RGBA", (W, H), (10, 16, 28, 255))
    d = ImageDraw.Draw(cv)
    cols = [(130, ), ]
    x = 40
    items = []
    for em, tier, name in keys:
        items.append((render_medal(em, tier, style, "got"), name, STARS[tier]))
    items.append((render_medal("lance", 2, style, "got", plated=True), "骑士归潮 · 镀层", "★★"))
    items.append((render_medal("tree", 2, style, "locked"), "未获得", "★★"))
    slot = W // len(items)
    for i, (img, name, st) in enumerate(items):
        cx = slot * i + slot / 2
        big = up(img, 6 if style == "B" or img.width < 30 else 5)
        if img.width >= 30:
            big = up(img, 5)
        paste(cv, big, cx, 210)
        small = up(img, 3)
        paste(cv, small, cx, 400)
        text(d, (cx, 450), name, 18, TEXT, anchor="mt")
        text(d, (cx, 478), st, 14, COPPER[4] if st == "★★★" else SILVER[4], anchor="mt")
    text(d, (24, 16), "上排：放大 5–6 倍看像素   下排：游戏里 1280×720 下的实际大小（1 美术像素 = 3 逻辑像素）", 16, SUB)
    return cv


def main():
    scene = Image.open(SHOT).convert("RGBA")
    ps = phone_scene()
    outs = {}
    outs["A1_samples"] = label_bar(samples("A"), "方案 A · 浮雕章面（深蓝面 + 银浮雕；稀有度 = 尺寸 + 框材，三星铜框亮面）")
    outs["A2_page_pc"] = label_bar(scheme_a_page(), "方案 A · 陈列页 · 电脑 1280×720（套组板：三星大章 + 二星蜂巢 + 一星小簇；未获得 = 暗色剪影）")
    outs["A3_page_phone"] = phone_frame(scheme_a_page(1688, 780, scale=1.33, phone=True), "方案 A · 陈列页 · 手机横屏 844×390 @2x")
    outs["A4_toast_pc"] = label_bar(toast_a(scene), "方案 A · 获得提示 · 电脑（第 0.35 秒：章压入定格 + 扫光；左侧增益行下方）")
    outs["A5_toast_phone"] = phone_frame(toast_a(ps, phone=True), "方案 A · 获得提示 · 手机（底图为电脑版截图按高缩放示意）")
    outs["B1_samples"] = label_bar(samples("B"), "方案 B · 蚀刻铭牌（银板刻纹；统一尺寸，稀有度 = 单框 / 双框 / 铜双框 + 铆钉）")
    outs["B2_page_pc"] = label_bar(scheme_b_page(), "方案 B · 陈列页 · 电脑 1280×720（档案柜：页签 + 筛选 + 按稀有度排的网格 + 详情卡；未获得 = 空板 + 问号）")
    outs["B3_page_phone"] = phone_frame(scheme_b_page(1688, 780, phone=True), "方案 B · 陈列页 · 手机横屏 844×390 @2x")
    outs["B4_toast_pc"] = label_bar(toast_b(scene), "方案 B · 获得提示 · 电脑（第 0.5 秒：章翻正 + 扫光；套组进度格新点亮一格）")
    outs["B5_toast_phone"] = phone_frame(toast_b(ps, phone=True), "方案 B · 获得提示 · 手机（底图为电脑版截图按高缩放示意）")
    for k, im in outs.items():
        im.convert("RGB").quantize(128, method=Image.Quantize.MEDIANCUT).save(os.path.join(OUT, f"{k}.png"), optimize=True)
        print(k, im.size)


if __name__ == "__main__":
    main()
