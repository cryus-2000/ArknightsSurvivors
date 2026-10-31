"""预烘焙像素粒子爆散帧条（pixfx，用户 10-30「粒子能够用贴图来替代，这样减小开销」）。

离线跑一遍粒子模拟（初速 + 阻力减速扩散 + 轻重力 + 按年龄冷却变暗），每帧画成 1 纹素的点，存成白灰色阶的帧条；
游戏里 u.strip 播帧、按人用 col 着色（红 / 水色 / 灰），sc 2 时 1 纹素 = 2 世界像素，对上 fx_grains 的 2 px 颗粒观感。
  python tools/imagegen/pxburst.py            # 生成 game/art/fx/fx_px_burst{1,2}@2x.png（大）、fx_px_burst_s@2x.png（小）
不抽游戏随机数（离线固定种子），同一张贴图在游戏里靠转角 / 镜像 / 着色换花样。
"""
import math, random
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "art" / "fx"
TIMES = [0.03, 0.08, 0.15, 0.24, 0.36, 0.5, 0.68, 0.9]   # 每帧对应的模拟时刻（秒），播放时按 8 帧 / 0.9 秒左右
# 色阶（白灰，乘在游戏里的 col 上）：热白 → 亮 → 本色 → 暗
RAMP = [(0.0, (255, 255, 255, 255)), (0.12, (235, 235, 235, 255)), (0.35, (200, 200, 200, 245)), (0.65, (130, 130, 130, 200)), (0.85, (75, 75, 75, 140))]


def ramp(age):
    c = RAMP[0][1]
    for t, col in RAMP:
        if age >= t:
            c = col
    return c


def bake(name, half, n, seed, vmax, life=(0.55, 1.1), grav=12.0):
    rng = random.Random(seed)
    W = half * 2
    sheet = np.zeros((W, W * len(TIMES), 4), np.uint8)
    parts = []
    for _ in range(n):
        a = rng.random() * math.tau
        drag = 3.0 + 2.0 * rng.random()
        sp = vmax * (0.12 + 0.88 * math.sqrt(rng.random()))   # 远近都有，外圈稀
        parts.append((a, sp, drag, life[0] + (life[1] - life[0]) * rng.random(), rng.random() < 0.18))
    for fi, t in enumerate(TIMES):
        for a, sp, drag, lf, big in parts:
            if t > lf:
                continue
            d = sp * (1.0 - math.exp(-drag * t)) / drag   # 带阻力的位移
            x = half + math.cos(a) * d
            y = half + math.sin(a) * d + 0.5 * grav * t * t
            xi, yi = int(x), int(y)
            if not (0 <= xi < W - 1 and 0 <= yi < W - 1):
                continue
            c = ramp(t / lf)
            sz = 2 if (big and t / lf < 0.35) else 1   # 少数刚迸出的亮核是 2×2
            for dy in range(sz):
                for dx in range(sz):
                    px = sheet[yi + dy, fi * W + xi + dx]
                    if c[3] >= px[3]:
                        sheet[yi + dy, fi * W + xi + dx] = c
    Image.fromarray(sheet).save(OUT / f"{name}@2x.png")
    print(name, sheet.shape[1], "x", sheet.shape[0])


if __name__ == "__main__":
    bake("fx_px_burst1", 180, 1400, 11, 520.0)
    bake("fx_px_burst2", 180, 1400, 23, 520.0, grav=20.0)
    bake("fx_px_burst_s", 48, 200, 37, 135.0, life=(0.35, 0.7))
