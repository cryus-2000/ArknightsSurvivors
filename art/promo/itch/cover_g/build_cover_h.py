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
SHIFT = {"itch_cover": 12, "toy_poster": 10}   # 整个画面下移的格数（给标题让位，水月头顶不碰副行）
FLOOR = (0.47, 0.71)   # 青光空地中心（相对整张生图）
CYAN = np.array([120, 235, 245], np.uint8)


def sprite(key):
    k, i = key.split(":")
    im = Image.open(OPS / FRAMES[k]).convert("RGBA")
    h = im.height
    fr = im.crop((int(i) * h, 0, (int(i) + 1) * h, h))
    return fr.crop(fr.getbbox())


def bg_pixels(W, H, cell):
    raw = K.fill_band(Image.open(BG).convert("RGB"))
    gw, gh = W // cell, H // cell
    x, y, cw, ch = X.crop_box(raw, gw, gh, FLOOR[0], 0.5)   # 11-07：裁切以青光空地为中心，人物居中后仍踩在光圈中央
    c = raw.crop((x, y, x + cw, y + ch))
    # 怪潮发闷：中间调对比 ×1.25（以 0.3 为中点），让深色海嗣剪影读得出
    ca = np.asarray(c, np.float32) / 255
    ca = np.clip(0.3 + (ca - 0.3) * 1.25, 0, 1)
    c = Image.fromarray((ca * 255).astype(np.uint8))
    big = c.resize((gw * 4, gh * 4), Image.LANCZOS)
    q = big.quantize(colors=K.COLORS, method=Image.Quantize.MAXCOVERAGE, dither=Image.Dither.NONE, kmeans=4)
    pal = np.array(q.getpalette()[:K.COLORS * 3], np.uint8).reshape(-1, 3)
    return pal[K.mode_down(np.asarray(q), 4)]          # gh×gw×3，1 像素 = 1 格


def shift_down(grid, n):
    """整幅下移 n 格：顶上补最上一行的颜色（本来就是暗渐变区），底部裁掉"""
    top = np.repeat(grid[:1], n, axis=0)
    return np.concatenate([top, grid[:-n]], 0)


def compose_grid(grid, spr, n_shift=0):
    """在格子分辨率上贴水月：脚踩护盾地面中心；外圈 1 格青色描边光 + 脚下一小块暗影"""
    g = grid.copy()
    gh, gw = g.shape[:2]
    a = np.asarray(spr)
    sh, sw = a.shape[:2]
    m = a[..., 3] > 127
    # 11-07 用户「人物居中一点」：以头部（精灵最上面 30% 的不透明像素）水平中心对准画面中线，伞伸出去多长都不影响
    top = m[: max(1, int(sh * 0.3))]
    hx = int(np.nonzero(top.any(0))[0].mean())
    fx, fy = gw // 2, int(gh * FLOOR[1]) + n_shift
    x0, y0 = fx - hx, fy - sh
    # 描边光：alpha 外扩 1 格的一圈，按 60% 混青色
    p = np.pad(m, 1)
    ring = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]) & ~m
    # 脚下暗影：一条 2 格高的椭圆
    yy, xx = np.mgrid[0:gh, 0:gw]
    shadow = ((xx - fx) / (sw * 0.22)) ** 2 + ((yy - fy) / 1.6) ** 2 < 1
    g[shadow] = (g[shadow] * 0.7).astype(np.uint8)   # 11-07：原来的硬黑条太突兀，改浅、窄
    reg = g[y0:y0 + sh, x0:x0 + sw]
    rr = ring[:reg.shape[0], :reg.shape[1]]
    reg[rr] = (reg[rr] * 0.4 + CYAN * 0.6).astype(np.uint8)
    mm = m[:reg.shape[0], :reg.shape[1]]
    reg[mm] = a[..., :3][:reg.shape[0], :reg.shape[1]][mm]
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
    n = SHIFT[kind]
    grid = compose_grid(shift_down(bg_pixels(W, H, cell), n), sprite(key), n)
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
    a = ap.parse_args()
    outs = []
    for key in a.frames.split(","):
        name = "H_" + key.replace(":", "")
        it, ty = build(key, "itch_cover"), build(key, "toy_poster")
        it.save(HERE / f"cover_{name}_itch_cover_630x500.png", optimize=True)
        ty.save(HERE / f"cover_{name}_toy_poster_1200x900.png", optimize=True)
        outs.append((name, it, ty))
        print(name)
    if a.sheet:
        K.sheet(outs, a.sheet)


if __name__ == "__main__":
    main()
