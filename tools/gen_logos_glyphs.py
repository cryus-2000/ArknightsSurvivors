# -*- coding: utf-8 -*-
"""逻各斯「言」符文（art/requests/v17_codex_logos_glyphs.md，程序生成版，固定种子、可重复）。

生成 art/incoming/ 下三组图（@1x 与严格 2 倍最近邻的 @2x）：
  fx_logos_glyphs   32×32 ×16 格横排：16 个互不重复的字，每字 2–5 条细笔画（楔形 / 篆刻感），
                    笔画起笔 2 px 宽（外侧亮紫白 #EEF0FF、内侧墨蓝 #3A48B8）、收笔收成 1 px，
                    楔形起笔；一两笔末端暗红 #7A2030。无填色、二值 alpha。字高约 22 px（69%），居中。
  fx_logos_glyph    24×24 ×6 帧：命中——第 1–3 帧逐笔写出字表第 7 字，第 4 帧全亮 + 1 px 抖动晕光（二值 alpha，
                    用墨蓝棋盘点代替半透明），第 5–6 帧碎成 5 片向外飞散、像素逐帧减少。锚点 (12,12)。
  fx_logos_script   64×12 ×4 帧横排：同一门文字缩到 7 px 高的连续小字，横向无缝平铺，每帧左移 16 px（1/4 周期）。

所有笔画共用一套词汇（竖、横、斜、钩、楔、小环、点），字由手写的笔画表组合；字形坐标按 0–1 相对盒子定义，
字表 / 命中 / 书写带各按自己的像素高度栅格化，所以三张图是同一套字。

用法：python tools/gen_logos_glyphs.py [--preview]
  --preview 另写 build/logos_glyphs/preview.png：每字 1x、游戏里弹体 13 px 高（最近邻缩小）、命中帧 16 px 高，
  以及旧图（art/incoming/_old_logos_glyphs/）与新图并排。
"""
import os, sys, random
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(ROOT, "art", "incoming")
OLD = os.path.join(OUT, "_old_logos_glyphs")
PREV = os.path.join(ROOT, "build", "logos_glyphs")

PALE = (0xEE, 0xF0, 0xFF, 255)
INK = (0x3A, 0x48, 0xB8, 255)
RED = (0x7A, 0x20, 0x30, 255)
CLEAR = (0, 0, 0, 0)

# ---------------------------------------------------------------------------
# 笔画词汇：每条笔画 = (类型, 参数…)，坐标为字盒内 0–1 相对值（x 向右、y 向下）。
#   ("ln", x0, y0, x1, y1)        直笔：起笔楔形 + 2 px 身 + 1 px 收笔
#   ("hk", x0, y0, x1, y1, x2, y2) 钩：两段折线，一笔写成
#   ("rg", cx, cy)                小环（直径约 5 px）
#   ("dt", cx, cy)                点（2×2）
#   ("wd", x, y, dir)             独立楔形（cuneiform 三角），dir = "d"/"r"/"l"
# 红色末端用 "red" 标记在笔画元组最后（只取一两笔）。
# ---------------------------------------------------------------------------
GLYPHS = [
 # 0 竖 + 两横（像「干」）
 [("ln", .50, .02, .50, .98, "red"), ("ln", .10, .30, .90, .30), ("ln", .18, .62, .82, .62)],
 # 1 左竖 + 右斜 + 下横钩
 [("ln", .20, .05, .20, .95), ("ln", .45, .08, .92, .55), ("hk", .40, .95, .92, .95, .92, .70, "red")],
 # 2 双竖 + 环
 [("ln", .08, .02, .08, .98), ("ln", .92, .02, .92, .98), ("rg", .50, .55), ("wd", .50, .12, "d")],
 # 3 大斜 + 反斜短 + 点
 [("ln", .10, .95, .90, .05), ("ln", .15, .20, .55, .62, "red"), ("dt", .82, .80)],
 # 4 倒 U 钩 + 中竖
 [("hk", .10, .98, .10, .05, .90, .05), ("ln", .90, .05, .90, .55), ("dt", .50, .60, "red")],
 # 5 三横递减（楔形）
 [("ln", .05, .15, .95, .15), ("ln", .18, .50, .82, .50), ("ln", .32, .85, .68, .85, "red")],
 # 6 竖 + 斜叉（命中帧用它）
 [("ln", .50, .02, .50, .98), ("ln", .05, .15, .95, .85), ("ln", .95, .15, .05, .85, "red")],
 # 7 Z 形钩 + 点
 [("hk", .08, .10, .92, .10, .08, .92), ("ln", .50, .92, .92, .92, "red"), ("dt", .82, .45)],
 # 8 两斜合拢（人字）+ 横
 [("ln", .50, .02, .08, .95), ("ln", .50, .02, .92, .95), ("ln", .25, .62, .75, .62, "red")],
 # 9 环在上 + 长竖 + 短横
 [("rg", .50, .20), ("ln", .50, .40, .50, .98), ("ln", .22, .70, .78, .70), ("wd", .50, .98, "d", "red")],
 # 10 竖 + 右上开口钩 + 点
 [("ln", .22, .02, .22, .98), ("hk", .45, .15, .92, .15, .92, .60), ("dt", .68, .85, "red")],
 # 11 反 Z + 竖
 [("hk", .92, .08, .08, .08, .92, .92), ("ln", .08, .50, .08, .98, "red")],
 # 12 双横 + 斜竖穿过
 [("ln", .08, .28, .92, .28), ("ln", .08, .72, .92, .72), ("ln", .72, .02, .28, .98, "red")],
 # 13 小环两颗 + 竖
 [("rg", .28, .30), ("rg", .72, .70), ("ln", .50, .02, .50, .98, "red")],
 # 14 大钩（L）+ 内斜
 [("hk", .15, .02, .15, .92, .92, .92), ("ln", .40, .15, .85, .60, "red"), ("dt", .85, .25)],
 # 15 V 叉 + 顶横 + 点
 [("ln", .05, .08, .95, .08), ("ln", .18, .25, .50, .92), ("ln", .82, .25, .50, .92, "red"), ("dt", .50, .40)],
]
HIT_GLYPH = 6      # 命中帧写的字
WIDTH_MAIN = 2     # 笔画身宽（外侧亮、内侧墨蓝）
TAIL = 0.22        # 收笔段占笔画长度比例（1 px；斜笔不收，1 px 斜线缩到 13 px 会断）
HEAD = 0.30        # 起笔段：内侧再加 1 px 墨蓝（笔锋压重）


def _bres(x0, y0, x1, y1):
    """整数 Bresenham 直线，返回像素序列（起点到终点）。"""
    pts = []
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    x, y = x0, y0
    while True:
        pts.append((x, y))
        if x == x1 and y == y1:
            break
        e2 = 2 * err
        if e2 >= dy:
            err += dy; x += sx
        if e2 <= dx:
            err += dx; y += sy
    return pts


def _raster_line(px, x0, y0, x1, y1, cx, cy, thick, red=False, wedge=True):
    """一条笔画：起笔楔形（thick 时）、2 px 身（外侧亮、内侧墨蓝，内侧朝字中心）、1 px 收笔。
    px: dict (x,y)->颜色，后画的笔画盖在先画的上；交叉处记为墨蓝。"""
    pts = _bres(x0, y0, x1, y1)
    n = len(pts)
    diag = x0 != x1 and y0 != y1
    body_end = n if diag else max(1, int(round(n * (1 - TAIL))))
    head_end = max(2, int(round(n * HEAD)))
    # 内侧方向：垂直于笔画，朝向字中心
    ddx, ddy = x1 - x0, y1 - y0
    if abs(ddx) >= abs(ddy):
        nx, ny = 0, (1 if cy >= (y0 + y1) / 2 else -1)
    else:
        nx, ny = (1 if cx >= (x0 + x1) / 2 else -1), 0
    for i, (x, y) in enumerate(pts):
        _put(px, x, y, PALE)
        if thick and i < body_end:
            _put(px, x + nx, y + ny, PALE)          # 2 px 身，两列都亮（缩到 13 px 仍能采到）
        if thick and i < head_end:
            _put(px, x + 2 * nx, y + 2 * ny, INK, inner=True)   # 起笔内侧压一层墨蓝
    if thick and wedge and n >= 6:
        # 起笔楔形：起点外沿两侧各补 1 px（三角头）
        x, y = pts[0]
        tx, ty = (1 if abs(ddx) >= abs(ddy) else 0), (0 if abs(ddx) >= abs(ddy) else 1)
        _put(px, x + tx, y + ty, PALE); _put(px, x - tx, y - ty, PALE)
        _put(px, x + nx, y + ny, PALE)
    if red:
        x, y = pts[-1]
        px[(x, y)] = RED
        if n >= 8:
            x2, y2 = pts[-2]
            px[(x2, y2)] = RED


def _put(px, x, y, col, inner=False):
    old = px.get((x, y))
    if inner:
        if old is None:
            px[(x, y)] = INK
        return
    if old is not None and old == PALE:
        px[(x, y)] = INK          # 交叉处墨蓝
    else:
        px[(x, y)] = col


def _raster_glyph(strokes, box, thick=True, only=None):
    """把一个字栅格化到像素字典。box = (x, y, w, h) 像素；only = 只画前 n 笔（命中逐笔用）。"""
    bx, by, bw, bh = box
    cx, cy = bx + bw / 2, by + bh / 2
    px = {}
    rg_r = max(1, int(round(bh * 0.14)))
    for si, s in enumerate(strokes):
        if only is not None and si >= only:
            break
        red = s[-1] == "red"
        t = s[0]
        X = lambda u: int(round(bx + u * (bw - 1)))
        Y = lambda v: int(round(by + v * (bh - 1)))
        if t == "ln":
            _raster_line(px, X(s[1]), Y(s[2]), X(s[3]), Y(s[4]), cx, cy, thick, red)
        elif t == "hk":
            _raster_line(px, X(s[1]), Y(s[2]), X(s[3]), Y(s[4]), cx, cy, thick, False)
            _raster_line(px, X(s[3]), Y(s[4]), X(s[5]), Y(s[6]), cx, cy, thick, red, wedge=False)
        elif t == "rg":
            x, y = X(s[1]), Y(s[2])
            r = rg_r
            if r <= 1:
                for (dx, dy) in [(0, -1), (-1, 0), (1, 0), (0, 1)]:
                    _put(px, x + dx, y + dy, PALE)
            else:
                ring = [(x - r, y - 1), (x - r, y), (x - r, y + 1), (x + r, y - 1), (x + r, y), (x + r, y + 1),
                        (x - 1, y - r), (x, y - r), (x + 1, y - r), (x - 1, y + r), (x, y + r), (x + 1, y + r)]
                for (qx, qy) in ring:
                    px[(qx, qy)] = PALE
                if red:
                    px[(x + r, y + 1)] = RED
                px[(x, y)] = INK if thick else PALE
        elif t == "dt":
            x, y = X(s[1]), Y(s[2])
            px[(x, y)] = RED if red else PALE
            if thick:
                px[(x + 1, y)] = PALE if not red else RED
                px[(x, y + 1)] = INK
                px[(x + 1, y + 1)] = INK
        elif t == "wd":
            x, y, d = X(s[1]), Y(s[2]), s[3]
            if d == "d":
                tri = [(x - 1, y - 1), (x, y - 1), (x + 1, y - 1), (x, y)]
            elif d == "r":
                tri = [(x - 1, y - 1), (x - 1, y), (x - 1, y + 1), (x, y)]
            else:
                tri = [(x + 1, y - 1), (x + 1, y), (x + 1, y + 1), (x, y)]
            if not thick:
                tri = tri[-2:]
            for (qx, qy) in tri:
                px[(qx, qy)] = PALE
            if red:
                px[tri[-1]] = RED
    return px


def _blit(im, px, dx=0, dy=0):
    w, h = im.size
    for (x, y), c in px.items():
        x += dx; y += dy
        if 0 <= x < w and 0 <= y < h:
            im.putpixel((x, y), c)


def _x2(im):
    return im.resize((im.width * 2, im.height * 2), Image.NEAREST)


def _save(im, name):
    im.save(os.path.join(OUT, name + ".png"))
    _x2(im).save(os.path.join(OUT, name + "@2x.png"))


# ---------------------------------------------------------------------------
def make_glyphs():
    cell = 32
    gh = 22                      # 字高 69%
    gw = 20
    im = Image.new("RGBA", (cell * 16, cell), CLEAR)
    for i, g in enumerate(GLYPHS):
        px = _raster_glyph(g, ((cell - gw) // 2, (cell - gh) // 2, gw, gh))
        _blit(im, px, i * cell, 0)
    return im


def make_hit():
    cell = 24
    gh, gw = 17, 14
    box = ((cell - gw) // 2, (cell - gh) // 2, gw, gh)
    g = GLYPHS[HIT_GLYPH]
    im = Image.new("RGBA", (cell * 6, cell), CLEAR)
    # 第 1–3 帧：逐笔
    for f in range(3):
        _blit(im, _raster_glyph(g, box, only=f + 1), f * cell, 0)
    # 第 4 帧：全亮 + 1 px 棋盘晕光（二值 alpha）
    full = _raster_glyph(g, box)
    halo = {}
    for (x, y) in full:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q not in full and (q[0] + q[1]) % 2 == 0:
                    halo[q] = INK
    _blit(im, halo, 3 * cell, 0)
    _blit(im, full, 3 * cell, 0)
    # 第 5–6 帧：碎成 5 片向外飞散、像素递减
    rnd = random.Random(17)
    pts = sorted(full.items())
    cx, cy = box[0] + box[2] / 2, box[1] + box[3] / 2
    import math
    nfrag = 5
    frags = [[] for _ in range(nfrag)]
    for (x, y), c in pts:
        a = math.atan2(y - cy, x - cx)
        frags[int((a + math.pi) / (2 * math.pi) * nfrag) % nfrag].append(((x, y), c))
    for f, (shift, keep) in enumerate([(2, 0.55), (4, 0.28)]):
        out = {}
        for k, fr in enumerate(frags):
            if not fr:
                continue
            fx = sum(p[0][0] for p in fr) / len(fr) - cx
            fy = sum(p[0][1] for p in fr) / len(fr) - cy
            L = max(1e-3, math.hypot(fx, fy))
            ox, oy = int(round(fx / L * shift)), int(round(fy / L * shift)) + f   # 略向下沉
            rnd.shuffle(fr)
            n = max(1, int(round(len(fr) * keep)))
            for (x, y), c in fr[:n]:
                out[(x + ox, y + oy)] = PALE if c == INK and f == 1 else c
        _blit(im, out, (4 + f) * cell, 0)
    return im


def make_script():
    fw, fh = 64, 12
    gh, gw = 7, 6
    im = Image.new("RGBA", (fw * 4, fh), CLEAR)
    # 一周期 64 px 放 6 个小字（间距 ≈ 10.7 px），顺序固定
    order = [0, 5, 8, 2, 12, 15]
    period = {}
    for k, gi in enumerate(order):
        x0 = int(round(k * fw / len(order))) + 2
        px = _raster_glyph(GLYPHS[gi], (x0, (fh - gh) // 2, gw, gh), thick=False)
        # 字间一粒墨蓝连笔点
        px[(x0 + gw + 1, fh // 2)] = INK
        for (x, y), c in px.items():
            period[(x % fw, y)] = c
    for f in range(4):
        sh = f * (fw // 4)
        _blit(im, {((x - sh) % fw, y): c for (x, y), c in period.items()}, f * fw, 0)
    return im


# ---------------------------------------------------------------------------
def _scale_h(im, h):
    return im.resize((max(1, round(im.width * h / im.height)), h), Image.NEAREST)


def preview(new_glyphs, new_hit, new_script):
    os.makedirs(PREV, exist_ok=True)
    bg = (28, 30, 44, 255)
    Z = 4
    rows = []
    def row(im, z, label=None):
        rows.append(im.resize((im.width * z, im.height * z), Image.NEAREST))
    row(new_glyphs, Z)                                   # 1x ×4
    row(_scale_h(new_glyphs, 13), Z)                     # 13 px ×4（游戏里弹体）
    row(_scale_h(new_glyphs, 13), 1)                     # 13 px 原大
    row(new_hit, Z)
    row(_scale_h(new_hit, 16), Z)                        # 16 px（命中）
    row(new_script, Z)
    olds = []
    for n in ("fx_logos_glyphs", "fx_logos_glyph", "fx_logos_script"):
        p = os.path.join(OLD, n + ".png")
        if os.path.exists(p):
            o = Image.open(p).convert("RGBA")
            olds.append(o)
            olds.append(_scale_h(o, 13 if n == "fx_logos_glyphs" else 16) if n != "fx_logos_script" else o)
    for o in olds:
        row(o, Z)
    W = max(r.width for r in rows) + 16
    H = sum(r.height + 8 for r in rows) + 8
    sheet = Image.new("RGBA", (W, H), bg)
    y = 8
    for r in rows:
        sheet.paste(r, (8, y), r)
        y += r.height + 8
    sheet.save(os.path.join(PREV, "preview.png"))
    return os.path.join(PREV, "preview.png")


def main():
    os.makedirs(OLD, exist_ok=True)
    for n in ("fx_logos_glyphs", "fx_logos_glyph", "fx_logos_script"):
        for suf in ("", "@2x"):
            src = os.path.join(OUT, n + suf + ".png")
            dst = os.path.join(OLD, n + suf + ".png")
            if os.path.exists(src) and not os.path.exists(dst):
                Image.open(src).save(dst)
    g, h, s = make_glyphs(), make_hit(), make_script()
    _save(g, "fx_logos_glyphs"); _save(h, "fx_logos_glyph"); _save(s, "fx_logos_script")
    print("wrote", g.size, h.size, s.size)
    if "--preview" in sys.argv:
        print("preview:", preview(g, h, s))


if __name__ == "__main__":
    main()
