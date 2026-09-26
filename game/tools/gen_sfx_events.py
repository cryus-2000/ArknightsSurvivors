"""1.1 新增事件的音效（16-bit 单声道 wav，输出 audio/sfx/）：
  knight_charge  骑士冲锋：冰面上的急冲（上扬的风切 + 冰碴碎响），冰霜拖尾
  knight_stab    骑士枪刺：短促的金属「锵」+ 冰光，连刺时连播
  knight_frost   寒冰领域：冰晶一圈爆开（一声闷响 + 一串细碎冰晶）
  hunt_warn      「围猎」预告横幅（合拢前 3 秒）：压下来的低吼 + 水下压迫，约 2.4 秒
  hunt_close     「围猎」合拢：四面水压收拢的「呜——嗡」，约 1.6 秒
  hunt_break     「围猎」突围：压力散开、向上释放的一口气，约 1.2 秒
每声用自己的随机数种子：单独重做某一声不影响其他；gen_sfx.py 重跑复现不了现有音效，别为这些去重跑它。
用法：cd game/tools && python gen_sfx_events.py [名字 ...]
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")


def T(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def env(sec, a, tau):
    t = T(sec)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / tau)


def glide(sec, f0, f1):
    f = f0 * (f1 / f0) ** (T(sec) / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def sweep(rng, sec, f0, f1, q=0.5):
    """带通扫频噪声（风切 / 水流）"""
    n = int(sec * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    for i in range(0, n, 256):
        f = f0 * (f1 / f0) ** (i / n)
        seg = bp(noise[max(0, i - 1024):i + 256], max(30, f * (1 - q)), min(SR / 2 - 100, f * (1 + q)))
        out[i:i + 256] = seg[-min(256, n - i):]
    return out


def at(x, sec, n):
    out = np.zeros(n)
    i = int(sec * SR)
    k = min(len(x), n - i)
    if k > 0:
        out[i:i + k] = x[:k]
    return out


def tinkles(rng, n, t0, t1, count, lo=2500, hi=7000, amp=1.0):
    """一串细碎冰晶：短促的高频正弦颗粒，随机频率与时刻"""
    out = np.zeros(n)
    for _ in range(count):
        c = rng.uniform(t0, t1)
        f = rng.uniform(lo, hi)
        d = rng.uniform(0.04, 0.12)
        g = np.sin(2 * np.pi * f * T(d)) * env(d, 0.001, d / 4) * rng.uniform(0.3, 1.0)
        out += at(g, c, n)
    return out * amp


def knight_charge():
    rng = np.random.default_rng(301)
    d = 0.65
    n = int(d * SR)
    wind = sweep(rng, d, 500, 2800, 0.45) * np.minimum(T(d) / 0.12, 1.0) * np.exp(-np.maximum(T(d) - 0.25, 0) / 0.12)
    body = lp(rng.standard_normal(n), 300) * env(d, 0.02, 0.15) * 1.5          # 蹬地的闷劲
    crackle = hp(tinkles(rng, n, 0.08, 0.55, 22, 3000, 8000), 2000)             # 冰碴
    return wind * 1.2 + body + crackle * 0.35


def knight_stab():
    rng = np.random.default_rng(302)
    d = 0.4
    n = int(d * SR)
    ring = sum(np.sin(2 * np.pi * f * T(d)) * env(d, 0.001, tau) * g
               for f, tau, g in ((1870, 0.09, 1.0), (3130, 0.06, 0.7), (4720, 0.045, 0.5), (6950, 0.03, 0.3)))
    air = sweep(rng, 0.12, 4000, 1500, 0.5) * env(0.12, 0.002, 0.04)
    return ring * 0.6 + at(air, 0.0, n) * 1.4 + hp(tinkles(rng, n, 0.02, 0.2, 6, 5000, 9000), 3000) * 0.25


def knight_frost():
    rng = np.random.default_rng(303)
    d = 0.9
    n = int(d * SR)
    thump = glide(0.25, 110, 55) * env(0.25, 0.003, 0.07)
    burst = bp(rng.standard_normal(n), 1500, 6000) * env(d, 0.002, 0.05)
    shards = tinkles(rng, n, 0.01, 0.7, 40, 2200, 7500)
    return at(thump, 0.0, n) * 1.2 + burst * 0.6 + shards * 0.45 * np.exp(-T(d) / 0.35)


def hunt_warn():
    """压下来的低吼：锯齿低音（75 → 52 Hz）轻失真后低通，喉音共振随时间合拢；底下是水压的低频涌动"""
    rng = np.random.default_rng(401)
    d = 2.4
    n = int(d * SR)
    t = T(d)
    f = 75 * (52 / 75) ** (t / d)
    ph = np.cumsum(f) / SR
    saw = 2 * (ph % 1.0) - 1
    growl = np.tanh(2.5 * (saw + 0.4 * lp(rng.standard_normal(n), 160)))
    # 喉音：带通中心 700 → 350 Hz 往下收
    throat = np.zeros(n)
    for i in range(0, n, 512):
        fc = 700 * (350 / 700) ** (i / n)
        seg = bp(growl[max(0, i - 2048):i + 512], fc * 0.6, fc * 1.5)
        throat[i:i + 512] = seg[-min(512, n - i):]
    shape = np.minimum(t / 0.35, 1.0) * np.exp(-np.maximum(t - 0.9, 0) / 0.6)
    pressure = lp(rng.standard_normal(n), 120, 4) * np.sin(np.pi * np.minimum(t / d, 1.0)) ** 1.5 * 3.0
    sub = glide(d, 48, 38) * np.sin(np.pi * t / d) ** 2
    x = lp(growl, 1400) * 0.5 * shape + throat * 0.9 * shape + pressure + sub * 0.6
    return x * np.minimum((d - t) / 0.3, 1.0)


def hunt_close():
    """四面水压收拢：低通噪声由宽到窄（1500 → 180 Hz）的吸入感，收拢一刻落一记低频「嗡」"""
    rng = np.random.default_rng(402)
    d = 1.6
    n = int(d * SR)
    t = T(d)
    rush = sweep(rng, 0.55, 1500, 180, 0.7) * np.minimum(T(0.55) / 0.35, 1.0) ** 2
    hit_t = 0.5
    wt = np.maximum(t - hit_t, 0)
    boom = glide(d, 70, 42) * np.minimum(wt / 0.02, 1.0) * np.exp(-wt / 0.4) * (t >= hit_t)
    boom = np.tanh(1.8 * boom) / np.tanh(1.8)
    swell = lp(rng.standard_normal(n), 220, 4) * np.minimum(wt / 0.05, 1.0) * np.exp(-wt / 0.5) * (t >= hit_t) * 2.5
    x = at(rush, 0.0, n) * 1.3 + boom + swell
    echo = lp(at(x, 0.3, n), 400) * 0.3
    return (x + echo) * np.minimum((d - t) / 0.3, 1.0)


def hunt_break():
    """突围：压力散开、往上释放——上扬的气泡风声 + 明亮的和弦余光（D 大三和弦，和配乐调性不打架）"""
    rng = np.random.default_rng(403)
    d = 1.2
    n = int(d * SR)
    t = T(d)
    rise = sweep(rng, 0.7, 250, 2600, 0.5) * np.minimum(T(0.7) / 0.1, 1.0) * np.exp(-T(0.7) / 0.35)
    bubbles = np.zeros(n)
    for _ in range(14):
        c = rng.uniform(0.02, 0.6)
        f0 = rng.uniform(500, 1400)
        bd = rng.uniform(0.04, 0.08)
        bubbles += at(glide(bd, f0, f0 * 1.8) * env(bd, 0.002, bd / 3) * rng.uniform(0.3, 1.0), c, n)
    shine = sum(np.sin(2 * np.pi * f * t) for f in (587.3, 740.0, 880.0, 1174.7)) * np.minimum(np.maximum(t - 0.15, 0) / 0.08, 1.0) * np.exp(-np.maximum(t - 0.15, 0) / 0.35) * (t >= 0.15)
    return at(rise, 0.0, n) * 1.2 + bubbles * 0.35 + shine * 0.12


SOUNDS = {"knight_charge": knight_charge, "knight_stab": knight_stab, "knight_frost": knight_frost,
          "hunt_warn": hunt_warn, "hunt_close": hunt_close, "hunt_break": hunt_break}


def save(name, x, peak=0.89):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), 200)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 2), "s")


if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        save(name, SOUNDS[name]())
