"""商店封面 K（11-07 重做，按调研结论）：一个焦点（水月单人、占画面高 60%）、主体比背景亮且饱和、
背景只有 3–4 层明暗、标题放在顶部干净暗区、真像素（成块色团，不是缩小一张画）。
生图：build/imagegen/cover1107_k/raw_*.png（gemini-3-pro-image，参照 = PRTS 水月模型渲染 + 标题页深海背景 / 水母）。
像素化：整图先收 COLORS 色（无抖动）→ 缩到 4×目标格 → 每 4×4 取众数色（保持色块干净，不平均成脏色）→ 最近邻放回。
用法：python art/promo/itch/cover_g/build_cover_k.py [--raw N,...] [--sheet <路径>]
"""
import sys, glob, argparse
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402
import build_cover_g_c2l as X  # noqa: E402

RAWS = sorted(glob.glob(str(B.RAW / "cover1107_k" / "raw_*.png")))
COLORS = 48
CELL = 2
SIZES = {"itch_cover": ((630, 500), 1, 16), "toy_poster": ((1200, 900), 2, 14)}


def mode_down(a, k):
    """a：H×W 调色板索引；每 k×k 取出现最多的索引"""
    H, W = a.shape
    h, w = H // k, W // k
    b = a[:h * k, :w * k].reshape(h, k, w, k).transpose(0, 2, 1, 3).reshape(h, w, k * k)
    out = np.zeros((h, w), a.dtype)
    for i in range(h):
        row = b[i]
        for j in range(w):
            v, n = np.unique(row[j], return_counts=True)
            out[i, j] = v[np.argmax(n)]
    return out


def fill_band(raw):
    """生图把 16:9 画面放进 4:3，顶部留了一条纯黑带：换成从画面顶边颜色往上渐暗的过渡（接缝不再是一条硬线）"""
    a = np.asarray(raw, np.float32)
    sd = a.mean(-1).std(1)
    top = next(i for i in range(a.shape[0]) if sd[i] > 6)
    k = top + 60                               # 取画面里往下一点的一行作起点（顶边几行常有过渡杂色）
    src = Image.fromarray(a[k:k + 1].astype(np.uint8)).resize((a.shape[1] // 40, 1), Image.BOX).resize((a.shape[1], 1), Image.BILINEAR)
    row = np.asarray(src, np.float32)[0]
    dark = np.array([6, 10, 16], np.float32)
    t = np.linspace(0, 1, k)[:, None, None] ** 1.6
    a[:k] = dark * (1 - t) + row[None] * t
    return Image.fromarray(a.astype(np.uint8))


def pixel_art(raw, W, H, fx=0.5, fy=0.5):
    raw = fill_band(raw)
    x, y, cw, ch = X.crop_box(raw, W, H, fx, fy)
    c = raw.crop((x, y, x + cw, y + ch))
    gw, gh = W // CELL, H // CELL
    big = c.resize((gw * 4, gh * 4), Image.LANCZOS)
    q = big.quantize(colors=COLORS, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE, kmeans=4)
    pal = np.array(q.getpalette()[:COLORS * 3], np.uint8).reshape(-1, 3)
    idx = mode_down(np.asarray(q), 4)
    small = Image.fromarray(pal[idx])
    return small.resize((W, H), Image.NEAREST)


PAINT = False   # --paint：插画风（11-07 用户给的参考 Crimsonland / Soulstone Survivors 都是插画 / 3D），不做像素化


def paint(raw, W, H, fx=0.5, fy=0.5):
    raw = fill_band(raw)
    x, y, cw, ch = X.crop_box(raw, W, H, fx, fy)
    return raw.crop((x, y, x + cw, y + ch)).resize((W, H), Image.LANCZOS)


def build(raw_path, kind):
    (W, H), up, logo_y = SIZES[kind]
    raw = Image.open(raw_path).convert("RGB")
    bg = np.asarray((paint if PAINT else pixel_art)(raw, W, H, 0.5, 0.5)).copy()
    rgb, cov, padt = A2.logo_block(482)
    if up > 1:
        rgb = np.kron(rgb, np.ones((up, up, 1), np.uint8))
        cov = np.kron(cov, np.ones((up, up), bool))
        padt *= up
    hb, wb = cov.shape
    x0 = (W - 482 * up) // 2
    x0 -= x0 % 2
    y0 = max(logo_y * up - padt, 0)
    reg = bg[y0:y0 + hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return X.notice_layer(Image.fromarray(bg), up)


def sheet(outs, path):
    f = ImageFont.truetype(str(B.ROOT / "game/fonts/ui.ttf"), 22)
    n = len(outs)
    out = Image.new("RGB", (20 + 630 + 20 + 600 + 20 + 340 + 20, 20 + n * 540), (18, 22, 30))
    d = ImageDraw.Draw(out)
    for r, (name, it, ty) in enumerate(outs):
        y = 20 + r * 540
        d.text((20, y), name, font=f, fill=(230, 236, 240))
        out.paste(it, (20, y + 34))
        out.paste(ty.resize((600, 450), Image.LANCZOS), (670, y + 34))
        out.paste(it.resize((315, 250), Image.LANCZOS), (1290, y + 34))
        out.paste(it.resize((158, 125), Image.LANCZOS), (1290, y + 300))
        out.paste(ty.resize((160, 120), Image.LANCZOS), (1460, y + 300))
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="")
    ap.add_argument("--tags", default="", help="另取 build/imagegen/<tag>/raw_*.png，逗号分隔（11-07 设计感三方向：cover1107_scale / _dyn / _halo）")
    ap.add_argument("--sheet")
    ap.add_argument("--paint", action="store_true")
    a = ap.parse_args()
    global PAINT
    PAINT = a.paint
    if a.tags:
        jobs = []
        for t in a.tags.split(","):
            for j, f in enumerate(sorted(glob.glob(str(B.RAW / t / "raw_*.png")))):
                jobs.append((t.replace("cover1107_", "K_") + str(j), f))
    else:
        sel = [int(v) for v in a.raw.split(",")] if a.raw else range(len(RAWS))
        jobs = [("K%d" % i, RAWS[i]) for i in sel]
    outs = []
    for name, f in jobs:
        it = build(f, "itch_cover")
        ty = build(f, "toy_poster")
        it.save(HERE / f"cover_{name}_itch_cover_630x500.png", optimize=True)
        ty.save(HERE / f"cover_{name}_toy_poster_1200x900.png", optimize=True)
        outs.append((name, it, ty))
        print(name)
    if a.sheet:
        sheet(outs, a.sheet)


if __name__ == "__main__":
    main()
