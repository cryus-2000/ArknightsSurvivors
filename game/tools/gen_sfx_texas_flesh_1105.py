#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯卡肉的「斩肉」声（11-05 用户「我用德克萨斯打，没有卡肉感」；协调人：短促、低频、频繁音要收着，原作音源可以用）。
素材：原作明日方舟客户端热更新 26-10-22-14-02-11-51447808 导出的 p_skill_bound3_hit（低频身体，300 Hz 以下 89%）+ p_skill_ninjasword_imp（刀刃咬进去的那一下），
原件在主仓库 build/ak_src/flat/（不进 git；docs/113 §19 / §20 同一来源，用户 10-31 同意原作音效进游戏）。
处理：bound3_hit 截 0.012–0.17 s、2.8 kHz 低通；ninjasword_imp 截命中峰前后 0.10–0.19 s、4 kHz 低通 × 0.35 叠在最前面；两个变体变调 ×0.94 / ×1.04；
尾 40 ms 淡出；rms100 对齐现用 op_texas_hit（同一档频繁音）。输出 game/audio/sfx/op_texas_flesh_1.wav / _2.wav。
用法：python game/tools/gen_sfx_texas_flesh_1105.py
"""
import os, subprocess

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt, resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(HERE, "..", ".."))
common = subprocess.run(["git", "-C", WT, "rev-parse", "--git-common-dir"], capture_output=True, text=True).stdout.strip()
MAIN = os.path.dirname(os.path.abspath(os.path.join(WT, common))) if common else WT
AK = os.path.join(MAIN, "build", "ak_src", "flat")
SR = 44100


def load(name, t0, t1):
    x, sr = sf.read(os.path.join(AK, name), always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        x = resample_poly(x, SR, sr)
    return x[int(t0 * SR):int(t1 * SR)]


def lp(x, f):
    return sosfilt(butter(4, f, "low", fs=SR, output="sos"), x)


def rms100(x):
    w = int(0.1 * SR)
    return max(np.sqrt((x[i:i + w] ** 2).mean() + 1e-12) for i in range(0, max(1, len(x) - w + 1), w // 4))


def main():
    ref, sr = sf.read(os.path.join(WT, "game", "audio", "sfx", "op_texas_hit.wav"), always_2d=True)
    target = rms100(ref.mean(axis=1))
    body = lp(load("p_skill_bound3_hit.wav", 0.012, 0.17), 2800)
    bite = lp(load("p_skill_ninjasword_imp.wav", 0.10, 0.19), 4000) * 0.35
    n = max(len(body), len(bite))
    x = np.zeros(n)
    x[:len(body)] += body / (np.abs(body).max() + 1e-9)
    x[:len(bite)] += bite / (np.abs(bite).max() + 1e-9) * 0.35
    for i, k in enumerate((0.94, 1.04)):
        y = resample_poly(x, 100, int(round(100 * k)))
        f = int(0.04 * SR)
        y[-f:] *= np.linspace(1, 0, f)
        y[:int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
        y = y * target / rms100(y)
        y = np.tanh(y / 0.89) * 0.89   # 软限幅 -1 dBFS
        path = os.path.join(WT, "game", "audio", "sfx", "op_texas_flesh_%d.wav" % (i + 1))
        sf.write(path, y.astype(np.float32), SR, subtype="PCM_16")
        print(path, "%.3f s" % (len(y) / SR), "rms100 %.1f dBFS" % (20 * np.log10(rms100(y))))


if __name__ == "__main__":
    main()
