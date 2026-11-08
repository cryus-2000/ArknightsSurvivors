# 蚀刻章章面：pixgen 原图 → 本作像素章面（11-08 用户「排版不要改，用生图工具来，只修改刻章」，docs/328）。
# 尺寸 / 外形严格跟现有插槽 game/art/ui/medals/medal_<id>_slot.png 一致（版式不动），只换章面像素。
# 用法：python tools/imagegen/medal_bake.py <id> <原图.png> [输出.png] [--colors 24]
#   原图是洋红底；抠图 → 按六边形外框对齐到插槽外框 → 缩到插槽尺寸（每格取均值）→ 量化 → 用插槽的 alpha 作外形。
import sys, colorsys
from pathlib import Path
from PIL import Image, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parents[2]
MED = ROOT / "game/art/ui/medals"


def keyed_bbox(im):
    """洋红底以外的像素外框"""
    px = im.load(); w, h = im.size
    xs, ys = [], []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            r, g, b = px[x, y][:3]
            hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if not (abs(hh - 300 / 360) < 0.06 and s > 0.45 and v > 0.45):
                xs.append(x); ys.append(y)
    return min(xs), min(ys), max(xs) + 2, max(ys) + 2


def bake(mid, src, dst=None, colors=24):
    slot = Image.open(MED / f"medal_{mid}_slot.png").convert("RGBA")
    W, H = slot.size
    sb = slot.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
    im = Image.open(src).convert("RGB")
    x0, y0, x1, y1 = keyed_bbox(im)
    face = im.crop((x0, y0, x1, y1)).resize((sb[2] - sb[0], sb[3] - sb[1]), Image.LANCZOS)
    face = face.filter(ImageFilter.UnsharpMask(radius=1, percent=120, threshold=2))
    face = ImageEnhance.Contrast(face).enhance(1.12)
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
    dst = Path(dst) if dst else MED / f"medal_{mid}.png"
    out.save(dst)
    return dst


if __name__ == "__main__":
    args = [x for x in sys.argv[1:] if not x.startswith("--")]
    c = 24
    if "--colors" in sys.argv:
        c = int(sys.argv[sys.argv.index("--colors") + 1]); args.remove(str(c))
    print(bake(int(args[0]), args[1], args[2] if len(args) > 2 else None, c))
