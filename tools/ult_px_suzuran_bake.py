"""铃兰终结技转平面（docs/271 §7，ult/px_plane）：把原版忍冬斩痕 fx_sz_rslash1–3（冷白 + 红刃边）逐像素换成米金狐火色系，另存 fx_sz_fslash1–3。
造型、尺寸、透明度不动，只换颜色：红刃边 → 狐火琥珀边；冷白 / 冷灰按亮度落到米金 7 阶（docs/271 §1，取色 PRTS 立绘尾巴 / 头发）。
用法：python tools/ult_px_suzuran_bake.py"""
import colorsys, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "game", "art", "fx")
F = ["#2e2618", "#5e4e34", "#9a8058", "#ccae78", "#e8d4a8", "#fbf1d8", "#ffffff"]


def hx(s):
    return tuple(int(s[i:i + 2], 16) for i in (1, 3, 5))


def recolor(a):
    out = a.copy()
    rgb = a[..., :3].astype(np.float32) / 255.0
    lum = rgb @ np.array([0.3, 0.59, 0.11], np.float32)
    red = (rgb[..., 0] > rgb[..., 1] * 1.6) & (rgb[..., 0] > 0.25)
    steps = [(0.93, F[6]), (0.85, F[5]), (0.72, F[4]), (0.58, F[3]), (0.42, F[2]), (-1.0, F[1])]
    for y, x in zip(*np.nonzero(a[..., 3] > 0)):
        if red[y, x]:
            c = F[3] if lum[y, x] > 0.3 else F[2]
        else:
            c = next(col for th, col in steps if lum[y, x] > th)
        out[y, x, :3] = hx(c)
    return out


def main():
    for i in (1, 2, 3):
        for sc in ("@2x", "@1x"):
            src = os.path.join(FX, "fx_sz_rslash%d%s.png" % (i, sc))
            if not os.path.exists(src):
                continue
            a = np.asarray(Image.open(src).convert("RGBA"))
            dst = os.path.join(FX, "fx_sz_fslash%d%s.png" % (i, sc))
            Image.fromarray(recolor(a), "RGBA").save(dst, optimize=True)
            print(os.path.basename(dst), a.shape[1], "x", a.shape[0])


if __name__ == "__main__":
    main()
