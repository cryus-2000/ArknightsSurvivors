"""光学观感原型的调色 LUT（render/optical，10-23 用户参照 build/ui_ref/look_ref_cave_1023.webp）：
深蓝黑底（暗部更沉、偏冷）、青色生物荧光与灯火暖橙加饱和、其余色相略收，亮部原样留给发光体。
输出 game/shaders/optical_lut.png：16³ 立方体展开成 256×16 横条（x = 蓝层 × 16 + 红，y = 绿），着色器里两层线性插值。
美术之后可以直接在这张图上调（任何调色软件套 LUT 的流程），不必改代码。
用法：python -X utf8 tools/probes/make_optical_lut.py
"""
import colorsys
import os
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "game", "shaders", "optical_lut.png")
N = 16
SHADOW = (0.015, 0.035, 0.075)   # 暗部去往的深蓝黑


def grade(r, g, b):
    l = 0.2126 * r + 0.7152 * g + 0.0722 * b
    # 1) 暗部明暗不再额外压（10-23 用户嫌太黑：「啥都看不见」），幂 1.0 = 原样；光池外的压暗只由着色器做
    if l < 0.55 and l > 1e-5:
        l2 = 0.55 * (l / 0.55) ** 1.0
        k = l2 / l
        r, g, b = r * k, g * k, b * k
        l = l2
    # 2) 暗部偏冷：越暗越往深蓝黑靠
    w = (1.0 - min(1.0, l / 0.45)) ** 2 * 0.2
    r, g, b = r + (SHADOW[0] - r) * w, g + (SHADOW[1] - g) * w, b + (SHADOW[2] - b) * w
    # 3) 按色相调饱和：青（生物荧光）、暖橙（灯火）加，紫红、绿略收
    h, s, v = colorsys.rgb_to_hsv(max(0, r), max(0, g), max(0, b))
    if 0.42 <= h <= 0.58:
        s *= 1.25
    elif 0.03 <= h <= 0.13:
        s *= 1.2
    elif 0.22 <= h <= 0.40:
        s *= 0.8
    elif 0.75 <= h <= 0.95:
        s *= 0.9
    r, g, b = colorsys.hsv_to_rgb(h, min(1.0, s), v)
    return r, g, b


img = Image.new("RGB", (N * N, N))
px = img.load()
for bi in range(N):
    for gi in range(N):
        for ri in range(N):
            r, g, b = grade(ri / (N - 1), gi / (N - 1), bi / (N - 1))
            px[bi * N + ri, gi] = tuple(int(round(max(0.0, min(1.0, c)) * 255)) for c in (r, g, b))
img.save(OUT)
print(OUT)
