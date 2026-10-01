# -*- coding: utf-8 -*-
"""宣传图「干员阵容」（界面与美术 2026-10-01）：全部可选主控的待机帧并排（整数倍最近邻放大），名字 + 职业，深色底、灯火暖光。
只用本项目像素资产（art/incoming 的 op_*_idle@2x / player_idle@2x、logo、game/fonts/ui.ttf）。
用法：python tools/promo_roster.py [输出目录，缺省 build/promo] [--size 1920x1080]
"""
import os, sys, json, glob
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promo_keyart as K

ROOT = K.ROOT
CHAR_DIR = os.path.join(ROOT, "game", "data", "characters")


# ui.ttf 缺个别字（「娅」「鲨」）：游戏里 Godot 会自动退到系统字体，这里同样退到系统的微软雅黑粗体（整个名字一起换，同一个词里字形一致）
FALLBACK = "C:/Windows/Fonts/msyhbd.ttc"
try:
    from fontTools.ttLib import TTFont
    _UI_CMAP = TTFont(K.FONT_UI).getBestCmap()
except Exception:
    _UI_CMAP = None


def font_for(text, size):
    if _UI_CMAP is not None and os.path.exists(FALLBACK) and any(ord(ch) not in _UI_CMAP for ch in text):
        return ImageFont.truetype(FALLBACK, size)
    return ImageFont.truetype(K.FONT_UI, size)


def roster():
    out = []
    for f in sorted(glob.glob(os.path.join(CHAR_DIR, "*.json"))):
        cid = os.path.basename(f)[:-5]
        d = json.load(open(f, encoding="utf-8"))
        tex = "player_idle@2x" if cid == "mizuki" else "op_%s_idle@2x" % cid
        if not os.path.exists(os.path.join(K.ART, tex + ".png")):
            continue
        out.append((cid, d.get("name", cid), d.get("class", d.get("cls", "")), tex))
    return out


def compose(W=1920, H=1080):
    s = H / 1080.0
    img = Image.new("RGBA", (W, H))
    d0 = ImageDraw.Draw(img)
    top, bot = (4, 7, 14), (10, 22, 36)
    for y in range(H):
        t = y / (H - 1)
        d0.line([(0, y), (W, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
    img.alpha_composite(K.radial((W, H), (W // 2, int(H * 0.62)), int(760 * s), (255, 190, 120), 70))
    ops = roster()
    n = len(ops)
    cols = (n + 1) // 2
    rows = [ops[:cols], ops[cols:]]
    f_name = ImageFont.truetype(K.FONT_UI, int(26 * s))
    f_cls = ImageFont.truetype(K.FONT_UI, int(17 * s))
    k = max(1, int(round(3 * s)))
    cell = W / (cols + 0.6)
    for ri, row in enumerate(rows):
        foot = int(H * (0.53 if ri == 0 else 0.88))
        x0 = (W - cell * len(row)) / 2.0
        for ci, (cid, name, cls, tex) in enumerate(row):
            im = K.up(K.frame(tex, 4, 0, trim=True), k)
            cx = int(x0 + cell * (ci + 0.5))
            x, y = cx - im.width // 2, foot - im.height
            sh = Image.new("RGBA", (int(im.width * 0.8), int(22 * s)), (0, 0, 0, 0))
            ImageDraw.Draw(sh).ellipse((0, 0, sh.width - 1, sh.height - 1), fill=(0, 0, 0, 160))
            img.alpha_composite(sh, (cx - sh.width // 2, foot - int(12 * s)))
            K.put_glow(img, im, (255, 206, 140), 8 * s, 0.8, (x, y))
            img.alpha_composite(im, (x, y))
            d = ImageDraw.Draw(img)
            fn = font_for(name, int(26 * s))
            bb = d.textbbox((0, 0), name, font=fn)
            d.text((cx - (bb[2] - bb[0]) // 2, foot + int(10 * s)), name, font=fn, fill=(236, 240, 244, 255), stroke_width=max(1, int(2 * s)), stroke_fill=(4, 8, 14, 255))
            bb2 = d.textbbox((0, 0), cls, font=f_cls)
            d.text((cx - (bb2[2] - bb2[0]) // 2, foot + int(44 * s)), cls, font=f_cls, fill=(255, 206, 130, 255))
    lg = K.up(K.load("logo"), max(1, int(round(1 * s))))
    img.alpha_composite(lg, (int(40 * s), int(28 * s)))
    d = ImageDraw.Draw(img)
    f_t = ImageFont.truetype(K.FONT_UI, int(34 * s))
    title = "%d 名干员 · 自由编队" % n
    d.text((int(40 * s) + lg.width + int(24 * s), int(28 * s) + lg.height // 2 - int(20 * s)), title, font=f_t, fill=(236, 240, 244, 255), stroke_width=max(1, int(2 * s)), stroke_fill=(4, 8, 14, 255))
    f3 = ImageFont.truetype(K.FONT_UI, int(14 * s))
    bb = d.textbbox((0, 0), K.NOTICE, font=f3)
    d.text((W - (bb[2] - bb[0]) - int(20 * s), H - int(26 * s)), K.NOTICE, font=f3, fill=(150, 160, 170, 200))
    return img.convert("RGB")


if __name__ == "__main__":
    args = sys.argv[1:]
    out = args[0] if args and not args[0].startswith("--") else os.path.join(ROOT, "build", "promo")
    size = args[args.index("--size") + 1] if "--size" in args else "1920x1080"
    W, H = (int(v) for v in size.split("x"))
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, "roster_%dx%d.png" % (W, H))
    compose(W, H).save(p, optimize=True)
    print(p, os.path.getsize(p) // 1024, "KB")
