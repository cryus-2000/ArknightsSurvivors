# -*- coding: utf-8 -*-
"""寻访 / 十连音效（10-26 用户：「十连的音效也设计一下，尽可能跟原作的声音差不多」）：全部程序合成（numpy + scipy），不含任何原作音频。

按原作寻访的段落各做一条（听感参照原作：投放落地的闷响、拉链齿、开包时随开口升调的光、开包光炸、6★ 高光、逐张翻卡、总览收尾）：
  hh_drop    作战包落下：下坠风声 → 0.32 秒落地闷响 + 包身布料 / 扣件轻响
  hh_zip     拉链一齿：三下短促金属齿声（开包时按进度换音高，往回拉音高更低）
  hh_hum     开口里的光（无缝循环 1 秒）：和弦泛音 + 细碎闪光；音量 / 音高跟开包进度走，往回拉就降下去（可逆）
  hh_burst   开包光炸：反向吸气 → 亮的冲击 + 低频 + 长的金属泛音尾
  hh_star6   6★ 高光：上行钟音琶音 + 闪光（本次有 6★ 时叠在光炸上，揭示 6★ 时再响一次）
  hh_reveal  逐个揭示：一记快速掠过的风声 + 轻点
  hh_card    总览翻卡：纸卡翻面的短促一下（十张依次，音高逐张升）
  hh_done    总览收尾：柔和的大三和弦

输出 game/audio/sfx/hh_*.wav（22.05 kHz 单声道 16 位；峰值 ≤ −3 dBFS，响度对齐现有界面音效）。
用法：python tools/gen_hh_sfx.py   （固定随机种子，重跑结果逐字节相同）
"""
import os
import wave

import numpy as np
from scipy import signal

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "game", "audio", "sfx")
rng = np.random.default_rng(20261026)


def t_of(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def env(n, a, d, shape=4.0):
    """起音 a 秒线性、之后指数衰减（d = 衰减到 1/e^shape 的秒数）"""
    tt = np.arange(n) / SR
    e = np.minimum(1.0, tt / max(a, 1e-4))
    rel = np.clip((tt - a) / max(d, 1e-4), 0.0, None)
    return e * np.exp(-shape * rel)


def sweep_bp(x, f0, f1, q=3.0, blocks=64):
    """中心频率随时间指数滑动的带通（分块滤波后交叉淡化）"""
    n = len(x)
    out = np.zeros(n)
    edges = np.linspace(0, n, blocks + 1).astype(int)
    win = np.hanning(2 * (edges[1] - edges[0]) + 2)[1:-1]
    hop = edges[1] - edges[0]
    for i in range(blocks):
        c = f0 * (f1 / f0) ** (i / max(1, blocks - 1))
        lo, hi = c / (1 + 1 / q), min(c * (1 + 1 / q), SR / 2 - 100)
        s0 = max(0, edges[i] - hop // 2)
        s1 = min(n, edges[i + 1] + hop // 2)
        seg = bp(x[s0:s1], lo, hi)
        w = np.hanning(s1 - s0)
        out[s0:s1] += seg * w
    return out


def place(dst, src, at):
    i = int(at * SR)
    j = min(len(dst), i + len(src))
    if j > i:
        dst[i:j] += src[: j - i]


def reverb(x, dur=1.2, decay=5.0, mix=0.35, bright=4000):
    ir = lp(noise(dur), bright) * np.exp(-decay * t_of(dur))
    ir /= np.sqrt((ir ** 2).sum()) + 1e-9
    wet = signal.fftconvolve(x, ir)[: len(x) + int(dur * SR)]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return dry * (1 - mix) + wet * mix


def bell(f, dur, decay=3.0, partials=((1, 1.0), (2.01, 0.5), (3.0, 0.25), (4.2, 0.15))):
    tt = t_of(dur)
    y = np.zeros(len(tt))
    for k, (m, a) in enumerate(partials):
        y += a * np.sin(2 * np.pi * f * m * tt) * np.exp(-decay * (1 + 0.6 * k) * tt)
    return y * np.minimum(1.0, tt / 0.003)


def finish(name, y, rms_db=-18.0, peak_db=-3.0, fade=0.02):
    y = np.asarray(y, dtype=float)
    y = y - y.mean()
    if fade > 0:
        n = int(fade * SR)
        y[-n:] *= np.linspace(1, 0, n)
    rms = np.sqrt((y ** 2).mean()) + 1e-12
    y *= 10 ** (rms_db / 20) / rms
    pk = np.abs(y).max()
    lim = 10 ** (peak_db / 20)
    if pk > lim:
        y *= lim / pk
    # 去掉尾部低于 −54 dBFS 的余响（省包体），再补 10 毫秒淡出
    loud = np.nonzero(np.abs(y) > 10 ** (-54 / 20))[0]
    if len(loud) and name != "hh_hum":
        end = min(len(y), loud[-1] + int(0.01 * SR))
        y = y[:end]
        n = min(len(y), int(0.01 * SR))
        y[-n:] *= np.linspace(1, 0, n)
    data = (np.clip(y, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("%-10s %.2fs  rms %.1f dB  peak %.1f dB" % (name, len(y) / SR, 20 * np.log10(np.sqrt((y ** 2).mean()) + 1e-9), 20 * np.log10(np.abs(y).max() + 1e-9)))


def make_drop():
    y = np.zeros(int(0.95 * SR))
    # 下坠风声（0–0.32 秒，越落越近越低）
    w = sweep_bp(noise(0.34), 2400, 500, q=2.0) * np.linspace(0.15, 1.0, int(0.34 * SR)) ** 2
    place(y, w * 0.6, 0.0)
    # 落地：低频闷响 70 → 42 Hz + 布料冲击（低通噪声）+ 扣件两下轻响
    tt = t_of(0.5)
    f = 42 + 28 * np.exp(-tt * 18)
    thud = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9)
    place(y, thud * 1.4, 0.32)
    place(y, lp(noise(0.25), 900) * env(int(0.25 * SR), 0.002, 0.12) * 0.9, 0.32)
    for k, at in enumerate([0.345, 0.395]):
        place(y, hp(noise(0.03), 3000) * env(int(0.03 * SR), 0.0005, 0.012) * (0.35 - 0.12 * k), at)
    finish("hh_drop", reverb(y, 0.5, 9.0, 0.18, 2500), rms_db=-17.0)


def make_zip():
    y = np.zeros(int(0.075 * SR))
    for k, at in enumerate([0.0, 0.013, 0.027]):
        c = hp(noise(0.02), 1800) * env(int(0.02 * SR), 0.0004, 0.006)
        ring = np.sin(2 * np.pi * (2600 + 200 * k) * t_of(0.02)) * env(int(0.02 * SR), 0.0004, 0.008) * 0.5
        place(y, (c + ring) * (1.0 - 0.15 * k), at)
    finish("hh_zip", y, rms_db=-19.0, fade=0.005)


def make_hum():
    # 1 秒无缝循环：各分量频率取整数 Hz，循环点相位连续；慢颤音周期 0.5 秒
    tt = t_of(1.0)
    y = np.zeros(len(tt))
    for f, a in [(220, 0.5), (330, 0.42), (440, 0.35), (554, 0.22), (660, 0.2), (880, 0.14), (1320, 0.08)]:
        y += a * np.sin(2 * np.pi * f * tt)
    y *= 0.8 + 0.2 * np.sin(2 * np.pi * 2 * tt)
    # 闪光：频域高通的噪声（FFT 本身是周期的，首尾相接无缝），再乘 4 Hz 慢变包络
    X = np.fft.rfft(noise(1.0)[: len(tt)])
    fr = np.fft.rfftfreq(len(tt), 1 / SR)
    X[fr < 5000] = 0
    sp = np.fft.irfft(X, len(tt))
    sp = sp / (np.abs(sp).max() + 1e-9) * (0.5 + 0.5 * np.sin(2 * np.pi * 4 * tt)) * 0.18
    y += sp
    finish("hh_hum", y, rms_db=-20.0, fade=0.0)


def make_burst():
    y = np.zeros(int(2.2 * SR))
    # 反向吸气 0–0.15 秒
    pre = sweep_bp(noise(0.16), 600, 5000, q=2.0) * np.linspace(0, 1, int(0.16 * SR)) ** 3
    place(y, pre * 0.7, 0.0)
    # 冲击 0.16 秒：亮噪声 + 低频
    place(y, hp(noise(0.3), 1500) * env(int(0.3 * SR), 0.001, 0.12), 0.16)
    tt = t_of(0.6)
    place(y, np.sin(2 * np.pi * np.cumsum(55 + 40 * np.exp(-tt * 20)) / SR) * np.exp(-tt * 5) * 1.2, 0.16)
    # 金属泛音尾（大调和弦钟）
    for f, a, at in [(523.25, 0.5, 0.17), (659.25, 0.42, 0.18), (783.99, 0.38, 0.19), (1046.5, 0.3, 0.2), (1568, 0.18, 0.21)]:
        place(y, bell(f, 1.9, 1.4) * a, at)
    finish("hh_burst", reverb(y, 1.4, 3.5, 0.4, 6000), rms_db=-16.0)


def make_star6():
    y = np.zeros(int(1.5 * SR))
    for i, f in enumerate([1318.5, 1568.0, 1975.5, 2637.0, 3136.0]):
        place(y, bell(f, 1.2, 2.6, ((1, 1.0), (2.0, 0.3), (3.01, 0.1))) * (0.55 - 0.05 * i), 0.07 * i)
    place(y, hp(noise(1.0), 6000) * env(int(1.0 * SR), 0.05, 0.6) * 0.12, 0.0)
    finish("hh_star6", reverb(y, 1.2, 3.0, 0.45, 8000), rms_db=-19.0)


def make_reveal():
    y = np.zeros(int(0.5 * SR))
    sw = sweep_bp(noise(0.3), 700, 4500, q=2.5) * np.sin(np.linspace(0, np.pi, int(0.3 * SR))) ** 2
    place(y, sw, 0.0)
    place(y, lp(noise(0.06), 1200) * env(int(0.06 * SR), 0.001, 0.03) * 0.8, 0.22)
    finish("hh_reveal", reverb(y, 0.4, 8.0, 0.2, 4000), rms_db=-19.0)


def make_card():
    y = np.zeros(int(0.2 * SR))
    place(y, bp(noise(0.05), 1500, 6000) * env(int(0.05 * SR), 0.002, 0.02), 0.0)
    place(y, bp(noise(0.04), 900, 3500) * env(int(0.04 * SR), 0.001, 0.015) * 0.7, 0.045)
    place(y, np.sin(2 * np.pi * 1760 * t_of(0.08)) * env(int(0.08 * SR), 0.001, 0.04) * 0.25, 0.045)
    finish("hh_card", y, rms_db=-20.0, fade=0.01)


def make_done():
    y = np.zeros(int(1.4 * SR))
    tt = t_of(1.3)
    for f, a in [(261.63, 0.5), (329.63, 0.42), (392.0, 0.4), (523.25, 0.3), (783.99, 0.15)]:
        pad = np.sin(2 * np.pi * f * tt) + 0.3 * np.sin(2 * np.pi * 2 * f * tt)
        place(y, pad * a * np.minimum(1.0, tt / 0.04) * np.exp(-2.2 * tt), 0.0)
    finish("hh_done", reverb(y, 1.0, 3.5, 0.35, 5000), rms_db=-19.0)


if __name__ == "__main__":
    make_drop()
    make_zip()
    make_hum()
    make_burst()
    make_star6()
    make_reveal()
    make_card()
    make_done()
