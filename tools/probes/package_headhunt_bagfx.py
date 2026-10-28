"""寻访拉包屏光效回归接入（Codex 交付 main 9444db06：art/archive/incoming_1028/headhunt_reference_fx_1022/reference_return/，HANDOFF.md + manifest.json）。

只把运行时要用的放进 art/incoming 根目录（游戏按名字找图），审查图 / 源图 / 预览不进运行时：
  fx_hh_beams@2x        flowing_beams@2x 原样（24 帧 384×400，12 fps，原点 (192,350)）
  fx_hh_frags@2x        rising_fragments@2x 原样（同规格）
  fx_hh_reveal@2x       opening_reveal@2x 8 档灰度遮罩 → 白色 + 灰度做 alpha（供 Image.blit_rect_mask）
  （10-22 用户：拉包光效只用金一档 = Codex 原图，青白换色删掉）
用法：python -X utf8 tools/probes/package_headhunt_bagfx.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "art", "archive", "incoming_1028", "headhunt_reference_fx_1022", "reference_return")
OUT = os.path.join(ROOT, "art", "incoming")
for src, dst in (("flowing_beams@2x.png", "fx_hh_beams"), ("rising_fragments@2x.png", "fx_hh_frags")):
    im = Image.open(os.path.join(SRC, src)).convert("RGBA")
    assert im.size == (384 * 24, 400), im.size
    im.save(os.path.join(OUT, dst + "@2x.png"))
    print(dst, im.size)

r = np.array(Image.open(os.path.join(SRC, "opening_reveal@2x.png")).convert("L"))
assert r.shape == (400, 384 * 8), r.shape
m = np.zeros((400, 384 * 8, 4), np.uint8)
m[..., :3] = 255
m[..., 3] = r
Image.fromarray(m, "RGBA").save(os.path.join(OUT, "fx_hh_reveal@2x.png"))
print("reveal", m.shape)
