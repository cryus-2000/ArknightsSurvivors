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

BG = sorted(glob.glob(str(B.RAW / "cover1107_bgdome" / "raw_*.png")))[0]
OPS = B.ROOT / "game/art/operators/mizuki"
FRAMES = {"a": "mizuki_runtime_attack@2x.png", "s": "mizuki_runtime_skill_attack@2x.png",
          "l": "mizuki_runtime_skill_loop@2x.png", "e": "mizuki_runtime_skill_end@2x.png"}
# 名字：(成品尺寸, 像素格, logo/标注倍数, logo 顶边)
SIZES = {"itch_cover": ((630, 500), 3, 1, 16), "toy_poster": ((1200, 900), 5, 2, 14)}
SHIFT = {"itch_cover": 12, "toy_poster": 10}   # 整个画面下移的格数（给标题让位，水月头顶不碰副行）
FLOOR = (0.50, 0.70)   # 护盾地面中心（相对去掉黑带后的画面）
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
    x, y, cw, ch = X.crop_box(raw, gw, gh, 0.5, 0.5)
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
    fx, fy = int(gw * FLOOR[0]), int(gh * FLOOR[1]) + n_shift
    x0, y0 = fx - sw // 2, fy - sh
    m = a[..., 3] > 127
    # 描边光：alpha 外扩 1 格的一圈，按 60% 混青色
    p = np.pad(m, 1)
    ring = (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]) & ~m
    # 脚下暗影：一条 2 格高的椭圆
    yy, xx = np.mgrid[0:gh, 0:gw]
    shadow = ((xx - fx) / (sw * 0.45)) ** 2 + ((yy - fy) / 2.2) ** 2 < 1
    g[shadow] = (g[shadow] * 0.45).astype(np.uint8)
    reg = g[y0:y0 + sh, x0:x0 + sw]
    rr = ring[:reg.shape[0], :reg.shape[1]]
    reg[rr] = (reg[rr] * 0.4 + CYAN * 0.6).astype(np.uint8)
    mm = m[:reg.shape[0], :reg.shape[1]]
    reg[mm] = a[..., :3][:reg.shape[0], :reg.shape[1]][mm]
    return g


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
