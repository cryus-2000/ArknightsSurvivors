"""itch 封面 A′（文件名 A2）：底图与补光同 A（build_cover_g.build 的前半段），logo 区改成标题页排法。

照 game/scripts/screens/title_jelly_menu.gd `_draw_logo` / `_en` 与 ui.gd `cond`：
- logo_mark 平涂原色（PNG 自带 #e4e8e5 / #a9b8bf），不加渐变；
- 「ARKNIGHTS」在徽记右上：o + (132·sc + 1, −3k)，9k 号，#c3d3dc，字距 3.2k；
- 细线 y = o.y + 92·sc，#3b5566，左端 22k 一段青 #9de5ef 加粗；
- 线下 6k：「RHODES ISLAND」#a2b9c8 字距 2.6k、+6k「·」#466171、+8k「SURVIVORS」#d5e2e8 字距 2.6k，9k 号；
- 英文字体 = ui.ttf 横向压到 0.82 + 加粗（UI.cond）。
成品分辨率下 logo 宽 482（k = 482/262），按像素格把线宽取整到 2 / 4 像素。
为在亮背景上可读：保留深蓝描边与下投影，去掉外发光。
用法：python art/promo/itch/cover_g/build_cover_g_a2.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cover_g as B  # noqa: E402

UI_FONT = B.ROOT / "game/fonts/ui.ttf"
C = (157, 229, 239)
M = (162, 185, 200)
L = (70, 97, 113)
ARK = (195, 211, 220)
SURV = (213, 226, 232)
INK = (6, 12, 24)
SHADOW = (4, 8, 18)


def background(kind):
    """与 A 完全相同的底图（裁切 → 补光 → 像素化），放回成品尺寸，不含 logo。"""
    p = B.PLANS["A"]
    W, H = B.SIZES[kind]
    raw = Image.open(B.RAW / p[kind]).convert("RGB")
    c = B.crop_to(raw, W, H, p["fx_" + kind], p["fy_" + kind]).resize((W, H), Image.LANCZOS)
    lit, _ = B.relight(c, p["lamp"], 0.30 if kind == "cover" else 0.36)
    return B.pixelize(lit, (W, H)).resize((W, H), Image.NEAREST)


def en_mask(text, size, sp):
    """UI.cond：横向 0.82 + 加粗；逐字按字宽 + 字距排。4 倍超采样后二值化成硬边。"""
    S = 4
    f = ImageFont.truetype(str(UI_FONT), size * S)
    asc, desc = f.getmetrics()
    xs, x = [], 0.0
    for ch in text:
        xs.append(x)
        x += f.getlength(ch) * 0.82 / S + sp
    w = int(np.ceil(x)) + 4
    big = Image.new("L", (int(w * S / 0.82) + 8 * S, asc + desc + 4 * S), 0)
    d = ImageDraw.Draw(big)
    for ch, x0 in zip(text, xs):
        d.text((x0 * S / 0.82, 0), ch, font=f, fill=255)
    big = big.filter(ImageFilter.MaxFilter(3))  # 加粗（embolden）
    big = big.resize((int(big.width * 0.82), big.height), Image.LANCZOS)
    small = big.resize((max(1, big.width // S), max(1, big.height // S)), Image.BOX)
    m = np.asarray(small) > 110
    width = x - sp
    return m, width, asc / S  # asc：顶边到基线


def stamp(canvas, m, x, y, col):
    a = np.asarray(canvas)
    h, w = m.shape
    sub = a[y:y + h, x:x + w]
    mm = m[:sub.shape[0], :sub.shape[1]]
    sub[mm] = col
    return Image.fromarray(a)


def dilate(m, n):
    return B.dilate(m, n)


def logo_block(W):
    """返回整块 logo 的 RGB 层和覆盖掩码（含描边 / 投影），块左上 = 徽记左上 o。"""
    lg = Image.open(B.LOGO).convert("RGBA")
    la = np.asarray(lg)
    w = lg.width                      # 482 = 262·k
    k = w / 262.0
    sc = w / 482.0
    fs = int(round(9 * k))
    PADT = 16                         # 徽记上方给「ARKNIGHTS」留的高度
    ry = PADT + int(round(92 * sc))
    Hb = ry + int(round(6 * k)) + fs + 12
    Wb = w + 8
    col = np.zeros((Hb, Wb, 3), np.uint8)
    face = np.zeros((Hb, Wb), bool)

    def put(mask, x, y, c):
        h, ww = mask.shape
        x, y = int(round(x)), int(round(y))
        region = face[y:y + h, x:x + ww]
        mm = mask[:region.shape[0], :region.shape[1]]
        col[y:y + h, x:x + ww][mm] = c
        region |= mm

    # 徽记：原色平涂
    mk = la[..., 3] > 127
    col[PADT:PADT + lg.height, 0:w][mk] = la[..., :3][mk]
    face[PADT:PADT + lg.height, 0:w] |= mk
    # 「ARKNIGHTS」：o + (132·sc + 1, −3k)，_en 的 top_left 是字顶
    m, _, _ = en_mask("ARKNIGHTS", fs, 3.2 * k)
    put(m, 132 * sc + 1, PADT - 3 * k, ARK)
    # 细线 + 左端青色加粗（线宽按 2 像素格取整：1→2、2→4）
    line = np.zeros_like(face)
    line[ry:ry + 2, 0:w] = True
    col[line] = (59, 85, 102)
    face |= line
    cyan = np.zeros_like(face)
    cyan[ry - 1:ry + 3, 0:int(round(22 * k))] = True
    col[cyan] = C
    face |= cyan
    # 线下一行
    ty = ry + 6 * k
    sx = 30 * k
    for txt, c, sp, gap in (("RHODES ISLAND", M, 2.6 * k, 6 * k), ("·", L, 0.0, 8 * k), ("SURVIVORS", SURV, 2.6 * k, 0)):
        m, tw, _ = en_mask(txt, fs, sp)
        put(m, sx, ty, c)
        sx += tw + gap
    # 深蓝描边 + 下投影（无外发光）；描边 2 像素 = 1 个像素格
    out = dilate(face, 2) & ~face
    sh = np.roll(dilate(face, 2), 4, axis=0) & ~dilate(face, 2)
    rgb = np.zeros((Hb, Wb, 3), np.uint8)
    rgb[sh] = SHADOW
    rgb[out] = INK
    rgb[face] = col[face]
    cover = sh | out | face
    return rgb, cover, PADT


def compose(kind):
    W, H = B.SIZES[kind]
    bg = np.asarray(background(kind)).copy()
    rgb, cov, padt = logo_block(W)
    hb, wb = cov.shape
    x0 = (W - 482) // 2
    x0 -= x0 % 2
    y0 = 16 if kind == "cover" else 12  # 与 A 相同的徽记顶边（原生 8 / 6 格）
    y0 -= padt
    y0 = max(y0, 0)
    reg = bg[y0:y0 + hb, x0:x0 + wb]
    c = cov[:reg.shape[0], :reg.shape[1]]
    reg[c] = rgb[:reg.shape[0], :reg.shape[1]][c]
    return Image.fromarray(bg)


def main():
    out = {}
    for kind in B.SIZES:
        W, H = B.SIZES[kind]
        im = compose(kind)
        im.save(B.OUT / f"cover_G_A2_{W}x{H}.png", optimize=True)
        im.resize((315, int(round(H * 315 / W))), Image.BOX).save(B.OUT / f"cover_G_A2_{W}x{H}_thumb.png", optimize=True)
        out[kind] = im
    # A vs A′ 并排：上排封面，中排横幅，下排缩略
    g = 16
    fnt = ImageFont.truetype(str(UI_FONT), 22)
    Wsh = 2 * 960 + 3 * g
    Hsh = 40 + 500 + 40 + 400 + 40 + 250 + g
    sh = Image.new("RGB", (Wsh, Hsh), (14, 18, 26))
    d = ImageDraw.Draw(sh)
    for i, (tag, lab) in enumerate((("A", "A（现版：渐变字 + 外发光 + 金色英文）"), ("A2", "A2（标题页排法：平涂 + 细线 + RHODES ISLAND · SURVIVORS）"))):
        x = g + i * (960 + g)
        d.text((x, 8), lab, font=fnt, fill=(220, 230, 235))
        sh.paste(Image.open(B.OUT / f"cover_G_{tag}_630x500.png"), (x, 40))
        sh.paste(Image.open(B.OUT / f"cover_G_{tag}_960x400.png"), (x, 40 + 500 + 30))
        sh.paste(Image.open(B.OUT / f"cover_G_{tag}_630x500_thumb.png"), (x, 40 + 500 + 30 + 400 + 30))
        sh.paste(Image.open(B.OUT / f"cover_G_{tag}_960x400_thumb.png"), (x + 315 + g, 40 + 500 + 30 + 400 + 30))
    sh.save(B.OUT / "cover_G_A_vs_A2.png", optimize=True)
    print("ok", sh.size)


if __name__ == "__main__":
    main()
