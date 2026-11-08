# 蚀刻章章面：pixgen 原图 → 本作像素章面（11-08 用户「排版不要改，用生图工具来，只修改刻章」，docs/328）。
# 尺寸 / 外形严格跟现有插槽 game/art/ui/medals/medal_<id>_slot.png 一致（版式不动），只换章面像素。
# 用法：python tools/imagegen/medal_bake.py <id> <原图.png> [输出.png] [--colors 32] [--nolight]
#   原图是洋红底；抠图 → 按六边形外框对齐到插槽外框 → 缩到插槽尺寸（每格取均值）→ 量化 → 用插槽的 alpha 作外形。
import sys, colorsys
from pathlib import Path
from PIL import Image, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
MED = ROOT / "game/art/ui/medals"


def is_bg(r, g, b):
    """洋红底（模型有时给偏暗的洋红，放宽到 v > 0.25）"""
    hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return abs(hh - 300 / 360) < 0.10 and s > 0.35 and v > 0.25


def keyed_bbox(im):
    """洋红底以外的像素外框"""
    px = im.load(); w, h = im.size
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y][:3]
            if not is_bg(r, g, b):
                xs.append(x); ys.append(y)
    return min(xs), min(ys), max(xs) + 2, max(ys) + 2


def relight(face):
    """光感（11-08 用户「光感是不是还得做一下」）：在最终像素尺寸上加强金属受光。
    ① 色调：暗部压暗（gamma）、亮部往白推，浮雕高光更跳；② 左上 → 右下的斜向受光（×1.3 → ×0.7）；
    ③ 最亮约 4% 的像素提成带一点青的白色闪点。外缘受光边在 rim_light() 里按插槽外形做。"""
    w, h = face.size
    p = face.load()
    lum = []
    for y in range(h):
        for x in range(w):
            r, g, b = p[x, y]
            k = 1.3 - 0.6 * ((x / w) * 0.5 + (y / h) * 0.5)          # 斜向受光
            out = []
            for c in (r, g, b):
                v = (c / 255) ** 1.3                                       # 暗部压暗
                if v > 0.6:
                    v = 0.55 + (v - 0.55) * 1.7                             # 亮部推白
                out.append(max(0, min(255, int(v * 255 * k))))
            p[x, y] = tuple(out)
            lum.append((out[0] * 0.3 + out[1] * 0.59 + out[2] * 0.11, x, y))
    lum.sort(reverse=True)
    for _, x, y in lum[:max(1, len(lum) * 4 // 100)]:
        p[x, y] = (236, 250, 255)
    return face


def rim_light(out, alpha):
    """六边形外缘 1 格：左上两条边提亮成受光边，右下两条边压暗"""
    W, H = out.size
    po, pa = out.load(), alpha.load()
    cx, cy = (W - 1) / 2, (H - 1) / 2
    for y in range(H):
        for x in range(W):
            if not pa[x, y]:
                continue
            edge = any(not (0 <= x + a < W and 0 <= y + b < H) or not pa[x + a, y + b] for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if not edge:
                continue
            d = (-(x - cx) * 0.6 - (y - cy) * 0.8) / max(1.0, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5)
            r, g, b, al = po[x, y]
            if d > 0.25:
                po[x, y] = (200, 228, 250, al)
            elif d < -0.35:
                po[x, y] = (int(r * 0.45), int(g * 0.45), int(b * 0.5), al)


def bake(mid, src, dst=None, colors=32, light=True):
    slot = Image.open(MED / f"medal_{mid}_slot.png").convert("RGBA")
    W, H = slot.size
    sb = slot.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    im = Image.open(src).convert("RGB")
    x0, y0, x1, y1 = keyed_bbox(im)
    pp = im.load()   # 底色先换成深色描边色，缩小时边缘混出来的是暗边而不是洋红 / 绿边
    for y in range(im.height):
        for x in range(im.width):
            if is_bg(*pp[x, y]):
                pp[x, y] = (8, 14, 24)
    face = im.crop((x0, y0, x1, y1)).resize((sb[2] - sb[0], sb[3] - sb[1]), Image.LANCZOS)
    face = face.filter(ImageFilter.UnsharpMask(radius=1, percent=120, threshold=2))
    face = ImageEnhance.Contrast(face).enhance(1.12)
    if light:
        face = relight(face)
    q = face.quantize(colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    out.paste(q, (sb[0], sb[1]))
    a = slot.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    out.putalpha(a)
    po = out.load()   # 插槽外形比生图的六边形略大时，边上会带进洋红底：改成深色描边
    for y in range(H):
        for x in range(W):
            r, g, b, al = po[x, y]
            if al and r > 150 and b > 150 and g < 110:
                po[x, y] = (8, 14, 24, al)
    if light:
        rim_light(out, a)
    dst =Path(dst) if dst else MED / f"medal_{mid}.png"
    out.save(dst)
    return dst


if __name__ == "__main__":
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    c = 32
    if "--colors" in sys.argv:
        c = int(sys.argv[sys.argv.index("--colors") + 1]); args.remove(str(c))
    print(bake(int(args[0]), args[1], args[2] if len(args) > 2 else None, c, light="--nolight" not in sys.argv))
