"""Toy 图标：logo 版（11-08 用户「或者放我们的logo呢」）。素材 = 标题页 logo_mark.png（塔形徽记 + 「方舟幸存者」像素字），整数倍最近邻放大：
L1 徽记单独放大 4 倍 + 下方细线（左端青色加粗，同封面标题）；深海青底；
L2 徽记 2 倍 + 「方舟 / 幸存者」两行 2 倍；
L3 同 L1，底换成标题页沉船背景；
L23 = L2 的版式 + L3 的底（11-08 用户选「L2+L3」），字加深色描边压住底图；
L4 定稿（11-08 用户同意改）：去掉悬空细线，只留两行字居中，徽记放大调暗作水印。
用法：python art/promo/toy/build_toy_icon_logo.py   出到 build/toy_icon/
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[3]
TD = ROOT / "game/art/ui/title_deep"
OUT = ROOT / "build/toy_icon"
S = 512
CYAN = (120, 235, 245)
LINE = (59, 85, 102)


def segs(mask):
    cols = mask.any(0)
    out, on, st = [], False, 0
    for x, c in enumerate(list(cols) + [False]):
        if c and not on:
            on, st = True, x
        elif not c and on:
            on = False
            out.append((st, x))
    return out


LOGO = Image.open(TD / "logo_mark.png").convert("RGBA")
_A = np.asarray(LOGO)[..., 3] > 127
_S = segs(_A)
MARK = LOGO.crop((_S[0][0], 0, _S[0][1], LOGO.height))
MARK = MARK.crop(MARK.getbbox())
_TA, _TB = _S[1][0], _S[-1][1]   # 五个字连成一段：按等宽切
_CS = _A.sum(0)
_CUT = [_TA] + [min(range(round(_TA + (_TB - _TA) * i / 5) - 10, round(_TA + (_TB - _TA) * i / 5) + 11), key=lambda x: _CS[x]) for i in range(1, 5)] + [_TB]
CHARS = [LOGO.crop((_CUT[i], 0, _CUT[i + 1], LOGO.height)) for i in range(5)]   # 切在等宽位置附近最空的列


def _trim(c):
    """去掉切字时带进来的邻字碎笔画：两端宽度 < 5 的孤立列段丢掉。"""
    sg = segs(np.asarray(c)[..., 3] > 127)
    while len(sg) > 1 and sg[0][1] - sg[0][0] < 5:
        sg.pop(0)
    while len(sg) > 1 and sg[-1][1] - sg[-1][0] < 5:
        sg.pop()
    c = c.crop((sg[0][0], 0, sg[-1][1], c.height))
    return c.crop(c.getbbox())


CHARS = [_trim(c) for c in CHARS]


def up(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def bg_plain(cell=8):
    n = S // cell
    y, x = np.mgrid[0:n, 0:n].astype(np.float32)
    d = np.clip(np.hypot((x + .5) / n - .5, (y + .5) / n - .42) / .75, 0, 1)
    bay = np.array([[0, 2], [3, 1]], np.float32) / 4 - .375
    d = np.clip(d + bay[(y % 2).astype(int), (x % 2).astype(int)] * .06, 0, 1)
    d = np.round(d * 8) / 8
    c0, c1 = np.array([40, 92, 108], np.float32), np.array([8, 18, 30], np.float32)
    c = c0 * (1 - d[..., None]) + c1 * d[..., None]
    return Image.fromarray(c.astype(np.uint8), "RGB").resize((S, S), Image.NEAREST).convert("RGBA")


def bg_title():
    bg = Image.open(TD / "bg.png").convert("RGBA")
    side = 171
    x0, y0 = 300 - side // 2, 0
    b = bg.crop((x0, y0, x0 + side, y0 + side)).resize((S, S), Image.NEAREST)
    a = np.asarray(b).astype(np.float32)
    a[..., :3] *= .8
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def glow(cv, mask, pos, color, k, blur):
    pd = blur * 3
    pm = Image.new("L", (mask.width + 2 * pd, mask.height + 2 * pd), 0)
    pm.paste(mask, (pd, pd))
    g = np.asarray(pm.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32)[..., None] / 255 * k
    b = np.asarray(cv).astype(np.float32)
    x, y = pos[0] - pd, pos[1] - pd
    h, w = g.shape[:2]
    x0, y0, x1, y1 = max(x, 0), max(y, 0), min(x + w, S), min(y + h, S)
    if x1 > x0 and y1 > y0:
        b[y0:y1, x0:x1, :3] += g[y0 - y:y1 - y, x0 - x:x1 - x] * np.array(color, np.float32)
    return Image.fromarray(np.clip(b, 0, 255).astype(np.uint8), "RGBA")


def underline(cv, x0, x1, y, k):
    d = ImageDraw.Draw(cv)
    d.rectangle((x0, y, x1, y + k - 1), fill=(*LINE, 255))
    d.rectangle((x0, y - k // 2, x0 + int((x1 - x0) * .18), y + k + k // 2 - 1), fill=(*CYAN, 255))
    return cv


def place_mark(cv, k, cy, glow_k=.45):
    m = up(MARK, k)
    x, y = (S - m.width) // 2, cy - m.height // 2
    cv = glow(cv, m.split()[3], (x, y), CYAN, glow_k, 22)
    cv.alpha_composite(m, (x, y))
    return cv, x, y, m


def l1(bg):
    cv = bg
    cv, x, y, m = place_mark(cv, 4, 236)
    return underline(cv, x - 24, x + m.width + 24, y + m.height + 22, 6)


def l2(bg=None):
    cv = bg if bg is not None else bg_plain()
    cv, x, y, m = place_mark(cv, 2, 108, .35)
    k = 2
    rows = [CHARS[:2], CHARS[2:]]
    gap = 2 * k
    yy = y + m.height + 40
    for r in rows:
        ims = [up(c, k) for c in r]
        w = sum(i.width for i in ims) + gap * (len(ims) - 1)
        xx = (S - w) // 2
        h = max(i.height for i in ims)
        for i in ims:
            cm = i.split()[3]
            sh = Image.new("RGBA", i.size, (6, 12, 20, 255))
            for dx, dy in ((-k, 0), (k, 0), (0, -k), (0, k), (k, k)):   # 深色描边，底图花也压得住字
                cv.paste(sh, (xx + dx, yy + h - i.height + dy), cm)
            cv.alpha_composite(i, (xx, yy + h - i.height))
            xx += i.width + gap
        yy += h + 18
    return underline(cv, 96, S - 96, y + m.height + 18, 4)


def text_rows(cv, k, y0, row_gap):
    rows = [CHARS[:2], CHARS[2:]]
    gap = 2 * k
    yy = y0
    for r in rows:
        ims = [up(c, k) for c in r]
        w = sum(i.width for i in ims) + gap * (len(ims) - 1)
        xx = (S - w) // 2
        h = max(i.height for i in ims)
        for i in ims:
            cm = i.split()[3]
            sh = Image.new("RGBA", i.size, (6, 12, 20, 255))
            for dx, dy in ((-k, 0), (k, 0), (0, -k), (0, k), (k, k)):
                cv.paste(sh, (xx + dx, yy + h - i.height + dy), cm)
            cv.alpha_composite(i, (xx, yy + h - i.height))
            xx += i.width + gap
        yy += h + row_gap
    return cv


def l4(bg):
    """11-08 改：只留一个视觉中心——「方舟 / 幸存者」两行字居中；徽记放大调暗做水印，去掉悬空的细线。"""
    cv = bg
    m = up(MARK, 5)
    a = np.asarray(m).astype(np.float32)
    a[..., :3] = np.array([90, 190, 215], np.float32)   # 青色剪影
    a[..., 3] *= .34
    wm = Image.fromarray(a.astype(np.uint8), "RGBA")
    x, y = (S - wm.width) // 2, (S - wm.height) // 2 - 6
    cv = glow(cv, m.split()[3], (x, y), CYAN, .18, 30)
    cv.alpha_composite(wm, (x, y))
    h = max(c.height for c in CHARS) * 2
    total = 2 * h + 22
    return text_rows(cv, 2, (S - total) // 2, 22)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    vs = {"L1": l1(bg_plain()), "L2": l2(), "L3": l1(bg_title()), "L23": l2(bg_title()), "L4": l4(bg_title())}
    for k, v in vs.items():
        v.convert("RGB").save(OUT / f"toy_icon_{k}.png", optimize=True)
    f = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 24)
    lab = {"L1": "L1 徽记", "L2": "L2 徽记 + 方舟幸存者", "L3": "L3 徽记 + 标题页背景", "L23": "L2+L3", "L4": "L4 字居中 + 徽记水印"}
    sheet = Image.new("RGB", (len(vs) * (S + 24) + 24, S + 210), (24, 26, 32))
    d = ImageDraw.Draw(sheet)
    for i, (k, v) in enumerate(vs.items()):
        x = 24 + i * (S + 24)
        d.text((x, 6), lab[k], fill=(255, 255, 255), font=f)
        sheet.paste(v.convert("RGB"), (x, 44))
        sheet.paste(v.convert("RGB").resize((128, 128), Image.LANCZOS), (x, S + 60))
        sheet.paste(v.convert("RGB").resize((64, 64), Image.LANCZOS), (x + 150, S + 60))
    sheet.save(OUT / "toy_icon_logo.png", optimize=True)
    print(OUT)


if __name__ == "__main__":
    main()
