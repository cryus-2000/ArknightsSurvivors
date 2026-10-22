"""寻访拉包屏光效回归接入（Codex 交付 main 9444db06：art/incoming/headhunt_reference_fx_1022/reference_return/，HANDOFF.md + manifest.json）。

只把运行时要用的放进 art/incoming 根目录（游戏按名字找图），审查图 / 源图 / 预览不进运行时：
  fx_hh_beams@2x        flowing_beams@2x 原样（24 帧 384×400，12 fps，原点 (192,350)）
  fx_hh_frags@2x        rising_fragments@2x 原样（同规格）
  fx_hh_reveal@2x       opening_reveal@2x 8 档灰度遮罩 → 白色 + 灰度做 alpha（供 Image.blit_rect_mask）
  fx_hh_beams_cyan@2x / fx_hh_frags_cyan@2x
                        青白档（docs/124 §9.3）：同一套素材按明度换色——暗部藏青 → #60E0E8 → #C8FFFF → 白，alpha 不变
用法：python -X utf8 tools/probes/package_headhunt_bagfx.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art", "incoming", "headhunt_reference_fx_1022", "reference_return")
OUT = os.path.join(ROOT, "art", "incoming")
# 青白档色阶（按明度 0–1 插值）
CYAN = [(0.0, (14, 60, 86)), (0.35, (40, 150, 180)), (0.6, (96, 224, 232)), (0.82, (200, 255, 255)), (1.0, (255, 255, 255))]


def cyan(img):
    a = np.array(img.convert("RGBA")).astype(np.float32)
    lum = (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255.0
    out = a.copy()
    xs = [c[0] for c in CYAN]
    for ch in range(3):
        out[..., ch] = np.interp(lum, xs, [c[1][ch] for c in CYAN])
    return Image.fromarray(out.round().astype(np.uint8), "RGBA")


for src, dst in (("flowing_beams@2x.png", "fx_hh_beams"), ("rising_fragments@2x.png", "fx_hh_frags")):
    im = Image.open(os.path.join(SRC, src)).convert("RGBA")
    assert im.size == (384 * 24, 400), im.size
    im.save(os.path.join(OUT, dst + "@2x.png"))
    cyan(im).save(os.path.join(OUT, dst + "_cyan@2x.png"))
    print(dst, im.size)

r = np.array(Image.open(os.path.join(SRC, "opening_reveal@2x.png")).convert("L"))
assert r.shape == (400, 384 * 8), r.shape
m = np.zeros((400, 384 * 8, 4), np.uint8)
m[..., :3] = 255
m[..., 3] = r
Image.fromarray(m, "RGBA").save(os.path.join(OUT, "fx_hh_reveal@2x.png"))
print("reveal", m.shape)
