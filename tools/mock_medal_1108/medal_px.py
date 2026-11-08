# 蚀刻章示意：用现有章面（game/art/ui/medals/medal_N.png）换框，按方案 A / B 生成像素章面
import math
from PIL import Image, ImageDraw

ROOT = r'E:/ArknightsSurvivors/.claude/worktrees/hud-skill-cd-e5a2f6/game/art/ui/medals/'


def hexpts(w, h, inset=0.0):
    cx, cy = (w - 1) / 2, (h - 1) / 2
    rx, ry = (w - 1) / 2 - inset, (h - 1) / 2 - inset
    return [(cx, cy - ry), (cx + rx, cy - ry / 2), (cx + rx, cy + ry / 2), (cx, cy + ry), (cx - rx, cy + ry / 2), (cx - rx, cy - ry / 2)]


def hexmask(w, h, inset=0.0):
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).polygon(hexpts(w, h, inset), fill=255)
    return m


_face = {}


def face(mid):
    """章面内图（去掉原银框）：RGBA，方形"""
    if mid in _face:
        return _face[mid]
    im = Image.open(ROOT + 'medal_%d.png' % mid).convert('RGBA')
    w, h = im.size
    ins = max(3, round(w * 0.14))
    m = hexmask(w, h, ins)
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    out.paste(im, (0, 0), m)
    bb = m.getbbox()
    _face[mid] = out.crop(bb)
    return _face[mid]


def lum(c):
    return 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2]


def ramp(cols, t):
    t = max(0.0, min(1.0, t))
    i = min(len(cols) - 2, int(t * (len(cols) - 1)))
    f = t * (len(cols) - 1) - i
    a, b = cols[i], cols[i + 1]
    # 像素风：不插值，取最近档
    return a if f < 0.5 else b


IRON = [(22, 28, 40), (52, 60, 76), (92, 102, 120), (140, 150, 166)]
SILVER = [(40, 52, 72), (110, 126, 150), (184, 196, 212), (236, 242, 248)]
BRONZE = [(46, 28, 18), (110, 66, 38), (176, 112, 62), (226, 170, 110)]
PLAT = [(38, 52, 78), (128, 150, 184), (206, 220, 236), (255, 255, 255)]
GOLD = [(60, 38, 12), (150, 104, 40), (222, 180, 92), (255, 236, 170)]
CYAN = (110, 220, 255)


def bevel(img, band_mask, cols, cx, cy):
    px = img.load()
    bm = band_mask.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            if bm[x, y]:
                dx, dy = x - cx, y - cy
                d = math.hypot(dx, dy) or 1
                k = (-0.6 * dx - 0.8 * dy) / d
                t = 0.5 + 0.5 * k
                px[x, y] = ramp(cols, t) + (255,)


def band(w, h, a, b):
    """外缩 a 到 b 像素之间的环"""
    m1 = hexmask(w, h, a)
    m2 = hexmask(w, h, b)
    out = Image.new('L', (w, h), 0)
    p1, p2, po = m1.load(), m2.load(), out.load()
    for y in range(h):
        for x in range(w):
            po[x, y] = 255 if p1[x, y] and not p2[x, y] else 0
    return out


def recolor_face(f, cols, keep_blue=False):
    out = f.copy()
    p = out.load()
    for y in range(out.height):
        for x in range(out.width):
            c = p[x, y]
            if c[3] == 0:
                continue
            blue = c[2] > c[0] + 40 and c[2] > 120
            if lum(c) < 62:
                p[x, y] = (10, 18, 34, c[3])   # 底板保持深色
                continue
            if keep_blue and blue:
                continue
            p[x, y] = ramp(cols, 0.25 + 0.75 * lum(c) / 255) + (c[3],)
    return out


def silhouette(f, dark=(16, 28, 46), mid=(30, 48, 74)):
    out = f.copy()
    p = out.load()
    for y in range(out.height):
        for x in range(out.width):
            c = p[x, y]
            if c[3]:
                p[x, y] = (mid if lum(c) > 95 else dark) + (255,)
    return out


def lineart(f, line=(90, 200, 240), bg=(12, 22, 38)):
    """线稿：章面亮部的边缘 1 像素线"""
    w, h = f.size
    src = f.load()
    out = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    p = out.load()
    on = lambda x, y: 0 <= x < w and 0 <= y < h and src[x, y][3] and lum(src[x, y]) > 110
    for y in range(h):
        for x in range(w):
            if not src[x, y][3]:
                continue
            if on(x, y) and (not on(x + 1, y) or not on(x - 1, y) or not on(x, y + 1) or not on(x, y - 1)):
                p[x, y] = line + (255,)
            else:
                p[x, y] = bg + (255,)
    return out


def medal(mid, S, scheme, tier, state='got', plated=False, fill=1.0):
    """S = 章外框边长（像素）；tier 1/2/3；state got / locked / line；fill 方案 B 蚀刻进度（0 线稿 → 1 金属）"""
    pad = 4 if (scheme == 'A' and tier >= 2) else 0
    W = S + pad * 2
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ox = pad
    base = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    cx = cy = (S - 1) / 2
    if scheme == 'A':
        fw = {1: 2, 2: 3, 3: 3}[tier]
        cols = {1: IRON, 2: SILVER, 3: SILVER}[tier]
        if plated:
            cols = GOLD
        inner_ins = fw + 1 + (2 if tier == 3 else 0)
    else:
        fw = 3
        cols = {1: BRONZE, 2: SILVER, 3: PLAT}[tier]
        inner_ins = fw + (3 if tier == 3 else 1)
    if state == 'locked':
        cols = [(14, 22, 36), (28, 40, 60), (44, 62, 90), (60, 84, 116)]
    # 底板
    plate = hexmask(S, S, 1)
    base.paste((10, 18, 34, 255), (0, 0), plate)
    # 外描边
    ImageDraw.Draw(base).polygon(hexpts(S, S), outline=(6, 10, 18, 255))
    bevel(base, band(S, S, 1, 1 + fw), cols, cx, cy)
    if tier == 3:
        # 双框：内圈一道细线（镀层时金、否则青）
        b2 = band(S, S, fw + 2, fw + 3)
        base.paste(((236, 200, 110, 255) if plated else (CYAN + (255,))) if state != 'locked' else (40, 60, 86, 255), (0, 0), b2)
    # 章面
    f = face(mid)
    im_m = hexmask(S, S, inner_ins)
    bb = im_m.getbbox()
    fw2, fh2 = bb[2] - bb[0], bb[3] - bb[1]
    ff = f.resize((fw2, fh2), Image.NEAREST)
    if state == 'locked':
        ff = silhouette(ff) if scheme == 'A' else lineart(ff, line=(54, 88, 120))
    elif scheme == 'B':
        metal = recolor_face(ff, cols, keep_blue=(tier == 3))
        if fill < 1.0:
            la = lineart(ff)
            cut = int(fh2 * (1 - fill))
            metal.paste(la.crop((0, 0, fw2, cut)), (0, 0))
        ff = metal
    elif plated:
        ff = recolor_face(ff, GOLD, keep_blue=True)
    layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    layer.paste(ff, bb[:2])
    base.paste(layer, (0, 0), Image.composite(layer.split()[3], Image.new('L', (S, S), 0), im_m))
    img.alpha_composite(base, (ox, ox))
    d = ImageDraw.Draw(img)
    c = (W - 1) / 2
    lit = state != 'locked'
    if scheme == 'A' and tier >= 2:
        # 外圈刻点：★★ 6 个顶点外短刺，★★★ 再加边中点
        pts = hexpts(S, S)
        col = (cols[2] if lit else (40, 58, 84))
        for (x, y) in pts:
            vx, vy = x - cx, y - cy
            n = math.hypot(vx, vy)
            for k in (1, 2, 3):
                px_, py_ = round(ox + x + vx / n * k), round(ox + y + vy / n * k)
                if 0 <= px_ < W and 0 <= py_ < W:
                    img.putpixel((px_, py_), col + (255,))
        if tier == 3:
            # 顶点青晶钉 + 顶冠
            for (x, y) in pts:
                gx, gy = round(ox + x), round(ox + y)
                for dx_ in (0, 1):
                    for dy_ in (0, 1):
                        if 0 <= gx + dx_ - 1 < W and 0 <= gy + dy_ - 1 < W:
                            img.putpixel((gx + dx_ - 1, gy + dy_ - 1), ((CYAN if not plated else (255, 236, 170)) if lit else (40, 60, 86)) + (255,))
    if plated and lit:
        for (x, y) in [(0.28, 0.22), (0.74, 0.62), (0.4, 0.8)]:
            sx, sy = round(ox + S * x), round(ox + S * y)
            for dx_, dy_ in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]:
                img.putpixel((sx + dx_, sy + dy_), (255, 250, 220, 255))
    return img


def up(img, k):
    return img.resize((img.width * k, img.height * k), Image.NEAREST)
