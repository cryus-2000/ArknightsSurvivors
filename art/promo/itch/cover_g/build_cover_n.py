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
# 11-07 用户「少了点压迫感」：怪潮更密更近（程序铺 CROWD 只、两侧叠成墙、只留正前方）、
# 前景两角大怪拉回画面内、光柱后面一只巨大的育母暗影俯视水月
# 11-07 用户「手工摆位清理」：每只怪的位置 / 大小 / 亮度手定（不再随机撒）。
# (名, 高〔水月高倍数〕, dx, dy〔水月高为单位，相对光圈中心脚底〕, 亮度〔< 0.66 = 平涂剪影〕)
# 原则：中景只放轮廓清楚的（spitter / skimmer / slider / offspring），浅色细碎的（runner 骨鱼、floater 白水母）
# 放后排当剪影或浮在上方；左右两组呈楔形朝水月压过来，正前方和她身后正中留空。
LAYOUT = [
    # 前景两角（彩色偏暗，压住下角）
    ("paranoia", 1.25, -1.78, 1.02, 0.72), ("izumik", 1.30, 1.82, 1.08, 0.70),
    # 中景左组
    ("spitter", 0.72, -1.02, 0.10, 0.95), ("skimmer", 0.62, -1.38, -0.16, 0.85),
    # 中景右组
    ("slider", 0.64, 1.02, 0.12, 0.95), ("offspring", 0.52, 1.36, -0.14, 0.85),
    # 后排剪影墙
    ("runner", 0.46, -1.62, -0.40, 0.55), ("nest", 0.48, -1.18, -0.48, 0.52), ("tracer", 0.44, -1.00, -0.62, 0.5),
    ("tracer", 0.44, 1.02, -0.62, 0.5), ("skimmer", 0.48, 1.20, -0.48, 0.52), ("runner", 0.46, 1.64, -0.40, 0.55),
    # 浮在上方的白水母（剪影）
    ("floater", 0.38, -0.95, -1.05, 0.5), ("floater", 0.34, 1.05, -1.15, 0.48),
]
LOOM = None   # 11-07：背后育母暗影在顶部只露出锯齿碎边、读不出是怪，去掉（压迫感交给四周怪墙）       # 背景巨物：(名, 高, dx, dy, 亮度)
CROWD_KINDS = ["slider", "spitter", "skimmer", "runner", "offspring", "floater", "nest", "tracer"]
CROWD = 0   # 11-07 改为全部手工摆位
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


DARK_MOD = np.array([0.2, 0.22, 0.3], np.float32)   # 与游戏 world.gd 灯火暗淡（docs/222）同值
EYE_CACHE = {}


def eye_points(name):
    """游戏 _emit 层（e_<名>_emit@2x.png 第 0 帧）里发光像素的位置，按本体外框归一到 0–1"""
    if name in EYE_CACHE:
        return EYE_CACHE[name]
    base = Image.open(M.ENEMY / name / f"e_{name}@2x.png").convert("RGBA")
    h = base.height
    fr = base.crop((0, 0, h, h)) if base.width > h else base
    bb = fr.getbbox()
    pts = []
    ep = M.ENEMY / name / f"e_{name}_emit@2x.png"
    if ep.exists():
        em = Image.open(ep).convert("RGBA")
        em = em.crop((0, 0, h, h)) if em.width > h else em
        a = np.asarray(em)
        ys, xs = np.nonzero(a[..., 3] > 100)
        if len(xs):
            # 每个发光小团取中心（一只怪通常 1–2 个眼点）
            lab, n = label(a[..., 3] > 100)
            for i in range(1, n + 1):
                yy, xx = np.nonzero(lab == i)
                pts.append(((xx.mean() - bb[0]) / (bb[2] - bb[0]), (yy.mean() - bb[1]) / (bb[3] - bb[1])))
    EYE_CACHE[name] = pts
    return pts


def paste(g, spr, fx, fy, light, bright, hm, face_left, name="", ring_r=0.62):
    """11-07 用户「怪物太亮，用游戏里灯火暗的表示」：本体按到光圈的距离压向 DARK_MOD（圈缘往外 30% 半径内渐变，同游戏），
    近处还留一点原色 + 朝光边光，远处只剩暗轮廓；眼点按游戏 _emit 层的位置画青色十字星，照常亮"""
    if face_left:
        spr = spr.transpose(Image.FLIP_LEFT_RIGHT)
    a = np.asarray(spr).astype(np.float32)
    sh, sw = a.shape[:2]
    m = a[..., 3] > 127
    gh, gw = g.shape[:2]
    x0, y0 = int(fx - sw / 2), int(fy - sh)
    R = ring_r * hm
    dist = math.hypot(fx - light[0], (fy - sh * 0.4) - light[1])
    f = float(np.clip((dist - R * 0.9) / (R * 0.3), 0.0, 1.0))
    mod = (1 - f) * np.ones(3, np.float32) + f * DARK_MOD
    rgb = a[..., :3] * mod * np.array([0.85, 0.93, 1.0]) * bright
    vx, vy = light[0] - fx, light[1] - (fy - sh / 2)
    nv = math.hypot(vx, vy) or 1
    sx, sy = int(round(vx / nv)), int(round(vy / nv))
    mf = binary_fill_holes(m)
    p = np.pad(mf, 1)
    nb = p[1 + sy:1 + sy + sh, 1 + sx:1 + sx + sw]
    rim = m & ~nb
    rk = 0.6 * (1 - f) + 0.12          # 暗处只留很淡的一丝轮廓光
    rgb[rim] = rgb[rim] * (1 - rk) + M.CYAN * rk
    # 眼点：游戏 _emit 位置的青色十字星
    star = 2 if sh > 90 else 1
    for u, v in eye_points(name):
        ex = int(round((1 - u if face_left else u) * (sw - 1)))
        ey = int(round(v * (sh - 1)))
        for dx, dy in [(0, 0)] + [(k * s1, k * s2) for k in range(1, star + 1) for s1, s2 in ((1, 0), (-1, 0), (0, 1), (0, -1))]:
            xx, yy = ex + dx, ey + dy
            if 0 <= xx < sw and 0 <= yy < sh:
                rgb[yy, xx] = (225, 255, 255) if (dx, dy) == (0, 0) else M.CYAN
                m[yy, xx] = True
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
    lay = list(LAYOUT)
    rng = np.random.default_rng(23)
    while len(lay) < len(LAYOUT) + CROWD:
        ang = rng.uniform(0, 2 * math.pi)
        if 0.30 * math.pi < ang < 0.70 * math.pi:        # 正前方留空
            continue
        rad = rng.uniform(0.85, 2.2)
        dx, dy = rad * math.cos(ang), rad * 0.40 * math.sin(ang)
        if abs(dx) < 0.62 and dy < 0.05:                  # 水月身后正中不叠
            continue
        depth = (dy + 0.9) / 1.3                          # 越靠后越小越暗
        hr = float(np.clip(0.38 + 0.32 * depth, 0.3, 0.75)) * rng.uniform(0.85, 1.15)
        br = float(np.clip(0.45 + 0.45 * depth, 0.4, 0.95))
        lay.append((CROWD_KINDS[int(rng.integers(0, len(CROWD_KINDS)))], hr, dx, dy, br))
    items = sorted((cy + dy * hm, name, hr, cx + dx * hm, br) for name, hr, dx, dy, br in lay)
    g = grid.copy()
    # 背景巨物：压暗成剪影，只留一点轮廓光，最先画（在所有怪和水月后面）
    if LOOM:
        ln, lh, ldx, ldy, lbr = LOOM
        paste(g, to_cells(load_src(ln), int(lh * hm)), cx + ldx * hm, cy + ldy * hm, light, lbr, hm, False)
    for fy, name, hr, fx, br in items:
        if fy > cy:
            continue
        paste(g, to_cells(load_src(name), max(6, int(hr * hm))), fx, fy, light, 1.0, hm, fx > cx, name)
    g = Hh.compose_grid(g, miz, rmask, (cx, cy), 0)
    for fy, name, hr, fx, br in items:
        if fy <= cy:
            continue
        paste(g, to_cells(load_src(name), max(6, int(hr * hm))), fx, fy, light, 1.0, hm, fx > cx, name)
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
