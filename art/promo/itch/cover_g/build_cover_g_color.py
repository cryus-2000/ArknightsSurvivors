"""itch 封面 A′ 配色方向 C1 / C2 / C3：构图、人物、logo 排法全同 A′，只重做配色与色调。

做法（在 A 补光后、像素化前的图上）：
1. 按亮度做色阶映射（gradient map）到该方向的冷色阶：暗部 → 中间 → 亮部。
2. 保护：人物（按 A′ 里的位置画羽化椭圆）和高饱和非蓝色像素（灯火、绿裙、肤色、Mon3tr 金色刃光）
   按权重保留原色，只跟随整体明暗；人物设定色不变。
3. 灯火亮核按方向的暖色重新加一次，保证全图最亮点是灯；人物外圈加一圈该方向的冷色轮廓光。
4. 像素化（2×2 格、MAXCOVERAGE 96 色）+ A′ 的标题页排法 logo。
用法：python art/promo/itch/cover_g/build_cover_g_color.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402

W, H = 630, 500
LAMP = (283, 280)
# 人物椭圆（cx, cy, rx, ry, 名字）——A′ 成品坐标
FIGS = [(195, 385, 92, 70, "mizuki"), (245, 285, 48, 62, "doctor"), (328, 345, 92, 112, "kaltsit")]


def hx(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


SCHEMES = {
    "C1": {"name": "深海青 × 灯火金", "line": "背景压成青蓝三阶，灯火与暖光是唯一暖色，冷暖对比最强",
           "stops": ["#03101a", "#0b3346", "#1f6f80", "#7fe3ee"], "lamp": "#ffc061", "rim": "#7fe3ee",
           "keep": {"mizuki": 0.9, "doctor": 0.75, "kaltsit": 0.85}, "hue_keep": 0.85, "mix": 0.9,
           "pal": ["#03101a", "#1f6f80", "#7fe3ee", "#ffc061", "#f3efe6"]},
    "C2": {"name": "整体压冷，暖点只给灯与水月", "line": "背景与同伴降饱和成冷灰蓝，只留灯火暖金和水月的设定色",
           "stops": ["#06080f", "#18222f", "#3a4b5e", "#9fb0c0"], "lamp": "#ffb347", "rim": "#b8c8d8",
           "keep": {"mizuki": 0.95, "doctor": 0.25, "kaltsit": 0.3}, "hue_keep": 0.4, "mix": 0.95,
           "pal": ["#06080f", "#3a4b5e", "#9fb0c0", "#ffb347", "#c6b8ff"]},
    "C3": {"name": "青绿生物荧光", "line": "深渊偏墨绿，亮部是青绿荧光，灯火保留暖金作对比",
           "stops": ["#02100e", "#08332f", "#147a68", "#5ff2c4"], "lamp": "#ffd36a", "rim": "#5ff2c4",
           "keep": {"mizuki": 0.85, "doctor": 0.7, "kaltsit": 0.8}, "hue_keep": 0.8, "mix": 0.9,
           "pal": ["#02100e", "#147a68", "#5ff2c4", "#ffd36a", "#e6fff4"]},
}


def gradient_map(L, stops):
    cols = np.stack([hx(s) for s in stops])
    pos = np.linspace(0, 1, len(stops))
    out = np.zeros(L.shape + (3,), np.float32)
    for c in range(3):
        out[..., c] = np.interp(L, pos, cols[:, c])
    return out


def fig_masks():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ms = {}
    for cx, cy, rx, ry, n in FIGS:
        r = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
        ms[n] = np.clip((1.15 - r) / 0.3, 0, 1)
    return ms


def lit_A():
    p = B.PLANS["A"]
    raw = Image.open(B.RAW / p["cover"]).convert("RGB")
    c = B.crop_to(raw, W, H, p["fx_cover"], p["fy_cover"]).resize((W, H), Image.LANCZOS)
    lit, _ = B.relight(c, p["lamp"], 0.30)
    return np.asarray(lit, np.float32) / 255


def grade(a, s):
    L = (a * [0.299, 0.587, 0.114]).sum(-1)
    Ln = np.minimum(L * 1.35 / (L + 0.35), 0.8)  # 柔和提中间调，背景最亮封顶，灯火仍是最亮点
    mapped = gradient_map(Ln, s["stops"])
    # 高饱和非蓝色像素保色（灯火、绿裙、肤色、Mon3tr 刃光）
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / (mx + 1e-4)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    blue = (b >= r) & (b >= g * 0.95)
    hue_keep = np.where(~blue & (sat > 0.3) & (mx > 0.25), s["hue_keep"], 0.0)
    ms = fig_masks()
    keep = hue_keep
    for n, m in ms.items():
        keep = np.maximum(keep, m * s["keep"][n])
    # 保色区也跟着新色阶的明暗走一点，避免人物像贴上去
    tone = gradient_map(Ln, s["stops"]).mean(-1, keepdims=True) / (L[..., None] + 1e-3)
    tone = np.clip(tone, 0.7, 1.2)
    kept = np.clip(a * (0.75 + 0.25 * tone), 0, 1)
    out = mapped * s["mix"] + a * (1 - s["mix"])
    out = out * (1 - keep[..., None]) + kept * keep[..., None]
    # 海嗣眼点 / 冷光点：小块高亮青色 → 该方向的点缀亮色
    eyes = (b > 0.45) & (g > 0.4) & (r < 0.35) & (b - r > 0.25)
    em = Image.fromarray(eyes.astype(np.uint8) * 255)
    large = np.asarray(em.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(9)), bool)  # 大片冷光区不算眼点
    eyes &= ~large
    out[eyes] = np.clip(hx(s["rim"]) * 1.1, 0, 1)
    # 人物冷色轮廓光：人物椭圆的外环，亮像素边缘上一层
    allm = np.maximum.reduce(list(ms.values()))
    edge = np.asarray(Image.fromarray((L * 255).astype(np.uint8)).filter(ImageFilter.FIND_EDGES), np.float32) / 255
    ring = np.clip(allm * 2, 0, 1) * (1 - np.clip(allm * 1.4 - 0.4, 0, 1))
    out = out + (np.clip(edge * 2.5, 0, 1) * ring * 0.35)[..., None] * hx(s["rim"])
    # 灯火亮核 + 暖晕（该方向的暖色）
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d2 = ((xx - LAMP[0]) ** 2 + (yy - LAMP[1]) ** 2) / (W * W)
    warm = hx(s["lamp"])
    out = out * (1 + (0.25 * np.exp(-d2 / (2 * 0.1 ** 2)))[..., None] * (warm - 0.35))
    out = out + (0.7 * np.exp(-d2 / (2 * 0.012 ** 2)))[..., None] * warm
    return np.clip(out, 0, 1)


def build(key):
    a = grade(lit_A(), SCHEMES[key])
    img = Image.fromarray((a * 255).astype(np.uint8))
    bg = np.asarray(B.pixelize(img, (W, H)).resize((W, H), Image.NEAREST)).copy()
    rgb, cov, padt = A2.logo_block(W)
    hb, wb = cov.shape
    x0 = (W - 482) // 2
    x0 -= x0 % 2
    reg = bg[0:hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return Image.fromarray(bg)


def main():
    font = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 20)
    small = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 15)
    g = 20
    cols = [("A2", None)] + [(k, SCHEMES[k]) for k in SCHEMES]
    Wsh = 4 * W + 5 * g
    Hsh = 44 + H + g + 250 + 40
    sh = Image.new("RGB", (Wsh, Hsh), (14, 18, 26))
    d = ImageDraw.Draw(sh)
    for i, (k, s) in enumerate(cols):
        if s is None:
            im = Image.open(HERE / "cover_G_A2_630x500.png").convert("RGB")
            title, line, pal = "A2（现配色，参照）", "Toy 原色调 + 补光", []
        else:
            im = build(k)
            im.save(HERE / f"cover_G_A2{k}_630x500.png", optimize=True)
            title, line, pal = f"{k}  {s['name']}", s["line"], s["pal"]
        th = im.resize((315, 250), Image.BOX)
        if s is not None:
            th.save(HERE / f"cover_G_A2{k}_630x500_thumb.png", optimize=True)
        x = g + i * (W + g)
        d.text((x, 10), title, font=font, fill=(225, 233, 238))
        sh.paste(im, (x, 44))
        y = 44 + H + g
        sh.paste(th, (x, y))
        for j, c in enumerate(pal):
            yy = y + j * 50
            d.rectangle((x + 331, yy, x + 371, yy + 40), fill=c, outline=(60, 70, 80))
            d.text((x + 381, yy + 10), c, font=small, fill=(200, 210, 218))
        d.text((x, y + 256), line, font=small, fill=(200, 210, 218))
    sh.save(HERE / "cover_G_A2_color_compare.png", optimize=True)
    print("ok", sh.size)


if __name__ == "__main__":
    main()
