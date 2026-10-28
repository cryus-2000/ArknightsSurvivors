# -*- coding: utf-8 -*-
"""分享卡快门音效（10-28 用户「分享卡出来的动效能不能跟拍照一样」）：程序合成（numpy + scipy），不含任何采样。

  ui_shutter  相机快门：前帘释放的「咔」（短促高频噪声 + 金属簧片泛音 + 机身闷响）→ 帘幕掠过的细沙声 → 75 毫秒后后帘合上的「嚓」（略低、略轻）

输出 game/audio/sfx/ui_shutter.wav（22.05 kHz 单声道 16 位，响度对齐界面音效；沿用 gen_hh_sfx 的收尾）。
用法：python tools/gen_shutter_sfx.py   （固定随机种子，重跑结果逐字节相同）
"""
import numpy as np

import gen_hh_sfx as H

H.rng = np.random.default_rng(20261028)


def click(bright, ring, body, dur=0.05):
    tt = H.t_of(dur)
    n = len(tt)
    y = H.hp(H.noise(dur), bright) * H.env(n, 0.0005, 0.006)
    y += 0.5 * np.sin(2 * np.pi * ring * tt) * np.exp(-tt / 0.012)
    y += 0.35 * np.sin(2 * np.pi * ring * 1.53 * tt) * np.exp(-tt / 0.008)
    y += 0.6 * np.sin(2 * np.pi * body * tt) * np.exp(-tt / 0.018)
    return y


def make_shutter():
    y = np.zeros(int(0.24 * H.SR))
    H.place(y, click(3500, 2600, 190), 0.0)
    swish = H.bp(H.noise(0.07), 1500, 4200) * H.env(int(0.07 * H.SR), 0.01, 0.05) * 0.18
    H.place(y, swish, 0.008)
    H.place(y, 0.75 * click(2800, 2150, 160), 0.075)
    H.finish("ui_shutter", H.reverb(y, 0.25, 9.0, 0.12, 6000), rms_db=-20.0)


if __name__ == "__main__":
    make_shutter()
