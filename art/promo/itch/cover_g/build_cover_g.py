"""itch 封面 G（基于 Toy shadow_1014）后期：裁切 → 补光影 → 像素化收色 → 叠标题页 logo → 出成品 / 缩略 / 对照。

原始生图在 build/imagegen/itchg_*（不进 git）。用法：python art/promo/itch/cover_g/build_cover_g.py
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[4]
RAW = ROOT / "build" / "imagegen"
OUT = Path(__file__).resolve().parent
LOGO = ROOT / "game/art/ui/title_deep/logo_mark.png"
FONT = ROOT / "game/fonts/montserrat_bold.ttf"
TOY = ROOT / "art/promo/toy/toy_poster_shadow_1014_4x3.png"
CELL = 2           # 成品 1 个像素格 = 2×2（与 logo_mark 的 2 像素格一致）
COLORS = 96

# 方案：原图、焦点（裁切时尽量保留的中心，0–1）、灯光强度
PLANS = {
    "A": {"cover": "itchg_A/raw_1793882271_0.png", "banner": "itchg_Aw/raw_1793882579_0.png",
          "fx_cover": 0.42, "fy_cover": 0.55, "fx_banner": 0.47, "fy_banner": 0.55, "lamp": 1.0},
    "B": {"cover": "itchg_B/raw_1793882270_0.png", "banner": "itchg_Bw/raw_1793882516_0.png",
          "fx_cover": 0.5, "fy_cover": 0.6, "fx_banner": 0.47, "fy_banner": 0.6, "lamp": 0.8},
    "C": {"cover": "itchg_C/raw_1793882402_0.png", "banner": "itchg_Cw/raw_1793882637_0.png",
          "fx_cover": 0.42, "fy_cover": 0.6, "fx_banner": 0.5, "fy_banner": 0.6, "lamp": 0.55},
}
SIZES = {"cover": (630, 500), "banner": (960, 400)}


def crop_to(im, w, h, fx, fy):
    W, H = im.size
    r = w / h
    if W / H > r:
        cw, ch = int(round(H * r)), H
    else:
        cw, ch = W, int(round(W / r))
    x = int(np.clip(fx * W - cw / 2, 0, W - cw))
    y = int(np.clip(fy * H - ch / 2, 0, H - ch))
    return im.crop((x, y, x + cw, y + ch))


def find_lamp(a):
    """灯火 = 暖色且最亮的一团：R+G-B 的模糊最大值。"""
    warm = np.clip(a[..., 0] + 0.8 * a[..., 1] - 1.2 * a[..., 2], 0, None)
    im = Image.fromarray((warm / max(warm.max(), 1e-6) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    w = np.asarray(im, dtype=np.float32)
    y, x = np.unravel_index(np.argmax(w), w.shape)
    return x, y


def relight(img, lamp_k, top_band):
    a = np.asarray(img, dtype=np.float32) / 255.0
    h, w = a.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    lx, ly = find_lamp(a)
    d2 = ((xx - lx) ** 2 + (yy - ly) ** 2) / (w * w)
    # 1) 暖金灯光：大范围柔光照亮人物正面与地面 + 灯芯小核，灯火是全图最亮点
    warm = np.array([1.0, 0.72, 0.32], np.float32)
    # 大范围用乘法小幅提亮（保留设定色相，不把发色 / 衣服洗成米白），只有灯芯一小团用加法做全图最亮点
    broad = lamp_k * (0.22 * np.exp(-d2 / (2 * 0.12 ** 2)))
    gy = ((xx - lx) ** 2 / (w * 0.16) ** 2 + (yy - (ly + 0.28 * h)) ** 2 / (h * 0.09) ** 2)
    broad += lamp_k * 0.12 * np.exp(-gy)  # 灯下地面光池
    gain = 1.0 + broad[..., None] * np.array([0.9, 0.55, 0.15], np.float32)
    a = a * gain
    core = lamp_k * 0.6 * np.exp(-d2 / (2 * 0.012 ** 2))
    a = a + core[..., None] * warm
    # 2) 对比提一档（以 0.35 为中点的 S 曲线）
    a = np.clip(a, 0, 1.2)
    a = 0.35 + (a - 0.35) * 1.18
    # 3) 前景压暗：四角暗角 + 底边压黑；冷色偏移让暗部偏深蓝
    r = np.sqrt(((xx - w / 2) / (w / 2)) ** 2 + ((yy - h * 0.45) / (h / 2)) ** 2)
    vig = np.clip(1.0 - 0.55 * np.clip(r - 0.55, 0, None) ** 1.4, 0.25, 1)
    bottom = np.clip(1.0 - 0.5 * np.clip((yy / h - 0.82) / 0.18, 0, 1), 0, 1)
    a = a * (vig * bottom)[..., None]
    # 4) 标题区上方压暗一条，logo 缩略时也读得清
    if top_band:
        band = 1.0 - 0.38 * np.clip(1.0 - yy / (h * top_band), 0, 1) ** 1.5
        a = a * band[..., None]
    a = np.clip(a, 0, 1)
    # 暗部偏冷：低亮度区域往 #0a1630 靠
    lum = (a * [0.3, 0.59, 0.11]).sum(-1, keepdims=True)
    cold = np.array([0.04, 0.09, 0.19], np.float32)
    t = np.clip(1 - lum / 0.18, 0, 1) * 0.35
    a = a * (1 - t) + cold * t
    return Image.fromarray((a * 255).astype(np.uint8)), (lx, ly)


def pixelize(img, size):
    W, H = size
    small = img.resize((W // CELL, H // CELL), Image.BOX)
    q = small.quantize(colors=COLORS, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE, kmeans=3).convert("RGB")
    return q


def dilate(mask, n):
    m = mask.copy()
    for _ in range(n):
        p = np.pad(m, 1)
        m = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    return m


def logo_layer(native_w, scale_cells):
    """标题页 logo_mark（2 像素格）按原生格缩一半：1 格 = 1 原生像素，再按 scale_cells 整数放大。"""
    lg = Image.open(LOGO).convert("RGBA")
    m = np.asarray(lg)[..., 3][::2, ::2] > 127  # 原生格
    m = np.kron(m, np.ones((scale_cells, scale_cells), bool)) if scale_cells > 1 else m
    h, w = m.shape
    pad = 6
    M = np.pad(m, pad)
    H2, W2 = M.shape
    out = np.zeros((H2, W2, 4), np.uint8)
    glow2 = dilate(M, 4) & ~dilate(M, 2)
    glow1 = dilate(M, 2) & ~dilate(M, 1)
    outline = dilate(M, 1) & ~M
    shadow = np.roll(dilate(M, 1), 2, axis=0) & ~dilate(M, 1)
    out[glow2] = (40, 140, 170, 70)
    out[glow1] = (70, 190, 215, 130)
    out[shadow] = (4, 8, 18, 255)
    out[outline] = (6, 12, 24, 255)
    # 字面：上亮下青的两段渐变（硬分段，不平滑）
    ys = np.arange(H2)[:, None].repeat(W2, 1)
    rel = (ys - pad) / max(h, 1)
    face = np.where(rel[..., None] < 0.55, np.array([236, 244, 246], np.uint8), np.array([157, 229, 239], np.uint8))
    out[M, :3] = face[M]
    out[M, 3] = 255
    return Image.fromarray(out, "RGBA")


def subtitle_layer(text, px):
    f = ImageFont.truetype(str(FONT), px)
    tw = int(f.getlength(text) + len(text) * 1.5) + 8
    im = Image.new("L", (tw, px + 8), 0)
    d = ImageDraw.Draw(im)
    x = 4
    for ch in text:
        d.text((x, 2), ch, font=f, fill=255)
        x += f.getlength(ch) + 1.5
    m = np.asarray(im) > 110
    M = np.pad(m, 2)
    out = np.zeros(M.shape + (4,), np.uint8)
    o = dilate(M, 1) & ~M
    out[o] = (6, 12, 24, 230)
    out[M] = (255, 196, 92, 255)
    return Image.fromarray(out, "RGBA")


def build(plan, kind):
    p = PLANS[plan]
    W, H = SIZES[kind]
    raw = Image.open(RAW / p[kind]).convert("RGB")
    c = crop_to(raw, W, H, p["fx_" + kind], p["fy_" + kind])
    c = c.resize((W, H), Image.LANCZOS)
    lit, lamp = relight(c, p["lamp"], 0.30 if kind == "cover" else 0.36)
    nat = pixelize(lit, (W, H))  # 原生分辨率（= 缩略预览尺寸）
    nw, nh = nat.size
    canvas = nat.convert("RGBA")
    lg = logo_layer(nw, 1)
    sub = subtitle_layer("ARKNIGHTS SURVIVORS", 8)
    if kind == "cover":
        lx, ly = (nw - lg.width) // 2, 8
    else:
        lx, ly = (nw - lg.width) // 2, 6
    canvas.alpha_composite(lg, (lx, ly))
    canvas.alpha_composite(sub, ((nw - sub.width) // 2 + 10, ly + lg.height - 4))
    full = canvas.convert("RGB").resize((W, H), Image.NEAREST)
    return full, lamp


def main():
    outs = {}
    for plan in PLANS:
        for kind in SIZES:
            img, lamp = build(plan, kind)
            W, H = SIZES[kind]
            name = f"cover_G{plan}_{W}x{H}"
            img.save(OUT / f"{name}.png", optimize=True)
            tw = 315
            th = int(round(H * tw / W))
            img.resize((tw, th), Image.BOX).save(OUT / f"{name}_thumb.png", optimize=True)
            outs[(plan, kind)] = img
            print(name, "lamp(native)", lamp)
    # 对照：原 Toy | A | B | C 封面；下一行横幅；最下一行缩略
    toy = Image.open(TOY).convert("RGB").resize((630, 473), Image.LANCZOS)
    g = 16
    Wsheet = 4 * 630 + 5 * g
    covers_h = 500
    ban_w = (Wsheet - 4 * g) // 3
    ban_h = int(ban_w * 400 / 960)
    thumbs_h = 250
    Hs = 40 + covers_h + 40 + ban_h + 40 + thumbs_h + g
    sheet = Image.new("RGB", (Wsheet, Hs), (14, 18, 26))
    d = ImageDraw.Draw(sheet)
    fnt = ImageFont.truetype(str(ROOT / "game/fonts/ui.ttf"), 22)
    labels = ["原 Toy 封面 shadow_1014", "方案 A 原构图补光", "方案 B 水月放大三角站位", "方案 C 灯光推开海嗣"]
    for i, lab in enumerate(labels):
        x = g + i * (630 + g)
        d.text((x, 8), lab, font=fnt, fill=(220, 230, 235))
        im = toy if i == 0 else outs[("ABC"[i - 1], "cover")]
        sheet.paste(im, (x, 40 + (covers_h - im.height) // 2))
    y = 40 + covers_h + 10
    d.text((g, y), "横幅 960×400（缩小显示）", font=fnt, fill=(220, 230, 235))
    for i, plan in enumerate("ABC"):
        sheet.paste(outs[(plan, "banner")].resize((ban_w, ban_h), Image.BOX), (g + i * (ban_w + g), y + 30))
    y = y + 30 + ban_h + 10
    d.text((g, y), "列表缩略 315×250 / 315×131（实际大小）", font=fnt, fill=(220, 230, 235))
    x = g
    for i, plan in enumerate("ABC"):
        t = Image.open(OUT / f"cover_G{plan}_630x500_thumb.png")
        sheet.paste(t, (x, y + 30))
        x += t.width + g
    sheet.paste(toy.resize((315, 236), Image.BOX), (x, y + 30))
    sheet.save(OUT / "cover_G_compare.png", optimize=True)
    print("compare", sheet.size)


if __name__ == "__main__":
    main()
