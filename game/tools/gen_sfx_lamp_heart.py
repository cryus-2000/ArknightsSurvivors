"""灯火暗淡心跳 lamp_heart.wav（docs/222 §4）：用 Sonniss GDC 2026 录音拼「咚—咚」。
素材：344 Audio - Cinematic Fight Vol. 1「FGHTImpt_4 x Punch, Body 02」（身体闷击，第 1 / 2 下），
原文件只放主仓库 build/sfx_lib/sonniss_gdc2026/extracted/（不进 git、不进包；授权见 docs/113 §20）。
处理：降调 ×0.55 + 160 Hz 低通作低频体，原调 300–900 Hz 带通作外放可闻层（同 heartbeat_hi 的做法）；第二下 0.3 秒后、×0.7。
用法：python game/tools/gen_sfx_lamp_heart.py
"""
import os
import wave
from fractions import Fraction

import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
MAIN = os.path.normpath(os.path.join(ROOT, "..", "..", "..")) if ".claude" in ROOT else ROOT   # 工作树里跑时素材在主仓库 build/
SRC = os.path.join(MAIN, "build", "sfx_lib", "sonniss_gdc2026", "extracted", "344 Audio - Cinematic Fight Vol. 1",
                   "FGHTImpt_4 x Punch, Body 02_344 Audio_Cinematic Fight Vol 1.wav")
OUT = os.path.join(ROOT, "game", "audio", "sfx", "lamp_heart.wav")
SR = 44100


def seg(x, sr, t0, dur, rate):
    s = x[int(t0 * sr):int((t0 + dur) * sr)]
    fr = Fraction(SR / (sr * rate)).limit_denominator(2000)
    return resample_poly(s, fr.numerator, fr.denominator)


def env_out(y, fout):
    n = min(len(y), int(fout * SR))
    y[-n:] *= np.linspace(1.0, 0.0, n) ** 2
    y[:40] *= np.linspace(0.0, 1.0, 40)
    return y


def beat(x, sr, t0):
    low = sosfilt(butter(4, 160, "low", fs=SR, output="sos"), seg(x, sr, t0, 0.32, 0.55))
    hi = sosfilt(butter(2, [300, 900], "band", fs=SR, output="sos"), seg(x, sr, t0, 0.12, 1.0))
    low = env_out(low / (np.abs(low).max() + 1e-9), 0.25)
    hi = env_out(hi / (np.abs(hi).max() + 1e-9), 0.08)
    out = np.zeros(max(len(low), len(hi)))
    out[:len(low)] += low
    out[:len(hi)] += 0.35 * hi
    return out


def main():
    x, sr = sf.read(SRC, dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    a = beat(x, sr, 0.18)
    b = beat(x, sr, 1.16) * 0.7
    n = int(0.95 * SR)
    y = np.zeros(n)
    y[:len(a)] += a[:n]
    o = int(0.3 * SR)
    y[o:o + len(b)] += b[:n - o]
    y = np.tanh(1.4 * y / (np.abs(y).max() + 1e-9))
    y = y / np.abs(y).max() * 0.89
    with wave.open(OUT, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    print(OUT, "%.2fs" % (n / SR))


if __name__ == "__main__":
    main()
