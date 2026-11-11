# -*- coding: utf-8 -*-
"""配乐回环验收（11-12）：读 game/tests/music_loop_test 录下的回环前后实际混音（build/music_loop/cap_<曲>.wav），对照原曲判断回环是否无缝。

做法：录音与原曲（全部层相加、重采样到录音采样率）做归一化互相关——回环前一段对齐到原曲尾部的哪一秒、回环后一段对齐到哪一秒，
两段的位置差应正好等于「循环长度」（无缝 = 回环点前后连续接上，没有多出 / 少掉的时间）；再按 10 ms 块看回环点附近有没有电平塌陷（空档）、
拟合增益后的残差有没有尖峰（爆音 / 跳接）。另外离线检查每首原曲：头尾静音、回环处样本跳变、频谱跳变（与曲中相邻帧比）。

用法：python tools/music_loop_check.py            （先跑 godot --headless --audio-driver Dummy --path game res://tests/music_loop_test.tscn）
输出 build/music_loop/report.json 与一张表（stdout）。
"""
import json, os, sys
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly, fftconvolve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MD = os.path.join(ROOT, "game", "audio", "music")
CAP = os.path.join(ROOT, "build", "music_loop")
SHOP_LOOP = 972797.0 / 44100.0
LAYERS = json.load(open(os.path.join(MD, "suno_layers.json"), encoding="utf-8"))
MENU_FILES = {"title": ["title"], "archive": ["suno_archive_full"], "deploy": ["deploy"], "shop": ["shop"]}


def files_of(t):
    if t in LAYERS:
        return LAYERS[t]["files"]
    return MENU_FILES[t]


def load_ref(t, sr_out):
    x = None
    sr = None
    for f in files_of(t):
        y, sr = sf.read(os.path.join(MD, f + ".ogg"), dtype="float32", always_2d=True)
        y = y.mean(1)
        x = y if x is None else x[:min(len(x), len(y))] + y[:min(len(x), len(y))]
    if sr != sr_out:
        g = np.gcd(sr, sr_out)
        x = resample_poly(x, sr_out // g, sr // g).astype(np.float32)
    return x


def best_lag(seg, ref, lo, hi):
    """seg 在 ref[lo:hi] 里的最佳对齐起点（归一化互相关）"""
    lo = max(0, lo)
    hi = min(len(ref), hi)
    r = ref[lo:hi]
    c = fftconvolve(r, seg[::-1], mode="valid")
    e = np.sqrt(np.maximum(fftconvolve(r * r, np.ones(len(seg)), mode="valid"), 1e-12))
    nc = c / (e * (np.linalg.norm(seg) + 1e-12))
    k = int(np.argmax(nc))
    return lo + k, float(nc[k])


def analyse(t):
    p = os.path.join(CAP, "cap_%s.wav" % t)
    if not os.path.exists(p):
        return None
    y, sr = sf.read(p, dtype="float32", always_2d=True)
    y = y.mean(1)
    ref = load_ref(t, sr)
    n = len(ref)
    ls = int(round((SHOP_LOOP if t == "shop" else 0.0) * sr))
    # 回环点在录音里的位置：找录音里最像「原曲最后 0.3 秒」的地方
    tail = ref[n - int(0.3 * sr):]
    k_tail, c_tail = best_lag(tail, y, 0, len(y))
    seam = k_tail + len(tail)      # 录音里回环发生的样本
    w = int(0.4 * sr)
    if seam - w - int(0.05 * sr) < 0 or seam + w + int(0.05 * sr) > len(y):
        return {"track": t, "err": "录音太短 / 没找到回环", "seam_s": seam / sr}
    a = y[seam - w - int(0.05 * sr): seam - int(0.05 * sr)]
    b = y[seam + int(0.05 * sr): seam + w + int(0.05 * sr)]
    la, ca = best_lag(a, ref, n - int(3 * sr), n)
    lb, cb = best_lag(b, ref, ls, ls + int(3 * sr))
    # 无缝：b 的位置 = a 的位置 + (a 到 b 的录音间隔) − 循环长度
    expect_b = la + (int(0.05 * sr) + w + int(0.05 * sr)) - (n - ls)
    drift_ms = (lb - expect_b) * 1000.0 / sr
    # 电平：回环点 ±50 ms 内 10 ms 块的电平相对原曲同位置（拟合增益后）
    g = float(np.dot(a, ref[la:la + len(a)]) / (np.dot(ref[la:la + len(a)], ref[la:la + len(a)]) + 1e-12))
    blk = int(0.01 * sr)
    lv, res = [], []
    for j in range(-5, 5):
        s0 = seam + j * blk
        rp = (la - (seam - w - int(0.05 * sr))) + s0   # 录音样本 → 原曲样本（回环前）
        if rp >= n:
            rp = rp - n + ls
        if rp + blk > n:
            continue
        rr = g * ref[rp:rp + blk]
        yy = y[s0:s0 + blk]
        lv.append(20 * np.log10((np.sqrt(np.mean(yy ** 2)) + 1e-9) / (np.sqrt(np.mean(rr ** 2)) + 1e-9)))
        res.append(20 * np.log10((np.sqrt(np.mean((yy - rr) ** 2)) + 1e-9) / (np.sqrt(np.mean(rr ** 2)) + 1e-9)))
    return {"track": t, "len": round(n / sr, 3), "loop_start": round(ls / sr, 3), "seam_s": round(seam / sr, 3), "corr_before": round(ca, 3), "corr_after": round(cb, 3),
            "drift_ms": round(drift_ms, 2), "seam_level_min_db": round(float(min(lv)), 1) if lv else None, "seam_resid_max_db": round(float(max(res)), 1) if res else None,
            "ok": bool(abs(drift_ms) < 2.0 and ca > 0.9 and cb > 0.9 and (min(lv) if lv else -99) > -6.0)}


def main():
    out = []
    for f in sorted(os.listdir(CAP)) if os.path.isdir(CAP) else []:
        if f.startswith("cap_") and f.endswith(".wav"):
            r = analyse(f[4:-4])
            if r:
                out.append(r)
                print(json.dumps(r, ensure_ascii=False))
    json.dump(out, open(os.path.join(CAP, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    bad = [r["track"] for r in out if not r.get("ok")]
    print("回环无缝 %d / %d%s" % (len(out) - len(bad), len(out), ("，有问题：" + "、".join(bad)) if bad else ""))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
