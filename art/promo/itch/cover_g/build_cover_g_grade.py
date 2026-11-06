"""itch 封面 A′ 全局调色 G1 / G2 / G3（11-06 用户：在最开始的版本上重新调色，全局调色）。

底图 = A′ 的背景层（build_cover_g_a2.background，像素化后、叠 logo 前），整张套同一个调色函数，
不用遮罩、不对单个人物单独改；调完再叠 A′ 的标题页排法 logo（logo 颜色保持与游戏一致，不参与调色）。
调色函数是逐颜色的 LUT（输入色 → 输出色），像素化后的 96 色各自映射，不产生新色带。

步骤（参数见 GRADES）：
1. 冷色段（色相 180°–280°，羽化 20°）：饱和度 × sat，色相往 HUE（214°，C2 的冷灰蓝）拉 pull。
2. 暖色段（0°–70°）不动（灯火、肤色、绿裙、黄领边保持暖）。
3. 分离色调：暗部加 shadow 色（冷灰蓝），亮部加 high 色（冷白），强度 split。
4. 明度保持：调完按原像素的亮度（Rec.601 luma）把颜色缩放回去，整体不压暗。
用法：python art/promo/itch/cover_g/build_cover_g_grade.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402

HUE = 214.0
GRADES = {
    "G1": {"name": "弱", "sat": 0.75, "pull": 0.30, "split": 0.10, "shadow": "#1a2a3c", "high": "#dfe8f0"},
    "G2": {"name": "中", "sat": 0.58, "pull": 0.50, "split": 0.16, "shadow": "#18222e", "high": "#dfe8f0"},
    "G3": {"name": "强", "sat": 0.42, "pull": 0.70, "split": 0.22, "shadow": "#141c26", "high": "#e2e8ee"},
}


def hx(s):
    s = s.lstrip("#")
    return np.array([int(s[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255


def rgb2hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx, mn = c.max(-1), c.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    m = d > 1e-6
    rm = m & (mx == r)
    gm = m & (mx == g) & ~rm
    bm = m & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    h = h * 60.0
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0)
    return h, s, mx


def hsv2rgb(h, s, v):
    h = (h % 360) / 60.0
    i = np.floor(h).astype(int) % 6
    f = h - np.floor(h)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    out = np.zeros(h.shape + (3,), np.float32)
    for k, (R, G, Bc) in enumerate(((v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q))):
        sel = i == k
        out[sel] = np.stack([R[sel], G[sel], Bc[sel]], -1)
    return out


def band(h, lo, hi, feather):
    """色相落在 [lo, hi] 的权重，两端各羽化 feather 度。"""
    a = np.clip((h - (lo - feather)) / feather, 0, 1)
    b = np.clip(((hi + feather) - h) / feather, 0, 1)
    return np.minimum(a, b)


def grade(c, p):
    luma0 = (c * [0.299, 0.587, 0.114]).sum(-1)
    h, s, v = rgb2hsv(c)
    w = band(h, 180, 280, 20)
    s2 = s * (1 - w * (1 - p["sat"]))
    dh = ((HUE - h + 180) % 360) - 180
    h2 = h + dh * p["pull"] * w
    out = hsv2rgb(h2, s2, v)
    # 分离色调：暗部偏冷灰蓝、亮部偏冷白
    t_sh = np.clip(1 - luma0 / 0.45, 0, 1)[..., None]
    t_hi = np.clip((luma0 - 0.55) / 0.4, 0, 1)[..., None]
    out = out * (1 - p["split"] * t_sh) + hx(p["shadow"]) * (p["split"] * t_sh) * 2.2
    out = out * (1 - p["split"] * t_hi) + hx(p["high"]) * (p["split"] * t_hi)
    # 明度保持
    luma1 = (out * [0.299, 0.587, 0.114]).sum(-1)
    out = out * (luma0 / np.maximum(luma1, 1e-4))[..., None]
    return np.clip(out, 0, 1)


def apply_lut(img, p):
    a = np.asarray(img.convert("RGB"))
    cols, inv = np.unique(a.reshape(-1, 3), axis=0, return_inverse=True)
    mapped = (grade(cols.astype(np.float32) / 255, p) * 255 + 0.5).astype(np.uint8)
    return mapped[inv.reshape(-1)].reshape(a.shape), len(cols)


def with_logo(arr):
    bg = arr.copy()
    W = bg.shape[1]
    rgb, cov, _ = A2.logo_block(W)
    hb, wb = cov.shape
    x0 = (W - 482) // 2
    x0 -= x0 % 2
    reg = bg[0:hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return Image.fromarray(bg)


def main():
    base = A2.background("cover")
    W, H = base.size
    ims = [("A2（A′）原色", Image.open(HERE / "cover_G_A2_630x500.png").convert("RGB"))]
    for k, p in GRADES.items():
        arr, n = apply_lut(base, p)
        im = with_logo(arr)
        im.save(HERE / f"cover_G_A2{k}_630x500.png", optimize=True)
        im.resize((315, 250), Image.BOX).save(HERE / f"cover_G_A2{k}_630x500_thumb.png", optimize=True)
        ims.append((f"{k} {p['name']}（冷段饱和×{p['sat']}，色相拉 {int(p['pull'] * 100)}%，分离 {p['split']}）", im))
        print(k, "colors", n)
    font = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 18)
    g = 20
    sh = Image.new("RGB", (len(ims) * (W + g) + g, 44 + H + g + 250 + g), (14, 18, 26))
    d = ImageDraw.Draw(sh)
    for i, (lab, im) in enumerate(ims):
        x = g + i * (W + g)
        d.text((x, 12), lab, font=font, fill=(225, 233, 238))
        sh.paste(im, (x, 44))
        sh.paste(im.resize((315, 250), Image.BOX), (x, 44 + H + g))
        sh.paste(im.crop((120, 230, 435, 480)), (x + 315, 44 + H + g))
    sh.save(HERE / "cover_G_A2_grade_compare.png", optimize=True)
    print("ok", sh.size)


if __name__ == "__main__":
    main()
