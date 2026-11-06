"""itch 封面 A′ 配色 C2b（C2 改版，11-06 用户：整体压暗、去掉降饱和造成的色散）。

和 C2 的区别：
- 背景不再「色阶映射 + 混一点原色」，而是纯粹的单色相冷灰蓝明度阶梯（12 阶，色相 ~215° 一条线），
  背景像素直接吸附到阶梯色，不进 MAXCOVERAGE 量化，中间灰不会出现灰紫 / 灰绿杂斑和断层。
- 同伴（博士、凯尔希）和 Mon3tr 刃光保持原色相，只乘明度压暗；水月几乎不压，仍是暖点之一。
- 人物与灯火区单独量化（MAXCOVERAGE 80 色），再和背景阶梯拼回。
- 整体压暗一档；灯火亮核仍是全图最亮点。
用法：python art/promo/itch/cover_g/build_cover_g_c2b.py
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
STOPS = ["#020307", "#0a0f17", "#18222e", "#334355", "#6f8296"]
STEPS = 12
LMAX = 0.72          # 背景最亮只到阶梯的 72%，灯火保持最亮
DIM = {"mizuki": 1.0, "doctor": 0.8, "kaltsit": 0.8}
GLINT_DIM = 0.78     # 背景里高饱和非蓝像素（Mon3tr 刃光等）：保色相，只压明度
LAMP = "#ffb347"
EYE = "#a9bccd"
PAL = ["#020307", "#18222e", "#6f8296", "#ffb347", "#c6b8ff"]


def soft_masks():
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ms = {}
    for cx, cy, rx, ry, n in CC.FIGS:
        r = np.sqrt(((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2)
        ms[n] = np.clip((1.08 - r) / 0.12, 0, 1)   # 羽化窄，过渡带不混出脏色
    return ms


def build():
    a = CC.lit_A()
    L = (a * [0.299, 0.587, 0.114]).sum(-1)
    Ln = np.minimum(L * 1.2 / (L + 0.4), 1.0) * LMAX
    mx, mn = a.max(-1), a.min(-1)
    sat = (mx - mn) / (mx + 1e-4)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    blue = (b >= r) & (b >= g * 0.95)
    glint = (~blue & (sat > 0.35) & (mx > 0.3)).astype(np.float32)
    ms = soft_masks()
    # 人物 + Mon3tr 剪影遮罩：Gemini 出的黑白遮罩（build/imagegen/itchg_mask2，不进 git），收紧 1 像素去掉边缘外溢
    mk = Image.open(sorted((B.RAW / "itchg_mask2").glob("raw_*.png"))[0]).convert("L").resize((W, H), Image.BILINEAR)
    mk = mk.point(lambda v: 255 if v > 128 else 0).filter(ImageFilter.MinFilter(3))
    sil = np.asarray(mk, np.float32) / 255
    # 遮罩带进来的背景蓝（Mon3tr 周围、凯尔希手臂外缘）：三人椭圆以外的高饱和蓝像素划回背景
    keep_blue = np.maximum.reduce(list(ms.values())) > 0.3
    sil[blue & (sat > 0.4) & ~keep_blue] = 0
    # 遮罩漏了博士的黑外套：博士椭圆内，非高饱和蓝的像素都算博士
    sil[(ms["doctor"] > 0.5) & ~(blue & (sat > 0.4))] = 1
    # 凯尔希外缘的青色反光边：剪影边缘 3 像素内的高饱和蓝划回背景（脸上的眼睛在内部，不受影响）
    inner = np.asarray(Image.fromarray((sil * 255).astype(np.uint8)).filter(ImageFilter.MinFilter(7)), np.float32) / 255
    yy0, xx0 = np.mgrid[0:H, 0:W]
    face = (xx0 - 322) ** 2 + (yy0 - 278) ** 2 < 16 ** 2   # 凯尔希的脸（眼睛）不剔
    sil[(ms["kaltsit"] > 0.3) & (ms["mizuki"] < 0.3) & blue & (sat > 0.4) & (inner < 0.5) & ~face] = 0
    sil[face & (ms["kaltsit"] > 0.5)] = np.maximum(sil[face & (ms["kaltsit"] > 0.5)], 1.0 * ~(blue & (sat > 0.6) & (L < 0.3))[face & (ms["kaltsit"] > 0.5)])

    # 前景：原色相 × 明度系数
    dimf = np.full((H, W), GLINT_DIM, np.float32)
    fig = np.zeros((H, W), np.float32)
    for n, m in ms.items():
        dimf = np.where(m > fig, DIM[n], dimf)
        fig = np.maximum(fig, m)
    fg = a * dimf[..., None]

    # 灯火：暖晕 + 亮核（只作用在前景层，并把灯周围划进前景）
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    d2 = ((xx - CC.LAMP[0]) ** 2 + (yy - CC.LAMP[1]) ** 2) / (W * W)
    warm = CC.hx(LAMP)
    halo = 0.22 * np.exp(-d2 / (2 * 0.07 ** 2))
    core = 0.8 * np.exp(-d2 / (2 * 0.012 ** 2))
    fg = fg * (1 + halo[..., None] * (warm - 0.3)) + core[..., None] * warm
    lampzone = (core > 0.05).astype(np.float32)

    front = np.clip(np.maximum(sil, lampzone), 0, 1)

    # 缩到原生格
    nw, nh = W // B.CELL, H // B.CELL
    def down(x):
        return np.asarray(Image.fromarray(np.clip(x * 255, 0, 255).astype(np.uint8)).resize((nw, nh), Image.BOX), np.float32) / 255
    fg_s = down(np.clip(fg, 0, 1))
    ln_s = down(Ln)
    # 背景先做中值去噪，免得冷光区阶梯化后满是零碎亮点
    ln_s = np.asarray(Image.fromarray((ln_s * 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5)), np.float32) / 255
    front_s = down(front)

    # 背景：单色相明度阶梯
    step = np.round(ln_s / LMAX * (STEPS - 1)) / (STEPS - 1) * LMAX
    bg_s = CC.gradient_map(step / LMAX, STOPS)
    # 灯的暖光落在背景（地面、岩壁）上：按 4 档量化，保持硬边色阶
    halo_s = down(halo / 0.22) * 0.22
    hq = np.round(halo_s / 0.22 * 4) / 4 * 0.22
    bg_s = bg_s * (1 + hq[..., None] * (warm - 0.3) * 2.2)

    # 前景单独量化
    q = Image.fromarray((fg_s * 255).astype(np.uint8)).quantize(colors=80, method=Image.Quantize.MAXCOVERAGE,
                                                               dither=Image.Dither.NONE, kmeans=3).convert("RGB")
    fq = np.asarray(q, np.float32) / 255
    use_fg = front_s > 0.5
    out = np.where(use_fg[..., None], fq, bg_s)

    # 海嗣眼点：小块高亮青色 → 冷白点缀
    eyes = (b > 0.45) & (g > 0.4) & (r < 0.35) & (b - r > 0.25)
    em = Image.fromarray(eyes.astype(np.uint8) * 255)
    large = np.asarray(em.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(9)), bool)
    eyes_s = down((eyes & ~large).astype(np.float32)) > 0.3
    out[eyes_s & ~use_fg] = CC.hx(EYE)

    img = Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.NEAREST)
    bg = np.asarray(img).copy()
    rgb, cov, _ = A2.logo_block(W)
    hb, wb = cov.shape
    x0 = (W - 482) // 2
    x0 -= x0 % 2
    reg = bg[0:hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return Image.fromarray(bg)


def main():
    im = build()
    im.save(HERE / "cover_G_A2C2b_630x500.png", optimize=True)
    th = im.resize((315, 250), Image.BOX)
    th.save(HERE / "cover_G_A2C2b_630x500_thumb.png", optimize=True)
    old = Image.open(HERE / "cover_G_A2C2_630x500.png").convert("RGB")
    font = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 20)
    small = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 15)
    g = 20
    sh = Image.new("RGB", (2 * W + 3 * g, 44 + H + g + 250 + 20), (14, 18, 26))
    d = ImageDraw.Draw(sh)
    for i, (lab, x_im) in enumerate((("C2（上一版）", old), ("C2b（压暗一档，背景单色相阶梯，同伴降明度不降饱和）", im))):
        x = g + i * (W + g)
        d.text((x, 10), lab, font=font, fill=(225, 233, 238))
        sh.paste(x_im, (x, 44))
        sh.paste(x_im.resize((315, 250), Image.BOX), (x, 44 + H + g))
    x = g + W + g + 331
    for j, c in enumerate(PAL):
        yy = 44 + H + g + j * 50
        d.rectangle((x, yy, x + 40, yy + 40), fill=c, outline=(60, 70, 80))
        d.text((x + 50, yy + 10), c, font=small, fill=(200, 210, 218))
    sh.save(HERE / "cover_G_C2_vs_C2b.png", optimize=True)
    print("ok", sh.size)


if __name__ == "__main__":
    main()
