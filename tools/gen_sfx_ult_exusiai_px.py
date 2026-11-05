#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使终结技转平面（docs/262 §11）的音效候选：只用有授权的录音（docs/113 §8 的 CC0、§20 的 Sonniss GDC 2026，用户 10-31 批准），
不用原作客户端解出的音源（原终结技的 charge / cast 是原作 p_atk_pistolup_sreload / dreload，这里换掉）。

  charge  起手（进入瞄准 / 双枪举起）：Sonniss ESM Tower Defense「ROBTMvmt … Robot Motor Dark Thump Servo Whine 04」机械伺服 0.55 s（锁定上膛感）
          + ESM Fantasy Game 2「MAGAngl_Magic Light Spell … Tonal Bright 03」光环亮起（6 kHz 低通、-9 dB）
  cast    放出：两声 CC0 枪声（op_exusiai_atk = Freesound 645317 DarkShroom M9，×0.9 / ×0.95，相隔 60 ms）+ Federico Soler Trailer Booms Vol.2 011 前 0.3 s 低频一顿
  blast   最大那一下爆炸（冲击帧第一拍，配慢动作）：ESM「EXPLDsgn_Explosion Small Blast … Delay 03」×0.8 + Trailer Booms Vol.2 214（低频）
          + Trailer Booms Vol.2 075 ×0.75、600 Hz 低通的拉长低频余音 2.2 s（跟着慢放拖尾，淡出）
  end     收尾（扫射结束、锁定框碎）：弹壳落地 —— CC0 Kenney「impactMetal_light_002」（op_exusiai_hit）四下错开、音高 ×1.25–1.5、渐弱
          + ESM「MAGShim_Shimmer Loop Small Bell Metal Taps」0.5 s（光环散去，5 kHz 低通、-12 dB）
  pop_1..3（路上的爆点）沿用原文件（Sonniss 小爆炸，已登记 docs/113 §20），不重做。

响度（docs/113 / docs/205 §4.4 口径）：每个文件峰值 −1 dBFS；最响 100 ms RMS charge −14 / cast −12 / blast −9 / end −15 dBFS；6 kHz 以上能量压到 ≤ 10%。
输出 build/ult_sfx_exu_px/（候选，不进游戏；用户点头后再拷进 game/audio/sfx/ 并登记 docs/113）。
用法：python tools/gen_sfx_ult_exusiai_px.py
"""
import os, wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
SON = os.path.join(MAIN, "build", "sfx_lib", "sonniss_gdc2026", "extracted")
SFX = os.path.join(ROOT, "game", "audio", "sfx")
OUT = os.path.join(MAIN, "build", "ult_sfx_exu_px")
SR = 44100

SRC = {
    "servo": "Epic Stock Media - Tower Defense Game/ROBTMvmt_Tower Deploy Hitech Robot Motor Dark Thump Servo Whine 04_ESM_TDG.wav",
    "halo": "Epic Stock Media - Fantasy Game 2 - Sound Kit for Enchanted Realms/MAGAngl_Magic Light Spell Enchantment Potion Effect Tonal Bright 03_ESM_FG2.wav",
    "blast": "Epic Stock Media - Anime Game/EXPLDsgn_Explosion Small Blast Enemy Death Crunchy Boom Cartoon Noisy Crash Impact Delay 03_ESM_AG.wav",
    "boom011": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_011.wav",
    "boom075": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav",
    "boom214": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_214.wav",
    "bell": "Epic Stock Media - Strange Game Ambient Loops 3/MAGShim_Shimmer Loop Small Bell Metal Taps_ESM_SGA3.wav",
}


def load(path):
    w = wave.open(path)
    n, sr, ch, sw = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
    raw = w.readframes(n)
    if sw == 2:
        a = np.frombuffer(raw, np.int16).astype(np.float32) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, np.uint8).reshape(-1, 3)
        a = ((b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16)) << 8 >> 8).astype(np.float32) / 8388608.0
    else:
        a = np.frombuffer(raw, np.int32).astype(np.float32) / 2147483648.0
    a = a.reshape(-1, ch).mean(1)
    if sr != SR:
        a = resample(a, SR / sr)
    return a


def son(k):
    return load(os.path.join(SON, SRC[k]))


def resample(a, k):
    """变速（k > 1 拉长 = 降调）：线性插值"""
    n = int(len(a) * k)
    return np.interp(np.arange(n) / k, np.arange(len(a)), a).astype(np.float32)


def pitch(a, p):
    return resample(a, 1.0 / p)


def cut(a, t0, dur):
    i0 = int(t0 * SR)
    return a[i0:i0 + int(dur * SR)].copy()


def lowpass(a, fc, order=4):
    A = np.fft.rfft(a)
    f = np.fft.rfftfreq(len(a), 1 / SR)
    A /= np.sqrt(1 + (f / fc) ** (2 * order))
    return np.fft.irfft(A, len(a)).astype(np.float32)


def highpass(a, fc, order=2):
    A = np.fft.rfft(a)
    f = np.fft.rfftfreq(len(a), 1 / SR)
    A *= 1 / np.sqrt(1 + (fc / np.maximum(f, 1)) ** (2 * order))
    return np.fft.irfft(A, len(a)).astype(np.float32)


def fade(a, fin=0.004, fout=0.05):
    a = a.copy()
    ni, no = int(fin * SR), int(fout * SR)
    if ni:
        a[:ni] *= np.linspace(0, 1, ni)
    if no:
        a[-no:] *= np.linspace(1, 0, no) ** 2
    return a


def db(x):
    return 10 ** (x / 20)


def mix(parts, dur):
    out = np.zeros(int(dur * SR), np.float32)
    for a, t, g in parts:
        i = int(t * SR)
        n = min(len(a), len(out) - i)
        if n > 0:
            out[i:i + n] += a[:n] * db(g)
    return out


def rms100(a):
    w = int(0.1 * SR)
    return max(20 * np.log10(np.sqrt(np.mean(a[i:i + w] ** 2)) + 1e-9) for i in range(0, max(1, len(a) - w), w // 4))


def norm(a, rms_target):
    a = a / (np.abs(a).max() + 1e-9) * db(-1)
    r = rms100(a)
    if r > rms_target:   # 太响：整体压下去（峰值随之低于 −1）
        a *= db(rms_target - r)
    return a


def save(name, a):
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, "ult_exusiai_%s.wav" % name)
    w = wave.open(p, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
    w.close()
    sp = np.abs(np.fft.rfft(a))
    f = np.fft.rfftfreq(len(a), 1 / SR)
    print("%-22s %.2fs  peak %.1f  rms100 %.1f  centroid %4.0f Hz  >6k %2.0f%%" % (os.path.basename(p), len(a) / SR, 20 * np.log10(np.abs(a).max() + 1e-9), rms100(a),
                                                                              (sp * f).sum() / sp.sum(), (sp[f > 6000] ** 2).sum() / (sp ** 2).sum() * 100))
    return p


def main():
    # 起手：机械伺服锁定 + 光环亮起
    servo = lowpass(fade(cut(son("servo"), 0.0, 0.6), 0.003, 0.15), 5000)
    halo = lowpass(fade(cut(son("halo"), 0.0, 0.9), 0.01, 0.35), 6000)
    save("charge", norm(lowpass(mix([(servo, 0.0, 0), (halo, 0.12, -9)], 1.05), 6500), -14))
    # 放出：双枪齐射 + 低频一顿
    gun = load(os.path.join(SFX, "op_exusiai_atk.wav"))
    b011 = lowpass(fade(cut(son("boom011"), 0.0, 0.35), 0.002, 0.15), 900)
    save("cast", norm(lowpass(mix([(pitch(gun, 0.9), 0.0, 0), (pitch(gun, 0.95), 0.06, -1), (b011, 0.0, -4)], 0.5), 6500), -12))
    # 最大爆炸：小爆炸降调 + 低频轰 + 拉长低频余音（配慢放）
    bl = pitch(cut(son("blast"), 0.02, 0.6), 0.8)
    b214 = lowpass(cut(son("boom214"), 0.0, 1.2), 2500)
    b075 = pitch(cut(son("boom075"), 0.0, 1.8), 0.75)
    tail = lowpass(fade(b075, 0.01, 1.0), 600)
    save("blast", norm(lowpass(fade(mix([(bl, 0.0, 0), (b214, 0.0, -2), (tail, 0.05, -3)], 2.6), 0.002, 0.8), 7000), -9))
    # 收尾：弹壳落地 + 光环散去
    clink = lowpass(load(os.path.join(SFX, "op_exusiai_hit.wav")), 5000)
    parts = [(pitch(clink, p), t, g) for p, t, g in ((1.35, 0.0, 0), (1.5, 0.09, -3), (1.25, 0.21, -5), (1.42, 0.36, -8))]
    bell = lowpass(fade(cut(son("bell"), 0.0, 0.6), 0.02, 0.3), 5000)
    save("end", norm(mix(parts + [(bell, 0.05, -12)], 0.8), -15))
    print("→", OUT)


if __name__ == "__main__":
    main()
