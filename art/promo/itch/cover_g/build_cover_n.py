"""商店封面 N（11-07，用户：「画封面用大海嗣」）：
海嗣 = 游戏怪物精灵的高清源图（art/archive/incoming_1028/enemy_redraw_1023/remaining/generated/*.png，
做游戏精灵时的原稿，设计就是游戏里的海嗣），抠黑底后按格取众数缩到封面像素格（与水月同一像素尺度），
大小按游戏内比例（泡影 / 伊祖米克 ≈ 水月 2 倍高，小怪 ≈ 0.5–0.8 倍），远处再缩一点做纵深；
光照：保留原配色 + 深海青环境色 + 朝光圈一侧外轮廓青色边光 + 离光越远越暗。
背景 = relit0 去怪版（cover1107_empty / emptyw），水月走 build_cover_h.compose_grid。
用法：python art/promo/itch/cover_g/build_cover_n.py
"""
import sys, glob, math
from pathlib import Path
import numpy as np
from PIL import Image
from scipy.ndimage import binary_fill_holes, label

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402
import build_cover_g_c2l as X  # noqa: E402
import build_cover_k as K  # noqa: E402
import build_cover_h as Hh  # noqa: E402
import build_cover_m as M  # noqa: E402

SRC = B.ROOT / "art/archive/incoming_1028/enemy_redraw_1023/remaining/generated"
MIZ = "t:1"
# (名, 高〔水月高的倍数〕, dx, dy〔水月高为单位，相对光圈中心脚底〕, 亮度, 朝左?)
LAYOUT = [
    # 后景（远、暗、小）
    ("mother", 0.70, -1.30, -0.45, 0.55), ("path", 0.70, 1.40, -0.48, 0.55),
    ("floater", 0.42, -0.55, -0.62, 0.55), ("offspring", 0.38, 0.62, -0.62, 0.55),
    ("nest", 0.42, -2.05, -0.30, 0.5), ("tracer", 0.45, 2.10, -0.32, 0.5),
    # 中景一圈
    ("slider", 0.58, -1.08, -0.14, 0.8), ("spitter", 0.62, 1.05, -0.16, 0.8),
    ("skimmer", 0.66, -1.62, 0.02, 0.75), ("runner", 0.50, 1.70, 0.00, 0.8),
    ("offspring", 0.46, -0.88, 0.20, 0.9), ("slider", 0.50, 0.98, 0.22, 0.9),
    # 前景两角（只露半身、偏暗）
    ("paranoia", 1.55, -2.00, 1.10, 0.5), ("izumik", 1.65, 2.02, 1.20, 0.45),
]
CACHE = {}


def load_src(name):
    """抠黑底：与图边连通、亮度低的像素 = 透明；填洞后取最大连通块外的小碎块也去掉"""
    if name in CACHE:
        return CACHE[name]
    im = Image.open(SRC / f"{name}.png").convert("RGB")
    a = np.asarray(im).astype(np.int32)
    lum = a.max(-1)
    dark = lum < 40
    lab, n = label(dark)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bgm = np.isin(lab, list(edge))
    fg = ~bgm
    lab2, n2 = label(fg)
    if n2 > 1:
        sizes = np.bincount(lab2.ravel())
        sizes[0] = 0
        fg = sizes[lab2] > sizes.max() * 0.02
    rgba = np.dstack([a.astype(np.uint8), (fg * 255).astype(np.uint8)])
    img = Image.fromarray(rgba, "RGBA")
    img = img.crop(img.getbbox())
    CACHE[name] = img
    return img


def to_cells(img, h_cells):
    """缩到 h_cells 格高：先放到 4 倍目标再每 4×4 取众数（色块干净），alpha 取多数"""
    w_cells = max(1, int(round(img.width * h_cells / img.height)))
    big = img.resize((w_cells * 4, h_cells * 4), Image.LANCZOS)
    a = np.asarray(big)
    al = a[..., 3].reshape(h_cells, 4, w_cells, 4).transpose(0, 2, 1, 3).reshape(h_cells, w_cells, 16)
    alpha = (al > 127).sum(-1) >= 8
    rgb = Image.fromarray(a[..., :3]).quantize(colors=64, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE)
    pal = np.array(rgb.getpalette()[:64 * 3], np.uint8).reshape(-1, 3)
    idx = K.mode_down(np.asarray(rgb), 4)
    out = np.zeros((h_cells, w_cells, 4), np.uint8)
    out[..., :3] = pal[idx]
    out[..., 3] = alpha * 255
    return Image.fromarray(out, "RGBA")


def paste(g, spr, fx, fy, light, bright, hm, face_left):
    if face_left:
        spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(spr).astype(np.float32)
    sh, sw = a.shape[:2]
    m = a[..., 3] > 127
    gh, gw = g.shape[:2]
    x0, y0 = int(fx - sw / 2), int(fy - sh)
    d = math.hypot(fx - light[0], (fy - sh / 2) - light[1]) / hm
    k = float(np.clip(1.1 - 0.28 * d, 0.35, 1.0)) * bright
    rgb = a[..., :3] * np.array([0.78, 0.90, 1.0]) * k
    vx, vy = light[0] - fx, light[1] - (fy - sh / 2)
    nv = math.hypot(vx, vy) or 1
    sx, sy = int(round(vx / nv)), int(round(vy / nv))
    mf = binary_fill_holes(m)
    p = np.pad(mf, 1)
    nb = p[1 + sy:1 + sy + sh, 1 + sx:1 + sx + sw]
    rim = m & ~nb
    rk = float(np.clip(0.95 - 0.22 * d, 0.25, 0.8))
    rgb[rim] = rgb[rim] * (1 - rk) + M.CYAN * rk
    ys0, xs0 = max(0, y0), max(0, x0)
    ys1, xs1 = min(gh, y0 + sh), min(gw, x0 + sw)
    if ys1 <= ys0 or xs1 <= xs0:
        return
    sm = m[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0]
    reg = g[ys0:ys1, xs0:xs1]
    reg[sm] = np.clip(rgb[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0][sm], 0, 255).astype(np.uint8)


def build(kind):
    (W, H), cell, up, logo_y = Hh.SIZES[kind]
    gw, gh = W // cell, H // cell
    if kind == "itch_banner":
        big = Hh.bg_pixels_path(M.BGW, W, H, cell, 1.06)
        grid, rmask, center = Hh.crop_on_ring(big, gw, gh, Hh.BANNER["floor_y"], Hh.BANNER["ring_x"])
    else:
        big = Hh.bg_pixels_path(M.BG, W, H, cell, Hh.OVER)
        grid, rmask, center = Hh.crop_on_ring(big, gw, gh, Hh.FLOOR[1])
    n = Hh.SHIFT[kind]
    grid, rmask = Hh.shift_down(grid, n), Hh.shift_down(rmask, n)
    cx, cy = center[0], center[1] + n
    miz = Hh.sprite(MIZ)
    hm = miz.height
    light = (cx, cy - hm * 0.15)
    items = sorted((cy + dy * hm, name, hr, cx + dx * hm, br) for name, hr, dx, dy, br in LAYOUT)
    g = grid.copy()
    for fy, name, hr, fx, br in items:
        if fy > cy:
            continue
        paste(g, to_cells(load_src(name), max(6, int(hr * hm))), fx, fy, light, br, hm, fx > cx)
    g = Hh.compose_grid(g, miz, rmask, (cx, cy), 0)
    for fy, name, hr, fx, br in items:
        if fy <= cy:
            continue
        paste(g, to_cells(load_src(name), max(6, int(hr * hm))), fx, fy, light, br, hm, fx > cx)
    t = np.clip(1 - np.arange(gh) / (gh * 0.48), 0, 1)[:, None, None] ** 1.8 * 0.92
    g = (g * (1 - t) + np.array([6, 10, 16]) * t).astype(np.uint8)
    if kind == "itch_banner":
        tb = np.clip((np.arange(gh) - gh * 0.72) / (gh * 0.28), 0, 1)[:, None, None] ** 1.5 * 0.85
        tl = np.clip(1 - np.arange(gw) / (gw * 0.45), 0, 1)[None, :, None] ** 1.4 * 0.6
        t2 = np.maximum(tb, tl)
        g = (g * (1 - t2) + np.array([6, 10, 16]) * t2).astype(np.uint8)
    img = Image.fromarray(g).resize((g.shape[1] * cell, g.shape[0] * cell), Image.NEAREST)
    canvas = Image.new("RGB", (W, H), (6, 10, 16))
    canvas.paste(img, ((W - img.width) // 2, (H - img.height) // 2))
    bg = np.asarray(canvas).copy()
    rgb, cov, padt = A2.logo_block(482)
    if up > 1:
        rgb = np.kron(rgb, np.ones((up, up, 1), np.uint8))
        cov = np.kron(cov, np.ones((up, up), bool))
        padt *= up
    hb, wb = cov.shape
    if kind == "itch_banner":
        x0, y0 = Hh.BANNER["logo_xy"][0], Hh.BANNER["logo_xy"][1] - padt
    else:
        x0 = (W - 482 * up) // 2
        x0 -= x0 % 2
        y0 = max(logo_y * up - padt, 0)
    reg = bg[y0:y0 + hb, x0:x0 + wb]
    cc = cov[:reg.shape[0], :reg.shape[1]]
    reg[cc] = rgb[:reg.shape[0], :reg.shape[1]][cc]
    return X.notice_layer(Image.fromarray(bg), up)


def main():
    for kind in ("itch_cover", "toy_poster", "itch_banner"):
        im = build(kind)
        W, H = im.size
        im.save(HERE / f"cover_N_{kind}_{W}x{H}.png", optimize=True)
        print(kind)


if __name__ == "__main__":
    main()
