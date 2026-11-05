#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""能天使终结技音效（docs/262 §11；口径 ult_brief.md §7 / §8「以原版为底，只往上加」）：两套候选 A / B，都只用有授权的录音。

原版用的文件（docs/113 §20、docs/205 §4）：
  sf      按 Q 定格提示：gen_sfx_ult_seg_1030 共用定格瞬态（保留，不动）
  charge  进入瞄准：**原作客户端** p_atk_pistolup_sreload（手枪换弹上膛）→ 不能用，换
  cast    放出：**原作客户端** p_atk_pistolup_dreload（拉栓）→ 不能用，换
  pop_1..3 每个爆点：Sonniss ESM「EXPLDsgn_Explosion Small Blast … Delay 03」×0.97 / 1.0 / 1.04（辨识度高，保留不动）
  impact  第一下掉血（转平面时 = 最大那一下爆炸，共用冲击在这一刻播）：同一小爆炸 ×0.85 + Trailer Booms 214 低频 —— 保留做底，加厚、补余音
听感问题（实测）：charge / cast 频谱重心 7.6 / 7.8 kHz、6 kHz 以上能量 42% / 59%，刺；impact 只有 1.3 秒、慢放还没完就没声了；收尾没有声。

候选（文件写进 game/audio/sfx：A 用原名，B 加 _b；游戏里缺省 A，ult/sfx_alt = 1 试听 B）：
  charge  A：Sonniss ESM Tower Defense「Robot Motor Dark Thump Servo Whine 04」机械伺服 0.6 s（锁定上膛感）+ ESM Fantasy Game 2「Magic Light Spell … Tonal Bright 03」光环亮起（-9 dB）
          B：同一机械伺服，只取前 0.4 s + CC0 Kenney「impactMetal_light_002」（op_exusiai_hit）×0.8 一下「咔」
  cast    A：两声 CC0 枪声（op_exusiai_atk = Freesound 645317 DarkShroom M9，×0.9 / ×0.95，相隔 60 ms）+ Trailer Booms 011 低频一顿
          B：一声 CC0 科幻狙击（op_exusiai_big = Freesound 517058 Invisible_inks）×0.9、5 kHz 低通 + 同一低频一顿
  impact  A：原 impact 做底 + Trailer Booms 075 ×0.75、600 Hz 低通的拉长低频余音（共 2.6 s，跟着慢放拖尾）
          B：原 impact 做底 + Trailer Booms 011 ×0.7 次低频 + Ivo Vicic「Fireworks powerful explosions multiples in a row」3 kHz 低通、-14 dB 的远处连爆余响（共 2.4 s）
  end     A：弹壳落地 —— op_exusiai_hit 四下错开、音高 ×1.25–1.5、渐弱 + ESM「Shimmer Loop Small Bell Metal Taps」0.5 s（光环散去，-12 dB）
          B：只有弹壳落地四下
响度（docs/205 §4.4）：峰值 ≤ −1 dBFS；最响 100 ms RMS charge −14 / cast −12 / impact −9 / end −15；全部 7 kHz 以下低通，6 kHz 以上能量 ≤ 5%。
原文件先备份到主仓库 build/ult_sfx_exu_px/orig/（这里读原 impact 做底）。用法：python tools/gen_sfx_ult_exusiai_px.py
"""
import hashlib, os, wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAIN = os.path.dirname(os.path.dirname(os.path.dirname(ROOT))) if ".claude" in ROOT else ROOT
SON = os.path.join(MAIN, "build", "sfx_lib", "sonniss_gdc2026", "extracted")
SFX = os.path.join(ROOT, "game", "audio", "sfx")
ORIG = os.path.join(MAIN, "build", "ult_sfx_exu_px", "orig")
SR = 44100

SRC = {
    "servo": "Epic Stock Media - Tower Defense Game/ROBTMvmt_Tower Deploy Hitech Robot Motor Dark Thump Servo Whine 04_ESM_TDG.wav",
    "halo": "Epic Stock Media - Fantasy Game 2 - Sound Kit for Enchanted Realms/MAGAngl_Magic Light Spell Enchantment Potion Effect Tonal Bright 03_ESM_FG2.wav",
    "boom011": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_011.wav",
    "boom075": "Federico Soler - Effective Trailer Booms Vol. 2/EffectiveTrailer_Booms_Vol2_075.wav",
    "bell": "Epic Stock Media - Strange Game Ambient Loops 3/MAGShim_Shimmer Loop Small Bell Metal Taps_ESM_SGA3.wav",
    "fw": "Ivo Vicic - Fireworks FX/13 Fireworks_powerful explosions_multiples in a row_near.wav",
}

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


def son(k):
    return load(os.path.join(SON, SRC[k]))


def resample(a, k):
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
    a = lowpass(a, 7000)
    a = a / (np.abs(a).max() + 1e-9) * db(-1)
    r = rms100(a)
    if r > rms_target:
        a *= db(rms_target - r)
    return a


def save(name, a):
    p = os.path.join(SFX, name + ".wav")
    w = wave.open(p, "wb")
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes())
    w.close()
    ip = p + ".import"
    if not os.path.exists(ip):
        fn = name + ".wav"
        h = int(hashlib.sha1(("sfx/" + fn).encode()).hexdigest(), 16)
        al = "abcdefghijklmnopqrstuvwxyz0123456789"
        uid = al[h % 26]
        h //= 26
        for _ in range(11):
            uid += al[h % 36]
            h //= 36
        open(ip, "w", encoding="utf-8", newline="\n").write(IMPORT.format(uid=uid, name=fn, md5=hashlib.md5(("res://audio/sfx/" + fn).encode()).hexdigest()))
    sp = np.abs(np.fft.rfft(a))
    f = np.fft.rfftfreq(len(a), 1 / SR)
    print("%-26s %.2fs  peak %.1f  rms100 %.1f  centroid %4.0f Hz  >6k %2.0f%%" % (name + ".wav", len(a) / SR, 20 * np.log10(np.abs(a).max() + 1e-9), rms100(a),
                                                                              (sp * f).sum() / sp.sum(), (sp[f > 6000] ** 2).sum() / (sp ** 2).sum() * 100))


def main():
    imp0 = load(os.path.join(ORIG, "ult_exusiai_impact.wav"))   # 原 impact（保留做底）
    gun = load(os.path.join(SFX, "op_exusiai_atk.wav"))
    big = load(os.path.join(SFX, "op_exusiai_big.wav"))
    clink = lowpass(load(os.path.join(SFX, "op_exusiai_hit.wav")), 5000)
    servo = son("servo")
    b011 = son("boom011")
    # charge
    halo = lowpass(fade(cut(son("halo"), 0.0, 0.9), 0.01, 0.35), 6000)
    save("ult_exusiai_charge", norm(mix([(lowpass(fade(cut(servo, 0.0, 0.6), 0.003, 0.15), 5000), 0.0, 0), (halo, 0.12, -9)], 1.05), -14))
    save("ult_exusiai_charge_b", norm(mix([(lowpass(fade(cut(servo, 0.0, 0.4), 0.003, 0.12), 5000), 0.0, 0), (pitch(clink, 0.8), 0.33, -2)], 0.6), -14))
    # cast
    thump = lowpass(fade(cut(b011, 0.0, 0.35), 0.002, 0.15), 900)
    save("ult_exusiai_cast", norm(mix([(pitch(gun, 0.9), 0.0, 0), (pitch(gun, 0.95), 0.06, -1), (thump, 0.0, -4)], 0.5), -12))
    save("ult_exusiai_cast_b", norm(mix([(lowpass(pitch(big, 0.9), 5000), 0.0, 0), (thump, 0.0, -4)], 0.75), -12))
    # impact（最大那一下）：原 impact 做底 + 余音
    tailA = lowpass(fade(pitch(cut(son("boom075"), 0.0, 1.8), 0.75), 0.01, 1.0), 600)
    save("ult_exusiai_impact", norm(fade(mix([(imp0, 0.0, 0), (tailA, 0.05, -3)], 2.6), 0.002, 0.8), -9))
    sub = lowpass(fade(pitch(cut(b011, 0.0, 1.6), 0.7), 0.01, 0.9), 400)
    fw = lowpass(fade(cut(son("fw"), 0.3, 1.6), 0.05, 0.8), 3000)
    save("ult_exusiai_impact_b", norm(fade(mix([(imp0, 0.0, 0), (sub, 0.03, -2), (fw, 0.35, -14)], 2.4), 0.002, 0.7), -9))
    # end
    casings = [(pitch(clink, p), t, g) for p, t, g in ((1.35, 0.0, 0), (1.5, 0.09, -3), (1.25, 0.21, -5), (1.42, 0.36, -8))]
    bell = lowpass(fade(cut(son("bell"), 0.0, 0.6), 0.02, 0.3), 5000)
    save("ult_exusiai_end", norm(mix(casings + [(bell, 0.05, -12)], 0.8), -15))
    save("ult_exusiai_end_b", norm(mix(casings, 0.6), -15))


if __name__ == "__main__":
    main()
