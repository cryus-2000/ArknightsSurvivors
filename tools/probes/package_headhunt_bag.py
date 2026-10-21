"""寻访作战包接入（Codex 交付 codex/art 35587bca，art/incoming/headhunt_bag_1022/delivery/）。

只把正式 PNG 放进 art/incoming 根目录（运行时按名字找图），源图 / 草稿 / 8x 审查图不进运行时：
  ui_hh_bag@2x / ui_hh_bag_zip@2x / ui_hh_bag_zip_front@2x / fx_hh_mouth_glow@2x / fx_hh_shards@2x / fx_hh_streak@2x  原样复制
  fx_hh_light_clip@2x   frames/light_clip_1..7 拼成 8 帧条（第 0 档不出光、留空），灰度转成 alpha，供 Image.blit_rect_mask 裁光柱
  fx_hh_mouth_glow_cyan@2x  青白档：金光 4 色按同明度换成青白档色（交付说明「金光已着色，青白档需独立配色资源」，Codex 正式版到了直接覆盖）
碎光 / 流光是灰度图，运行时按档位色调制，不另出色版。

用法：python -X utf8 tools/probes/package_headhunt_bag.py [提交号，缺省 35587bca]
"""
import io
import os
import subprocess
import sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REV = sys.argv[1] if len(sys.argv) > 1 else "35587bca"
SRC = "art/incoming/headhunt_bag_1022/delivery/"
OUT = os.path.join(ROOT, "art", "incoming")
COPY = ["ui_hh_bag@2x.png", "ui_hh_bag_zip@2x.png", "ui_hh_bag_zip_front@2x.png", "fx_hh_mouth_glow@2x.png", "fx_hh_shards@2x.png", "fx_hh_streak@2x.png"]
# 金光 4 色 → 青白档（docs/124 §9.3：#60E0E8 / #C8FFFF，暗部按同明度往藏青压）
CYAN = {(135, 85, 28): (28, 104, 124), (196, 136, 44): (52, 168, 188), (255, 196, 80): (96, 224, 232), (255, 240, 180): (200, 255, 255)}


def blob(path):
    return subprocess.run(["git", "show", "%s:%s" % (REV, SRC + path)], cwd=ROOT, capture_output=True, check=True).stdout


def img(path):
    return Image.open(io.BytesIO(blob(path)))


for f in COPY:
    open(os.path.join(OUT, f), "wb").write(blob(f))
    print("copy", f, img(f).size)

clips = [np.zeros((320, 256), np.uint8)] + [np.array(img("frames/light_clip_%d.png" % i).convert("L")) for i in range(1, 8)]
strip = np.zeros((320, 256 * 8, 4), np.uint8)
for i, c in enumerate(clips):
    strip[:, i * 256:(i + 1) * 256, :3] = 255
    strip[:, i * 256:(i + 1) * 256, 3] = c
Image.fromarray(strip, "RGBA").save(os.path.join(OUT, "fx_hh_light_clip@2x.png"))
print("clip strip", strip.shape)

g = np.array(img("fx_hh_mouth_glow@2x.png").convert("RGBA")).astype(np.int32)
c = g.copy()
for src, dst in CYAN.items():
    m = (g[..., 0] == src[0]) & (g[..., 1] == src[1]) & (g[..., 2] == src[2]) & (g[..., 3] > 0)
    c[m, :3] = dst
left = (g[..., 3] > 0) & ~np.isin(g[..., 0] * 65536 + g[..., 1] * 256 + g[..., 2], [a * 65536 + b * 256 + d for a, b, d in CYAN])
assert not left.any(), "金光出现了色板外的颜色"
Image.fromarray(c.astype(np.uint8), "RGBA").save(os.path.join(OUT, "fx_hh_mouth_glow_cyan@2x.png"))
print("cyan glow ok")
