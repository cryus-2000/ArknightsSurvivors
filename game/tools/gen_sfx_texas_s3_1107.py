#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""德克萨斯 S3「剑雨滂沱」的刀剑声（11-07 用户「德克萨斯 S3 技能的时候得是有声音的，调整一下，刀剑声」）。
原来：发动音借艾丽妮 S3（sfx.OP_ALT），每一刀只有通用收势音 op_texas_hit（又轻又闷，叠在战斗声里听不见）。
素材：原作客户端导出（主仓库 build/ak_src/flat/，不进 git；用户 10-31 / 11-05 同意原作音效进游戏）：
  op_texas_s3.wav      发动：p_skill_swordrain（原作「剑雨」）0–1.3 s，尾 0.25 s 淡出；rms100 对齐 op_irene_s3（原来借的那个）。
  op_texas_s3_cut_1/2/3 每一刀：p_skill_arccutting 0.03–0.26 s（利刃划开）+ p_skill_ninjasword_imp 0.03–0.20 s × 0.45（金属咬合），
                        250 Hz 高通去闷；三个变体变调 ×0.96 / ×1.04 / ×1.10 轮着播；尾 40 ms 淡出；rms100 = op_texas_hit + 3 dB。
用法：python game/tools/gen_sfx_texas_s3_1107.py
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
OUT = os.path.join(WT, "game", "audio", "sfx")
SR = 44100


def load(name, t0, t1):
    x, sr = sf.read(os.path.join(AK, name), always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        x = resample_poly(x, SR, sr)
    return x[int(t0 * SR):int(t1 * SR)]


def ref(name):
    x, sr = sf.read(os.path.join(OUT, name), always_2d=True)
    return x.mean(axis=1)


def hp(x, f):
    return sosfilt(butter(2, f, "high", fs=SR, output="sos"), x)


def rms100(x):
    w = int(0.1 * SR)
    return max(np.sqrt((x[i:i + w] ** 2).mean() + 1e-12) for i in range(0, max(1, len(x) - w + 1), w // 4))


def fin(y, target, fade):
    f = int(fade * SR)
    y = y.copy()
    y[-f:] *= np.linspace(1, 0, f)
    y[:int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
    y = y * target / rms100(y)
    return np.tanh(y / 0.89) * 0.89   # 软限幅 -1 dBFS


def save(name, y):
    path = os.path.join(OUT, name)
    sf.write(path, y.astype(np.float32), SR, subtype="PCM_16")
    print(path, "%.3f s" % (len(y) / SR), "rms100 %.1f dBFS" % (20 * np.log10(rms100(y))))


def main():
    cast = load("p_skill_swordrain.wav", 0.0, 1.3)
    save("op_texas_s3.wav", fin(cast, rms100(ref("op_irene_s3.wav")), 0.25))
    cut = hp(load("p_skill_arccutting.wav", 0.03, 0.26), 250)
    bite = hp(load("p_skill_ninjasword_imp.wav", 0.03, 0.20), 250)
    x = cut / (np.abs(cut).max() + 1e-9)
    x[:len(bite)] += bite / (np.abs(bite).max() + 1e-9) * 0.45
    target = rms100(ref("op_texas_hit.wav")) * 10 ** (3 / 20)
    for i, k in enumerate((0.96, 1.04, 1.10)):
        y = resample_poly(x, 100, int(round(100 * k)))
        save("op_texas_s3_cut_%d.wav" % (i + 1), fin(y, target, 0.04))


if __name__ == "__main__":
    main()
