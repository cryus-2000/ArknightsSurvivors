"""寻访作战包接入（Codex 交付 codex/art 35587bca，art/incoming/headhunt_bag_1022/delivery/）。

只把正式 PNG 放进 art/incoming 根目录（运行时按名字找图），源图 / 草稿 / 8x 审查图不进运行时：
  ui_hh_bag@2x / ui_hh_bag_zip@2x / ui_hh_bag_zip_front@2x / fx_hh_mouth_glow@2x / fx_hh_shards@2x / fx_hh_streak@2x  原样复制
  fx_hh_light_clip@2x   frames/light_clip_1..7 拼成 8 帧条（第 0 档不出光、留空），灰度转成 alpha，供 Image.blit_rect_mask 裁光柱
（10-22 用户：拉包光效只用金一档，青白换色删掉；开口金光 / 碎光已由 package_headhunt_bagfx.py 的光效回归取代）

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
