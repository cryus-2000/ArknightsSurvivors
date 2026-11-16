# -*- coding: utf-8 -*-
"""维什戴尔终结技原型两声（docs/360，11-17）：原作音源（build/ak_src，memory canon-audio-ok）拼接，不合成。
salvo  = 方向 A 开炮那一下：p_atk_blackcannonoverload_h，截 1.0 秒淡出
finale = 方向 B 终爆：p_imp_blackcannonfull_h + p_skill_aeroliteexplo（降 0.85 倍速、-4 dB、晚 30 ms），截 2.2 秒淡出
输出 game/audio/sfx/ult_wisadel_{salvo,finale}.wav（44.1k 单声道 16 位，峰值 -1 dBFS）"""
import os
import numpy as np
import soundfile as sf
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join("E:/ArknightsSurvivors/build/ak_src")
SR = 44100


def ld(rel, speed=1.0):
    d, sr = sf.read(os.path.join(SRC, rel))
    if d.ndim > 1:
        d = d.mean(axis=1)
    assert sr == SR
    if speed != 1.0:
        d = np.interp(np.arange(0, len(d) - 1, speed), np.arange(len(d)), d)
    return d


def fin(y, secs, fade):
    y = y[: int(secs * SR)].copy()
    n = int(fade * SR)
    y[-n:] *= np.linspace(1, 0, n) ** 2
    return y / np.abs(y).max() * 10 ** (-1 / 20)


def out(name, y):
    sf.write(os.path.join(ROOT, "game", "audio", "sfx", "ult_wisadel_%s.wav" % name), y, SR, subtype="PCM_16")
    print(name, round(len(y) / SR, 2))


out("salvo", fin(ld("wav_atk/p_atk_blackcannonoverload_h.wav"), 1.0, 0.3))
a = ld("wav_atk/p_imp_blackcannonfull_h.wav")
b = ld("flat/p_skill_aeroliteexplo.wav", 0.85) * 10 ** (-4 / 20)
y = np.zeros(max(len(a), len(b) + 1323))
y[: len(a)] += a
y[1323: 1323 + len(b)] += b
out("finale", fin(y, 2.2, 0.8))
