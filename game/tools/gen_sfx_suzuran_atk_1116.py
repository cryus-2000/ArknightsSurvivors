#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""铃兰普攻出手音候选（11-16 用户「铃兰的普攻声音我觉得需要换掉」）。

口径同流明普攻（gen_sfx_lumen_atk_1105.py）与终结技音效（用户 10-31：尽量用录音，不用合成音）：只取原作录音，
截一小段、低通削高频、收短尾巴，不新合成。现版 op_suzuran_atk 是 gen_sfx_ops.py 程序合成的。
原作素材在主仓库 build/ak_src/wav_atk/（ArknightsStudioCLI 从客户端 p_atk_* 包导出；不进 git / 包，用户 10-15 确认已获授权，11-05 确认原作音效可进包）。
本机解包铃兰战斗预制体（charpack/char_358_lisa、[uc]projectiles 的 projectile_chr_lisa、effects/lisa）里没有直接写音效名，
所以候选取原作「符咒」（charm）系出手音——与铃兰的符咒 / 狐火气质最贴，再加一版带原作小铃（docs/28 定的「狐火噗 + 小铃」）：
  A 符咒·短：p_atk_charm2_n 全段（0.15 秒），低通 4.5 kHz，30 ms 淡出；
  B 符咒·长：p_atk_charm_n 开头 0.22 秒，低通 3.6 kHz，60 ms 淡出；
  C 符咒 + 小铃：A 叠 p_atk_shakebell_n 开头 0.18 秒（低通 6 kHz、−12 dB），40 ms 淡出。
  第二批（用户「还有什么候选音效吗」）：
  D 远程法术：p_atk_magfar_n（原作通用远程法术出手）开头 0.25 秒，低通 4.5 kHz，70 ms 淡出；
  E 火系法术：p_atk_firemag_n 开头 0.25 秒（重心约 2.2 kHz，偏暖，狐火感），低通 5 kHz，70 ms 淡出；
  F 法术咏唱：p_atk_magspell_n 开头 0.25 秒，低通 4 kHz，80 ms 淡出。
响度按 docs/113 §1「有效响度」（50 ms 窗 RMS 最大值）对齐现版 op_suzuran_atk（约 −14.5 dB），峰值封顶 −6 dB；
音量 / 节流仍由 sfx.gd 的 OP_VOL（普攻 −11 dB）与 OP_LIMIT 管，和其他术士普攻同一档。

用法（仓库根目录）：python game/tools/gen_sfx_suzuran_atk_1116.py              → 只写 build/sfx_suzuran_1116/（a–f + _old 现版副本）
                    python game/tools/gen_sfx_suzuran_atk_1116.py --apply a…f → 再把选中的一版写进 game/audio/sfx/op_suzuran_atk.wav
"""
import argparse, os, shutil

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
AKA = os.path.join(MAIN, "build", "ak_src", "wav_atk")
SFX = os.path.join(ROOT, "game", "audio", "sfx")
OUT = os.path.join(MAIN, "build", "sfx_suzuran_1116")
SR = 44100


def load(name, t0=0.0, dur=None):
    x, sr = sf.read(os.path.join(AKA, name), always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        x = np.interp(np.arange(0, len(x), sr / SR), np.arange(len(x)), x)
    a = int(t0 * SR)
    return x[a:a + int(dur * SR)].copy() if dur else x[a:].copy()


def lp(x, hz, order=8):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def fade(x, ms, fin_ms=2.0):
    n = min(len(x), int(ms / 1000 * SR))
    x[len(x) - n:] *= np.linspace(1.0, 0.0, n) ** 2
    m = int(fin_ms / 1000 * SR)
    x[:m] *= np.linspace(0.0, 1.0, m)
    return x


def eff_db(x):
    w = int(0.05 * SR)
    hop = max(1, w // 4)
    r = max(np.sqrt(np.mean(x[i:i + w] ** 2)) for i in range(0, max(1, len(x) - w), hop))
    return 20 * np.log10(r + 1e-12)


def level(x, target_db, peak_db=-6.0):
    x = x * 10 ** ((target_db - eff_db(x)) / 20)
    pk = np.abs(x).max()
    lim = 10 ** (peak_db / 20)
    return x * (lim / pk) if pk > lim else x


def cand_a():
    return fade(lp(load("p_atk_charm2_n.wav"), 4500), 30)


def cand_b():
    return fade(lp(load("p_atk_charm_n.wav", 0.0, 0.22), 3600), 60)


def cand_c():
    a = lp(load("p_atk_charm2_n.wav"), 4500)
    bell = lp(load("p_atk_shakebell_n.wav", 0.0, 0.18), 6000) * 10 ** (-12 / 20) * 4.0   # 原文件有效响度约 −27 dB，比符咒低 18 dB：×4 后实际约比符咒低 12 dB
    n = max(len(a), len(bell))
    y = np.zeros(n)
    y[:len(a)] += a
    y[:len(bell)] += bell
    return fade(y, 40)


def cand_d():
    return fade(lp(load("p_atk_magfar_n.wav", 0.0, 0.25), 4500), 70)


def cand_e():
    return fade(lp(load("p_atk_firemag_n.wav", 0.0, 0.25), 5000), 70)


def cand_f():
    return fade(lp(load("p_atk_magspell_n.wav", 0.0, 0.25), 4000), 80)


CANDS = {"a": cand_a, "b": cand_b, "c": cand_c, "d": cand_d, "e": cand_e, "f": cand_f}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", choices=list(CANDS), default=None)
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    cur = os.path.join(SFX, "op_suzuran_atk.wav")
    old = os.path.join(OUT, "op_suzuran_atk_old.wav")
    if not os.path.exists(old):
        shutil.copy(cur, old)
    x0, _ = sf.read(old)
    target = eff_db(x0 if x0.ndim == 1 else x0.mean(axis=1))
    for k, f in CANDS.items():
        y = level(f(), target)
        p = os.path.join(OUT, "op_suzuran_atk_%s.wav" % k)
        sf.write(p, y, SR, subtype="PCM_16")
        print("%s  %.3f 秒  有效响度 %.1f dB（现版 %.1f）  峰值 %.1f dB  → %s" % (k, len(y) / SR, eff_db(y), target, 20 * np.log10(np.abs(y).max()), p))
    if a.apply:
        shutil.copy(os.path.join(OUT, "op_suzuran_atk_%s.wav" % a.apply), cur)
        print("已写入", cur)


if __name__ == "__main__":
    main()
