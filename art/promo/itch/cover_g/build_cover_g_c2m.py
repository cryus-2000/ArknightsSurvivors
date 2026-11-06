"""itch 封面 C2m（11-06 用户：回到 C2，只改水月的颜色，让她和 C2 的整体色调统一）。

除水月以外和 C2 完全一样（同一个 grade，同一套参数）。水月的改动：
1. 保色范围从「椭圆」收紧到「椭圆 ∩ 人物剪影」（Gemini 黑白遮罩 build/imagegen/itchg_mask2，不进 git）：
   C2 里她身后那块原蓝背景也被保了下来，形成一团跳出来的蓝晕；现在背景照 C2 的冷灰蓝阶梯走。
2. 她本人：色相往 C2 的冷调（约 214°）转一部分，饱和度、明度都不降；
   黄色领边、粉红瞳色等暖色不转（只转 180°–300° 的冷色段：淡紫发、深蓝外套、伞），保持设定色。
3. 亮部加一点 C2 色板的冷白（#c8d4e0）分离色调，和同伴、背景的高光同一个色温。
用法：python art/promo/itch/cover_g/build_cover_g_c2m.py
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402
import build_cover_g_color as CC  # noqa: E402

W, H = CC.W, CC.H
TARGET_HUE = 214 / 360
HUE_AMT = 0.45
HI_TINT = CC.hx("#c8d4e0")


def silhouette():
    mk = Image.open(sorted((B.RAW / "itchg_mask2").glob("raw_*.png"))[0]).convert("L").resize((W, H), Image.BILINEAR)
    mk = mk.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.8))
    return np.asarray(mk, np.float32) / 255


def rgb_to_hsv(a):
    im = Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8)).convert("HSV")
    return np.asarray(im, np.float32) / 255


def hsv_to_rgb(h):
    im = Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8), "HSV").convert("RGB")
    return np.asarray(im, np.float32) / 255


def build():
    sil = silhouette()
    base_masks = CC.fig_masks

    def masks():
        ms = base_masks()
        ms["mizuki"] = ms["mizuki"] * sil
        return ms

    CC.fig_masks = masks
    try:
        out = CC.grade(CC.lit_A(), CC.SCHEMES["C2"])
    finally:
        CC.fig_masks = base_masks
    mz = masks()["mizuki"]

    # 水月本人：冷色段色相往 214° 转，饱和 / 明度不动
    hsv = rgb_to_hsv(out)
    h = hsv[..., 0]
    cold = (h > 180 / 360) & (h < 300 / 360)
    dh = (TARGET_HUE - h)
    h2 = np.where(cold, h + dh * HUE_AMT * mz, h)
    hsv2 = hsv.copy()
    hsv2[..., 0] = h2
    rgb = hsv_to_rgb(hsv2)
    # 亮部冷白分离色调（只在她身上）
    L = (rgb * [0.299, 0.587, 0.114]).sum(-1, keepdims=True)
    hi = np.clip((L - 0.55) / 0.35, 0, 1) * 0.25 * mz[..., None]
    rgb = rgb * (1 - hi) + (HI_TINT * np.maximum(L, 0.6)) * hi
    out = np.where(mz[..., None] > 0.01, rgb, out)

    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))
    new = np.asarray(B.pixelize(img, (W, H)).resize((W, H), Image.NEAREST))
    # 水月椭圆（含 C2 的蓝晕范围）以外直接用 C2 原像素，保证其余部分与 C2 逐像素一致
    c2 = np.asarray(Image.open(HERE / "cover_G_A2C2_630x500.png").convert("RGB"))
    cx, cy, rx, ry, _ = CC.FIGS[0]
    yy, xx = np.mgrid[0:H, 0:W]
    yy, xx = (yy // B.CELL) * B.CELL, (xx // B.CELL) * B.CELL  # 按像素格切，不切碎格子
    region = ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 < 1.2 ** 2
    bg = np.where(region[..., None], new, c2).copy()
    return Image.fromarray(bg)  # logo 在 C2 原图里已有（水月区不碰标题区）


def main():
    im = build()
    im.save(HERE / "cover_G_A2C2m_630x500.png", optimize=True)
    im.resize((315, 250), Image.BOX).save(HERE / "cover_G_A2C2m_630x500_thumb.png", optimize=True)
    old = Image.open(HERE / "cover_G_A2C2_630x500.png").convert("RGB")
    font = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 20)
    g = 20
    sh = Image.new("RGB", (2 * W + 3 * g, 44 + H + g + 250 + 20), (14, 18, 26))
    d = ImageDraw.Draw(sh)
    for i, (lab, x_im) in enumerate((("C2", old), ("C2m（只调水月：去掉身后蓝晕，冷色段色相往 C2 冷调靠）", im))):
        x = g + i * (W + g)
        d.text((x, 10), lab, font=font, fill=(225, 233, 238))
        sh.paste(x_im, (x, 44))
        sh.paste(x_im.resize((315, 250), Image.BOX), (x, 44 + H + g))
        sh.paste(x_im.crop((100, 300, 300, 500)).resize((250, 250), Image.NEAREST), (x + 315 + g, 44 + H + g))
    sh.save(HERE / "cover_G_C2_vs_C2m.png", optimize=True)
    print("ok", sh.size)


if __name__ == "__main__":
    main()
