"""原创配乐合成（v1.0）：深海氛围 + 紧张战斗，多曲目 + 动态分层。

输出到 audio/music/：
  title.ogg                     标题《海底祈愿》升 F 小调 60 BPM（海愿气质：钢琴+竖琴+人声+弦乐涌浪）
  shop.ogg                      商人《灯下小憩》F 大调 92 BPM
  win.ogg / lose.ogg            结算短乐句（不循环）
  win_loop.ogg / lose_loop.ogg  结算短乐句之后接续的循环
  opening.ogg                   开场动画引子《沉降》（不循环，对齐 3.6 s 动画）
  boss_in.ogg / boss_down.ogg   Boss 登场 / 击破叠加短乐句（不循环，叠在当前音乐之上）
全部为原创旋律与编曲，合成方式：减法/FM/Karplus-Strong + 卷积混响。
战斗曲、中期 Boss、最终 Boss 自 v2.0 起由 gen_music_battle.py 生成，本脚本不再生成它们。
依赖 numpy / scipy / soundfile（不需要 ffmpeg）。
随机数序列取决于同一个进程里前面跑过什么，现有文件是分三轮生成的；要重做其中几首并保持随机细节和现有文件一致，按原来的轮次跑，
同轮里不想覆盖的曲目用 --skip 列出（照样「算」，只是不写文件）。竖琴音准修正（2026-09-26）就是这样重做的：
  python gen_music.py title
  python gen_music.py opening boss_cues shop --skip boss_in
  python gen_music.py result_loops --skip lose_loop
win / lose 短乐句还是 v0.9 时生成的，没有竖琴，没重做。shop 的现有文件在竖琴修正之前就与本脚本对不上
（当时生成它的代码后来改过），所以重做后音符不变、随机细节（力度抖动等）会变。
"""
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
import soundfile as sf
import os

SR = 44100
rng = np.random.default_rng(7)
HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "audio", "music")
os.makedirs(OUTDIR, exist_ok=True)
SKIP = set()       # 只算不写的曲目名（见文件头）
OGG_LEVEL = 0.45   # Vorbis 压缩档（libsndfile；码率与原来的 ffmpeg -q:a 5 相当，五首平均约 120 kbps）


# ============================================================ 基础
TRANSPOSE = 0  # 全局移调（半音），make_title 内临时设置


def midi(n):
    return 440.0 * 2 ** ((n + TRANSPOSE - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def env(n, a, r, s=1.0):
    e = np.ones(n) * s
    ai = min(int(a * SR), n)
    ri = min(int(r * SR), n - ai)
    if ai > 0:
        e[:ai] = np.linspace(0, s, ai)
    if ri > 0:
        e[n - ri:] = np.linspace(s, 0, ri)
    return e


def lp(x, fc, order=2):
    return sosfilt(butter(order, min(fc, SR / 2 - 100), fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def saw(f, n, ph=0.0):
    return ((tt(n) * f + ph) % 1.0) * 2 - 1


class Track:
    def __init__(self, bpm, bars, tail=4.0, beats=4):
        self.bpm = bpm
        self.beat = 60 / bpm
        self.bar = self.beat * beats
        self.bars = bars
        self.len = int(SR * self.bar * bars)
        self.tail = int(SR * tail)
        self.buf = np.zeros((self.len + self.tail, 2))

    def add(self, sig, start, pan=0.0, gain=1.0):
        i = max(0, int(start * SR))
        if i >= len(self.buf):
            return
        j = min(i + len(sig), len(self.buf))
        s = sig[: j - i] * gain
        self.buf[i:j, 0] += s * np.sqrt(0.5 * (1 - pan))
        self.buf[i:j, 1] += s * np.sqrt(0.5 * (1 + pan))

    def at(self, bar, beat=0.0):
        return bar * self.bar + beat * self.beat


def reverb(buf, secs=2.6, decay=2.4, mix=0.35, tone=4000):
    n = int(secs * SR)
    t_ = tt(n)
    out = buf.copy()
    for c in range(2):
        ir = rng.standard_normal(n) * np.exp(-t_ * decay)
        ir = lp(ir, tone)
        ir /= np.sqrt(np.sum(ir ** 2))
        wet = fftconvolve(buf[:, c], ir)[: len(buf)]
        out[:, c] = buf[:, c] * (1 - mix * 0.5) + wet * mix
    return out


def finish(track, name, loop=True, peak=0.8, verb=(2.6, 2.4, 0.35), gain=None):
    buf = reverb(track.buf, *verb) if verb else track.buf
    if loop:
        data = buf[: track.len].copy()
        data[: track.tail] += buf[track.len: track.len + track.tail]
    else:
        data = buf
    if gain is None:
        data /= np.max(np.abs(data)) / peak
    else:
        data *= gain
        data = np.tanh(data * 1.1) / 1.1
    if name in SKIP:
        return np.max(np.abs(data))
    pcm = np.clip(data, -1, 1).astype(np.float32)
    dst = os.path.join(OUTDIR, name + ".ogg")
    with sf.SoundFile(dst, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=OGG_LEVEL) as f:
        for i in range(0, len(pcm), 8192):   # libsndfile 一次写整段 Vorbis 会崩，分块写
            f.write(pcm[i:i + 8192])
    print(name, round(len(data) / SR, 2), "s")
    return np.max(np.abs(data))


# ============================================================ 乐器
def pad(notes, dur, bright=900, amp=0.02, a=1.2, r=1.5):
    n = int(dur * SR)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        for det in (-0.1, 0.0, 0.09):
            sig += saw(f * 2 ** (det / 12), n, rng.random())
    sig = lp(sig, bright) * env(n, a, r) * amp
    return sig * (0.85 + 0.15 * np.sin(2 * np.pi * tt(n) / max(dur, 1.0)))


def strings(notes, dur, amp=0.018, a=0.4, r=0.8, bright=2200, trem=0.0):
    n = int(dur * SR)
    t_ = tt(n)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        vib = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t_ + rng.random() * 6)
        for det in (-0.06, 0.07):
            ph = np.cumsum(f * 2 ** (det / 12) * vib) / SR
            sig += (ph % 1.0) * 2 - 1
    sig = lp(sig, bright) * env(n, a, r) * amp
    if trem > 0:
        sig *= 0.6 + 0.4 * np.abs(np.sin(np.pi * trem * t_))
    return sig


def choir(notes, dur, amp=0.02, a=0.8, r=1.2):
    """合唱感：锯齿波经元音共振峰带通（"啊"）"""
    n = int(dur * SR)
    t_ = tt(n)
    src = np.zeros(n)
    for note in notes:
        f = midi(note)
        for det in (-0.08, 0.0, 0.08):
            vib = 1 + 0.004 * np.sin(2 * np.pi * (4.5 + rng.random()) * t_)
            src += (np.cumsum(f * 2 ** (det / 12) * vib) / SR % 1.0) * 2 - 1
    sig = bp(src, 650, 1100) * 1.0 + bp(src, 1100, 1300) * 0.6 + bp(src, 2400, 2800) * 0.25
    return sig * env(n, a, r) * amp


def sub(note, dur, amp=0.2, a=0.01, r=0.15):
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    s = np.sin(2 * np.pi * f * t_) + 0.3 * np.sin(4 * np.pi * f * t_)
    return s * env(n, a, r) * amp


def reese(note, dur, amp=0.12, cut=500, a=0.01, r=0.08):
    n = int(dur * SR)
    f = midi(note)
    s = saw(f * 0.997, n) + saw(f * 1.003, n, 0.3)
    s = lp(s, cut, 3) + np.sin(2 * np.pi * f * tt(n)) * 0.8
    return s * env(n, a, r) * amp


def pluck(note, dur=0.6, amp=0.1, bright=0.5):
    """Karplus-Strong 拨弦"""
    f = midi(note)
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    buf = lp(buf, 2000 + 6000 * bright) if p > 20 else buf
    damp = 0.996 - (1 - bright) * 0.01
    out = np.zeros(n + p + 1)
    out[:p] = buf
    # y[i] = 0.5·damp·(y[i-p] + y[i-p+1])：按 p-1 长度分块向量化
    i = p
    while i < n:
        j = min(i + p - 1, n)
        out[i:j] = 0.5 * damp * (out[i - p:j - p] + out[i - p + 1:j - p + 1])
        i = j
    # 循环延迟只能取整数采样 p，加上平均滤波的半个采样，实际音高是 SR / (p - 0.5)，比目标偏高（音越高越偏，
    # 竖琴最高的几个音偏一个多半音）。按「实际 / 目标」音高比放慢读取，拉回精确音高。随机数消耗与原来一样，
    # 所以重做后同一首里的其他声部、同一轮里后面的曲目，随机细节都不变
    ratio = SR / (p - 0.5) / f
    out = np.interp(np.arange(n) / ratio, np.arange(n), out[:n])
    return out * amp


def bell(note, dur=1.8, amp=0.07, ratio=3.5, index=2.0, decay=3.0):
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    mod = np.sin(2 * np.pi * f * ratio * t_) * index * np.exp(-t_ * 5)
    return np.sin(2 * np.pi * f * t_ + mod) * np.exp(-t_ * decay) * amp


def musicbox(note, dur=1.4, amp=0.06):
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    s = np.sin(2 * np.pi * f * t_) + 0.4 * np.sin(2 * np.pi * f * 4.02 * t_) * np.exp(-t_ * 8)
    return s * np.exp(-t_ * 3.5) * env(n, 0.002, 0.05) * amp


def lead(note, dur, amp=0.05, bright=2800, a=0.03, r=0.25):
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    vib = 1 + 0.005 * np.sin(2 * np.pi * 5.5 * t_) * np.clip(t_ - 0.15, 0, 1)
    ph = np.cumsum(f * vib) / SR
    s = ((ph % 1.0) * 2 - 1) * 0.6 + np.sign(np.sin(2 * np.pi * ph)) * 0.25
    return lp(s, bright) * env(n, a, r) * amp


def brass(notes, dur, amp=0.05, a=0.02, r=0.2):
    n = int(dur * SR)
    t_ = tt(n)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        for det in (-0.05, 0.05):
            sig += saw(f * 2 ** (det / 12), n)
    cut = 600 + 2400 * np.exp(-t_ * 6)
    # 时变低通：分段滤波近似
    out = np.zeros(n)
    seg = int(0.02 * SR)
    for i in range(0, n, seg):
        c = cut[min(i, n - 1)]
        out[i:i + seg] = lp(sig[max(0, i - 400):i + seg], c)[-len(out[i:i + seg]):]
    return out * env(n, a, r) * amp


def kick(amp=0.5, dur=0.4):
    n = int(dur * SR)
    t_ = tt(n)
    f = 45 + 110 * np.exp(-t_ * 28)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t_ * 7)
    s += hp(rng.standard_normal(n), 3000) * np.exp(-t_ * 120) * 0.2
    return np.tanh(s * 1.5) * amp


def snare(amp=0.25, dur=0.3):
    n = int(dur * SR)
    t_ = tt(n)
    tone_ = np.sin(2 * np.pi * 190 * t_) * np.exp(-t_ * 25)
    noise = bp(rng.standard_normal(n), 900, 5000) * np.exp(-t_ * 16)
    return (tone_ * 0.9 + noise * 0.7) * amp


def hat(amp=0.05, dur=0.06, open_=False):
    n = int((0.25 if open_ else dur) * SR)
    t_ = tt(n)
    return lp(hp(rng.standard_normal(n), 6000), 10000) * np.exp(-t_ * (12 if open_ else 70)) * amp * 0.45


def taiko(amp=0.5, pitch=70, dur=0.7):
    n = int(dur * SR)
    t_ = tt(n)
    f = pitch * (1 + 0.6 * np.exp(-t_ * 20))
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t_ * 5)
    s += lp(rng.standard_normal(n), 900) * np.exp(-t_ * 30) * 0.5
    return np.tanh(s * 1.3) * amp


def cymbal(amp=0.08, dur=2.5):
    n = int(dur * SR)
    t_ = tt(n)
    return lp(hp(rng.standard_normal(n), 4000), 9000) * np.exp(-t_ * 2.2) * amp * 0.5


def riser(dur, amp=0.06):
    n = int(dur * SR)
    t_ = tt(n)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    seg = int(0.05 * SR)
    for i in range(0, n, seg):
        c = 400 + 7000 * (i / n) ** 2
        out[i:i + seg] = lp(x[max(0, i - 500):i + seg], c)[-len(out[i:i + seg]):]
    return out * (t_ / t_[-1]) ** 2 * amp


def wash(n, amp=0.03, cut=500, waves=7):
    spec = np.fft.rfft(rng.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR)
    spec *= 1 / (1 + (fr / cut) ** 4)
    w = np.fft.irfft(spec, n)
    w = w / np.std(w)
    return w * (0.55 + 0.45 * np.sin(2 * np.pi * np.arange(n) / n * waves)) * amp


def heartbeat(amp=0.35):
    n = int(0.5 * SR)
    t_ = tt(n)
    b1 = np.sin(2 * np.pi * np.cumsum(55 + 30 * np.exp(-t_ * 30)) / SR) * np.exp(-t_ * 14)
    b2 = np.zeros(n)
    k = int(0.2 * SR)
    b2[k:] = b1[: n - k] * 0.7
    return lp(b1 + b2, 250) * amp


def piano(note, dur=3.0, amp=0.09, vel=1.0, tone=6500):
    """加法合成钢琴：带非谐性的分音 + 双段衰减 + 击弦噪声"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    sig = np.zeros(n)
    B = 0.0004
    for k in range(1, 10):
        fk = f * k * np.sqrt(1 + B * k * k)
        if fk > SR / 2 - 800:
            break
        a = (1.0 / k ** 1.5) * (1.0 if k < 4 else 0.55)
        dec = 0.6 + 0.45 * k + f / 700
        e = 0.8 * np.exp(-t_ * dec) + 0.2 * np.exp(-t_ * dec * 0.3)
        sig += a * np.sin(2 * np.pi * fk * t_ + rng.random() * 6.28) * e
    sig += lp(rng.standard_normal(n), 2500) * np.exp(-t_ * 90) * 0.12
    sig = sig * env(n, 0.003, 0.12)
    return lp(sig, tone) * amp * vel


def harp(note, dur=2.0, amp=0.04):
    s = pluck(note, dur, amp=amp, bright=0.3)
    return lp(s, 4200) * env(len(s), 0.002, 0.3)


def voice(notes, dur, amp=0.02, a=2.0, r=2.0, morph=True):
    """人声合唱：锯齿源 + 迟到颤音，元音由「呜」渐变到「啊」"""
    n = int(dur * SR)
    t_ = tt(n)
    src = np.zeros(n)
    for note in notes:
        f = midi(note)
        for det in (-0.09, 0.0, 0.08):
            depth = 0.005 * np.clip((t_ - 0.8) / 1.2, 0, 1)
            vib = 1 + depth * np.sin(2 * np.pi * (4.6 + rng.random() * 0.8) * t_ + rng.random() * 6)
            src += (np.cumsum(f * 2 ** (det / 12) * vib) / SR % 1.0) * 2 - 1
    oo = bp(src, 260, 460) * 1.0 + bp(src, 620, 880) * 0.45 + bp(src, 2200, 2600) * 0.12
    ah = bp(src, 620, 880) * 1.0 + bp(src, 1100, 1400) * 0.6 + bp(src, 2500, 2900) * 0.25
    if morph:
        m = np.clip(t_ / (a * 1.6), 0, 1) ** 1.5
        sig = oo * (1 - m) + ah * m
    else:
        sig = oo
    breath = bp(rng.standard_normal(n), 1500, 4500) * 0.006
    return (sig + breath) * env(n, a, r) * amp


def swell(notes, dur, amp=0.02, peak=0.55, bright=1600):
    """弦乐浪涌：慢起慢落，音量像一次涌浪"""
    n = int(dur * SR)
    t_ = tt(n)
    s = strings(notes, dur, amp=amp, a=0.05, r=0.05, bright=bright)
    x = t_ / dur
    shape = np.exp(-((x - peak) / 0.28) ** 2)
    return s * shape


def whale(n0, n1, dur=3.0, amp=0.025):
    """远处鲸歌：缓慢滑音的正弦 + 弱二次谐波"""
    n = int(dur * SR)
    t_ = tt(n)
    x = t_ / dur
    f = midi(n0) * (midi(n1) / midi(n0)) ** (x ** 1.4)
    f = f * (1 + 0.004 * np.sin(2 * np.pi * 3.0 * t_))
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) + 0.25 * np.sin(2 * ph)
    return lp(s, 1500) * env(n, dur * 0.35, dur * 0.4) * amp


# ============================================================ 主题动机（全作共用，原创）
# 「灯火动机」：D-F-A-G | F-E-D-C —— 标题呈示，最终 Boss 以大调/和声小调变形引用
THEME = [(62, 1), (65, 1), (69, 1.5), (67, 0.5), (65, 1), (64, 1), (62, 1.5), (60, 0.5),
         (62, 1), (65, 1), (69, 1), (72, 1), (70, 2), (69, 2)]


def play_melody(tr, mel, start_bar, inst, **kw):
    pos = 0.0
    for note, beats in mel:
        if note is not None:
            s = inst(note, beats * tr.beat + 0.25, **kw)
            tr.add(s, tr.at(start_bar) + pos * tr.beat, pan=-0.1)
        pos += beats


# ============================================================ 1. 标题《海底祈愿》
# 参考《海愿》的气质：慢板、大量留白、钢琴主旋律 + 竖琴分解 + 无词人声 + 弦乐涌浪 + 深海低鸣。
# 旋律、和声均为原创。D 小调 / 多利亚色彩，66 BPM，32 小节：引子 8 | A 8 | B 8 | 尾声 8，尾声收薄以便循环接回引子。
TITLE_MEL = [(69, 1), (74, 1.5), (72, 0.5), (69, 1), (67, 1), (65, 1), (67, 0.5), (69, 1.5),
             (65, 1), (67, 1), (69, 1), (72, 1), (70, 1.5), (69, 0.5), (67, 2),
             (69, 1), (74, 1.5), (72, 0.5), (76, 1), (77, 1), (76, 1), (74, 0.5), (72, 1.5),
             (70, 1), (72, 1), (74, 1), (70, 1), (69, 3), (None, 1)]


def make_title():
    global TRANSPOSE
    TRANSPOSE = 4  # 整体升大三度：D 小调 -> 升 F 小调，更明亮通透
    S = 4  # 引子小节数
    tr = Track(60, S + 24, tail=8.0)
    bt, bar = tr.beat, tr.bar
    Dm = [50, 57, 62, 65, 69]; Bb = [46, 53, 58, 62, 65]; F = [41, 48, 53, 57, 60]
    Gm = [43, 50, 55, 58, 62]; A = [45, 52, 57, 61, 64]; Asus = [45, 52, 57, 62, 64]
    # 每小节和弦（第 4/8 小节后半拍换 A）
    phrase = [[(Dm, 4)], [(Bb, 4)], [(F, 4)], [(Gm, 2), (A, 2)], [(Dm, 4)], [(F, 4)], [(Bb, 4)], [(Asus, 2), (A, 2)]]
    roots = {tuple(Dm): 26, tuple(Bb): 22, tuple(F): 29, tuple(Gm): 31, tuple(A): 33, tuple(Asus): 33}

    def chords_at(b):
        return phrase[(b - S) % 8]

    def piano_mel(mel, start_bar, oct_=0, amp=0.09, double=False):
        pos = 0.0
        for note, beats in mel:
            if note is not None:
                nn = note + oct_
                vel = 0.65 + 0.35 * np.clip((nn - 65 - oct_) / 12, 0, 1)
                t0 = tr.at(start_bar) + pos * bt + rng.uniform(-0.012, 0.012)
                tr.add(piano(nn, beats * bt + 2.0, amp=amp, vel=vel * 0.85, tone=3800), t0, pan=-0.12)
                if double:
                    tr.add(piano(nn - 12, beats * bt + 2.0, amp=amp * 0.4, vel=vel * 0.85, tone=3000), t0 + 0.01, pan=0.1)
            pos += beats

    # ---- 通底：深海低鸣 + 海浪
    n = tr.len
    w = wash(n, 0.007, 380, 14)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 6000)
    # 低音：引子/尾声只有 D 持续音，A/B 段跟和弦
    for b in range(S + 24):
        if S <= b < S + 20:
            pos = 0
            for ch, beats in chords_at(b):
                tr.add(sub(roots[tuple(ch)], beats * bt + 0.3, amp=0.03, a=0.6, r=0.8), tr.at(b, pos))
                pos += beats
        elif b % 4 == 0:
            tr.add(sub(26, bar * 4 + 1.0, amp=0.02, a=2.0, r=2.5), tr.at(b))

    # ---- 引子（0–3）：钢琴呈示动机头，鲸歌，人声「呜」铺底
    intro = [(69, 2), (74, 1), (72, 1), (69, 4), (67, 1), (65, 1), (67, 1), (69, 4), (None, 1)]
    piano_mel(intro, 0, amp=0.075)
    tr.add(whale(43, 50, 4.5, 0.03), tr.at(1, 1), pan=0.45)
    tr.add(voice([74, 81], bar * 2.5, amp=0.007, a=3.0, r=2.5, morph=False), tr.at(1), pan=-0.3)
    tr.add(whale(50, 45, 5.0, 0.026), tr.at(3, 0), pan=-0.4)
    tr.add(voice([50, 57, 62, 69], bar * 2 + 2.0, amp=0.014, a=2.5, r=2.5, morph=False), tr.at(2), pan=0.15)

    # ---- A 段（S..S+7）：竖琴四分音符分解 + 钢琴主旋律 + 轻人声
    for b in range(S, S + 8):
        pos = 0
        for ch, beats in chords_at(b):
            pat = [(0, ch[0] + 12), (1.5, ch[3] + 12), (2, ch[2] + 12), (3, ch[4] + 12)] if beats == 4 else [(0, ch[0] + 12), (1, ch[4] + 12)]
            for k, (off, note) in enumerate(pat):
                tr.add(harp(note, 3.0, amp=0.026), tr.at(b, pos + off + rng.uniform(0, 0.02)), pan=-0.35 + 0.7 * k / max(1, len(pat) - 1))
            tr.add(voice([ch[2] + 12, ch[3] + 12, ch[4] + 12], beats * bt + 2.0, amp=0.017, a=2.4, r=2.4), tr.at(b, pos), pan=0.2)
            tr.add(voice([ch[4] + 24], beats * bt + 2.0, amp=0.006, a=2.6, r=2.6, morph=False), tr.at(b, pos), pan=-0.3)
            pos += beats
    piano_mel(TITLE_MEL, S, amp=0.085)
    tr.add(swell([57, 62, 65, 69], bar * 2, amp=0.014, peak=0.5, bright=1200), tr.at(S + 4), pan=0.1)
    tr.add(swell([57, 61, 64, 69], bar * 2, amp=0.016, peak=0.6, bright=1200), tr.at(S + 6), pan=-0.1)

    # ---- B 段（S+8..S+15）：全奏——弦乐 + 人声「啊」+ 竖琴八分音符 + 钢琴高八度并叠低八度
    for b in range(S + 8, S + 16):
        pos = 0
        for ch, beats in chords_at(b):
            pat8 = [ch[0] + 12, ch[2] + 12, ch[3] + 12, ch[4] + 12, ch[2] + 24, ch[4] + 12, ch[3] + 12, ch[2] + 12]
            steps = int(beats * 2)
            for k in range(steps):
                note = pat8[k % 8]
                tr.add(harp(note, 2.4, amp=0.02 if k % 2 else 0.026), tr.at(b, pos + k * 0.5 + rng.uniform(0, 0.015)), pan=0.5 * np.sin(k * 1.3))
            tr.add(voice([n_ + 12 for n_ in ch[1:]], beats * bt + 2.0, amp=0.028, a=2.0, r=2.4), tr.at(b, pos), pan=0.15)
            tr.add(voice([ch[3] + 24, ch[4] + 24], beats * bt + 2.0, amp=0.008, a=2.4, r=2.6, morph=False), tr.at(b, pos), pan=-0.35)
            tr.add(strings([n_ + 12 for n_ in ch], beats * bt + 1.5, amp=0.01, a=1.4, r=1.6, bright=1100), tr.at(b, pos), pan=-0.2)
            pos += beats
        if b in (S + 8, S + 12):
            tr.add(swell([62, 65, 69, 74], bar * 4, amp=0.016, peak=0.45, bright=1400), tr.at(b), pan=0.25)
    piano_mel(TITLE_MEL, S + 8, oct_=12, amp=0.08, double=True)
    # 高音竖琴的回应（每小节末拍）
    for b in range(S + 8, S + 16):
        ch = chords_at(b)[-1][0]
        tr.add(harp(ch[4] + 24, 3.0, amp=0.018), tr.at(b, 3.5), pan=0.5)
    tr.add(whale(45, 52, 5.0, 0.026), tr.at(S + 14, 2), pan=-0.5)

    # ---- 尾声（S+16..S+23）：钢琴低声重述前半句，配器逐层退出，第 30–31 小节几乎留白
    for b in range(S + 16, S + 20):
        pos = 0
        for ch, beats in chords_at(b):
            pat = [(0, ch[0] + 12), (2, ch[3] + 12), (3, ch[4] + 12)] if beats == 4 else [(0, ch[0] + 12)]
            for k, (off, note) in enumerate(pat):
                tr.add(harp(note, 3.0, amp=0.022), tr.at(b, pos + off), pan=-0.35 + 0.7 * k / max(1, len(pat) - 1))
            tr.add(voice([ch[2] + 12, ch[3] + 12, ch[4] + 12], beats * bt + 2.0, amp=0.014, a=2.4, r=2.8), tr.at(b, pos), pan=0.2)
            pos += beats
    piano_mel(TITLE_MEL[:15], S + 16, amp=0.08)
    tr.add(voice([50, 57, 62, 69], bar * 3, amp=0.013, a=2.5, r=3.5, morph=False), tr.at(S + 20), pan=0.1)
    tr.add(voice([74, 81], bar * 2.5, amp=0.006, a=3.0, r=3.0, morph=False), tr.at(S + 21), pan=-0.3)
    tr.add(piano(62, 6.0, amp=0.06, vel=0.8), tr.at(S + 21, 0), pan=-0.1)
    tr.add(piano(69, 6.0, amp=0.05, vel=0.7), tr.at(S + 21, 2), pan=0.1)
    tr.add(whale(48, 43, 5.5, 0.026), tr.at(S + 22, 0), pan=0.4)
    # 玻璃风铃：A/B/尾声零星的高音泛音点缀
    for b in range(S, S + 22):
        if rng.random() < 0.55:
            ch = chords_at(b)[0][0]
            note = ch[2 + int(rng.integers(0, 3))] + 24
            tr.add(bell(note, 5.0, amp=0.011, ratio=2.0, index=0.5, decay=0.9), tr.at(b, float(rng.integers(0, 8)) / 2), pan=rng.uniform(-0.6, 0.6))
    # 整体轻微「水下」低通
    tr.buf[:, 0] = lp(tr.buf[:, 0], 9000)
    tr.buf[:, 1] = lp(tr.buf[:, 1], 9000)
    finish(tr, "title", peak=0.72, verb=(6.5, 0.9, 0.5, 4200))
    TRANSPOSE = 0


# ============================================================ 5. 商人《灯下小憩》
def make_shop():
    tr = Track(92, 8)
    prog = [[53, 57, 60, 64], [50, 53, 57, 60], [46, 50, 53, 57], [48, 52, 55, 60]]  # Fmaj7 Dm7 Bbmaj7 C
    roots = [41, 38, 34, 36]
    for b in range(8):
        ch = prog[b % 4]
        tr.add(strings([n + 12 for n in ch[:3]], tr.bar + 0.8, amp=0.009, a=0.6, r=0.8, bright=1400), tr.at(b), pan=-0.15)
        tr.add(voice([ch[1] + 12, ch[3] + 12], tr.bar + 1.0, amp=0.008, a=0.8, r=1.0), tr.at(b), pan=0.2)
        tr.add(sub(roots[b % 4], tr.beat * 1.5, amp=0.08), tr.at(b))
        tr.add(sub(roots[b % 4] + 7, tr.beat * 1.0, amp=0.055), tr.at(b, 2))
        for k in (1, 3):
            tr.add(harp(ch[1] + 12, 1.2, amp=0.03), tr.at(b, k), pan=-0.3)
            tr.add(harp(ch[3] + 12, 1.2, amp=0.026), tr.at(b, k + 0.02), pan=0.3)
        for e in range(8):
            tr.add(hat(0.01), tr.at(b, e * 0.5 + (0.08 if e % 2 else 0)), pan=0.4)
    mel = [(72, 1), (74, 0.5), (76, 0.5), (77, 1), (76, 1), (74, 1.5), (72, 0.5), (69, 2),
           (70, 1), (72, 0.5), (74, 0.5), (72, 1), (70, 1), (69, 1), (67, 1), (72, 2),
           (72, 1), (74, 0.5), (76, 0.5), (77, 1), (79, 1), (81, 1.5), (79, 0.5), (77, 2),
           (76, 1), (74, 1), (72, 1), (70, 1), (72, 4)]
    play_melody(tr, mel, 0, lambda n, d, **k: musicbox(n, d + 1.0, amp=0.05))
    finish(tr, "shop", verb=(2.0, 2.4, 0.35))


# ============================================================ 6. 结算短乐句
def make_stingers():
    tr = Track(96, 4, tail=3.0)
    for i, ch in enumerate([[50, 57, 62, 66], [55, 59, 62, 67], [57, 61, 64, 69], [50, 57, 62, 66, 74]]):
        tr.add(brass([n + 12 for n in ch], tr.beat * (1 if i < 3 else 4), amp=0.05), tr.at(0, i * 1.0))
        tr.add(strings([n + 12 for n in ch], tr.beat * (1.2 if i < 3 else 6), amp=0.02, a=0.05), tr.at(0, i * 1.0))
    tr.add(taiko(0.5, 60), 0)
    tr.add(cymbal(0.1, 4.0), tr.at(0, 3))
    play_melody(tr, [(74, 1), (78, 1), (81, 1), (86, 4)], 0, lambda n, d, **k: bell(n, d + 2.0, amp=0.05))
    finish(tr, "win", loop=False, verb=(3.0, 1.8, 0.4))

    tr = Track(60, 3, tail=3.0)
    for i, ch in enumerate([[50, 57, 62, 65], [49, 55, 58, 64], [46, 53, 58, 62], [45, 50, 53, 57]]):
        tr.add(strings([n + 12 for n in ch], tr.beat * 1.8, amp=0.025, a=0.3, r=0.8, bright=1500), tr.at(0, i * 1.0))
    tr.add(sub(26, 4.0, amp=0.2, a=0.5, r=2.0), 0)
    play_melody(tr, [(74, 1), (72, 1), (70, 1), (69, 3)], 0, lambda n, d, **k: bell(n, d + 2.0, amp=0.04, decay=1.5))
    finish(tr, "lose", loop=False, verb=(3.5, 1.5, 0.5))


# ============================================================ 7. 开场引子《沉降》（不循环，约 9 s）
# 对齐 game.gd 开场动画：0–1.7 s 自海面沉降，1.7 s 落地，2.1 s 灯火点亮，3.6 s 动画结束（之后战斗曲淡入）。
def make_opening():
    global TRANSPOSE
    TRANSPOSE = 4  # 与标题曲同调（升 F 小调），情绪自标题延续
    tr = Track(60, 3, tail=3.0)   # 3 小节 = 12 s 缓冲
    # 沉降：鲸歌下行 + 高音人声 + 反向涌浪
    tr.add(whale(62, 50, 1.9, 0.035), 0.0, pan=0.3)
    tr.add(voice([74, 81], 2.4, amp=0.01, a=0.4, r=1.2, morph=False), 0.0, pan=-0.3)
    tr.add(swell([62, 65, 69, 74], 1.9, amp=0.02, peak=0.85, bright=1300), 0.0, pan=0.1)
    tr.add(riser(1.7, 0.03), 0.0)
    for k in range(6):
        tr.add(bell(81 - k * 3 if k % 2 else 86 - k * 2, 2.0, amp=0.01, ratio=2.0, index=0.5, decay=1.2), 0.15 + k * 0.25, pan=rng.uniform(-0.5, 0.5))
    # 落地（1.7 s）：太鼓 + 低音 + 低音钢琴和弦
    tr.add(taiko(0.5, 55, 0.9), 1.7)
    tr.add(sub(26, 3.0, amp=0.1, a=0.01, r=1.5), 1.7)
    for n_ in (38, 45, 50):
        tr.add(piano(n_, 4.0, amp=0.07, vel=0.9, tone=3000), 1.7, pan=-0.1)
    # 灯火点亮（2.1 s）：玻璃铃 + 人声「啊」涌起 + 竖琴上行
    tr.add(bell(86, 5.0, amp=0.03, ratio=2.0, index=0.6, decay=0.8), 2.1, pan=0.2)
    tr.add(bell(81, 5.0, amp=0.022, ratio=3.0, index=0.8, decay=1.0), 2.15, pan=-0.2)
    tr.add(voice([62, 65, 69, 74], 6.0, amp=0.02, a=0.6, r=3.0), 2.1, pan=0.1)
    for k, n_ in enumerate([62, 65, 69, 74, 77, 81]):
        tr.add(harp(n_, 3.0, amp=0.03), 2.1 + k * 0.09, pan=-0.4 + 0.16 * k)
    # 尾巴：主题头两音（钢琴）+ 弦乐渐弱，交给战斗曲
    tr.add(piano(69, 4.0, amp=0.07, vel=0.8, tone=3800), 3.0, pan=-0.1)
    tr.add(piano(74, 5.0, amp=0.07, vel=0.9, tone=3800), 3.6, pan=0.1)
    tr.add(strings([57, 62, 65, 69], 6.0, amp=0.012, a=0.8, r=3.5, bright=1200), 2.4, pan=-0.2)
    finish(tr, "opening", loop=False, peak=0.75, verb=(5.0, 1.1, 0.42, 4000))
    TRANSPOSE = 0


# ============================================================ 8. Boss 叠加短乐句（不循环，叠在当前音乐之上）
def make_boss_cues():
    # 登场《浮现》：太鼓滚奏 + 铜管砸击 + 不协和合唱（约 3 s）
    tr = Track(120, 2, tail=2.5)
    for k in range(10):
        tr.add(taiko(0.18 + 0.03 * k, 75, 0.35), k * 0.07, pan=(-0.3 + 0.06 * k))
    tr.add(taiko(0.6, 52, 1.0), 0.75)
    tr.add(sub(26, 2.5, amp=0.16, a=0.005, r=1.2), 0.75)
    tr.add(brass([50, 51, 57, 62], 1.6, amp=0.06, a=0.01, r=0.9), 0.75, pan=-0.15)
    tr.add(brass([62, 63, 69], 1.2, amp=0.04, a=0.01, r=0.6), 0.78, pan=0.2)
    tr.add(choir([74, 75, 81], 2.6, amp=0.02, a=0.15, r=1.4), 0.8, pan=0.25)
    tr.add(cymbal(0.09, 2.4), 0.75)
    tr.add(strings([38, 39], 2.4, amp=0.025, a=0.1, r=0.8, bright=1400, trem=14), 0.9)
    finish(tr, "boss_in", loop=False, peak=0.8, verb=(2.0, 3.0, 0.28))

    # 击破《退潮》：上行铃声 + 铜管短号角 + 人声一声（约 4 s）
    tr = Track(120, 3, tail=3.0)
    tr.add(taiko(0.45, 60, 0.8), 0.0)
    tr.add(cymbal(0.08, 3.0), 0.0)
    for k, n_ in enumerate([62, 69, 74, 81]):
        tr.add(bell(n_, 3.0, amp=0.045, ratio=2.0, index=0.7, decay=1.1), k * 0.13, pan=-0.4 + 0.27 * k)
        tr.add(harp(n_ + 12, 2.5, amp=0.03), k * 0.13 + 0.02, pan=0.3)
    tr.add(brass([50, 57, 62, 66], 1.4, amp=0.045, a=0.02, r=0.8), 0.5, pan=-0.1)
    tr.add(voice([62, 66, 69, 74], 3.5, amp=0.02, a=0.35, r=2.0), 0.55, pan=0.15)
    tr.add(strings([57, 62, 66, 69], 3.0, amp=0.02, a=0.1, r=1.8, bright=1800), 0.5)
    finish(tr, "boss_down", loop=False, peak=0.75, verb=(2.8, 2.0, 0.35))


# ============================================================ 9. 结算后循环（短乐句播完后接续）
def make_result_loops():
    # 胜利《灯火长明》：标题主题（升 F 小调）的钢琴变奏 + 人声，循环 16 小节
    global TRANSPOSE
    TRANSPOSE = 4
    tr = Track(60, 16, tail=6.0)
    Dm = [50, 57, 62, 65, 69]; Bb = [46, 53, 58, 62, 65]; F = [41, 48, 53, 57, 60]; A = [45, 52, 57, 61, 64]
    prog = [Dm, Bb, F, A] * 4
    roots = [26, 22, 29, 33] * 4
    for b in range(16):
        ch = prog[b]
        tr.add(sub(roots[b], tr.bar + 0.5, amp=0.03, a=0.6, r=0.8), tr.at(b))
        tr.add(voice([ch[2] + 12, ch[3] + 12, ch[4] + 12], tr.bar + 2.0, amp=0.016, a=2.2, r=2.2), tr.at(b), pan=0.2)
        for k, note in enumerate([ch[0] + 12, ch[3] + 12, ch[4] + 12]):
            tr.add(harp(note, 3.0, amp=0.022), tr.at(b, k * 1.33), pan=-0.3 + 0.3 * k)
        if rng.random() < 0.5:
            tr.add(bell(ch[2 + int(rng.integers(0, 3))] + 24, 5.0, amp=0.01, ratio=2.0, index=0.5, decay=0.9), tr.at(b, float(rng.integers(0, 8)) / 2), pan=rng.uniform(-0.6, 0.6))
    pos = 0.0
    for note, beats in TITLE_MEL:
        if note is not None:
            tr.add(piano(note, beats * tr.beat + 2.0, amp=0.07, vel=0.75, tone=3600), tr.at(2) + pos * tr.beat, pan=-0.1)
        pos += beats
    n = tr.len
    w = wash(n, 0.006, 380, 6)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 6000)
    finish(tr, "win_loop", peak=0.6, verb=(6.0, 1.0, 0.5, 4200))
    TRANSPOSE = 0

    # 失败《沉底》：只剩深海低鸣、缓慢低音和零星钢琴，循环 8 小节
    tr = Track(54, 8, tail=6.0)
    n = tr.len
    w = wash(n, 0.018, 320, 4)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 7000)
    tr.add(sub(26, tr.bar * 8 + 2.0, amp=0.05, a=3.0, r=3.0), 0)
    for b in range(8):
        tr.add(voice([50, 56, 62], tr.bar + 2.0, amp=0.009, a=2.5, r=2.5, morph=False), tr.at(b), pan=0.15)
        if b % 2 == 0:
            tr.add(piano([62, 65, 60, 58][b // 2], 6.0, amp=0.055, vel=0.6, tone=2800), tr.at(b, 1), pan=-0.1)
        if b % 4 == 3:
            tr.add(whale(48, 41, 6.0, 0.022), tr.at(b), pan=rng.uniform(-0.4, 0.4))
    finish(tr, "lose_loop", peak=0.35, verb=(6.5, 0.9, 0.5, 3200))


if __name__ == "__main__":
    import sys
    args = sys.argv[1:]
    if "--skip" in args:   # --skip a,b：这几首照样算，只是不写文件（见文件头）
        k = args.index("--skip")
        SKIP.update(args[k + 1].split(","))
        del args[k:k + 2]
    which = args or ["title", "shop", "stingers", "opening", "boss_cues", "result_loops"]
    for w in which:
        globals()["make_" + w]()
