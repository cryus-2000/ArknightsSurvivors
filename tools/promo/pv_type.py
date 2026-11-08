# -*- coding: utf-8 -*-
"""PV 文字与 3D 段后期（按 docs/327「鹰角 PV 风格规范」§3、§4.3；pv-style 会话 11-08 定）。

  letterbox_post(img, i)            3D 段 / 字卡后期：2.39:1 遮幅（上下各 138 px）、单色颗粒 ±6/255、暗角（四角 ≤ 40%）。实机不用
  name_strip(img, t, name, en, cls) 干员名字条 N1–N3：Noto Serif SC 700 96 中文名 + 左侧 8 px 青竖条、Montserrat Bold 170 英文底纹、
                                    Noto Sans SC 500 26 / Montserrat 15 职业行；落地那拍硬切出现（t ≥ 0）
  end_card(img, t)                  结尾卡 T1 / T2 / C1 / D1：Noto Serif SC 600 132 主标题（字距 0.12）、Montserrat Bold 30 英文（0.42）、
                                    行动语 C1（Sans 700 40，青底深字）、同人声明 D1（左下，Sans 400 20 + Montserrat 13）
字体：Noto Serif SC / Noto Sans SC 可变字重全字库（C:/Windows/Fonts，SIL OFL 1.1）、仓库 Montserrat（OFL）。
"""
import math
import os
import random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WIN = os.environ.get("WINDIR", "C:/Windows") + "/Fonts/"
W, H = 1920, 1080
BAR = 138
INK = (236, 241, 244)
INK_DIM = (150, 166, 178)
LABEL = (120, 138, 150)
CYAN = (94, 230, 230)
DEEP = (5, 9, 18)
_F = {}


def _font(path, size, wght=None):
    k = (path, size, wght)
    if k not in _F:
        f = ImageFont.truetype(path, size)
        if wght is not None:
            try:
                f.set_variation_by_axes([wght])
            except Exception:
                pass
        _F[k] = f
    return _F[k]


def serif(size, wght=400):
    return _font(WIN + "NotoSerifSC-VF.ttf", size, wght)


def sans(size, wght=400):
    return _font(WIN + "NotoSansSC-VF.ttf", size, wght)


def latin(size, bold=True):
    return _font(ROOT + "/game/fonts/" + ("montserrat_bold.ttf" if bold else "montserrat_semibold.ttf"), size)


def tracked(d, xy, text, font, fill, tracking=0.0, anchor="l"):
    sp = font.size * tracking
    ws = [d.textlength(c, font=font) for c in text]
    total = sum(ws) + sp * (len(text) - 1)
    x, y = xy
    if anchor == "m":
        x -= total / 2
    elif anchor == "r":
        x -= total
    for c, w in zip(text, ws):
        d.text((x, y), c, font=font, fill=fill)
        x += w + sp
    return total


def _ease(x):
    x = min(1.0, max(0.0, x))
    return 1 - (1 - x) ** 3


_VIG = None


def letterbox_post(img, i=0, bars=True):
    global _VIG
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w = a.shape[:2]
    if _VIG is None or _VIG.shape[:2] != (h, w):
        yy = np.linspace(-1, 1, h)[:, None]
        xx = np.linspace(-1, 1, w)[None, :]
        r = np.sqrt((xx * 0.92) ** 2 + (yy * 1.05) ** 2) / np.sqrt(0.92 ** 2 + 1.05 ** 2)
        _VIG = (1.0 - 0.6 * np.clip((r - 0.45) / 0.55, 0, 1) ** 1.6)[..., None].astype(np.float32)   # 四角 ≈ 40%
    a = a * _VIG
    rng = np.random.default_rng(1000 + i // 2)
    a += rng.uniform(-6, 6, (h, w, 1)).astype(np.float32)   # 单色颗粒 ±6/255
    if bars:
        a[:BAR] = 0
        a[h - BAR:] = 0
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def name_strip(img, t, name, en, cls_cn, cls_en, x=1180, y=420):
    """N1–N3。t = 落地后秒数（< 0 不画）；英文底纹慢移 20 px / 小节"""
    if t < 0:
        return img
    im = img.convert("RGBA")
    lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    # N2 英文底纹：只比底色亮一档
    tracked(d, (x - 40 + 12 * min(1.0, t / 1.64), y - 60), en, latin(170), (24, 48, 60, 255), 0.02)
    # N1 中文名 + 左侧青竖条
    f1 = serif(96, 700)
    d.rectangle((x - 30, y + 18, x - 22, y + 18 + 104), fill=CYAN + (255,))
    tracked(d, (x, y), name, f1, INK + (255,), 0.08)
    # N3 职业行
    tracked(d, (x + 2, y + 150), cls_cn, sans(26, 500), INK_DIM + (255,), 0.12)
    tracked(d, (x + 2, y + 192), cls_en, latin(15, False), LABEL + (255,), 0.4)
    im.alpha_composite(lay)
    return im.convert("RGB")


def end_card(img, t, title="方舟幸存者", en="ARKNIGHTS SURVIVORS", cta="B站 Toy 点开即玩", cx=1290, cy=430):
    """T1 / T2 / C1 / D1。t = 结尾卡开始后的秒数：T1 12 帧淡入 + 模糊到清，T2 晚 4 帧，C1 最后出，D1 全程"""
    im = img.convert("RGBA")
    W_, H_ = im.size

    def layer(draw_fn, a, blur=0.0):
        if a <= 0:
            return
        lay = Image.new("RGBA", im.size, (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(lay))
        if blur > 0.05:
            lay = lay.filter(ImageFilter.GaussianBlur(blur))
        if a < 1:
            lay.putalpha(lay.getchannel("A").point(lambda v: int(v * a)))
        im.alpha_composite(lay)

    k1 = _ease(t / 0.2)
    layer(lambda d: tracked(d, (cx, cy), title, serif(132, 600), INK + (255,), 0.12, "m"), k1, 4 * (1 - k1))
    k2 = _ease((t - 4 / 60) / 0.2)
    layer(lambda d: tracked(d, (cx, cy + 190), en, latin(30), INK_DIM + (255,), 0.42, "m"), k2, 4 * (1 - k2))
    k3 = _ease((t - 0.9) / 0.25)

    def cta_fn(d):
        f = sans(40, 700)
        tw = tracked(ImageDraw.Draw(Image.new("RGBA", (10, 10))), (0, 0), cta, f, (0, 0, 0, 0), 0.08)
        x0, y0 = cx - tw / 2 - 28, cy + 268
        d.rectangle((x0, y0, x0 + tw + 56, y0 + 66), fill=CYAN + (255,))
        tracked(d, (cx, y0 + 6), cta, f, DEEP + (255,), 0.08, "m")
    layer(cta_fn, k3)

    def d1(d):
        y0 = H_ - BAR - 70
        tracked(d, (96, y0), "明日方舟同人", sans(20, 400), INK_DIM + (255,), 0.1)
        tracked(d, (96, y0 + 32), "ARKNIGHTS FAN WORK", latin(13, False), LABEL + (255,), 0.32)
    layer(d1, 1.0)
    return im.convert("RGB")


def mean_luma(img):
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    return float((a @ np.array([0.2126, 0.7152, 0.0722], np.float32)).mean())


# ---------------------------------------------------------------- 实机最外层叠层（docs/327 §9.3，用户 11-08「可以叠」）：前景虚化海雪 + 轻暗角；实机本身不调色、不加颗粒
_SNOW = {}
_GVIG = {}


def _snow_sprite(d, blur):
    k = (d, blur)
    if k not in _SNOW:
        pad = int(blur * 3) + 2
        sz = d + pad * 2
        m = Image.new("L", (sz, sz), 0)
        ImageDraw.Draw(m).ellipse((pad, pad, pad + d, pad + d), fill=255)
        _SNOW[k] = m.filter(ImageFilter.GaussianBlur(blur))
    return _SNOW[k]


def gameplay_overlay(img, t, n_big=5, n_far=2, seed=0, vig=True):
    """n_big：大颗海雪 3–8（高潮段 0–2）；直径 40–120 px、模糊到看不出边、不透明 15–35%、#BFEFF5、上漂 10–30 px/s、避开中央 40%；
    n_far：远层 1–2 颗 8–16 px、10%、反向漂（视差）。暗角：中心 60% 半径内不动，四角 60–70%"""
    im = img.convert("RGB")
    w, h = im.size
    if vig:
        if (w, h) not in _GVIG:
            yy = np.linspace(-1, 1, h)[:, None]
            xx = np.linspace(-1, 1, w)[None, :]
            r = np.sqrt(xx ** 2 + yy ** 2) / math.sqrt(2)
            _GVIG[(w, h)] = (1.0 - 0.35 * np.clip((r - 0.6) / 0.4, 0, 1) ** 1.4)[..., None].astype(np.float32)
        a = np.asarray(im).astype(np.float32) * _GVIG[(w, h)]
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    rng = random.Random(seed)
    for k in range(n_big + n_far):
        far = k >= n_big
        d = rng.randint(8, 16) if far else rng.randint(40, 120)
        alpha = 0.10 if far else rng.uniform(0.15, 0.35)
        v = (-rng.uniform(6, 12) if far else rng.uniform(10, 30))   # px/s，正 = 上漂
        # 避开中央 40%：x 落在左 30% 或右 30%
        x0 = rng.uniform(0.02, 0.28) if rng.random() < 0.5 else rng.uniform(0.72, 0.98)
        y0 = rng.uniform(0, 1)
        x = x0 * w + 8 * math.sin(t * 0.6 + k)
        y = ((y0 * (h + 300) - v * t) % (h + 300)) - 150
        spr = _snow_sprite(d, max(2.0, d * 0.28))
        a = spr.point(lambda p, al=alpha: int(p * al))
        x0_, y0_ = int(x - spr.width / 2), int(y - spr.height / 2)
        im.paste((191, 239, 245), (x0_, y0_, x0_ + spr.width, y0_ + spr.height), a)
    return im
