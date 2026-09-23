"""原创背景音乐合成：《潮底灯火》—— D 小调深海氛围，84 BPM，32 小节无缝循环。
层次：长音铺底 pad、低音、钟琴般的五声音阶琶音、海浪噪声、后半段加入轻打击。"""
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
import subprocess, os

SR = 44100
BPM = 84
BEAT = 60 / BPM
BARS = 32
LEN = int(SR * BEAT * 4 * BARS)
TAIL = int(SR * 4)
rng = np.random.default_rng(3)
out = np.zeros((LEN + TAIL, 2))


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, a, r, sustain=1.0):
    e = np.ones(n) * sustain
    ai = min(int(a * SR), n)
    ri = min(int(r * SR), n - ai)
    e[:ai] = np.linspace(0, sustain, ai)
    if ri > 0:
        e[n - ri:] = np.linspace(sustain, 0, ri)
    return e


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def add(sig, start, pan=0.0, gain=1.0):
    i = int(start * SR)
    j = min(i + len(sig), len(out))
    s = sig[: j - i] * gain
    out[i:j, 0] += s * np.sqrt(0.5 * (1 - pan))
    out[i:j, 1] += s * np.sqrt(0.5 * (1 + pan))


# 和弦进行：Dm9 – Bbmaj7 – Fmaj7 – C(add9)，每个和弦 2 小节
CHORDS = [
    [50, 57, 60, 64, 65],   # Dm9 (D A C E F)
    [46, 53, 57, 62, 65],   # Bbmaj7 (Bb F A D F)
    [41, 53, 57, 60, 64],   # Fmaj7 (F F A C E)
    [48, 55, 62, 64, 67],   # Cadd9 (C G D E G)
]
BASS = [38, 34, 41, 36]
PENTA = [62, 64, 65, 69, 72, 74, 76, 77, 81]  # D 小调色彩的高音区

bar = BEAT * 4

# ---- Pad：多个略微失谐的锯齿波，低通后缓慢起落
for b in range(0, BARS, 2):
    ch = CHORDS[(b // 2) % 4]
    dur = bar * 2 + 1.5
    n = int(dur * SR)
    tt = np.arange(n) / SR
    sig = np.zeros(n)
    for note in ch:
        f = midi(note)
        for det in (-0.12, 0.0, 0.11):
            ph = rng.random() * 2 * np.pi
            sig += ((tt * f * 2 ** (det / 12) + ph / (2 * np.pi)) % 1.0 * 2 - 1)
    sig = lp(sig, 900) * env(n, 1.6, 1.8) * 0.018
    # 缓慢的滤波"呼吸"
    sig *= 0.8 + 0.2 * np.sin(2 * np.pi * tt / (bar * 2))
    add(sig, b * bar, pan=0.0)

# ---- 低音：正弦 + 少量二次谐波
for b in range(BARS):
    root = BASS[(b // 2) % 4]
    for beat, length in ((0, 1.4), (2.5, 1.2)):
        n = int(length * BEAT * SR)
        tt = np.arange(n) / SR
        f = midi(root)
        s = np.sin(2 * np.pi * f * tt) + 0.25 * np.sin(4 * np.pi * f * tt)
        s *= env(n, 0.02, 0.25) * np.exp(-tt * 1.2) * 0.22
        add(s, b * bar + beat * BEAT)

# ---- 钟琴琶音：FM 合成，八分音符，按和弦挑音
def bell(f, length=1.6):
    n = int(length * SR)
    tt = np.arange(n) / SR
    mod = np.sin(2 * np.pi * f * 3.5 * tt) * 2.2 * np.exp(-tt * 5)
    return np.sin(2 * np.pi * f * tt + mod) * np.exp(-tt * 3.2)

motif = [0, 2, 4, 3, 5, 4, 2, 1]
for b in range(BARS):
    ch = CHORDS[(b // 2) % 4]
    tones = sorted(set([n + 12 for n in ch[1:]] + PENTA[:6]))
    density = 0.55 if b < 8 else 0.8
    for k in range(8):
        if rng.random() > density and k % 4 != 0:
            continue
        idx = (motif[k] + (b % 4) * 2) % len(tones)
        f = midi(tones[idx])
        add(bell(f) * 0.07, b * bar + k * BEAT / 2, pan=np.sin(k * 0.9) * 0.5)

# ---- 高音旋律（第 9–24 小节）：稀疏的长音
melody = [(8, 0, 74, 2), (8, 2.5, 72, 1.5), (9, 0, 69, 3), (10, 0, 70, 2), (10, 2, 69, 2),
          (11, 0, 65, 4), (12, 0, 67, 2), (12, 2, 69, 2), (13, 0, 72, 3), (14, 0, 74, 1.5),
          (14, 1.5, 76, 2.5), (15, 0, 72, 4), (16, 0, 74, 2), (16, 2.5, 77, 1.5), (17, 0, 76, 3),
          (18, 0, 74, 2), (18, 2, 72, 2), (19, 0, 69, 4), (20, 0, 70, 3), (21, 0, 72, 2),
          (21, 2, 74, 2), (22, 0, 76, 4), (23, 0, 74, 4)]
for (b, beat, note, length) in melody:
    n = int(length * BEAT * SR + 0.6 * SR)
    tt = np.arange(n) / SR
    f = midi(note)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5 * tt) * np.clip(tt - 0.3, 0, 1)
    s = np.sin(2 * np.pi * f * np.cumsum(vib) / SR) + 0.3 * np.sin(4 * np.pi * f * np.cumsum(vib) / SR)
    s = lp(s, 2500) * env(n, 0.25, 0.6) * 0.05
    add(s, b * bar + beat * BEAT, pan=-0.2)

# ---- 海浪噪声：低通噪声 + 慢速起伏
# 用 FFT 做循环低通，使噪声本身首尾相接；起伏周期取整个循环长度的整数分之一
spec = np.fft.rfft(rng.standard_normal(LEN))
freqs = np.fft.rfftfreq(LEN, 1 / SR)
spec *= 1 / (1 + (freqs / 500) ** 4)
wash = np.fft.irfft(spec, LEN)
wash = wash / np.std(wash) * (0.5 + 0.5 * np.sin(2 * np.pi * np.arange(LEN) / LEN * 13)) * 0.03
out[:LEN, 0] += wash
out[:LEN, 1] += np.roll(wash, 3000)

# ---- 轻打击（第 9 小节起）：闷鼓 + 沙锤
for b in range(8, BARS):
    for beat in (0, 2):
        n = int(0.35 * SR)
        tt = np.arange(n) / SR
        f = 55 * np.exp(-tt * 18) + 40
        k = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9) * 0.28
        add(k, b * bar + beat * BEAT)
    for e in range(8):
        n = int(0.08 * SR)
        s = hp(rng.standard_normal(n), 6000) * np.exp(-np.arange(n) / SR * 60) * (0.035 if e % 2 else 0.02)
        add(s, b * bar + e * BEAT / 2 + (0.02 if e % 2 else 0), pan=0.3)

# ---- 混响：合成指数衰减脉冲响应
ir_len = int(2.8 * SR)
ir_t = np.arange(ir_len) / SR
for c in range(2):
    ir = rng.standard_normal(ir_len) * np.exp(-ir_t * 2.2)
    ir = lp(ir, 3500)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = fftconvolve(out[:, c], ir)[: len(out)]
    out[:, c] = out[:, c] * 0.75 + wet * 0.45

# ---- 无缝循环：尾部叠回开头
loop = out[:LEN].copy()
loop[:TAIL] += out[LEN:LEN + TAIL]

loop /= np.max(np.abs(loop)) / 0.8

here = os.path.dirname(os.path.abspath(__file__))
wav = "/tmp/claude-0/bgm.wav"
import wave
with wave.open(wav, "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((loop * 32767).astype(np.int16).tobytes())
dst = os.path.join(here, "..", "audio", "bgm_tide_lamp.ogg")
os.makedirs(os.path.dirname(dst), exist_ok=True)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
print("ok", LEN / SR, "s")
