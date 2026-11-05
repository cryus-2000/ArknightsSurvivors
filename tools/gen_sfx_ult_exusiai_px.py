#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使终结技转平面（docs/262 §11）的音效：口径 ult_brief §9「原版保留，原作音源可以用；只在明显刺耳或没有余音时调整」。

原版（不动）：sf 定格提示、charge = 原作 p_atk_pistolup_sreload、cast = 原作 p_atk_pistolup_dreload、pop_1..3 = Sonniss 小爆炸、
impact = 同一小爆炸 ×0.85 + Trailer Booms 214 低频（docs/113 §20）。
问题：impact 只有 1.3 秒，最大那一下爆炸配上共用冲击的慢放（定格 0.25 + 0.45 秒 0.25 倍 + 0.35 秒缓回）还没放完就没声了。
调整：只做一个 impact 的加长版 `ult_exusiai_impact_px.wav` —— 原 impact 原样做底，叠 Federico Soler「Effective Trailer Booms Vol.2 075」×0.75、600 Hz 低通的
低频余音（Sonniss GDC 2026，docs/113 §20 已登记的同一套库），共 2.6 秒淡出；峰值 −1 dBFS 以内，最响 100 ms RMS −9 dBFS（docs/205 §4.4 impact 档）。
ult.gd `_ua`：ult/px_plane 开着且有 `<名>_px.wav` 时播它，关着就是原声。
用法：python tools/gen_sfx_ult_exusiai_px.py
"""
import hashlib, os, wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
SON = os.path.join(MAIN, "build", "sfx_lib", "sonniss_gdc2026", "extracted")
SFX = os.path.join(ROOT, "game", "audio", "sfx")
BOOM075 = "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav"
SR = 44100

IMPORT = """[remap]

importer="wav"
type="AudioStreamWAV"
uid="uid://{uid}"
path="res://.godot/imported/{name}-{md5}.sample"

[deps]

source_file="res://audio/sfx/{name}"
dest_files=["res://.godot/imported/{name}-{md5}.sample"]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=2
"""


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
    return resample(a, SR / sr) if sr != SR else a


def resample(a, k):
    n = int(len(a) * k)
    return np.interp(np.arange(n) / k, np.arange(len(a)), a).astype(np.float32)


def lowpass(a, fc, order=4):
    A = np.fft.rfft(a)
    f = np.fft.rfftfreq(len(a), 1 / SR)
    A /= np.sqrt(1 + (f / fc) ** (2 * order))
    return np.fft.irfft(A, len(a)).astype(np.float32)


def fade(a, fin, fout):
    a = a.copy()
    ni, no = int(fin * SR), int(fout * SR)
    if ni:
        a[:ni] *= np.linspace(0, 1, ni)
    if no:
        a[-no:] *= np.linspace(1, 0, no) ** 2
    return a


def rms100(a):
    w = int(0.1 * SR)
    return max(20 * np.log10(np.sqrt(np.mean(a[i:i + w] ** 2)) + 1e-9) for i in range(0, max(1, len(a) - w), w // 4))


def main():
    imp = load(os.path.join(SFX, "ult_exusiai_impact.wav"))   # 原 impact，原样做底
    tail = lowpass(fade(resample(load(os.path.join(SON, BOOM075))[: int(1.8 * SR)], 1 / 0.75), 0.01, 1.0), 600)
    out = np.zeros(int(2.6 * SR), np.float32)
    out[: len(imp)] += imp
    i0 = int(0.05 * SR)
    n = min(len(tail), len(out) - i0)
    out[i0:i0 + n] += tail[:n] * 10 ** (-3 / 20)
    out = fade(out, 0.0, 0.8)
    out = out / (np.abs(out).max() + 1e-9) * 10 ** (-1 / 20)
    r = rms100(out)
    if r > -9.0:
        out *= 10 ** ((-9.0 - r) / 20)
    fn = "ult_exusiai_impact_px.wav"
    p = os.path.join(SFX, fn)
    w = wave.open(p, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(out, -1, 1) * 32767).astype(np.int16).tobytes())
    w.close()
    if not os.path.exists(p + ".import"):
        h = int(hashlib.sha1(("sfx/" + fn).encode()).hexdigest(), 16)
        al = "abcdefghijklmnopqrstuvwxyz0123456789"
        uid = al[h % 26]
        h //= 26
        for _ in range(11):
            uid += al[h % 36]
            h //= 36
        open(p + ".import", "w", encoding="utf-8", newline="\n").write(IMPORT.format(uid=uid, name=fn, md5=hashlib.md5(("res://audio/sfx/" + fn).encode()).hexdigest()))
    sp = np.abs(np.fft.rfft(out))
    f = np.fft.rfftfreq(len(out), 1 / SR)
    print("%s %.2fs peak %.1f rms100 %.1f centroid %.0f Hz >6k %.0f%%" % (fn, len(out) / SR, 20 * np.log10(np.abs(out).max()), rms100(out), (sp * f).sum() / sp.sum(),
                                                                       (sp[f > 6000] ** 2).sum() / (sp ** 2).sum() * 100))


if __name__ == "__main__":
    main()
