#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""近战肉感层（docs/291 §7，11-07 用户定「近战干员补原作音源的肉感层」）：推进之王、星熊的 op_<干员>_flesh_1/2，做法同德克萨斯（gen_sfx_texas_flesh_1105.py）。
素材：原作客户端导出（主仓库 build/ak_src/flat/，不进 git；用户 10-31 / 11-05 同意原作音效进游戏）：
  身体：p_skill_bound3_hit 0.012–0.17 s 低通（锤 / 盾比刀更闷：2.2 kHz）；
  咬合：推进之王 p_skill_magnetichammer 命中峰附近 0.05–0.16 s；星熊 p_skill_MHshieldaxe_h2 0.24–0.33 s；4 kHz 低通 × 0.35 叠在最前。
两个变体变调 ×0.9 / ×0.98（比德克萨斯沉）；尾 40 ms 淡出；rms100 统一对齐 op_texas_flesh_1（11-07 推全员时改）。
用法：python game/tools/gen_sfx_flesh_1107.py
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
BLADE = ("p_skill_ninjasword_imp.wav", 0.10, 0.19)    # 刀剑类：同德克萨斯的咬合
BLUNT = ("p_skill_magnetichammer.wav", 0.05, 0.16)     # 锤 / 锚 / 拳
AXE = ("p_skill_MHshieldaxe_h2.wav", 0.24, 0.33)       # 盾斧 / 锯刃 / 钩
OPS = {"siege": BLUNT, "hoshiguma": AXE,
       # 11-07 用户「先推到全员吧」：其余近战
       "skadi": BLADE, "lappland": BLADE, "irene": BLADE, "mizuki": AXE, "gladiia": AXE, "specter_unchained": AXE, "ulpianus": BLUNT, "saria": BLUNT}


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
    for op, (bn, b0, b1) in OPS.items():
        # 响度统一对齐用户 11-05 认可的 op_texas_flesh_1（各人命中音文件响度差 13 dB，对齐各自的会忽大忽小）
        ref, sr = sf.read(os.path.join(WT, "game", "audio", "sfx", "op_texas_flesh_1.wav"), always_2d=True)
        target = rms100(ref.mean(axis=1))
        body = lp(load("p_skill_bound3_hit.wav", 0.012, 0.17), 2200)
        bite = lp(load(bn, b0, b1), 4000)
        n = max(len(body), len(bite))
        x = np.zeros(n)
        x[:len(body)] += body / (np.abs(body).max() + 1e-9)
        x[:len(bite)] += bite / (np.abs(bite).max() + 1e-9) * 0.35
        for i, k in enumerate((0.9, 0.98)):
            y = resample_poly(x, 100, int(round(100 * k)))
            f = int(0.04 * SR)
            y[-f:] *= np.linspace(1, 0, f)
            y[:int(0.002 * SR)] *= np.linspace(0, 1, int(0.002 * SR))
            y = y * target / rms100(y)
            y = np.tanh(y / 0.89) * 0.89   # 软限幅 -1 dBFS
            path = os.path.join(WT, "game", "audio", "sfx", "op_%s_flesh_%d.wav" % (op, i + 1))
            sf.write(path, y.astype(np.float32), SR, subtype="PCM_16")
            print(path, "%.3f s" % (len(y) / SR), "rms100 %.1f dBFS" % (20 * np.log10(rms100(y))))


if __name__ == "__main__":
    main()
