"""标题页·深海水母 v2（10-24 用户：底图对像素风太精细，按游戏像素精度做；要有动态，水母要能动）。
- 3 像素格：640×360 原图 → 428×240（1280×720 逻辑下 1 美术像素 = 3 逻辑像素），共用 28 色调色板、无抖动、去孤立像素；
- 三只水母从底图拆成独立图层（水母像素 = 比周围水色亮出一截的像素，限定在各自范围内），底图背后用邻域扩散补全；
- 每只水母另出一张柔光遮罩（跟着水母走）。
产物 game/art/ui/title_deep/：bg.png、jelly_<i>.png、jglow_<i>.png；锚点 / 范围写 jelly.json（着色器常量据此填）。
调试图 build/title_jelly/v2_*.png。
运行：D:/Anaconda/python.exe -B art/incoming/title_jelly_1024/bake_v2.py
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

P = Path(__file__).resolve().parent
ROOT = P.parents[2]
OUT = ROOT / 'game/art/ui/title_deep'
DBG = ROOT / 'build/title_jelly'
GW, GH = 428, 240
K = GW / 640.0

# 640×360 原图坐标：范围多边形（含触须）、伞顶锚点、主轴方向（伞顶 → 触须）、伞体长度
JELLIES = [
    {'poly': [(374, 74), (490, 74), (492, 162), (456, 232), (404, 276), (328, 286), (294, 266), (306, 226), (338, 192), (344, 168), (360, 140)],
     'anchor': (430, 86), 'axis': (-0.56, 0.83), 'bell': 64.0},
    {'poly': [(250, 192), (300, 192), (302, 232), (292, 272), (262, 276), (246, 240)],
     'anchor': (276, 197), 'axis': (-0.15, 0.99), 'bell': 22.0},
    {'poly': [(505, 88), (538, 88), (540, 120), (536, 142), (512, 142), (504, 118)],
     'anchor': (521, 92), 'axis': (-0.05, 1.0), 'bell': 15.0},
]


def lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def poly_mask(poly, w=640, h=360):
    m = Image.new('L', (w, h), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return np.array(m) > 0


def inpaint(img, hole, iters=400):
    """邻域扩散补洞：洞里的像素反复取四邻已知像素的均值"""
    out = img.copy()
    known = ~hole
    out[hole] = 0
    w = known.astype(np.float32)
    for _ in range(iters):
        s = np.zeros_like(out)
        c = np.zeros(hole.shape, np.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            s += np.roll(np.roll(out * w[..., None], dy, 0), dx, 1)
            c += np.roll(np.roll(w, dy, 0), dx, 1)
        upd = hole & (c > 0)
        out[upd] = s[upd] / c[upd][:, None]
        w = np.where(upd, 1.0, w).astype(np.float32)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    DBG.mkdir(parents=True, exist_ok=True)
    src = np.asarray(Image.open(P / 'src/background_native.png').convert('RGB')).astype(np.float32)
    L = lum(src)
    base = ndimage.median_filter(L, size=17)
    hole = np.zeros(L.shape, bool)
    alphas = []
    for j in JELLIES:
        region = poly_mask(j['poly'])
        lift = L - base
        a = np.clip((lift - 6.0) / 22.0, 0.0, 1.0) * region
        a = np.maximum(a, ((L > 118) & region) * 1.0)
        a = ndimage.grey_closing(a, size=(2, 2))
        # 伞体内部亮度高、与中值底色差得少，单靠「亮出一截」会漏掉：轮廓闭合后填满，内部给半透明
        solid = ndimage.binary_fill_holes(ndimage.binary_closing(a > 0.15, iterations=3)) & region
        a = np.where(solid, np.maximum(a, 0.45), a)
        alphas.append(a)
        # 补洞范围比水母大一圈（主水母 7 格）：原画伞体周围的光晕一并拆走，免得留下不跟水母走的亮斑（10-25 用户：水母有断层）
        grow = ndimage.binary_dilation(region, iterations=8)
        hole |= ndimage.binary_dilation(a > 0.15, iterations=7 if j is JELLIES[0] else 4) & grow
    bg = inpaint(src, hole)
    # 底图与水母都缩到 3 像素格
    def down(arr):
        return np.asarray(Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).resize((GW, GH), Image.Resampling.BOX)).astype(np.float32)
    bg_s = down(bg)
    layers = []
    for j, a in zip(JELLIES, alphas):
        rgb = down(src * (a[..., None] > 0) + bg * (a[..., None] <= 0))
        al = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((GW, GH), Image.Resampling.BOX)).astype(np.float32) / 255.0
        al = np.where(al > 0.22, np.clip(0.55 + al * 0.6, 0, 1), 0.0)   # 半透明两档：伞裙 / 实体，边缘干净
        layers.append((rgb, al))
    # 调色板：底图 24 色；水母另 14 色（亮部层次不被水色挤掉）
    def pal_of(sample, n):
        return Image.fromarray(sample.reshape(1, -1, 3).astype(np.uint8)).quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    bg_pal = pal_of(bg_s.reshape(-1, 3), 24)
    j_pal = pal_of(np.concatenate([l[0][l[1] > 0] for l in layers]), 14)
    def to_pal(arr, pal=None):
        return np.asarray(Image.fromarray(arr.astype(np.uint8)).quantize(palette=pal or bg_pal, dither=Image.Dither.NONE).convert('RGB'))
    bg_q = Image.fromarray(to_pal(bg_s)).filter(ImageFilter.ModeFilter(3))
    bg_q.save(OUT / 'bg.png', optimize=True)
    meta = []
    for i, (j, (rgb, al)) in enumerate(zip(JELLIES, layers)):
        ys, xs = np.nonzero(al > 0)
        x0, x1, y0, y1 = xs.min() - 2, xs.max() + 3, ys.min() - 2, ys.max() + 3
        q = to_pal(rgb, j_pal)
        rgba = np.dstack([q, (al * 255).astype(np.uint8)])[y0:y1, x0:x1]
        Image.fromarray(rgba, 'RGBA').save(OUT / f'jelly_{i}.png', optimize=True)
        # 柔光：水母不透明度 → 模糊，四周留 12 格
        pad = 12
        g = np.pad((al[y0:y1, x0:x1] * (lum(rgb[y0:y1, x0:x1]) > 95)).astype(np.float32), pad)
        g = ndimage.gaussian_filter(g, 5.0)
        g = g / max(1e-6, g.max())
        Image.fromarray((g * 255).astype(np.uint8), 'L').save(OUT / f'jglow_{i}.png', optimize=True)
        ax = np.array(j['axis'], float); ax /= np.linalg.norm(ax)
        meta.append({'rect': [int(x0), int(y0), int(x1 - x0), int(y1 - y0)], 'anchor': [round(j['anchor'][0] * K, 2), round(j['anchor'][1] * K, 2)],
                     'axis': [round(float(ax[0]), 4), round(float(ax[1]), 4)], 'bell': round(j['bell'] * K, 2), 'glow_pad': pad})
    # 参数抄进 game/scripts/title_deep.gd 的 JELLY 常量（导出包不收 art/ 下的 json）
    # 调试：拆层后的底图、合成回去、放大对照
    comp = bg_q.convert('RGBA')
    for i, m in enumerate(meta):
        comp.alpha_composite(Image.open(OUT / f'jelly_{i}.png'), (m['rect'][0], m['rect'][1]))
    up = lambda im: im.resize((GW * 3, GH * 3), Image.Resampling.NEAREST)
    up(bg_q).save(DBG / 'v2_bg.png')
    up(comp.convert('RGB')).save(DBG / 'v2_comp.png')
    print(json.dumps(meta))
    for f in sorted(OUT.iterdir()):
        print(f.name, f.stat().st_size)


if __name__ == '__main__':
    main()
