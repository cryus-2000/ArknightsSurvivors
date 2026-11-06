"""商店封面 M（11-07，用户：「怪物能不能换成我们的怪物」）：
背景 = relit0 交 Gemini 去掉所有怪物（cover1107_empty / emptyw，光池 / 光柱 / 遗迹不变）；
怪物 = 游戏内海嗣精灵（game/art/enemies/*/e_*@2x.png 第 0 帧），与水月同为「1 精灵像素 = 1 格」，游戏内比例不变；
围成一圈（中景小怪）+ 前景两角大型怪（画面切掉一部分、偏暗）+ 后景两只；全部朝向水月，
光照：朝光圈一侧青色边光、离光越远越暗、整体深海青环境色。水月仍走 build_cover_h.compose_grid。
用法：python art/promo/itch/cover_g/build_cover_m.py [--sheet <路径>]
"""
import sys, glob, math, argparse
from pathlib import Path
import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import build_cover_g as B  # noqa: E402
import build_cover_g_a2 as A2  # noqa: E402
import build_cover_g_c2l as X  # noqa: E402
import build_cover_k as K  # noqa: E402
import build_cover_h as Hh  # noqa: E402

ENEMY = B.ROOT / "game/art/enemies"
BG = sorted(glob.glob(str(B.RAW / "cover1107_empty" / "raw_*.png")))[0]
BGW = sorted(glob.glob(str(B.RAW / "cover1107_emptyw" / "raw_*.png")))[0]
MIZ = "t:1"
# 11-07 改：前景巨怪放大后很粗糙（游戏怪精灵按「屏幕上很小」画的），改成像实机那样一大群小怪围上来；
# Boss 只用 @1x 放在远处地平线当剪影。BIG：(名, 帧, dx, dy, 亮度, @1x?)，dx / dy 以水月精灵高为单位、相对光圈中心
BIG = [("paranoia", 0, -1.45, -0.30, 0.5, True), ("izumik", 1, 1.45, -0.34, 0.5, True)]
SMALL = ["runner", "slider", "spitter", "skimmer", "floater", "offspring", "brood", "nest", "reaper", "tracer",
         "mimic", "stone", "tear", "bone"]
N_CROWD = 34
CYAN = np.array([120, 235, 245], np.float32)


def half(im):
    """@2x → 半尺寸：每 2×2 取 alpha 多数，颜色取不透明像素的众数（保持色块干净）"""
    a = np.asarray(im)
    h, w = a.shape[0] // 2 * 2, a.shape[1] // 2 * 2
    a = a[:h, :w].reshape(h // 2, 2, w // 2, 2, 4).transpose(0, 2, 1, 3, 4).reshape(h // 2, w // 2, 4, 4)
    out = np.zeros((h // 2, w // 2, 4), np.uint8)
    for y in range(h // 2):
        for x in range(w // 2):
            px = a[y, x]
            op = px[px[:, 3] > 127]
            if len(op) >= 2:
                k = (op[:, 0].astype(int) << 16) | (op[:, 1].astype(int) << 8) | op[:, 2]
                v, n = np.unique(k, return_counts=True)
                out[y, x] = op[np.argmax(k == v[np.argmax(n)])]
    return Image.fromarray(out)


def enemy(name, i, one_x=False, halve=False):
    im = Image.open(ENEMY / name / (f"e_{name}.png" if one_x else f"e_{name}@2x.png")).convert("RGBA")
    h = im.height
    n = max(1, im.width // h)
    fr = im.crop(((i % n) * h, 0, (i % n + 1) * h, h)) if n > 1 else im
    fr = fr.crop(fr.getbbox())
    return half(fr) if halve else fr


def paste_lit(g, spr, fx, fy, light, bright, hm, face_left):
    """贴一只怪：朝向光、环境色、离光越远越暗、朝光一侧 1 格青色边光"""
    if face_left:
        spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(spr).astype(np.float32)
    sh, sw = a.shape[:2]
    m = a[..., 3] > 127
    gh, gw = g.shape[:2]
    x0, y0 = int(fx - sw / 2), int(fy - sh)
    d = math.hypot(fx - light[0], (fy - sh / 2) - light[1]) / hm
    k = float(np.clip(1.15 - 0.35 * d, 0.3, 1.0)) * bright
    # 11-07 剪影化：怪身压成深海蓝剪影（保留一点原明暗），原图里的亮点（眼睛 / 发光部位）变成青色发光
    lum = (a[..., :3] * [0.299, 0.587, 0.114]).sum(-1, keepdims=True) / 255
    sil = np.array([10, 20, 32], np.float32) + lum * np.array([30, 52, 70]) * k
    rgb = sil
    r_, g_, b_ = a[..., 0], a[..., 1], a[..., 2]
    glow = m & (g_ > 150) & (b_ > 170) & (r_ < 150)        # 只认原图里本来就是青色的亮点（海嗣的眼）
    rgb = np.where(glow[..., None], CYAN * (0.6 + 0.4 * k), rgb)
    # 朝光边缘：沿「指向光」方向的邻格是透明的边缘像素
    vx, vy = light[0] - fx, light[1] - (fy - sh / 2)
    nv = math.hypot(vx, vy) or 1
    sx, sy = int(round(vx / nv)), int(round(vy / nv))
    from scipy.ndimage import binary_fill_holes
    mf = binary_fill_holes(m)                                # 填掉身体内部空洞：边光只在外轮廓
    p = np.pad(mf, 1)
    nb = p[1 + sy:1 + sy + sh, 1 + sx:1 + sx + sw]
    rim = m & ~nb
    rim_k = float(np.clip(0.9 - 0.25 * d, 0.2, 0.7))
    rgb[rim] = rgb[rim] * (1 - rim_k) + CYAN * rim_k
    ys0, xs0 = max(0, y0), max(0, x0)
    ys1, xs1 = min(gh, y0 + sh), min(gw, x0 + sw)
    if ys1 <= ys0 or xs1 <= xs0:
        return
    sub_m = m[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0]
    sub = rgb[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0]
    reg = g[ys0:ys1, xs0:xs1]
    reg[sub_m] = np.clip(sub[sub_m], 0, 255).astype(np.uint8)


def build(kind):
    (W, H), cell, up, logo_y = Hh.SIZES[kind]
    gw, gh = W // cell, H // cell
    if kind == "itch_banner":
        big = Hh.bg_pixels_path(BGW, W, H, cell, 1.06)
        grid, rmask, center = Hh.crop_on_ring(big, gw, gh, Hh.BANNER["floor_y"], Hh.BANNER["ring_x"])
    else:
        big = Hh.bg_pixels_path(BG, W, H, cell, Hh.OVER)
        grid, rmask, center = Hh.crop_on_ring(big, gw, gh, Hh.FLOOR[1])
    n = Hh.SHIFT[kind]
    grid, rmask = Hh.shift_down(grid, n), Hh.shift_down(rmask, n)
    cx, cy = center[0], center[1] + n
    miz = Hh.sprite(MIZ)
    hm = miz.height
    light = (cx, cy - hm * 0.15)
    items = []
    for name, fi, dx, dy, br, ox in BIG:
        items.append((cy + dy * hm, name, fi, cx + dx * hm, br, ox))
    rng = np.random.default_rng(5)
    placed = 0
    while placed < N_CROWD:
        ang = rng.uniform(0, 2 * math.pi)
        if 0.35 * math.pi < ang < 0.65 * math.pi:      # 正前方留空（不压水月的腿）
            continue
        rad = rng.uniform(1.05, 2.3)
        dx, dy = rad * math.cos(ang), rad * 0.42 * math.sin(ang)
        if abs(dx) < 0.75 and dy < 0.1:                 # 水月身后正中留空（不和她叠在一起）
            continue
        name = SMALL[int(rng.integers(0, len(SMALL)))]
        br = float(np.clip(1.05 - 0.25 * (rad - 1.05), 0.55, 1.0))
        items.append((cy + dy * hm, name, int(rng.integers(0, 6)), cx + dx * hm, br, "half"))
        placed += 1
    items.sort()
    g = grid.copy()
    behind = [it for it in items if it[0] <= cy]
    front = [it for it in items if it[0] > cy]
    for fy, name, fi, fx, br, ox in behind:
        paste_lit(g, enemy(name, fi, ox is True, ox == "half"), fx, fy, light, br, hm, fx > cx)
    g = Hh.compose_grid(g, miz, rmask, (cx, cy), 0)
    for fy, name, fi, fx, br, ox in front:
        paste_lit(g, enemy(name, fi, ox is True, ox == "half"), fx, fy, light, br, hm, fx > cx)
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
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet")
    a = ap.parse_args()
    outs = {}
    for kind in ("itch_cover", "toy_poster", "itch_banner"):
        im = build(kind)
        W, H = im.size
        im.save(HERE / f"cover_M_{kind}_{W}x{H}.png", optimize=True)
        outs[kind] = im
        print(kind)
    if a.sheet:
        K.sheet([("M", outs["itch_cover"], outs["toy_poster"])], a.sheet)


if __name__ == "__main__":
    main()
