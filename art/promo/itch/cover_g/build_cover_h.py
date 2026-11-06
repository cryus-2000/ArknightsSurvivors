"""商店封面 H（11-07，用户：方向对〔怪潮包围、参考 Crimsonland / Soulstone Survivors〕，但水月画风全没了、要像素画）。
约束：水月不交给 AI 画 —— 用游戏内水月精灵（已按 PRTS 核对），1 个精灵像素 = 1 个封面像素格，整数倍放大；
AI（gemini-3-pro-image）只画背景：像素风海嗣潮 + 中间留空的青色护盾，提示词明令画面无人。
背景按同一像素格大小像素化（收色 → 每格取众数），整张同一套像素尺度；水月外圈 1 格青色描边光（像素式，不用模糊光晕）。
用法：python art/promo/itch/cover_g/build_cover_h.py [--frames a:2,s:0 ...] [--sheet <路径>]
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
import build_cover_k as K  # noqa: E402

BG = sorted(glob.glob(str(B.RAW / "cover1107_bgopen" / "raw_*.png")))[0]   # 11-07 用户：盾不要了 → 无护盾、中间青光空地的背景
OPS = B.ROOT / "game/art/operators/mizuki"
FRAMES = {"a": "mizuki_runtime_attack@2x.png", "s": "mizuki_runtime_skill_attack@2x.png",
          "l": "mizuki_runtime_skill_loop@2x.png", "e": "mizuki_runtime_skill_end@2x.png",
          "t": "mizuki_runtime_s1_attack@2x.png", "r": "mizuki_runtime_run@2x.png", "b": "mizuki_runtime_skill_start@2x.png",
          "n": "op_mizuki_entry@2x.png"}
# 名字：(成品尺寸, 像素格, logo/标注倍数, logo 顶边)
SIZES = {"itch_cover": ((630, 500), 3, 1, 16), "toy_poster": ((1200, 900), 5, 2, 14)}
SHIFT = {"itch_cover": 12, "toy_poster": 10, "itch_banner": 0}
SIZES["itch_banner"] = ((960, 400), 2, 1, 0)
# 横幅（11-07）：背景用 relit0 左右外扩到 21:9 的生图；光圈 / 水月在右侧，标题在左侧暗区
BANNER = {"bg": None, "ring_x": 0.68, "floor_y": 0.86, "logo_xy": (34, 72)}   # 整个画面下移的格数（给标题让位，水月头顶不碰副行）
FLOOR = (0.47, 0.71)   # 青光空地中心（相对整张生图）
CYAN = np.array([120, 235, 245], np.uint8)


def sprite(key):
    k, i = key.split(":")
    im = Image.open(OPS / FRAMES[k]).convert("RGBA")
    h = im.height
    fr = im.crop((int(i) * h, 0, (int(i) + 1) * h, h))
    return fr.crop(fr.getbbox())


OVER = 1.15   # 背景多做 15% 的余量，按青光圈中心再裁（11-07：光圈要和人物对齐居中）


def bg_pixels(W, H, cell, over=OVER):
    raw = K.fill_band(Image.open(BG).convert("RGB"))
    gw, gh = int(W // cell * over), int(H // cell * over)
    x, y, cw, ch = X.crop_box(raw, gw, gh, 0.5, 0.5)
    c = raw.crop((x, y, x + cw, y + ch))
    ca = np.asarray(c, np.float32) / 255
    ca = np.clip(0.3 + (ca - 0.3) * 1.25, 0, 1)
    c = Image.fromarray((ca * 255).astype(np.uint8))
    big = c.resize((gw * 4, gh * 4), Image.LANCZOS)
    q = big.quantize(colors=BG_COLORS, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE, kmeans=4)
    pal = np.array(q.getpalette()[:BG_COLORS * 3], np.uint8).reshape(-1, 3)
    return pal[K.mode_down(np.asarray(q), 4)]


BG_COLORS = 112   # 11-07 用户「头上面的光线有点割裂」：48 色把柔和光柱切成硬边竖色带，多收些色让台阶变细


def ring_center(g):
    """在格子图里找地面青光圈：亮青像素（G、B 高，R 低）在中下部的分布，取 5% / 95% 分位的中点"""
    gh, gw = g.shape[:2]
    r, gg, b = [g[..., i].astype(int) for i in range(3)]
    m = (gg > 170) & (b > 170) & (r < 160)
    m[: int(gh * 0.5)] = False
    m[:, : int(gw * 0.15)] = False
    m[:, int(gw * 0.85):] = False
    ys, xs = np.nonzero(m)
    cx = (np.percentile(xs, 5) + np.percentile(xs, 95)) / 2
    cy = (np.percentile(ys, 5) + np.percentile(ys, 95)) / 2
    return int(round(cx)), int(round(cy)), m


def crop_on_ring(big, gw, gh, floor_y, ring_x=0.5):
    """把带余量的格子图裁到 gw×gh：光圈中心落在水平 ring_x、竖直 floor_y 处"""
    cx, cy, m = ring_center(big)
    Hb, Wb = big.shape[:2]
    x0 = int(np.clip(cx - int(gw * ring_x), 0, Wb - gw))
    y0 = int(np.clip(cy - int(gh * floor_y), 0, Hb - gh))
    return big[y0:y0 + gh, x0:x0 + gw], m[y0:y0 + gh, x0:x0 + gw], (cx - x0, cy - y0)


def bg_pixels_path(path, W, H, cell, over):
    global BG
    old = BG
    BG = path
    try:
        return bg_pixels(W, H, cell, over)
    finally:
        BG = old


def shift_down(grid, n):
    """整幅下移 n 格：顶上补最上一行的颜色（本来就是暗渐变区），底部裁掉"""
    if n <= 0:
        return grid
    top = np.repeat(grid[:1], n, axis=0)
    return np.concatenate([top, grid[:-n]], 0)


def compose_grid(grid, spr, ringmask, center, n_shift=0):
    """贴水月（11-07 改：不再整圈描边〔像贴纸〕）：
    - 环境色：整体乘一点深海青，越往脚越受地面青光照亮；
    - 反光：只在下半身、朝外的边缘加青色反光（光从地面光圈来）；
    - 前后关系：光圈前半圈（脚下以下的亮青像素）重新画在脚前面；身前撒几颗飞溅光点。"""
    g = grid.copy()
    gh, gw = g.shape[:2]
    a = np.asarray(spr).astype(np.float32)
    sh, sw = a.shape[:2]
    m = a[..., 3] > 127
    top = m[: max(1, int(sh * 0.3))]
    hx = int(np.nonzero(top.any(0))[0].mean())
    fx, fy = center[0], center[1] + n_shift
    x0, y0 = fx - hx, fy - sh + 1
    # 环境色 + 地面上光
    yy = np.linspace(0, 1, sh)[:, None]
    amb = np.array([0.86, 0.94, 1.0])
    up = np.clip((yy - 0.55) / 0.45, 0, 1)[..., None] * np.array([0.10, 0.30, 0.34]) * 255 * 0.35
    rgb = np.clip(a[..., :3] * amb + up, 0, 255)
    # 下半身朝外边缘的反光
    p = np.pad(m, 1)
    edge = m & ~(p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:])
    lower = (np.arange(sh)[:, None] > sh * 0.45)
    rim = edge & lower
    rgb[rim] = rgb[rim] * 0.45 + np.array([120, 235, 245]) * 0.55
    # 11-07 用户「头像是贴上去的，和背景不在一个图层」：
    # ① 选择性描边：外圈近黑描边换成「背后背景色 + 深青」，不再一圈黑线；
    # ② 顶光：光柱从头顶来，朝上的边缘（上邻透明）在上半身加淡青白受光；
    # ③ 光包边：边缘一格按背后亮度混入背景光（背后越亮混得越多）。
    gh_, gw_ = grid.shape[:2]
    bx0, by0 = fx - hx, fy - sh + 1
    behind = np.zeros((sh, sw, 3), np.float32)
    ys0, xs0 = max(0, by0), max(0, bx0)
    ys1, xs1 = min(gh_, by0 + sh), min(gw_, bx0 + sw)
    behind[ys0 - by0:ys1 - by0, xs0 - bx0:xs1 - bx0] = grid[ys0:ys1, xs0:xs1]
    blum = (behind * [0.299, 0.587, 0.114]).sum(-1)
    lum = (rgb * [0.299, 0.587, 0.114]).sum(-1)
    dark_edge = edge & (lum < 70)
    rgb[dark_edge] = behind[dark_edge] * 0.5 + np.array([18, 52, 66]) * 0.5
    up_open = m & ~p[:-2, 1:-1]
    upper = (np.arange(sh)[:, None] < sh * 0.55)
    toplit = up_open & upper
    rgb[toplit] = rgb[toplit] * 0.5 + np.array([205, 245, 250]) * 0.5
    wrap = edge & ~dark_edge & ~toplit
    k = np.clip((blum - 60) / 140, 0, 0.45)[..., None]
    rgb = np.where(wrap[..., None], rgb * (1 - k) + behind * k, rgb)
    # 脚下暗影（浅、窄）
    gy, gx = np.mgrid[0:gh, 0:gw]
    shadow = ((gx - fx) / (sw * 0.2)) ** 2 + ((gy - fy) / 1.4) ** 2 < 1
    g[shadow] = (g[shadow] * 0.75).astype(np.uint8)
    reg = g[y0:y0 + sh, x0:x0 + sw]
    mm = m[:reg.shape[0], :reg.shape[1]]
    reg[mm] = rgb[:reg.shape[0], :reg.shape[1]][mm].astype(np.uint8)
    # 光圈前半圈画回脚前（脚底所在行以下 1 格起）
    front = ringmask.copy()
    front[: fy] = False
    g[front] = grid[front]
    # 身前飞溅光点
    rng = np.random.default_rng(11)
    for _ in range(14):
        x = int(fx + rng.normal(0, sw * 0.35))
        y = int(fy - rng.uniform(0, sh * 0.45))
        if 0 <= x < gw and 0 <= y < gh:
            g[y, x] = (235, 255, 255) if rng.random() < 0.4 else (120, 235, 245)
    if THRUST:
        thrust_lines(g, m, x0, y0)
    return g


THRUST = True


def thrust_lines(g, m, x0, y0):
    """刺击方向（向左）的像素冲刺线：伞尖前方几道青色横线（亮芯 + 暗青尾），伞尖一个十字亮点"""
    gh, gw = g.shape[:2]
    cols = np.nonzero(m.any(0))[0]
    tip_x = cols[0]
    rows = np.nonzero(m[:, tip_x])[0]
    ty, tx = y0 + int(rows.mean()), x0 + tip_x
    core, mid, tail = np.array([235, 255, 255]), np.array([120, 235, 245]), np.array([40, 140, 160])
    rng = np.random.default_rng(7)
    for dy, ln in ((0, 26), (-3, 16), (3, 18), (-6, 9), (6, 11), (-1, 34), (2, 22)):
        y = ty + dy
        if not 0 <= y < gh:
            continue
        start = tx - 2 - int(rng.integers(0, 4))
        for k in range(ln):
            x = start - k
            if not 0 <= x < gw:
                break
            t = k / ln
            c = core if t < 0.25 else (mid if t < 0.6 else tail)
            al = 1.0 if t < 0.6 else 0.6
            g[y, x] = (g[y, x] * (1 - al) + c * al).astype(np.uint8)
    for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (-2, 0), (0, -2), (0, 2)):
        x, y = tx - 1 + dx, ty + dy
        if 0 <= x < gw and 0 <= y < gh:
            g[y, x] = core if abs(dx) + abs(dy) <= 1 else mid


def build(key, kind):
    (W, H), cell, up, logo_y = SIZES[kind]
    gw, gh = W // cell, H // cell
    if kind == "itch_banner":
        big = bg_pixels_path(BANNER["bg"], W, H, cell, 1.06)
        grid, rmask, center = crop_on_ring(big, gw, gh, BANNER["floor_y"], BANNER["ring_x"])
    else:
        big = bg_pixels(W, H, cell)
        grid, rmask, center = crop_on_ring(big, gw, gh, FLOOR[1])
    n = SHIFT[kind]
    grid, rmask = shift_down(grid, n), shift_down(rmask, n)
    grid = compose_grid(grid, sprite(key), rmask, center, n)
    # 顶部平滑压暗到统一深色（盖掉生图黑带补过渡留下的台阶，也给标题干净底）
    t = np.clip(1 - np.arange(gh) / (gh * 0.48), 0, 1)[:, None, None] ** 1.8 * 0.92   # 拉长放缓：光柱往上慢慢淡出，不被截断
    grid = (grid * (1 - t) + np.array([6, 10, 16]) * t).astype(np.uint8)
    if kind == "itch_banner":
        # 底边压暗（外扩生图左下有一截黑边）+ 左侧压暗（标题区）
        tb = np.clip((np.arange(gh) - gh * 0.72) / (gh * 0.28), 0, 1)[:, None, None] ** 1.5 * 0.85
        tl = np.clip(1 - np.arange(gw) / (gw * 0.45), 0, 1)[None, :, None] ** 1.4 * 0.6
        t2 = np.maximum(tb, tl)
        grid = (grid * (1 - t2) + np.array([6, 10, 16]) * t2).astype(np.uint8)
    img = Image.fromarray(grid).resize((grid.shape[1] * cell, grid.shape[0] * cell), Image.NEAREST)
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
        x0, y0 = BANNER["logo_xy"][0], BANNER["logo_xy"][1] - padt
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
    ap.add_argument("--frames", default="s:0,a:2")
    ap.add_argument("--sheet")
    ap.add_argument("--bg", default="", help="背景生图路径（缺省 cover1107_bgopen；11-07 重打光版在 cover1107_relit）")
    ap.add_argument("--suffix", default="")
    ap.add_argument("--banner_bg", default="", help="横幅背景生图（21:9 外扩）")
    a = ap.parse_args()
    global BG
    if a.bg:
        BG = a.bg
    outs = []
    for key in a.frames.split(","):
        name = "H_" + key.replace(":", "") + a.suffix
        it, ty = build(key, "itch_cover"), build(key, "toy_poster")
        if a.banner_bg:
            BANNER["bg"] = a.banner_bg
            bn = build(key, "itch_banner")
            bn.save(HERE / f"cover_{name}_itch_banner_960x400.png", optimize=True)
        it.save(HERE / f"cover_{name}_itch_cover_630x500.png", optimize=True)
        ty.save(HERE / f"cover_{name}_toy_poster_1200x900.png", optimize=True)
        outs.append((name, it, ty))
        print(name)
    if a.sheet:
        K.sheet(outs, a.sheet)


if __name__ == "__main__":
    main()
