"""itch / Toy 封面 C2L（11-07 用户：「C2，但是暖点只保留灯我觉得最好」）：
C2 配色（整体压冷灰蓝、同伴降饱和），水月也和同伴一样降饱和，高饱和暖色只留提灯一处。
一次出三张：itch 封面 630×500、itch 横幅 960×400、Toy 1200×900（在 600×450 上做完再最近邻 ×2，像素格 4×4）。
另加「明日方舟同人」（右下角，ui.ttf 二值化）。
人物 / 灯的位置：C2 的 FIGS 是封面坐标，这里先换回生图原图坐标，再换到各成品；
横幅生图（itchg_Aw）是封面生图外扩的，用模板匹配测得 = 封面生图 × 0.75 + (684, 0)。
用法：python art/promo/itch/cover_g/build_cover_g_c2l.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402
import build_cover_g_color as CO  # noqa: E402

OUT_DIR = HERE
NOTICE = "明日方舟同人 · Arknights fan work"   # 11-07 用户：「非官方去掉」「明日方舟同人也要用双语」；英文沿用 promo_keyart 的 fan work
SCHEME = dict(CO.SCHEMES["C2"])
SCHEME.update({"name": "C2L 整体压冷，暖点只留灯",
               "keep": {"mizuki": 0.3, "doctor": 0.25, "kaltsit": 0.3}, "hue_keep": 0.12})
# 输出：(名字, 制作尺寸, 放大倍数, 生图键, fx, fy, 标题区压暗, logo 顶边)
OUTS = [("itch_cover", (630, 500), 1, "cover", 0.42, 0.55, 0.30, 16),
        ("itch_banner", (960, 400), 1, "banner", 0.47, 0.55, 0.36, 12),
        ("toy_poster", (1200, 900), 2, "cover", 0.42, 0.55, 0.30, 14)]   # Toy：1200×900 直接做（像素格 2），logo / 标注 ×2
AW_SCALE, AW_OFF = 0.75, (684, 0)


def crop_box(im, w, h, fx, fy):
    W, H = im.size
    r = w / h
    if W / H > r:
        cw, ch = int(round(H * r)), H
    else:
        cw, ch = W, int(round(W / r))
    x = int(np.clip(fx * W - cw / 2, 0, W - cw))
    y = int(np.clip(fy * H - ch / 2, 0, H - ch))
    return x, y, cw, ch


def figs_raw():
    """C2 的封面坐标 → 封面生图坐标"""
    raw = Image.open(B.RAW / B.PLANS["A"]["cover"])
    x, y, cw, ch = crop_box(raw, 630, 500, 0.42, 0.55)
    s = 630 / cw
    return [((cx / s) + x, (cy / s) + y, rx / s, ry / s, n) for cx, cy, rx, ry, n in CO.FIGS]


def grade(a, figs, lamp):
    """同 build_cover_g_color.grade，尺寸 / 人物椭圆 / 灯位置按参数给"""
    s = SCHEME
    H, W = a.shape[:2]
    L = (a * [0.299, 0.587, 0.114]).sum(-1)
    Ln = np.minimum(L * 1.35 / (L + 0.35), 0.8)
    mapped = CO.gradient_map(Ln, s["stops"])
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / (mx + 1e-4)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    blue = (b >= r) & (b >= g * 0.95)
    hue_keep = np.where(~blue & (sat > 0.3) & (mx > 0.25), s["hue_keep"], 0.0)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ms = {}
    for cx, cy, rx, ry, n in figs:
        rr = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
        ms[n] = np.clip((1.15 - rr) / 0.3, 0, 1)
    keep = hue_keep
    for n, m in ms.items():
        keep = np.maximum(keep, m * s["keep"][n])
    tone = mapped.mean(-1, keepdims=True) / (L[..., None] + 1e-3)
    tone = np.clip(tone, 0.7, 1.2)
    kept = np.clip(a * (0.75 + 0.25 * tone), 0, 1)
    out = mapped * s["mix"] + a * (1 - s["mix"])
    # 人物（11-07 修细节）：不走压缩过的色阶映射（会把白大衣 / 脸的亮部压平），
    # 用原亮度做冷灰（只降饱和、往冷灰蓝偏），再按 keep 混回原色 —— 明暗层次全保留
    figm = np.clip(np.maximum.reduce(list(ms.values())) * 1.6, 0, 1)
    cool = CO.hx("#b8c8d8")
    cool = cool / (cool * [0.299, 0.587, 0.114]).sum()
    Lf = np.clip(L * 0.92, 0, 1)
    desat = np.clip(Lf[..., None] * cool, 0, 1) * 0.75 + a * 0.25
    fig_out = desat * (1 - keep[..., None]) + kept * keep[..., None]
    bg_out = out * (1 - keep[..., None]) + kept * keep[..., None]
    out = bg_out * (1 - figm[..., None]) + fig_out * figm[..., None]
    eyes = (b > 0.45) & (g > 0.4) & (r < 0.35) & (b - r > 0.25)
    em = Image.fromarray(eyes.astype(np.uint8) * 255)
    k7 = max(3, int(round(7 * W / 630)) | 1)
    k9 = max(3, int(round(9 * W / 630)) | 1)
    large = np.asarray(em.filter(ImageFilter.MinFilter(k7)).filter(ImageFilter.MaxFilter(k9)), bool)
    eyes &= ~large
    out[eyes] = np.clip(CO.hx(s["rim"]) * 1.1, 0, 1)
    allm = np.maximum.reduce(list(ms.values()))
    edge = np.asarray(Image.fromarray((L * 255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES), np.float32) / 255
    ring = np.clip(allm * 2, 0, 1) * (1 - np.clip(allm * 1.4 - 0.4, 0, 1))
    out = out + (np.clip(edge * 2.5, 0, 1) * ring * 0.15)[..., None] * CO.hx(s["rim"])
    # 灯火亮核 + 暖晕：半径按成品宽归一（与 C2 相同的相对大小）
    d2 = ((xx - lamp[0]) ** 2 + (yy - lamp[1]) ** 2) / (W * W) * (W / 630) ** 2 * (630 / W) ** 2
    warm = CO.hx(s["lamp"])
    out = out * (1 + (0.25 * np.exp(-d2 / (2 * 0.1 ** 2)))[..., None] * (warm - 0.35))
    out = out + (0.7 * np.exp(-d2 / (2 * 0.012 ** 2)))[..., None] * warm
    return np.clip(out, 0, 1), figm


BAYER = (np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], np.float32) + 0.5) / 16 - 0.5


def despeckle(q, protect, rounds=3, thr=24):
    """去麻点（11-07 用户嫌脏，实测孤立像素 7%，游戏内像素画 0.2%）：
    与上下左右都明显不同的单个像素，改成 3×3 邻域里最多的颜色；protect 处（人物亮点 / 眼睛 / 灯）不动"""
    a = q.astype(np.int32)
    H, W = a.shape[:2]
    key = (a[..., 0] << 16) | (a[..., 1] << 8) | a[..., 2]
    for _ in range(rounds):
        p = np.pad(a, ((1, 1), (1, 1), (0, 0)), mode="edge")
        kp = np.pad(key, 1, mode="edge")
        c = p[1:-1, 1:-1]
        nb = [p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]]
        iso = np.logical_and.reduce([np.abs(c - b).sum(-1) > thr for b in nb]) & ~protect
        if not iso.any():
            break
        ys, xs = np.nonzero(iso)
        for y, x in zip(ys, xs):
            win = kp[y:y + 3, x:x + 3].ravel()
            win = np.delete(win, 4)
            v, n = np.unique(win, return_counts=True)
            k = v[np.argmax(n)]
            key[y, x] = k
            a[y, x] = ((k >> 16) & 255, (k >> 8) & 255, k & 255)
    return a.astype(np.uint8)


def pixelize2(img, figm, cell):
    """11-07 修色彩断层：背景加 4×4 有序抖动再收 96 色；人物（figm）不抖动、单独收 96 色、先轻锐化保细节"""
    W, H = img.size
    w, h = W // cell, H // cell
    small = img.resize((w, h), Image.BOX)
    sharp = img.filter(ImageFilter.UnsharpMask(radius=1.2, percent=60, threshold=2)).resize((w, h), Image.BOX)
    fm = np.asarray(Image.fromarray((figm * 255).astype(np.uint8)).resize((w, h), Image.BOX), np.float32) / 255 > 0.5
    # 11-07 用户嫌脏：不再抖动（点阵本身就是颗粒），改为背景先 3×3 中值去噪、多收颜色（160）来消色带
    ad = np.asarray(small.filter(ImageFilter.MedianFilter(3)))
    q = lambda im, n, mask=None: np.asarray(Image.fromarray(im).quantize(colors=n, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE, kmeans=3).convert("RGB"))
    bgq = q(ad, 160)
    fa = np.asarray(sharp)
    fq = q(fa, 96)
    out = bgq.copy()
    out[fm] = fq[fm]
    # 保护：人物区里的亮点 / 高饱和点（眼睛、高光）、全图最亮的灯芯
    lum = (out.astype(np.float32) * [0.299, 0.587, 0.114]).sum(-1)
    mxc, mnc = out.max(-1).astype(np.float32), out.min(-1).astype(np.float32)
    satc = (mxc - mnc) / (mxc + 1)
    protect = (fm & ((lum > 200) | (satc > 0.45))) | (lum > 235)
    out = despeckle(out, protect)
    return Image.fromarray(out).resize((W, H), Image.NEAREST)


def notice_layer(img, scale):
    f = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 12)
    bb = f.getbbox(NOTICE)
    w, h = bb[2] - bb[0] + 4, bb[3] - bb[1] + 4
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    d.fontmode = "1"
    d.text((2 - bb[0], 2 - bb[1]), NOTICE, font=f, fill=255)
    face = np.asarray(m) > 127
    ol = B.dilate(face, 1) & ~face
    if scale > 1:
        face = np.kron(face, np.ones((scale, scale), bool))
        ol = np.kron(ol, np.ones((scale, scale), bool))
        h, w = face.shape
    W, H = img.size
    a = np.asarray(img).copy()
    x0, y0 = W - w - 6 * scale, H - h - 4 * scale
    reg = a[y0:y0 + h, x0:x0 + w]
    reg[ol] = A2.INK
    reg[face] = (200, 214, 224)
    return Image.fromarray(a)


def build(name, size, up, key, fx, fy, top, logo_y):
    """up：logo 与标注的放大倍数（Toy 为 2）"""
    W, H = size
    raw = Image.open(B.RAW / B.PLANS["A"][key]).convert("RGB")
    x, y, cw, ch = crop_box(raw, W, H, fx, fy)
    c = raw.crop((x, y, x + cw, y + ch)).resize((W, H), Image.LANCZOS)
    s = W / cw
    figs = []
    for rx_, ry_, rrx, rry, n in figs_raw():
        if key == "banner":
            rx_, ry_, rrx, rry = rx_ * AW_SCALE + AW_OFF[0], ry_ * AW_SCALE + AW_OFF[1], rrx * AW_SCALE, rry * AW_SCALE
        figs.append(((rx_ - x) * s, (ry_ - y) * s, rrx * s, rry * s, n))
    lit, lamp = B.relight(c, B.PLANS["A"]["lamp"], top)
    a, figm = grade(np.asarray(lit, np.float32) / 255, figs, lamp)
    img = Image.fromarray((a * 255).astype(np.uint8))
    bg = np.asarray(pixelize2(img, figm, B.CELL)).copy()
    rgb, cov, padt = A2.logo_block(482)
    if up > 1:
        rgb = np.kron(rgb, np.ones((up, up, 1), np.uint8))
        cov = np.kron(cov, np.ones((up, up), bool))
        padt *= up
    hb, wb = cov.shape
    x0 = (W - 482 * up) // 2
    x0 -= x0 % 2
    y0 = max(logo_y * up - padt, 0)
    reg = bg[y0:y0 + hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return notice_layer(Image.fromarray(bg), up)


def main():
    outs = {}
    for o in OUTS:
        im = build(*o)
        p = OUT_DIR / f"cover_G_A2C2L_{o[0]}_{im.width}x{im.height}.png"
        im.save(p, optimize=True)
        outs[o[0]] = im
        print(p.name)
    return outs


if __name__ == "__main__":
    main()
