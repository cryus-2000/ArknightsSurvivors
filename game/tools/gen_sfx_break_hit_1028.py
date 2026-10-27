"""破绽命中音 break_hit 去音高（10-28，用户「破绽的音效现在也有点难听」）：现用版 = 低频闷击 + 3–10 kHz 脆响 + 1650 Hz 正弦环（那一声「叮」），
破绽窗口里每一击都叠一声，最快每 0.12 秒一次（sfx.gd LIMIT）。三个去音高候选，都是「打在破绽上要重、要脆」的同一思路，只是没有任何持续音高：
  A 闷击：200→80 Hz 下滑重体 + 1.5–5 kHz 宽带短噪（无环）；最干净、最像「闷实地打中」
  B 脆裂：重体减半 + 2–8 kHz 两下极短颗粒（像甲壳崩裂）；最脆、最像「裂开」
  C 厚实：重体 + 500–2500 Hz 带通「咔」+ 少量 3–6 kHz 沙粒；偏中频、不尖
评估：音高感 = 平滑频谱最高峰比 ±1 个八度中位数高多少 dB（纯音 > 20、噪声 < 12）；4 kHz 以上占比；响度对齐现用版最响 100 ms RMS。
用法：python game/tools/gen_sfx_break_hit_1028.py            写 <主仓库>/build/break_hit_1028/break_hit_A/B/C.wav 并打印评估
      python game/tools/gen_sfx_break_hit_1028.py --apply A   把该候选写进 game/audio/sfx/break_hit.wav（16 位单声道 44.1 kHz）
"""
import os, subprocess, sys, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx"))
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
OUT = os.path.join(ROOT, "build", "break_hit_1028")
BASE = "d88b56b56"      # 「改前」固定读这个提交里的 break_hit.wav


def T(sec):
    return np.arange(int(sec * SR)) / SR


def bp(x, lo, hi):
    return sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), x)


def env(sec, a, tau):
    t = T(sec)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / tau)


def glide(sec, f0, f1):
    f = f0 * (f1 / f0) ** (T(sec) / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def at(x, sec, n):
    out = np.zeros(n)
    i = int(sec * SR)
    out[i:i + len(x)] += x[:n - i]
    return out


def read_old():
    import io
    import soundfile as sf
    b = subprocess.run(["git", "show", "%s:game/audio/sfx/break_hit.wav" % BASE], cwd=HERE, capture_output=True).stdout
    x, _ = sf.read(io.BytesIO(b), dtype="float64")
    return x if x.ndim == 1 else x.mean(1)


def rms100(x):
    w = int(0.1 * SR)
    e = np.convolve(x * x, np.ones(w) / w, "valid") if len(x) > w else np.array([np.mean(x * x)])
    return 10 * np.log10(e.max() + 1e-12)


def peaky(x):
    n = max(len(x), 8192)
    X = np.abs(np.fft.rfft(np.pad(x, (0, n - len(x))) * np.hanning(n))) + 1e-9
    f = np.fft.rfftfreq(n, 1 / SR)
    S = np.convolve(X, np.ones(7) / 7, "same")
    m = (f > 400) & (f < 8000)
    i = np.argmax(np.where(m, S, 0))
    near = (f > f[i] / 2) & (f < f[i] * 2)
    return float(f[i]), 20 * np.log10(S[i] / np.median(S[near]))


def hi4k(x):
    X = np.abs(np.fft.rfft(x)) ** 2
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return float(X[f > 4000].sum() / X.sum())


def cand_a():
    rng = np.random.default_rng(1028)
    d = 0.26
    n = int(d * SR)
    body = np.tanh(2.2 * glide(0.22, 200, 80)) * env(0.22, 0.001, 0.06)
    snap = bp(rng.standard_normal(n), 1500, 5000) * env(d, 0.0006, 0.02)
    return at(body, 0.0, n) * 1.0 + snap * 0.7


def cand_b():
    rng = np.random.default_rng(1029)
    d = 0.2
    n = int(d * SR)
    body = np.tanh(2.0 * glide(0.14, 160, 70)) * env(0.14, 0.001, 0.04)
    g1 = bp(rng.standard_normal(n), 2000, 8000) * env(d, 0.0006, 0.012)
    g2 = np.roll(bp(rng.standard_normal(n), 2500, 8000) * env(d, 0.0006, 0.009), int(0.018 * SR))
    return at(body, 0.0, n) * 0.55 + g1 * 0.75 + g2 * 0.5


def cand_c():
    rng = np.random.default_rng(1030)
    d = 0.24
    n = int(d * SR)
    body = np.tanh(2.2 * glide(0.2, 190, 85)) * env(0.2, 0.001, 0.05)
    crunch = bp(rng.standard_normal(n), 500, 2500) * env(d, 0.001, 0.035)
    grit = bp(rng.standard_normal(n), 3000, 6000) * env(d, 0.0006, 0.014)
    return at(body, 0.0, n) * 0.85 + crunch * 0.8 + grit * 0.25


CANDS = {"A": cand_a, "B": cand_b, "C": cand_c}


def write(path, x):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def main():
    old = read_old()
    os.makedirs(OUT, exist_ok=True)
    fo, po = peaky(old)
    print("现用   %.2f s  峰值频率 %5.0f Hz  音高感 %4.1f dB  4 kHz 以上 %2.0f%%  rms100 %.1f  峰值 %.1f" % (len(old) / SR, fo, po, 100 * hi4k(old), rms100(old), 20 * np.log10(np.abs(old).max())))
    out = {}
    for k, fn in CANDS.items():
        x = fn()
        x = x * 10 ** ((rms100(old) - rms100(x)) / 20)
        cap = np.abs(old).max()
        if np.abs(x).max() > cap:
            x = np.tanh(x / cap) * cap
        x[-int(0.02 * SR):] *= np.linspace(1, 0, int(0.02 * SR))
        f, p = peaky(x)
        print("候选 %s %.2f s  峰值频率 %5.0f Hz  音高感 %4.1f dB  4 kHz 以上 %2.0f%%  rms100 %.1f  峰值 %.1f" % (k, len(x) / SR, f, p, 100 * hi4k(x), rms100(x), 20 * np.log10(np.abs(x).max())))
        write(os.path.join(OUT, "break_hit_%s.wav" % k), x)
        out[k] = x
    if "--apply" in sys.argv:
        k = sys.argv[sys.argv.index("--apply") + 1]
        write(os.path.join(SFX, "break_hit.wav"), out[k])
        print("已写入 audio/sfx/break_hit.wav = 候选", k)


main()
