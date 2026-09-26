"""主控倒下过渡的「灯灭」音效：短促的灯焰熄灭 + 低沉的水下回响（约 1.4 秒）。输出 audio/sfx/lamp_out.wav（16-bit 单声道）。
单独成文件、用自己的随机数：gen_sfx.py 重跑复现不了现有音效，别为了这一声去重跑它。
用法：cd game/tools && python gen_sfx_lamp.py [试听.wav]   # 给了试听路径时，另外输出「lose 乐句 + 1.2 秒处灯灭」的试听混音
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "audio", "sfx", "lamp_out.wav")
rng = np.random.default_rng(1207)
DUR = 1.4


def T(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def at(x, sec, n):
    """把 x 放到长度 n 的缓冲里 sec 秒处"""
    out = np.zeros(n)
    i = int(sec * SR)
    k = min(len(x), n - i)
    out[i:i + k] = x[:k]
    return out


def glide(sec, f0, f1):
    f = f0 * (f1 / f0) ** (T(sec) / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def lamp_out():
    n = int(DUR * SR)
    t = T(DUR)
    # 1) 灯焰熄灭：一口「噗」——带通噪声，频带从 2.6 kHz 往下扫到 700 Hz，5 ms 起音、约 40 ms 衰减
    m = int(0.22 * SR)
    noise = rng.standard_normal(m)
    puff = np.zeros(m)
    blk = 256
    for i in range(0, m, blk):
        f = 2600 * (700 / 2600) ** (i / m)
        seg = bp(noise[max(0, i - 1024):i + blk], f * 0.55, min(f * 1.6, SR / 2 - 100))
        puff[i:i + blk] = seg[-min(blk, m - i):]
    te = T(0.22)
    puff *= np.minimum(te / 0.005, 1.0) * np.exp(-te / 0.045)
    thump = glide(0.09, 130, 70) * np.minimum(T(0.09) / 0.003, 1.0) * np.exp(-T(0.09) / 0.025)
    # 灯芯最后几下细碎的「滋」：稀疏的高频小颗粒，前 0.18 秒
    sizzle = np.zeros(int(0.2 * SR))
    for _ in range(9):
        c = int(rng.uniform(0.01, 0.18) * SR)
        g = hp(rng.standard_normal(90), 3500) * np.hanning(90) * rng.uniform(0.3, 1.0)
        sizzle[c:c + 90] += g[:len(sizzle) - c]
    snuff = at(puff, 0.0, n) * 1.0 + at(thump, 0.0, n) * 0.55 + at(sizzle, 0.0, n) * 0.18
    # 2) 水下回响：低沉的「嗡」（58 → 40 Hz 下滑）+ 低通噪声涌动，60 ms 起、约 0.45 s 衰减，整体压在 1.1 kHz 以下
    wt = np.maximum(t - 0.03, 0.0)
    body = glide(DUR, 62, 44) * np.minimum(wt / 0.06, 1.0) * np.exp(-wt / 0.45) * (t >= 0.03)
    body = np.tanh(2.2 * body) / np.tanh(2.2)   # 轻饱和：带出 2、3 次泛音，手机 / 笔记本外放也听得到这声「嗡」
    swell = lp(rng.standard_normal(n), 240, 4) * np.minimum(wt / 0.08, 1.0) * np.exp(-wt / 0.35) * (t >= 0.03)
    # 一点缓慢摆动的中低频共鸣（180 Hz 附近，水下的「闷」）
    res = bp(rng.standard_normal(n), 150, 230, 2) * (1 + 0.5 * np.sin(2 * np.pi * 3.1 * t)) * np.minimum(wt / 0.1, 1.0) * np.exp(-wt / 0.3)
    whoom = lp(body * 0.8 + swell * 2.2 + res * 2.6, 1100)
    # 回声：0.28 / 0.56 秒两次，越往后越闷、越轻
    echo = np.zeros(n)
    for d, g, fc in ((0.28, 0.4, 600), (0.56, 0.18, 350)):
        e = lp(whoom + 0.35 * snuff, fc, 2)
        echo += at(e, d, n) * g
    x = snuff * 2.4 + whoom + echo
    x *= np.minimum((DUR - t) / 0.25, 1.0)   # 尾巴 0.25 秒淡出
    return x / np.max(np.abs(x)) * 0.89       # 峰值 −1 dBFS


def save(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


if __name__ == "__main__":
    x = lamp_out()
    save(OUT, x)
    print("lamp_out", round(len(x) / SR, 2), "s")
    if len(sys.argv) > 1:   # 试听：游戏里的相对电平——lose 乐句（-4 dB、Music 总线 0.8）+ 灯灭（SFX 总线 0.9，sfx.gd 里 LAMP_OUT_DB）
        import soundfile as sf
        vol_db = float(sys.argv[2]) if len(sys.argv) > 2 else -6.0
        m, sr = sf.read(os.path.join(HERE, "..", "audio", "music", "lose.ogg"), always_2d=True)
        m = m[:int(4.0 * SR)] * 10 ** (-4 / 20) * 0.8
        s = at(x, 1.2, len(m)) * 10 ** (vol_db / 20) * 0.9
        sf.write(sys.argv[1], m + s[:, None], SR, subtype="PCM_16")
