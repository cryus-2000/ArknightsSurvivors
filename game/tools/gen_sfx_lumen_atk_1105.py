#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""流明普攻音效重做（docs/255 §7，11-05 用户「流明的攻击音效也需要重做一下，有点吵现在」）。

口径同终结技音效（用户 10-31：尽量用录音，不用合成音）：只取原作流明系录音，截一小段、低通削高频、收短尾巴，不新合成。
  op_lumen_hit（光弹 / 发光单元每颗命中都放，后期一秒十来次）：原作 p_skill_fishhealbuff1（治疗水声）开头 0.14 秒，
      250 Hz 高通去闷响，叠一半原作 p_skill_shinestar 开头（低通 2.8 kHz），8 阶低通 3.2 kHz + 5 kHz 以上再压，40 ms 淡出 → 一声轻亮的水滴，代替原来 6.4 kHz 重心、36% 能量在 6 kHz 以上的「叮」；
  op_lumen_atk（每次出手）：原作 p_skill_lantern_cast 开头 0.2 秒（提灯起手那一下），低通 4 kHz、60 ms 淡出。
响度：按 docs/113 §1「有效响度」口径（50 ms 窗 RMS 最大值）对齐原文件后，命中、出手都再 −4 dB，峰值封顶 −6 dB（sfx.gd OP_DB 另有节流 / 音高随机，见 docs/255 §7）。
原作素材在主仓库 build/ak_src/flat/（不进 git / 包；用户 10-15 确认已获授权，终结技音效同源）。

用法（仓库根目录）：python game/tools/gen_sfx_lumen_atk_1105.py          → 只写 build/sfx_lumen_1105/（含 _old 原文件副本）
                    python game/tools/gen_sfx_lumen_atk_1105.py --apply  → 再写进 game/audio/sfx/
"""
import argparse, os, shutil

import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
AK = os.path.join(MAIN, "build", "ak_src", "flat")
SFX = os.path.join(ROOT, "game", "audio", "sfx")
OUT = os.path.join(MAIN, "build", "sfx_lumen_1105")
SR = 44100


def load(name, t0, dur):
    x, sr = sf.read(os.path.join(AK, name), always_2d=True)
    x = x.mean(axis=1)
    assert sr == SR
    return x[int(t0 * sr):int((t0 + dur) * sr)].copy()


AKA = os.path.join(MAIN, "build", "ak_src", "wav_atk")


def load_atk(name, t0, dur):
    x, sr = sf.read(os.path.join(AKA, name), always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        x = np.interp(np.arange(0, len(x), sr / SR), np.arange(len(x)), x)
    return x[int(t0 * SR):int((t0 + dur) * SR)].copy()


def lp(x, hz, order=8):
    return sosfilt(butter(order, hz, "low", fs=SR, output="sos"), x)


def hp(x, hz, order=4):
    return sosfilt(butter(order, hz, "high", fs=SR, output="sos"), x)


def shelf_cut(x, hz, k):
    """hz 以上的部分再乘 k（用高通取出、按比例减掉）"""
    hi = sosfilt(butter(4, hz, "high", fs=SR, output="sos"), x)
    return x - hi * (1.0 - k)


def fades(x, fin=0.002, fout=0.04):
    n = len(x)
    a, b = int(fin * SR), int(fout * SR)
    x[:a] *= np.linspace(0, 1, a)
    x[n - b:] *= np.linspace(1, 0, b) ** 2
    return x


def eff(x):
    """有效响度：50 ms 窗 RMS 最大值（dB）"""
    h = int(0.05 * SR)
    return max(20 * np.log10(np.sqrt((x[i:i + h] ** 2).mean()) + 1e-12) for i in range(0, max(1, len(x) - h), h // 2))


def stats(x):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return "%.2f s  有效响度 %.1f dB  峰值 %.1f dB  频谱重心 %.0f Hz  6 kHz 以上 %.0f%%" % (len(x) / SR, eff(x), 20 * np.log10(np.abs(x).max() + 1e-12), (X * f).sum() / X.sum(), X[f > 6000].sum() / X.sum() * 100)


def make():
    """v2（11-05 用户「现在这个音效更难听了，看看原作的音效是怎么处理的」）：v1 用治疗水声 + 星光声拼新音色、重低通，发闷、不像流明，作废。
    改用原作流明自己的普攻 / 命中音（原作安装包 audio/sound_beta_2/player/p_atk_*.ab、p_imp_*.ab 解出，主仓库 build/ak_src/wav_atk/；
    流明的技能音是 p_skill_lantern*、终结技已在用，普攻对应 p_atk_lantern_n、命中 p_imp_lantern_n）。
    原作流明出手慢（一下一个目标），命中声带 2 秒长尾；本作 1 秒一发、发光单元 / 额外弹也命中，长尾会糊成一片，所以只截短、不改音色：
      出手 p_atk_lantern_n 开头 0.45 秒（一声亮音 + 一小段尾巴），150 ms 淡出；
      命中 p_imp_lantern_n 开头 0.22 秒（第一下最响的那团，后面 0.25 秒起的第二段不要），80 ms 淡出；只加 7 kHz 以上轻微压（×0.6），不再重低通。"""
    atk = load_atk("p_atk_lantern_n.wav", 0.0, 0.45)
    atk = fades(atk, 0.001, 0.15)
    hit = load_atk("p_imp_lantern_n.wav", 0.0, 0.22)
    hit = shelf_cut(hit, 7000, 0.6)
    hit = fades(hit, 0.001, 0.08)
    return {"op_lumen_hit": (hit, -3.0, 0.7), "op_lumen_atk": (atk, 0.0, 0.7)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for name, (x, rel, pk_cap) in make().items():
        src = os.path.join(SFX, name + ".wav")
        old_copy = os.path.join(OUT, name + "_old.wav")
        if not os.path.exists(old_copy):
            shutil.copy(src, old_copy)
        old, _ = sf.read(old_copy)
        x = x * 10 ** ((eff(old) + rel - eff(x)) / 20.0)
        pk = np.abs(x).max()
        if pk > pk_cap:   # 峰值封顶 −3 dB
            x *= pk_cap / pk
        print(name, "原：", stats(old))
        print(name, "新：", stats(x))
        sf.write(os.path.join(OUT, name + ".wav"), x.astype(np.float32), SR, subtype="PCM_16")
        if a.apply:
            sf.write(src, x.astype(np.float32), SR, subtype="PCM_16")
            print("  → 写入", src)


if __name__ == "__main__":
    main()
