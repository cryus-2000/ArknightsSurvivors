#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""维什戴尔终结技只改颜色（docs/274 §8，开关 ult/px_plane_wisadel）：原版帧条逐像素按亮度换成普攻 / 技能定稿的黑红色阶，其余（形状、帧数、alpha）不动。
- 有饱和度的像素（原版的玫红 / 品红爆裂、紫灰雾）→ FIRE 色阶（亮橙红热芯 → 偏橙血红 → 暗血红 → 近黑）；
- 低饱和的暗像素（烟、焦黑）→ 带红的近黑 SMOKE 色阶；紫色一律不留。
- 防闪眼：最亮一阶（白热）只给原图本来就接近白的像素（亮度 ≥ 0.9）。
输出 game/art/fx/<名>_br(@2x).png + .import（Godot 缺省纹理参数，uid 按文件名哈希），游戏里 ult/px_plane_wisadel = 1 时换用。
用法：python tools/ult_wd_recolor.py"""
import colorsys, hashlib, os, sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pxplane_wisadel_art as A
import pxplane_bake_wisadel as B

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FX = os.path.join(ROOT, "game", "art", "fx")
SRC = ["fx_wd_cannon@2x.png", "fx_cannon_burst.png"]
FIRE = [A.hx(c)[:3] for c in A.FIRE]
SMOKE = [A.hx(c)[:3] for c in A.SMOKE]


def remap(rgb):
    r, g, b = [x / 255.0 for x in rgb]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    L = 0.3 * r + 0.59 * g + 0.11 * b
    if s < 0.22 or (v < 0.35 and s < 0.5):   # 烟 / 焦黑 / 紫灰雾
        k = min(4, int(v * 6.0))
        return SMOKE[k]
    if L >= 0.9:
        return FIRE[0]
    for th, i in ((0.62, 1), (0.42, 2), (0.27, 3), (0.17, 4), (0.1, 5), (0.05, 6)):
        if L >= th:
            return FIRE[i]
    return FIRE[7]


def main():
    for fn in SRC:
        im = Image.open(os.path.join(FX, fn)).convert("RGBA")
        a = np.asarray(im).copy()
        cache = {}
        H, W = a.shape[:2]
        for y in range(H):
            for x in range(W):
                if a[y, x, 3] == 0:
                    continue
                key = tuple(int(c) for c in a[y, x, :3])
                if key not in cache:
                    cache[key] = remap(key)
                a[y, x, :3] = cache[key]
        base, ext = os.path.splitext(fn)
        out = base.replace("@2x", "") + "_br" + ("@2x" if "@2x" in base else "") + ext
        p = os.path.join(FX, out)
        Image.fromarray(a, "RGBA").save(p, optimize=True)
        ip = p + ".import"
        if not os.path.exists(ip):
            md5 = hashlib.md5(("res://art/fx/" + out).encode()).hexdigest()
            txt = B.IMPORT_TMPL.format(uid=B.uid_of("ult_wd/" + out), name=out, md5=md5).replace("res://art/fx/pxp/", "res://art/fx/")
            open(ip, "w", encoding="utf-8", newline="\n").write(txt)
        print(out, "%d 色 → %d 色" % (len(cache), len(set(cache.values()))))


if __name__ == "__main__":
    main()
