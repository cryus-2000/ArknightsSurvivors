"""蚀刻章页「深蓝之下」像素化烘焙（Claude 接入，10-25）。
用户：「改成我们的像素风格并且保持一致」。按标题页「青光航标」的像素精度（docs/67 §13.3）重新量化 Codex 交付：
- 背景 ocean_backdrop_v7.png：1280×720 下 1 美术像素 = 3 逻辑像素 → 428×240 网格（四周各留 PAD 格给形变）；
  不在这里压色，游戏里 shader 先做低频形变再按 bg_pal.png 的 24 色就近取色（无抖动），形变后每帧仍是干净的像素画。
- 九枚章 medals_silver_clean_1025.png：同一个美术像素尺寸（版式里的 grid，设计像素），各章按版式里的半径出图；
  九枚共用一套色板（≤ MEDAL_COLORS 色），六边形硬边二值透明，去孤立像素。
版式读 game/data/medals_layout.json（v2，10-25 用户让 Claude 重排；Codex 的 approved_layout_1025.json 留作原稿）。
用法：python bake_pixel.py [--layout game/data/medals_layout.json] [--out game/art/ui/medals] [--preview build/medals_preview.png]
"""
from pathlib import Path
import argparse, json, math
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GRID_BG = (428, 240)          # 标题页同精度：1280×720 下 3 逻辑像素一格
PAD = 6                       # 形变留边（美术像素）
BG_COLORS = 24
MEDAL_COLORS = 24
CELLS = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 7: 5, 8: 6, 10: 7, 11: 8}   # 章 id → 图集格（同 apply_pixel_medals.py）
SRC_R = 200                   # 图集里一格的六边形半径（源像素）


def hex_mask(n, r_px):
    """尖顶六边形二值遮罩（像素中心在内即算）"""
    m = Image.new("L", (n, n), 0)
    px = m.load()
    c = n / 2.0
    for y in range(n):
        for x in range(n):
            dx = abs(x + 0.5 - c)
            dy = abs(y + 0.5 - c)
            # 尖顶：|x| ≤ r·cos30，且 |y| + |x|·tan30 ≤ r
            if dx <= r_px * math.cos(math.pi / 6) and dy + dx * math.tan(math.pi / 6) <= r_px:
                px[x, y] = 255
    return m


def despeckle(im, mask):
    """孤立像素：四邻没有同色、且至少三个四邻同为另一色 → 并进那一色（只动遮罩内）"""
    w, h = im.size
    src = im.load()
    mk = mask.load()
    out = im.copy()
    dst = out.load()
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if not mk[x, y]:
                continue
            c = src[x, y]
            nb = [src[x + 1, y], src[x - 1, y], src[x, y + 1], src[x, y - 1]]
            if c in nb:
                continue
            best = max(set(nb), key=nb.count)
            if nb.count(best) >= 3:
                dst[x, y] = best
    return out


def locked(im):
    """未获得：同一张图按亮度换成暗钢蓝一阶色（逐色映射，色数不增加），轮廓与蚀刻纹样仍看得出"""
    out = im.copy()
    px = out.load()
    for y in range(out.size[1]):
        for x in range(out.size[0]):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            v = (0.3 * r + 0.59 * g + 0.11 * b) / 255.0
            v = v ** 1.15
            px[x, y] = (int(16 + 92 * v), int(24 + 104 * v), int(38 + 118 * v), 255)
    return out


def bake_medals(layout, out_dir):
    grid = float(layout["grid"])
    atlas = Image.open(HERE / "medals_silver_clean_1025.png").convert("RGBA")
    smalls = {}
    for m in layout["medals"]:
        mid, r = m["id"], m["radius"]
        cell = CELLS[mid]
        cx, cy = 209 + 418 * (cell % 3), 209 + 418 * (cell // 3)
        n = int(round(2 * r / grid))
        crop = atlas.crop((cx - SRC_R, cy - SRC_R, cx + SRC_R, cy + SRC_R))
        # 先轻微锐化保住倒角高光，再按面积平均缩到美术像素
        crop = crop.filter(ImageFilter.UnsharpMask(radius=2, percent=60, threshold=2))
        small = crop.resize((n, n), Image.BOX)
        smalls[mid] = (small, hex_mask(n, n / 2.0))
    # 九枚共用色板：把所有遮罩内像素拼成一张图求色板
    total = sum(s.size[0] * s.size[1] for s, _ in smalls.values())
    side = int(math.ceil(math.sqrt(total))) + 1
    sheet = Image.new("RGB", (side, side), (0, 0, 0))
    i = 0
    sp = sheet.load()
    for s, mk in smalls.values():
        rgb = s.convert("RGB").load()
        mkp = mk.load()
        for y in range(s.size[1]):
            for x in range(s.size[0]):
                if mkp[x, y]:
                    sp[i % side, i // side] = rgb[x, y]
                    i += 1
    # 空位填遮罩内第一个像素，不让纯黑挤进色板
    first = sp[0, 0]
    for j in range(i, side * side):
        sp[j % side, j // side] = first
    pal_img = sheet.quantize(colors=MEDAL_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    out_dir.mkdir(parents=True, exist_ok=True)
    res = {}
    for mid, (s, mk) in smalls.items():
        q = s.convert("RGB").quantize(palette=pal_img, dither=Image.Dither.NONE)
        q = despeckle(q, mk).convert("RGBA")
        q.putalpha(mk)
        # 遮罩外的 RGB 清零（二值透明，免得线性取样时带出杂色）
        px = q.load()
        for y in range(q.size[1]):
            for x in range(q.size[0]):
                if px[x, y][3] == 0:
                    px[x, y] = (0, 0, 0, 0)
        q.save(out_dir / f"medal_{mid}.png")
        locked(q).save(out_dir / f"medal_{mid}_off.png")
        res[mid] = q
    pal = pal_img.getpalette()[: MEDAL_COLORS * 3]
    return res, pal


def bake_bg(out_dir):
    src = Image.open(HERE / "ocean_backdrop_v7.png").convert("RGB")
    gw, gh = GRID_BG[0] + 2 * PAD, GRID_BG[1] + 2 * PAD
    # 原图按「铺满 + 四周留边」缩到美术像素网格（等比，居中裁切）
    k = max(gw / src.size[0], gh / src.size[1])
    tmp = src.resize((int(math.ceil(src.size[0] * k)), int(math.ceil(src.size[1] * k))), Image.BOX)
    ox, oy = (tmp.size[0] - gw) // 2, (tmp.size[1] - gh) // 2
    bg = tmp.crop((ox, oy, ox + gw, oy + gh))
    bg.save(out_dir / "bg_src.png")   # 不压色：shader 形变后再就近取色
    pal = bg.quantize(colors=BG_COLORS, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    cols = pal.getpalette()[: BG_COLORS * 3]
    strip = Image.new("RGB", (BG_COLORS, 1))
    for j in range(BG_COLORS):
        strip.putpixel((j, 0), tuple(cols[j * 3: j * 3 + 3]))
    strip.save(out_dir / "bg_pal.png")
    still = pal.convert("RGB")   # 静帧（减少动态效果 / 预览用；shader 在 time=0 时与它一致）
    return still


def preview(medals, bg, layout, path):
    """预览：背景放大到版式画布 + 九枚章按版式摆好（最近邻放大）"""
    grid = float(layout["grid"])
    big = bg.crop((PAD, PAD, PAD + GRID_BG[0], PAD + GRID_BG[1])).resize(tuple(layout["canvas"]), Image.NEAREST).convert("RGBA")
    for m in layout["medals"]:
        im = medals[m["id"]]
        sz = int(round(im.size[0] * grid))
        up = im.resize((sz, sz), Image.NEAREST)
        cx, cy = m["center"]
        big.alpha_composite(up, (int(round(cx - sz / 2)), int(round(cy - sz / 2))))
    path.parent.mkdir(parents=True, exist_ok=True)
    big.save(path)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--layout", default=str(ROOT / "game/data/medals_layout.json"))
    ap.add_argument("--out", default=str(ROOT / "game/art/ui/medals"))
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    out = Path(a.out)
    lay = json.loads(Path(a.layout).read_text(encoding="utf-8"))
    md, pal = bake_medals(lay, out)
    bg = bake_bg(out)
    if a.preview:
        preview(md, bg, lay, Path(a.preview))
    print("grid=%s medals=%s colors=%d" % (lay["grid"], {k: v.size[0] for k, v in md.items()}, len(pal) // 3))
