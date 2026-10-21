"""原创配乐合成（v1.0）：深海氛围 + 紧张战斗，多曲目 + 动态分层。

输出到 audio/music/：
  title.ogg                     标题《海底祈愿》升 F 小调 60 BPM（海愿气质：钢琴+竖琴+人声+弦乐涌浪）
  shop.ogg                      商人《灯下小憩》F 大调 92 BPM
  win.ogg / lose.ogg            结算短乐句（不循环）
  win_loop.ogg / lose_loop.ogg  结算短乐句之后接续的循环
  opening.ogg                   开场动画引子《沉降》（不循环，对齐 3.6 s 动画）
  boss_in.ogg / boss_down.ogg   Boss 登场 / 击破叠加短乐句（不循环，叠在当前音乐之上）
  （archive.ogg 图鉴《潮汐档案》V0 A 大调 54 BPM：文件已删，make_archive 保留，点名生成）
  deploy.ogg                    选人 / 难度 / Boss 演练《整装》升 F 小调 76 BPM（同上）
  （archive_v1.ogg 图鉴 V1「本舰」88 BPM：未选用，文件已删，make_archive_v1 保留）
  archive_v2.ogg                图鉴「卫戍」战术律动电子 104 BPM（2026-10-12 定稿，自带种子；编制避开标题曲；sfx.gd ARCHIVE_FILE）
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
OGG_LEVEL = 0.70   # Vorbis 压缩档（libsndfile）；10-21 网页包压音频从 0.45 降到 0.70（约 96 kbps 档，tools/shrink_audio.py）


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


# ============================================================ 10. 局外配乐（2026-10-12，docs/21「局外配乐」）
# 两首都自带随机种子（与前面几轮无关，单独重做结果一样），循环接缝靠 finish 把余音折回开头；
# 响度对齐标题曲（BS.1770 积分 -17.8 LUFS，gen_music_battle.lufs 测），峰值用 tanh 软限。
MENU_LUFS = -17.8


def finish_lufs(tr, name, verb, target=MENU_LUFS):
    from gen_music_battle import lufs   # 延迟导入：gen_music_battle 自己也 import 本文件
    buf = reverb(tr.buf, *verb)
    data = buf[: tr.len].copy()
    data[: tr.tail] += buf[tr.len: tr.len + tr.tail]
    for _ in range(3):   # 软限会吃掉一点响度，迭代两三次收敛
        data = data * 10 ** ((target - lufs(data)) / 20)
        data = np.tanh(data * 1.25) / 1.25
    print(name, "LUFS %.2f" % lufs(data), "峰值 %.3f" % np.max(np.abs(data)))
    pcm = np.clip(data, -1, 1).astype(np.float32)
    dst = os.path.join(OUTDIR, name + ".ogg")
    with sf.SoundFile(dst, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=OGG_LEVEL) as f:
        for i in range(0, len(pcm), 8192):
            f.write(pcm[i:i + 8192])
    print(name, round(len(data) / SR, 2), "s")


def make_archive():
    """图鉴《潮汐档案》：A 大调 54 BPM，16 小节约 71 秒循环。安静、私语感：竖琴慢分解 + 钢琴稀疏旋律 + 「呜」声垫 + 远处鲸歌。
    和弦（按 F 大调写，TRANSPOSE +4 → A 大调，与标题升 F 小调互为关系调）：F | Am | B♭ | Csus–C | Dm | Am | Gm7 | Csus，
    引子 4 小节 = 前半句和声只有竖琴；第 4–11 小节钢琴旋律（原创）；第 12–15 小节竖琴 + 八音盒回声收薄，末小节停在属和弦接回开头。"""
    global TRANSPOSE, rng
    rng = np.random.default_rng(1012)
    TRANSPOSE = 4
    tr = Track(54, 16, tail=9.0)
    bt, bar = tr.beat, tr.bar
    F = [53, 57, 60, 64]; Am = [57, 60, 64, 67]; Bb = [58, 62, 65, 69]; Csus = [55, 60, 65, 67]; C = [55, 60, 64, 67]
    Dm = [57, 60, 62, 65]; Gm7 = [55, 58, 62, 65]
    phrase = [[(F, 4)], [(Am, 4)], [(Bb, 4)], [(Csus, 2), (C, 2)], [(Dm, 4)], [(Am, 4)], [(Gm7, 4)], [(Csus, 4)]]
    roots = {tuple(F): 29, tuple(Am): 33, tuple(Bb): 34, tuple(Csus): 36, tuple(C): 36, tuple(Dm): 26, tuple(Gm7): 31}
    order = [0, 1, 2, 3, 0, 1, 2, 3, 4, 5, 6, 7, 4, 5, 6, 7]   # 每小节用 phrase 的第几项

    n = tr.len
    w = wash(n, 0.004, 340, 8)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 9000)
    for b in range(16):
        pos = 0
        for ch, beats in phrase[order[b]]:
            # 低音：长音、慢起
            tr.add(sub(roots[tuple(ch)], beats * bt + 1.0, amp=0.015, a=0.9, r=1.2), tr.at(b, pos))
            # 声垫：「呜」不变元音，很轻
            tr.add(voice([ch[1], ch[2], ch[3]], beats * bt + 2.5, amp=0.011, a=2.6, r=2.8, morph=False), tr.at(b, pos), pan=0.2)
            # 竖琴：上行分解（每拍一音，第 3 拍后半补一个高音），音量随段落起伏
            amp_h = 0.022 if 4 <= b < 12 else 0.026
            pat = [(0, ch[0]), (1, ch[1] + 12 if ch[1] + 12 < 80 else ch[1]), (2, ch[2] + 12), (2.5, ch[3] + 12), (3, ch[1] + 12)]
            for k, (off, note) in enumerate(pat):
                if off >= beats:
                    break
                tr.add(harp(note - 12 if k == 0 else note, 3.2, amp=amp_h * (1.0 if k == 0 else 0.8)),
                       tr.at(b, pos + off + rng.uniform(0, 0.025)), pan=-0.4 + 0.2 * k)
            pos += beats
    # 弦乐涌浪：两次，托住旋律的句中
    tr.add(swell([57, 60, 64, 69], bar * 2, amp=0.011, peak=0.55, bright=1100), tr.at(6), pan=-0.15)
    tr.add(swell([57, 62, 65, 69], bar * 2, amp=0.012, peak=0.5, bright=1100), tr.at(10), pan=0.15)
    # 钢琴旋律（原创）：两句问答，第二句高一点、落在属音上
    mel = [(None, 1), (72, 1), (77, 2),
           (76, 1.5), (72, 0.5), (69, 2),
           (70, 1), (74, 1), (77, 1), (72, 1),
           (72, 4),
           (None, 1), (74, 1), (77, 1), (81, 1),
           (79, 1.5), (76, 0.5), (72, 2),
           (74, 1), (70, 1), (72, 1), (74, 1),
           (72, 3), (None, 1)]
    p_ = 0.0
    for note, beats in mel:
        if note is not None:
            t0 = tr.at(4) + p_ * bt + rng.uniform(-0.015, 0.015)
            tr.add(piano(note, beats * bt + 2.5, amp=0.075, vel=0.7 + 0.2 * (note >= 77), tone=3400), t0, pan=-0.1)
        p_ += beats
    # 收尾：八音盒轻轻回声旋律开头（第 12–14 小节），末小节只剩竖琴与声垫
    for k, (note, beat_at) in enumerate([(72, 1), (77, 2), (76, 4 + 0), (72, 4 + 1.5), (69, 4 + 2), (70, 8 + 1), (74, 8 + 2)]):
        tr.add(musicbox(note + 12, 2.6, amp=0.022), tr.at(12) + beat_at * bt, pan=0.3 - 0.1 * k)
    # 远处鲸歌
    tr.add(whale(45, 52, 6.0, 0.018), tr.at(2, 1), pan=0.45)
    tr.add(whale(52, 45, 6.5, 0.016), tr.at(13, 0), pan=-0.45)
    # 零星玻璃风铃
    for b in range(16):
        if rng.random() < 0.4:
            ch = phrase[order[b]][0][0]
            tr.add(bell(ch[int(rng.integers(1, 4))] + 24, 5.0, amp=0.008, ratio=2.0, index=0.5, decay=0.9),
                   tr.at(b, float(rng.integers(0, 8)) / 2), pan=rng.uniform(-0.6, 0.6))
    tr.buf[:, 0] = lp(tr.buf[:, 0], 8000)
    tr.buf[:, 1] = lp(tr.buf[:, 1], 8000)
    finish_lufs(tr, "archive", verb=(6.0, 0.95, 0.5, 4000))
    TRANSPOSE = 0


def make_deploy():
    """选人 / 难度 / Boss 演练《整装》：升 F 小调 76 BPM，24 小节约 76 秒循环。标题主旋律（TITLE_MEL）换一套和声，
    底下一直走轻脉动（低鼓 1、「2 与」两下 + 竖琴八分持续音滴答），越往后越满，制造出发前的期待感。
    和弦（按 D 小调写，TRANSPOSE +4）：Dm9 | Gm7 | F | B♭–C | Am7 | Dm7 | Gm7 | Asus–A（标题曲是 Dm B♭ F Gm–A …）。
    0–3 引子（脉动 + 和声）/ 4–11 钢琴唱主旋律 / 12–19 主旋律高八度交给人声「啊」+ 钢琴，弦乐与军鼓边击加入 /
    20–23 退回脉动与钢琴回声，末小节属和弦 + 轻微上扬接回开头。"""
    global TRANSPOSE, rng
    rng = np.random.default_rng(1013)
    TRANSPOSE = 4
    tr = Track(76, 24, tail=8.0)
    bt, bar = tr.beat, tr.bar
    Dm9 = [50, 57, 60, 64, 65]; Gm7 = [43, 50, 53, 58, 62]; F = [41, 48, 53, 57, 60]
    Bb = [46, 53, 58, 62, 65]; C = [48, 55, 60, 64, 67]; Am7 = [45, 52, 55, 60, 64]; Dm7 = [38, 50, 57, 60, 65]
    Asus = [45, 52, 57, 62, 64]; A = [45, 52, 57, 61, 64]
    phrase = [[(Dm9, 4)], [(Gm7, 4)], [(F, 4)], [(Bb, 2), (C, 2)], [(Am7, 4)], [(Dm7, 4)], [(Gm7, 4)], [(Asus, 2), (A, 2)]]
    roots = {id(Dm9): 26, id(Gm7): 31, id(F): 29, id(Bb): 34, id(C): 36, id(Am7): 33, id(Dm7): 26, id(Asus): 33, id(A): 33}

    def chords_at(b):
        return phrase[(b - 4) % 8] if b >= 4 else phrase[b]

    def piano_mel(mel, start_bar, oct_=0, amp=0.08):
        pos = 0.0
        for note, beats in mel:
            if note is not None:
                t0 = tr.at(start_bar) + pos * bt + rng.uniform(-0.01, 0.01)
                tr.add(piano(note + oct_, beats * bt + 1.8, amp=amp, vel=0.8, tone=3800), t0, pan=-0.12)
            pos += beats

    n = tr.len
    w = wash(n, 0.006, 380, 12)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 6000)
    for b in range(24):
        full = 12 <= b < 20
        pos = 0
        for ch, beats in chords_at(b):
            r = roots[id(ch)]
            tr.add(sub(r, beats * bt + 0.2, amp=0.018, a=0.05, r=0.4), tr.at(b, pos))
            tr.add(voice([n_ + 12 for n_ in ch[2:]], beats * bt + 1.6, amp=0.014 if not full else 0.018, a=1.2, r=1.6, morph=False),
                   tr.at(b, pos), pan=0.2)
            if full:
                tr.add(strings([n_ + 12 for n_ in ch[1:4]], beats * bt + 0.8, amp=0.009, a=0.6, r=0.9, bright=1500), tr.at(b, pos), pan=-0.25)
            pos += beats
        # 脉动：低鼓（第 1 拍 + 第 2 拍后半，第 3 拍轻一下），第 20–23 小节退回只剩第 1 拍
        tr.add(taiko(0.11, 82, 0.5), tr.at(b, 0))
        if b < 20 or b == 23:
            tr.add(taiko(0.06, 82, 0.4), tr.at(b, 1.5))
            tr.add(taiko(0.075, 76, 0.45), tr.at(b, 2))
        if full or b == 11:
            tr.add(snare(0.05, 0.18), tr.at(b, 3), pan=0.15)   # 轻边击（只在第 4 拍）
        # 竖琴滴答：八分音符持续音（主音 + 五度交替），落在当前和弦的根音上
        ch0 = chords_at(b)[0][0]
        tick = [ch0[2] + 12, ch0[1] + 24 if ch0[1] + 24 < 84 else ch0[1] + 12]
        for e in range(8):
            if b < 2 and e % 2:
                continue   # 引子头两小节只有四分音符，慢慢起来
            note = tick[e % 2]
            tr.add(harp(note, 1.4, amp=0.017 if e % 2 else 0.021), tr.at(b, e * 0.5 + rng.uniform(0, 0.01)), pan=0.35 if e % 2 else -0.3)
        # 小沙锤式的高频滴答（第 4 小节起，反拍）
        if b >= 4:
            for e in range(1, 8, 2):
                tr.add(hat(0.012 if not full else 0.016), tr.at(b, e * 0.5), pan=0.45)
    piano_mel(TITLE_MEL, 4, amp=0.078)
    piano_mel(TITLE_MEL, 12, oct_=12, amp=0.06)
    # 人声「啊」高八度唱主旋律（第 12–19 小节）
    pos = 0.0
    for note, beats in TITLE_MEL:
        if note is not None:
            tr.add(voice([note + 12], beats * bt + 0.6, amp=0.013, a=0.25, r=0.5), tr.at(12) + pos * bt, pan=0.1)
        pos += beats
    tr.add(swell([62, 65, 69, 74], bar * 4, amp=0.014, peak=0.6, bright=1400), tr.at(12), pan=0.2)
    tr.add(swell([57, 61, 64, 69], bar * 4, amp=0.014, peak=0.5, bright=1400), tr.at(16), pan=-0.2)
    tr.add(cymbal(0.05, 3.0), tr.at(12))
    # 第 20–23 小节：钢琴回声主旋律头两个音组，末小节轻微上扬接回开头
    for k, (note, at) in enumerate([(69, 0), (74, 1), (72, 2.5), (69, 4), (74, 5), (76, 6.5)]):
        tr.add(piano(note, 3.0, amp=0.055, vel=0.75, tone=3400), tr.at(20) + at * bt, pan=0.1)
    tr.add(riser(bar * 0.9, 0.012), tr.at(23, 0.4))
    tr.add(whale(43, 50, 5.0, 0.018), tr.at(1, 2), pan=0.4)
    tr.buf[:, 0] = lp(tr.buf[:, 0], 9000)
    tr.buf[:, 1] = lp(tr.buf[:, 1], 9000)
    finish_lufs(tr, "deploy", verb=(4.0, 1.4, 0.4, 4200))
    TRANSPOSE = 0


# ============================================================ 11. 电子乐器与效果（2026-10-12，图鉴 V1「本舰」/ V2「卫戍」用，可复用）
# 只借「风格」：暖的模拟味合成器声垫、侧链式音量起伏、拨弦合成器琶音、模拟低音、电子鼓、比特粉碎的科技滴答、磁带饱和。
# 旋律、和弦进行、节奏型全部原创，不取样、不模仿任何现成曲目的具体音型。
def _blep(p, dt):
    y = np.zeros_like(p)
    m = p < dt
    x = p[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = p > 1.0 - dt
    x = (p[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def osc(f, n, wave="saw", ph=None):
    """限带振荡器（PolyBLEP）。f 可以是常数或逐采样数组；wave = saw / square / pulse（25%）/ tri / sine"""
    fa = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    dt = np.minimum(fa / SR, 0.45)
    p = (np.cumsum(dt) + (rng.random() if ph is None else ph)) % 1.0
    if wave == "sine":
        return np.sin(2 * np.pi * p)
    if wave == "tri":
        return 1.0 - 4.0 * np.abs(p - 0.5)
    if wave == "saw":
        return 2.0 * p - 1.0 - _blep(p, dt)
    pw = 0.25 if wave == "pulse" else 0.5
    y = np.where(p < pw, 1.0, -1.0) + _blep(p, dt) - _blep((p + 1.0 - pw) % 1.0, dt)
    return y


def fenv_lp(x, lo, hi, k, order=2):
    """滤波包络的近似：亮 / 暗两路低通按 exp(-k·t) 交叉，起音亮、随后变暗（拨弦合成器的「啵」）"""
    e = np.exp(-tt(len(x)) * k)
    d = lp(x, lo, order)
    b = lp(x, hi, order)
    return d + (b - d) * e


def synpad(notes, dur, amp=0.012, cut=1200, a=0.8, r=1.2, wave="saw", voices=3, detune=0.14, motion=0.3, rate=0.11):
    """去谐锯齿 / 方波声垫 + 低通，截止频率缓慢呼吸（暖、模拟味）"""
    n = int(dur * SR)
    t_ = tt(n)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        for v in range(voices):
            det = detune * (2 * v / max(1, voices - 1) - 1)
            drift = 1 + 0.0012 * np.sin(2 * np.pi * (0.2 + 0.4 * rng.random()) * t_ + rng.random() * 6)
            sig += osc(f * 2 ** (det / 12) * drift, n, wave)
    lo_ = lp(sig, cut * (1 - motion))
    hi_ = lp(sig, cut * (1 + motion))
    m = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t_ + rng.random() * 6)
    return (lo_ + (hi_ - lo_) * m) * env(n, a, r) * amp


def spluck(note, dur=0.45, amp=0.03, wave="saw", lo=400, hi=3500, k=16, decay=5.0, det=0.06):
    """拨弦合成器：两个微去谐振荡器 + 快速关闭的滤波包络"""
    n = int(dur * SR)
    f = midi(note)
    raw = osc(f * 2 ** (-det / 12), n, wave) + osc(f * 2 ** (det / 12), n, wave)
    return fenv_lp(raw, lo, hi, k) * np.exp(-tt(n) * decay) * env(n, 0.002, 0.04) * amp


def abass(note, dur, amp=0.06, cut=320, k=10, wave="saw", sub_mix=0.9, drive=1.6, a=0.004, r=0.06):
    """模拟低音：滤波锯齿（给小喇叭听得见的泛音）+ 正弦次低音，轻微过载"""
    n = int(dur * SR)
    f = midi(note)
    body = fenv_lp(osc(f, n, wave), cut, cut * 2.6, k, order=3)
    s = body * 0.7 + np.sin(2 * np.pi * f * tt(n)) * sub_mix
    return np.tanh(s * drive) / drive * env(n, a, r) * amp


def epiano(note, dur=2.0, amp=0.04, vel=1.0):
    """FM 电钢琴：1:1 调制（温暖的「叮」随时间变圆）+ 短促的高次金属音叉"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    mod = np.sin(2 * np.pi * f * t_) * (1.4 * vel) * np.exp(-t_ * 2.5)
    car = np.sin(2 * np.pi * f * t_ + mod)
    tine = np.sin(2 * np.pi * f * 14.0 * t_) * np.exp(-t_ * 45) * 0.12 * vel
    body = car * (0.7 * np.exp(-t_ * 1.3) + 0.3 * np.exp(-t_ * 0.35))
    return (body + tine) * env(n, 0.002, 0.15) * amp * vel


def slead(note, dur, amp=0.025, wave="square", cut=2400, a=0.004, r=0.05, k=9):
    """合成器主奏：方波 / 锯齿 + 滤波包络，迟到颤音"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note) * (1 + 0.004 * np.sin(2 * np.pi * 5.3 * t_) * np.clip((t_ - 0.25) / 0.3, 0, 1))
    raw = osc(f, n, wave) * 0.8 + osc(f * 2 ** (0.07 / 12), n, "saw") * 0.3
    return fenv_lp(raw, cut * 0.45, cut, k) * env(n, a, r) * amp


def ekick(amp=0.5, f0=140, f1=47, sweep=32, decay=7.0, click=0.2, drive=1.5, tone=None):
    """电子底鼓：正弦扫频 + 起音咔嗒，tone 给低通（lo-fi 闷鼓）"""
    n = int(0.5 * SR)
    t_ = tt(n)
    f = f1 + (f0 - f1) * np.exp(-t_ * sweep)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t_ * decay)
    s += hp(rng.standard_normal(n), 2500) * np.exp(-t_ * 260) * click
    s = np.tanh(s * drive) / np.tanh(drive)
    if tone:
        s = lp(s, tone)
    return s * env(n, 0.0005, 0.05) * amp


def esnare(amp=0.2, tone=205, tight=24, nlo=1600, nhi=8500):
    """电子军鼓：短促的鼓皮音 + 带通噪声"""
    n = int(0.35 * SR)
    t_ = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(tone * (1 + 0.35 * np.exp(-t_ * 60))) / SR) * np.exp(-t_ * tight * 1.3)
    noise = bp(rng.standard_normal(n), nlo, nhi) * np.exp(-t_ * tight)
    return (body * 0.55 + noise) * amp


def eclap(amp=0.15):
    """拍手：三下极短的噪声 + 一段尾巴"""
    n = int(0.4 * SR)
    t_ = tt(n)
    e = np.zeros(n)
    for k, off in enumerate((0.0, 0.010, 0.021, 0.030)):
        i = int(off * SR)
        e[i:] += np.exp(-(t_[i:] - off) * (200 if k < 3 else 20)) * (1.0 if k < 3 else 0.7)
    return bp(rng.standard_normal(n), 900, 3800) * e * amp


_HAT_F = (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)


def ehat(amp=0.04, open_=False, tone=7000):
    """电子镲：六个不谐和方波（金属感）+ 噪声，高通"""
    n = int((0.32 if open_ else 0.07) * SR)
    t_ = tt(n)
    m = sum(np.sign(np.sin(2 * np.pi * f * 1.9 * t_ + rng.random() * 6)) for f in _HAT_F)
    s = hp(m * 0.5 + rng.standard_normal(n) * 0.6, tone, 3)
    return s * np.exp(-t_ * (10 if open_ else 65)) * env(n, 0.0005, 0.01) * amp * 1.8


def erim(amp=0.06):
    """边击 / 木块：短促的高音 + 一点噪声"""
    n = int(0.12 * SR)
    t_ = tt(n)
    s = np.sin(2 * np.pi * 1650 * t_) * np.exp(-t_ * 90) + np.sin(2 * np.pi * 520 * t_) * np.exp(-t_ * 60) * 0.5
    s += bp(rng.standard_normal(n), 2000, 7000) * np.exp(-t_ * 150) * 0.4
    return s * amp


def bitcrush(x, bits=6, down=4):
    """比特粉碎：降采样（采样保持）+ 量化"""
    held = np.repeat(x[::down], down)[: len(x)]
    q = 2 ** (bits - 1)
    return np.round(held * q) / q


def glitch(amp=0.012, dur=0.05):
    """科技滴答：一两个音阶的短方波，比特粉碎"""
    n = int(dur * SR)
    t_ = tt(n)
    f0 = float(rng.choice([1760, 2217, 2637, 3322]))
    f = np.where(t_ < dur * 0.5, f0, f0 * float(rng.choice([0.75, 1.0, 1.5])))
    s = osc(f, n, "square") * np.exp(-t_ * 70)
    return bitcrush(s, bits=4, down=int(rng.choice([3, 5, 8]))) * env(n, 0.0005, 0.005) * amp


def ping(note, amp=0.02, dur=1.6):
    """声呐 / 雷达式的轻「叮」：正弦 + 很轻的 FM，配合延迟用"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    return np.sin(2 * np.pi * f * t_ + 0.6 * np.sin(2 * np.pi * f * 2 * t_) * np.exp(-t_ * 12)) * np.exp(-t_ * 3.2) * env(n, 0.002, 0.1) * amp


def add_st(tr, st, start, gain=1.0):
    """把立体声信号（N×2）叠进 Track"""
    i = max(0, int(start * SR))
    j = min(i + len(st), len(tr.buf))
    if j > i:
        tr.buf[i:j] += st[: j - i] * gain


def pingpong(x, delay_s, fb=0.35, taps=6, tone=3200):
    """乒乓延迟（只返回湿声，长度不变）：回声左右交替、越来越暗。单声道相加不抵消（没有反相）"""
    d = int(delay_s * SR)
    out = np.zeros((len(x), 2))
    y = x
    for k in range(1, taps + 1):
        y = lp(y, tone) * fb
        if k * d >= len(x):
            break
        out[k * d:, k % 2] += y[: len(x) - k * d]
    return out


def pump_env(n, period, depth, rel=0.55, att=0.006):
    """侧链式音量起伏：每 period 秒在拍点压下 depth（depth 可以是逐采样数组，按段落给深浅），rel = 恢复占周期的比例"""
    t_ = tt(n)
    ph = np.mod(t_, period)
    e = np.clip(1 - ph / (period * rel), 0, 1) ** 2 * np.clip(ph / att, 0, 1)
    return 1 - depth * e


def fft_tone(data, lo=None, hi=None, order=2):
    """循环（FFT）高通 / 低通：对循环段做滤波不会在接缝处留下滤波器状态的跳变"""
    X = np.fft.rfft(data, axis=0)
    fr = np.fft.rfftfreq(len(data), 1 / SR)
    g = np.ones_like(fr)
    if hi:
        g /= np.sqrt(1 + (fr / hi) ** (2 * order))
    if lo:
        g /= np.sqrt(1 + (lo / np.maximum(fr, 1e-6)) ** (2 * order))
    return np.fft.irfft(X * g[:, None], len(data), axis=0)


def tape_loop(data, drive=1.5, wow_ms=0.6, wow_hz=0.45, flutter_ms=0.04, flutter_hz=6.0, hi=9000):
    """磁带 / lo-fi：循环的速度起伏（wow + flutter，周期取整让接缝对上）+ tanh 饱和 + 循环低通"""
    L = len(data)
    secs = L / SR
    k1 = max(1, round(wow_hz * secs))
    k2 = max(1, round(flutter_hz * secs))
    i = np.arange(L)
    d = (wow_ms * np.sin(2 * np.pi * k1 * i / L) + flutter_ms * np.sin(2 * np.pi * k2 * i / L + 1.0)) * SR / 1000
    pad_ = int(np.max(np.abs(d))) + 4
    out = np.zeros_like(data)
    for c in range(2):
        ext = np.concatenate([data[-pad_:, c], data[:, c], data[:pad_, c]])
        out[:, c] = np.interp(i + d + pad_, np.arange(len(ext)), ext)
    rms = np.sqrt(np.mean(out ** 2)) + 1e-12
    out = np.tanh(out / rms * 0.12 * drive) / (0.12 * drive) * rms   # 饱和量按电平归一，与混音前的绝对音量无关
    return fft_tone(out, lo=28, hi=hi)


def limit_loop(x, ceil=0.68, look=0.004):
    """循环峰值限制器：前瞻最小值滤波 + 平滑（mode=wrap，接缝处一样）。保证 |x| ≤ ceil"""
    from scipy.ndimage import minimum_filter1d, uniform_filter1d
    a = np.max(np.abs(x), axis=1)
    g = np.minimum(1.0, ceil / np.maximum(a, 1e-9))
    w = max(3, int(look * SR))
    gm = minimum_filter1d(g, 2 * w + 1, mode="wrap")
    gs = uniform_filter1d(gm, w, mode="wrap")
    gs = minimum_filter1d(gs, 3, mode="wrap")
    return np.clip(x * gs[:, None], -ceil, ceil), gs


def finish_loop_fx(buf, L, tail, name, target=None, ceil=0.68, post=None):
    """局外循环曲的收尾：余音折回开头 → post（磁带等，循环处理）→ 响度迭代对齐 + 循环限制器（峰值 ≤ -3.3 dBFS）"""
    from gen_music_battle import lufs
    target = MENU_LUFS if target is None else target
    data = buf[:L].copy()
    data[:tail] += buf[L:L + tail]
    if post is not None:
        data = post(data)
    gs = np.ones(L)
    for _ in range(5):
        data = data * 10 ** ((target - lufs(data)) / 20)
        data, gs = limit_loop(data, ceil)
    mono = data.mean(axis=1)
    corr = float(np.corrcoef(data[:, 0], data[:, 1])[0, 1])
    print(name, "LUFS %.2f" % lufs(data), "峰值 %.2f dBFS" % (20 * np.log10(np.max(np.abs(data)))),
          "单声道 %.2f LU" % (lufs(mono) - lufs(data)), "左右相关 %.2f" % corr,
          "限制 >1 dB 的时间 %.1f%%" % (100 * np.mean(gs < 10 ** (-1 / 20))), "长度 %.2f s" % (L / SR))
    if name in SKIP:
        return data
    pcm = np.clip(data, -1, 1).astype(np.float32)
    dst = os.path.join(OUTDIR, name + ".ogg")
    with sf.SoundFile(dst, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=OGG_LEVEL) as f:
        for i in range(0, len(pcm), 8192):
            f.write(pcm[i:i + 8192])
    return data


class Mix:
    """几条总线（各自一个 Track 缓冲）：drums / bass / pad / pluck / lead / harp / mallet / bells / fx / amb，最后各自加效果再相加"""
    def __init__(self, bpm, bars, tail=8.0):
        self.bus = {k: Track(bpm, bars, tail) for k in ("drums", "bass", "pad", "pluck", "lead", "harp", "mallet", "bells", "fx", "amb")}
        self.t = self.bus["pad"]

    def balance(self, targets):
        """各总线按 BS.1770 响度拉到给定值（相对值，最后整体再对齐 MENU_LUFS）：targets = {总线: (LUFS, 起小节, 止小节)}，
        只在给定的参考段里测（段落之间的起伏仍由编曲里的 amp 决定）。总线之间的比例在这里一处定，改起来不用逐个乐器调"""
        from gen_music_battle import lufs
        for k, (tgt, b0, b1) in targets.items():
            cur = lufs(self.bus[k].buf[int(self.at(b0) * SR):int(self.at(b1) * SR)])
            if cur > -90:
                self.bus[k].buf *= 10 ** ((tgt - cur) / 20)

    def at(self, bar, beat=0.0):
        return self.t.at(bar, beat)

    def add(self, bus, sig, start, pan=0.0, gain=1.0):
        self.bus[bus].add(sig, start, pan, gain)


def play_line(mx, bus, mel, start_bar, inst, pan=0.0, swing=0.0, **kw):
    """按（音, 拍数）列表演奏一条旋律；None 是休止"""
    pos = 0.0
    for note, beats in mel:
        if note is not None:
            mx.add(bus, inst(note, beats * mx.t.beat, **kw), mx.at(start_bar) + pos * mx.t.beat + swing, pan=pan)
        pos += beats


# ============================================================ 12. 图鉴 V1「本舰」：舒缓电子氛围（88 BPM 半速感）
# 和弦（升 F 小调 / A 大调，原创排列）：
#   引子 0–3 + A 4–11：F#m9 | Dmaj9 | Amaj7/C# | E6sus4 | F#m9 | Dmaj9 | Bm9 | Esus4–E
#   B 12–19：Dmaj9 | C#m7 | Bm9 | F#m9 | Dmaj9 | C#m7 | Bm9 | Esus4–E（电钢琴唱原创旋律）
#   间奏 20–23：Dmaj9 | C#m7 | Bm9 | E6sus4（鼓退场，竖琴 + 鲸歌 + 弦乐涌浪）
#   尾段 24–27：F#m9 | Dmaj9 | Amaj7/C# | E6sus4（电钢琴回声旋律头，逐层收薄，接回引子）
V1_CH = {
    "F#m9": (42, [57, 61, 64, 68]), "Dmaj9": (38, [54, 57, 61, 64]), "Amaj7/C#": (37, [56, 61, 64, 69]),
    "E6sus4": (40, [57, 59, 61, 64]), "Bm9": (35, [57, 61, 62, 66]), "C#m7": (37, [56, 59, 64, 68]),
    "Esus4": (40, [57, 59, 64, 71]), "E": (40, [56, 59, 64, 71]),
}
V1_A = [[("F#m9", 4)], [("Dmaj9", 4)], [("Amaj7/C#", 4)], [("E6sus4", 4)],
        [("F#m9", 4)], [("Dmaj9", 4)], [("Bm9", 4)], [("Esus4", 2), ("E", 2)]]
V1_B = [[("Dmaj9", 4)], [("C#m7", 4)], [("Bm9", 4)], [("F#m9", 4)],
        [("Dmaj9", 4)], [("C#m7", 4)], [("Bm9", 4)], [("Esus4", 2), ("E", 2)]]
V1_BARS = V1_A[:4] + V1_A + V1_B + [[("Dmaj9", 4)], [("C#m7", 4)], [("Bm9", 4)], [("E6sus4", 4)]] + V1_A[:4]
V1_BAL = {"pad": (-21.6, 4, 12), "pluck": (-24.1, 4, 12), "lead": (-22.1, 12, 20), "amb": (-31.0, 4, 12), "harp": (-26.0, 20, 24),
          "drums": (-24.4, 4, 12), "bass": (-26.0, 4, 12)}   # 总线响度（相对，按 A 段 / 主旋律按 B 段测）
V1_MEL = [(None, 0.5), (73, 0.5), (76, 1), (78, 1.5), (76, 0.5),
          (73, 2), (None, 1), (71, 0.5), (73, 0.5),
          (74, 1), (73, 0.5), (71, 0.5), (69, 1.5), (66, 0.5),
          (68, 3), (None, 1),
          (None, 0.5), (73, 0.5), (76, 1), (81, 1.5), (80, 0.5),
          (76, 2), (None, 0.5), (78, 0.5), (80, 0.5), (76, 0.5),
          (78, 1), (74, 1), (73, 1), (71, 1),
          (71, 2), (68, 1), (None, 1)]


def make_archive_v1():
    global TRANSPOSE, rng
    rng = np.random.default_rng(1014)
    TRANSPOSE = 0
    bars = len(V1_BARS)   # 28
    mx = Mix(88, bars, tail=8.0)
    tr = mx.t
    bt, bar = tr.beat, tr.bar
    A_, B_, BRK, OUT = range(4, 12), range(12, 20), range(20, 24), range(24, 28)
    groove = lambda b: 4 <= b < 20 or 24 <= b < 27

    for b in range(bars):
        pos = 0.0
        for name, beats in V1_BARS[b]:
            root, vc = V1_CH[name]
            t0 = mx.at(b, pos)
            dur = beats * bt
            # 声垫：左右两层（随机相位不同，单声道相加不抵消），截止频率按段落开合
            if b < 4:
                cut = 700 + 150 * b          # 引子：慢慢打开
            elif b in A_:
                cut = 1300
            elif b in B_:
                cut = 1500
            elif b in BRK:
                cut = 1650                   # 间奏：声垫最开
            else:
                cut = 1150 - 90 * (b - 24)   # 尾段：慢慢合上，接回引子
            for pan in (-0.55, 0.55):
                mx.add("pad", synpad(vc, dur + 0.7, amp=0.0105 * (0.6 if b in BRK else 1.0), cut=cut, a=0.35, r=0.8), t0, pan=pan)
            if b in B_ or b in BRK:   # 高八度方波微光
                mx.add("pad", synpad([vc[2] + 12, vc[3] + 12], dur + 0.7, amp=0.004, cut=2600, wave="square", voices=2, a=0.6, r=0.9), t0, pan=0.25)
            # 低音
            if b < 4 or b in BRK or b == 27:
                mx.add("bass", sub(root, dur + 0.4, amp=0.03 if b >= 4 else 0.035, a=0.4, r=0.6), t0)
            else:
                for off, d, a_ in ((0, 1.5, 1.0), (1.75, 0.6, 0.7), (2.5, 1.4, 0.85)):
                    if off < beats:
                        mx.add("bass", abass(root, min(d, beats - off) * bt, amp=0.075 * a_, cut=300), mx.at(b, pos + off))
                if b in B_ and beats == 4:
                    mx.add("bass", abass(root + 12, 0.4 * bt, amp=0.04, cut=420), mx.at(b, pos + 3.5))
            # 拨弦合成器琶音（八分音符，第 2 小节起；间奏让给竖琴）
            if 2 <= b < 20 or 24 <= b < 27:
                pat = [0, 2, 1, 3, 0, 2, 3, 1]
                hi_c = 1700 if b < 4 else 2600 if b in B_ else 3400
                a_p = 0.016 if b < 4 else 0.012 if b in B_ else 0.017
                for e in range(int(beats * 2)):
                    note = vc[pat[e % 8]] + 12
                    acc = 1.0 if e % 2 == 0 else 0.7
                    mx.add("pluck", spluck(note, 0.42, amp=a_p * acc, wave="saw", lo=380, hi=hi_c, k=14),
                           mx.at(b, pos + e * 0.5 + (0.04 if e % 2 else 0)), pan=-0.3 + 0.6 * ((e * 3) % 8) / 7)
            # 竖琴：引子 / 间奏 / 尾末小节每拍一音的上行分解（深海底色），groove 段每两小节末拍一声高音回应
            if b < 4 or b in BRK or b == 27:
                step = 0.5 if b in BRK else 1.0
                for k in range(int(beats / step)):
                    note = vc[k % 4] + (12 if k < 4 else 24)
                    mx.add("harp", harp(note, 2.6, amp=0.016 if b in BRK else 0.018), mx.at(b, pos + k * step + rng.uniform(0, 0.02)),
                           pan=-0.4 + 0.8 * (k % 4) / 3)
            elif b % 2 == 1 and pos + beats >= 4:
                mx.add("harp", harp(vc[3] + 24, 3.0, amp=0.016), mx.at(b, 3.5), pan=0.45)
            pos += beats

        # ---- 鼓：半速感（第 1 拍底鼓、第 3 拍拍手 / 边击），八分镲带一点摇摆
        if groove(b):
            soft = b >= 24
            kt = 2600 if not soft else 1400
            mx.add("drums", ekick(0.5 if not soft else 0.36, f0=120, f1=46, decay=6.5, click=0.12, tone=kt), mx.at(b, 0))
            if not soft:
                mx.add("drums", ekick(0.26, f0=110, f1=48, decay=8, click=0.05, tone=2200), mx.at(b, 1.75))
                if b % 2 == 1:
                    mx.add("drums", ekick(0.22, f0=110, f1=48, decay=8, click=0.05, tone=2200), mx.at(b, 3.5))
                if b in B_:
                    mx.add("drums", eclap(0.09), mx.at(b, 2), pan=0.05)
                    mx.add("drums", esnare(0.07, tone=190, tight=20, nhi=6000), mx.at(b, 2))
                else:
                    mx.add("drums", erim(0.05), mx.at(b, 2), pan=0.1)
                    mx.add("drums", eclap(0.045), mx.at(b, 2), pan=-0.05)
            for e in range(8):
                if soft and e % 2 == 0:
                    continue
                sw = 0.06 if e % 2 else 0.0
                mx.add("drums", ehat(0.03 if e % 2 else 0.018, tone=7500), mx.at(b, e * 0.5 + sw), pan=0.3)
            if b in B_ and b % 2 == 0:
                mx.add("drums", ehat(0.012, tone=8000), mx.at(b, 3.75), pan=0.3)
            if b % 2 == 1 and not soft:
                mx.add("drums", ehat(0.018, open_=True, tone=7000), mx.at(b, 3.5 + 0.06), pan=0.35)
        elif b in BRK or b == 3:
            for e in range(1, 8, 2):   # 只剩反拍轻沙沙
                mx.add("drums", ehat(0.012, tone=8500), mx.at(b, e * 0.5 + 0.06), pan=0.4)
        # 科技滴答：十六分格子上零星几下
        if b >= 2:
            for s in range(16):
                if rng.random() < (0.1 if groove(b) else 0.06):
                    mx.add("amb", glitch(0.006), mx.at(b, s * 0.25), pan=float(rng.uniform(-0.7, 0.7)))

    # ---- 主旋律（电钢琴，B 段）+ 尾段回声旋律头
    play_line(mx, "lead", V1_MEL, 12, lambda n_, d, **k: epiano(n_, d + 1.6, amp=0.05, vel=0.9), pan=-0.08)
    play_line(mx, "lead", V1_MEL[16:], 16, lambda n_, d, **k: osc(midi(n_ + 12), int((d + 0.2) * SR), "tri") * env(int((d + 0.2) * SR), 0.05, 0.2) * 0.006, pan=0.2)
    play_line(mx, "lead", V1_MEL[:9], 24, lambda n_, d, **k: epiano(n_, d + 1.6, amp=0.032, vel=0.75), pan=0.1)
    # ---- 深海底色：海浪声、鲸歌、弦乐涌浪、玻璃风铃
    am = mx.bus["amb"]
    n = tr.len
    w = wash(n, 0.004, 340, 7)
    am.buf[:n, 0] += w
    am.buf[:n, 1] += np.roll(w, 9000)
    mx.add("amb", whale(45, 52, 6.0, 0.006), mx.at(1, 1), pan=0.45)
    mx.add("amb", whale(52, 45, 6.5, 0.006), mx.at(21, 0), pan=-0.45)
    mx.add("amb", swell([57, 61, 64, 69], bar * 2, amp=0.003, peak=0.55, bright=1200), mx.at(20), pan=-0.15)
    mx.add("amb", swell([57, 59, 64, 68], bar * 2, amp=0.003, peak=0.5, bright=1200), mx.at(22), pan=0.15)
    for b in range(bars):
        if rng.random() < 0.3:
            vc = V1_CH[V1_BARS[b][0][0]][1]
            mx.add("amb", bell(vc[int(rng.integers(1, 4))] + 24, 4.0, amp=0.006, ratio=2.0, index=0.5, decay=1.0),
                   mx.at(b, float(rng.integers(0, 8)) / 2), pan=float(rng.uniform(-0.6, 0.6)))

    # ---- 混音：声垫 / 低音侧链起伏（groove 段深、其余浅），琶音与主旋律走附点八分乒乓延迟
    L = tr.len + tr.tail
    depth = np.full(L, 0.08)
    for b in range(bars):
        if groove(b):
            depth[int(mx.at(b) * SR):int(mx.at(b + 1) * SR)] = 0.32
    depth = uniform_smooth(depth, int(0.2 * SR))
    pmp = pump_env(L, bt, depth)
    pb = pump_env(L, bt, depth * 0.6)
    B = mx.bus
    B["pad"].buf *= pmp[:, None]
    B["bass"].buf *= pb[:, None]
    for k in ("pluck", "lead"):
        m_ = B[k].buf.mean(axis=1)
        B[k].buf += pingpong(m_, 0.75 * bt, fb=0.38 if k == "pluck" else 0.3, taps=6, tone=2800) * (0.45 if k == "pluck" else 0.35)
    mx.balance(V1_BAL)
    out = (reverb(B["drums"].buf, 0.8, 6.0, 0.12, 5000) + B["bass"].buf
           + reverb(B["pad"].buf + B["pluck"].buf + B["lead"].buf, 3.0, 1.6, 0.3, 4200)
           + reverb(B["amb"].buf + B["harp"].buf, 5.5, 0.95, 0.45, 4000))
    finish_loop_fx(out, tr.len, tr.tail, "archive_v1",
                   post=lambda d: tape_loop(d, drive=1.6, wow_ms=0.55, hi=8500))
    TRANSPOSE = 0


def uniform_smooth(x, w):
    from scipy.ndimage import uniform_filter1d
    return uniform_filter1d(x, max(1, w), mode="nearest")


# ============================================================ 12b. 图鉴专用音色（2026-10-12 第三轮：与标题《海底祈愿》的钢琴 / 竖琴 / 人声 / 弦乐涌浪 / 鲸歌区分开）
def pwm_osc(f, n, pw):
    """脉宽调制方波（两个限带锯齿相减），pw 可以是逐采样数组（0.1–0.9）"""
    fa = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    dt = np.minimum(fa / SR, 0.45)
    p = (np.cumsum(dt) + rng.random()) % 1.0
    q = (p - pw) % 1.0
    return (2.0 * p - _blep(p, dt)) - (2.0 * q - _blep(q, dt))


def pwm_pad(notes, dur, amp=0.01, cut=1300, a=0.3, r=0.6, rate=0.35, depth=0.22, voices=2, detune=0.07):
    """暖的 PWM 声垫：脉宽缓慢摆动（每个声部速率不同），低通 + 去直流"""
    n = int(dur * SR)
    t_ = tt(n)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        for v in range(voices):
            det = detune * (2 * v / max(1, voices - 1) - 1)
            pw = 0.5 + depth * np.sin(2 * np.pi * (rate + 0.15 * rng.random()) * t_ + rng.random() * 6)
            sig += pwm_osc(f * 2 ** (det / 12), n, pw)
    return hp(lp(sig, cut), 70) * env(n, a, r) * amp


def mallet(note, dur=1.6, amp=0.03, kind="vibe"):
    """FM / 加法槌击乐器：vibe = 颤音琴式（1 : 4 : 10 分音 + 马达颤音），marimba = 木琴式（1 : 3.93 : 9.2，短、木头感）"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    if kind == "vibe":
        parts = ((1.0, 1.0, 1.1), (4.0, 0.22, 4.5), (10.0, 0.05, 14.0))
        trem = 1 - 0.28 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.6 * t_ + rng.random() * 6))
    else:
        parts = ((1.0, 1.0, 3.4), (3.93, 0.32, 9.0), (9.2, 0.07, 22.0))
        trem = 1.0
    s = np.zeros(n)
    for ratio, a_, dec in parts:
        if f * ratio < SR / 2 - 500:
            s += np.sin(2 * np.pi * f * ratio * t_ + rng.random() * 6) * np.exp(-t_ * dec) * a_
    s += lp(rng.standard_normal(n), 2500 if kind == "vibe" else 1500) * np.exp(-t_ * 250) * 0.15   # 槌头
    return s * trem * env(n, 0.001, 0.08) * amp


def glass(note, dur=3.0, amp=0.008):
    """玻璃质感的 FM 铃：不谐和调制比 2.76 + 5.4 分音、两个微去谐的副本（区别于标题曲 2:1 的玻璃风铃）"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    s = np.zeros(n)
    for c in (-3, 3):
        fc = f * 2 ** (c / 1200)
        mod = np.sin(2 * np.pi * fc * 2.76 * t_) * 1.8 * np.exp(-t_ * 3.0)
        s += np.sin(2 * np.pi * fc * t_ + mod) * np.exp(-t_ * 1.6)
    s += np.sin(2 * np.pi * f * 5.4 * t_) * np.exp(-t_ * 6) * 0.25
    return s * env(n, 0.001, 0.2) * amp


_FORMANT_BANDS = (310, 450, 640, 900, 1250, 1700, 2350, 3200)


def formant_pad(notes, dur, amp=0.006, a=1.2, r=1.6):
    """声码器味的共振峰声垫：脉冲源过八条窄带通（固定频率），各带音量随机慢速起伏——机械、透明，不是人声元音"""
    n = int(dur * SR)
    t_ = tt(n)
    src = np.zeros(n)
    for note in notes:
        src += pwm_osc(midi(note), n, 0.3)
    out = np.zeros(n)
    for fc in _FORMANT_BANDS:
        lfo = 0.55 + 0.45 * np.sin(2 * np.pi * (0.12 + 0.3 * rng.random()) * t_ + rng.random() * 6)
        out += bp(src, fc * 0.94, fc * 1.06) * lfo
    return out * env(n, a, r) * amp


def sea_noise(n, amp=0.004, waves=6):
    """「海」噪声：低 / 中两段带通噪声按整数个周期缓慢交替起伏（FFT 生成，本身首尾相接），取代鲸歌做深海底色"""
    fr = np.fft.rfftfreq(n, 1 / SR)
    out = []
    for lo_, hi_ in ((120, 480), (550, 1800)):
        X = np.fft.rfft(rng.standard_normal(n))
        X *= 1 / np.sqrt(1 + (lo_ / np.maximum(fr, 1e-6)) ** 4) / np.sqrt(1 + (fr / hi_) ** 4)
        w_ = np.fft.irfft(X, n)
        out.append(w_ / np.std(w_))
    ph = 2 * np.pi * np.arange(n) / n * waves
    return (out[0] * (0.6 + 0.4 * np.sin(ph)) + out[1] * 0.5 * (0.5 + 0.5 * np.sin(ph * 1.5 + 1.0) ** 2)) * amp


# ============================================================ 13. 图鉴 V2「卫戍」：战术律动电子（104 BPM）
# 和弦（升 F 小调，原创排列）：
#   引子 0–3：F#m | D | E | C#m（滤波琶音逐小节打开）
#   A 4–11：F#m | D | E | C#m | F#m | D | E | C#sus–C#（底鼓 + 2/4 拍军鼓 + 十六分镲 + 八分低音推进）
#   B 12–19：Bm | D | F#m | E | Bm | D | C#sus | C#（共振滤波方波主奏原创动机 + FM 合成铃高八度叠奏）
#   间奏 20–25：D | E | F#m | F#m | Bm | C#sus–C#（鼓退场，方波拨弦琶音 + 声码器声垫 + 比特粉碎主奏回声 + 声呐，第 24 小节起闷鼓慢慢回来）
# 编制刻意避开标题曲（钢琴 / 竖琴 / 人声 / 弦乐涌浪 / 鲸歌，用户 10-12），并按「电子感更强一点」改成纯合成器 + 鼓机（见 make_archive_v2）
#   回归 26–31：F#m | D | E | C#m | Bm–D | C#sus–C#（末小节只剩镲与琶音，接回引子）
V2_CH = {
    "F#m": (42, [57, 61, 66, 69]), "D": (38, [57, 62, 66, 69]), "E": (40, [56, 59, 64, 68]),
    "C#m": (37, [56, 61, 64, 68]), "C#sus": (37, [54, 61, 66, 68]), "C#": (37, [56, 61, 65, 68]),
    "Bm": (35, [54, 59, 62, 66]),
}
V2_BARS = ([[("F#m", 4)], [("D", 4)], [("E", 4)], [("C#m", 4)]]
           + [[("F#m", 4)], [("D", 4)], [("E", 4)], [("C#m", 4)], [("F#m", 4)], [("D", 4)], [("E", 4)], [("C#sus", 2), ("C#", 2)]]
           + [[("Bm", 4)], [("D", 4)], [("F#m", 4)], [("E", 4)], [("Bm", 4)], [("D", 4)], [("C#sus", 4)], [("C#", 4)]]
           + [[("D", 4)], [("E", 4)], [("F#m", 4)], [("F#m", 4)], [("Bm", 4)], [("C#sus", 2), ("C#", 2)]]
           + [[("F#m", 4)], [("D", 4)], [("E", 4)], [("C#m", 4)], [("Bm", 2), ("D", 2)], [("C#sus", 2), ("C#", 2)]])
V2_MEL = [(71, 0.5), (None, 0.25), (71, 0.25), (74, 0.5), (76, 0.5), (78, 1), (76, 0.5), (74, 0.5),
          (73, 1.5), (None, 0.5), (69, 0.5), (71, 0.5), (73, 1),
          (73, 0.5), (None, 0.25), (73, 0.25), (76, 0.5), (78, 0.5), (81, 1), (80, 0.5), (78, 0.5),
          (76, 1.5), (None, 2.5),
          (71, 0.5), (None, 0.25), (71, 0.25), (74, 0.5), (76, 0.5), (78, 1), (81, 0.5), (83, 0.5),
          (81, 1.5), (78, 0.5), (76, 1), (74, 1),
          (73, 1), (None, 0.5), (73, 0.5), (71, 0.5), (73, 0.5), (78, 1),
          (77, 3), (None, 1)]
V2_BAL = {"pad": (-23.5, 12, 20), "pluck": (-23.3, 4, 12), "lead": (-22.2, 12, 20), "amb": (-35.0, 4, 12), "bells": (-27.0, 20, 24),
          "fx": (-31.0, 0, 32),
          "drums": (-21.4, 4, 12), "bass": (-25.0, 4, 12)}
V2_ARP = [0, 2, 1, 3, 2, 1, 0, 2, 0, 2, 1, 3, 2, 3, 1, 2]
FORMANT_AMP, BELL_AMP, SWELL_AMP = 0.005, 0.016, 0.004   # 间奏声码器声垫 / B 段 FM 合成铃叠奏 / 间奏 PWM 慢涌


# ============================================================ 12c. 更电子的音色与效果（2026-10-12 第四轮，用户「电子感更强一点」）
def res_lp(x, cut, q=0.9, block=64):
    """时变共振低通（RBJ 双二阶，按块更新系数、状态连续）：cut 可以是常数或逐采样数组，q > 0.707 出共振峰"""
    from scipy.signal import lfilter
    n = len(x)
    cut = np.broadcast_to(np.asarray(cut, dtype=float), (n,))
    out = np.empty(n)
    zi = np.zeros(2)
    for i in range(0, n, block):
        c = min(max(float(cut[i]), 30.0), SR * 0.45)
        w0 = 2 * np.pi * c / SR
        al = np.sin(w0) / (2 * q)
        cs = np.cos(w0)
        a0 = 1 + al
        b = np.array([(1 - cs) / 2, 1 - cs, (1 - cs) / 2]) / a0
        a = np.array([1.0, -2 * cs / a0, (1 - al) / a0])
        out[i:i + block], zi = lfilter(b, a, x[i:i + block], zi=zi)
    return out


def supersaw(notes, dur, amp=0.006, voices=7, detune=0.22, a=0.05, r=0.4, cut=7000):
    """超级锯齿声垫：每个音 voices 个去谐锯齿（中间的最响），只做一个宽松低通，扫频交给总线上的 res_lp"""
    n = int(dur * SR)
    t_ = tt(n)
    sig = np.zeros(n)
    for note in notes:
        f = midi(note)
        for v in range(voices):
            x = 2 * v / max(1, voices - 1) - 1
            g = 1.0 if v == voices // 2 else 0.6
            drift = 1 + 0.0008 * np.sin(2 * np.pi * (0.2 + 0.3 * rng.random()) * t_ + rng.random() * 6)
            sig += osc(f * 2 ** (detune * x / 12) * drift, n, "saw") * g
    return hp(lp(sig, cut), 90) * env(n, a, r) * amp


def kick909(amp=0.5, click=0.55):
    """鼓机底鼓：高起点快扫频 + 明显咔嗒 + 过载"""
    return ekick(amp, f0=230, f1=50, sweep=42, decay=6.0, click=click, drive=2.2)


def gated_verb(x, length=0.11, mix=0.6):
    """门限混响（80 年代鼓机味）：平直的噪声冲激在 length 秒处被一刀切断"""
    n = int(length * SR)
    ir = lp(rng.standard_normal(n), 6500) * env(n, 0.002, 0.006)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = fftconvolve(x, ir)[: len(x) + n]
    out = np.zeros(len(x) + n)
    out[: len(x)] += x
    out[: len(wet)] += wet * mix
    return out


def growl_bass(note, dur, amp=0.06, hi=1500, lo=180, q=3.2, k=13, drive=2.4):
    """次低音（正弦）+ 中频咆哮层（两个去谐锯齿过共振低通，滤波包络从 hi 关到 lo）"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    raw = osc(f, n, "saw") + osc(f * 1.007, n, "saw")
    mid = res_lp(raw, lo + (hi - lo) * np.exp(-t_ * k), q)
    s = np.tanh(mid * 0.5 * drive) / drive + np.sin(2 * np.pi * f * t_) * 0.75
    return s * env(n, 0.003, 0.05) * amp


def synbell(note, dur=1.2, amp=0.02):
    """短 FM 合成铃：金属调制比 3.41、调制深度快速衰减，两个副本差 5 音分"""
    n = int(dur * SR)
    t_ = tt(n)
    f = midi(note)
    s = np.zeros(n)
    for c in (-2.5, 2.5):
        fc = f * 2 ** (c / 1200)
        s += np.sin(2 * np.pi * fc * t_ + 2.4 * np.exp(-t_ * 7) * np.sin(2 * np.pi * fc * 3.41 * t_))
    return s * np.exp(-t_ * 4.5) * env(n, 0.001, 0.1) * amp


def noise_sweep(dur, up=True, amp=0.02, lo=250, hi=7500, q=2.5):
    """上扬 / 下沉的噪声扫频（riser / downlifter）：共振低通按指数扫，音量跟着走"""
    n = int(dur * SR)
    x = np.linspace(0, 1, n)
    c = lo * (hi / lo) ** (x if up else 1 - x)
    s = res_lp(rng.standard_normal(n), c, q, block=128)
    shape = x ** 2 if up else (1 - x) ** 1.5
    return s * shape * env(n, 0.01, 0.03) * amp


def rev_cymbal(dur=1.6, amp=0.03):
    """反向镲：衰减的高通噪声倒过来，正好在落点前涌到最大"""
    n = int(dur * SR)
    t_ = tt(n)
    s = hp(rng.standard_normal(n), 3500) * np.exp(-t_ * 2.6)
    return s[::-1] * env(n, 0.05, 0.004) * amp


def stutter(buf, t0, beat, plan):
    """节拍重复式切片（beat-repeat）：plan = [(起拍, 切片拍长, 重复次数, 增益)…]，从 t0 + 起拍处取一片、在原地往后连贴几次（覆盖原声）"""
    for at, sl, reps, g in plan:
        i0 = int((t0 + at * beat) * SR)
        m = int(sl * beat * SR)
        piece = buf[i0:i0 + m].copy()
        fade = np.ones(m)
        k = min(m // 4, int(0.003 * SR))
        if k > 0:
            fade[:k] = np.linspace(0, 1, k)
            fade[-k:] = np.linspace(1, 0, k)
        piece *= fade[:, None]
        for r_ in range(reps):
            j = i0 + r_ * m
            buf[j:j + m] = piece * (g ** r_)


def mono_line(mx, bus, mel, start_bar, amp=0.022, glide=0.05, hi=3400, lo=650, q=4.0, k=8.0, crush=None, pan=0.0, gate=0.85):
    """单音合成器主奏：方波 + 锯齿，共振低通滤波包络，前后两音之间带滑音（portamento），crush=(位数, 降采样) 时比特粉碎"""
    bt = mx.t.beat
    pos = 0.0
    prev = None
    for note, beats in mel:
        if note is not None:
            d = max(beats * bt * gate, 0.08)
            n = int((d + 0.06) * SR)
            t_ = tt(n)
            f1 = midi(note)
            f0 = midi(prev) if prev is not None else f1
            f = f1 + (f0 - f1) * np.exp(-t_ / (glide / 3))
            raw = osc(f, n, "square") * 0.8 + osc(f * 1.004, n, "saw") * 0.35
            y = res_lp(raw, lo + (hi - lo) * np.exp(-t_ * k), q)
            y = y * env(n, 0.003, 0.06) * amp
            if crush:
                y = bitcrush(y / amp, *crush) * amp
            mx.add(bus, y, mx.at(start_bar) + pos * bt, pan=pan)
            prev = note
        pos += beats


def make_archive_v2():
    """图鉴「卫戍」（第四轮：电子感更强）。编制：超级锯齿 + PWM 声垫（共振低通分段扫频、每拍约 5 dB 侧链、A 段 trance gate）、
    909 式底鼓 / 门限混响军鼓拍手 / 清脆开闭镲、次低音 + 咆哮中频低音、十六分脉冲波琶音、共振滤波方波主奏（滑音）+ FM 合成铃叠奏、
    段落交界的噪声上扬 / 下沉与反向镲、句尾节拍重复切片、间奏比特粉碎主奏回声 + 声码器味声垫 + 方波拨弦琶音，声呐叮作深海标志"""
    global TRANSPOSE, rng
    rng = np.random.default_rng(1015)
    TRANSPOSE = 0
    bars = len(V2_BARS)   # 32
    mx = Mix(104, bars, tail=8.0)
    tr = mx.t
    bt, bar = tr.beat, tr.bar
    A_, B_, BRK, RET = range(4, 12), range(12, 20), range(20, 26), range(26, 32)
    groove = lambda b: 4 <= b < 20 or 26 <= b < 31

    for b in range(bars):
        pos = 0.0
        for name, beats in V2_BARS[b]:
            root, vc = V2_CH[name]
            t0 = mx.at(b, pos)
            dur = beats * bt
            # 声垫：超级锯齿左右两层 + PWM 一层（扫频与侧链在总线上做）
            pg = 0.6 if b in BRK else 0.75 if b < 4 else 1.0   # 间奏 / 引子声垫轻一点
            for pan in (-0.6, 0.6):
                mx.add("pad", supersaw(vc, dur + 0.35, amp=0.0042 * pg, a=0.03 if groove(b) else 0.3, r=0.35), t0, pan=pan)
            mx.add("pad", pwm_pad([c + 12 for c in vc[1:]], dur + 0.4, amp=0.004 * pg, cut=3000, a=0.05, r=0.4), t0, pan=0.0)
            if b in BRK:   # 声码器味的共振峰声垫
                mx.add("amb", formant_pad([vc[1] + 12, vc[2] + 12, vc[3] + 12], dur + 1.5, amp=FORMANT_AMP, a=1.5, r=2.0), t0, pan=0.2)
            # 低音：groove 段八分推进（次低音 + 咆哮层），间奏长音，引子后半闷声八分
            if groove(b):
                patt = [(0, 0, 1.0, 0.45), (0.75, 0, 0.6, 0.2), (1.5, 12, 0.6, 0.22), (2, 0, 0.9, 0.45),
                        (2.75, 0, 0.6, 0.2), (3, 7, 0.65, 0.22), (3.5, 12, 0.6, 0.22)]
                for off, iv, a_, d in patt:
                    if off < beats:
                        mx.add("bass", growl_bass(root + iv, d * bt * 1.6, amp=0.07 * a_, hi=1700 if b in B_ else 1300), mx.at(b, pos + off))
            elif b in BRK or b == 31:
                mx.add("bass", growl_bass(root, dur + 0.2, amp=0.035, hi=400, lo=150, k=1.5, q=1.5), t0)
            elif b >= 2:
                for e in range(int(beats * 2)):
                    mx.add("bass", growl_bass(root, 0.35 * bt, amp=0.035, hi=500, lo=150), mx.at(b, pos + e * 0.5))
            # 十六分琶音（脉冲波拨弦）
            if not (20 <= b < 24):
                if b < 4:
                    hi_c, a_p = 900 + 650 * b, 0.011
                elif b in B_:
                    hi_c, a_p = 2300, 0.0085
                elif b in (24, 25):
                    hi_c, a_p = 900 + 700 * (b - 24) + 500 * (pos / 4), 0.01
                elif b == 31:
                    hi_c, a_p = 2400 - 400 * pos, 0.011
                else:
                    hi_c, a_p = 3200, 0.012
                for s in range(int(beats * 4)):
                    note = vc[V2_ARP[s % 16]] + 12
                    acc = 1.0 if s % 4 == 0 else 0.8 if s % 2 == 0 else 0.6
                    mx.add("pluck", spluck(note, 0.22, amp=a_p * acc, wave="pulse", lo=500, hi=hi_c, k=22, decay=9),
                           mx.at(b, pos + s * 0.25), pan=0.35 if s % 2 else -0.35)
            # 间奏：去谐方波拨弦八分上行分解（取代木琴）
            if b in BRK:
                for k in range(int(beats * 2)):
                    note = vc[k % 4] + (12 if (k // 4) % 2 == 0 else 24)
                    mx.add("bells", spluck(note, 0.6, amp=0.03, wave="square", lo=600, hi=2800, k=10, decay=5, det=0.12),
                           mx.at(b, pos + k * 0.5), pan=-0.45 + 0.9 * (k % 4) / 3)
            pos += beats

        # ---- 鼓（鼓机味）
        if groove(b):
            full = not (b == 30)
            kicks = [0, 1.5, 2] + ([3.25] if b % 2 == 0 else [3.75])
            for kb in kicks:
                if not full and kb >= 2:
                    continue
                mx.add("drums", kick909(0.58 if kb in (0, 2) else 0.4), mx.at(b, kb))
            for sb in (1, 3):
                if not full and sb == 3:
                    continue
                hit = esnare(0.13, tone=225, tight=36, nlo=2200, nhi=9000) + eclap(0.07 if b in B_ or sb == 3 else 0.04)[: int(0.35 * SR)]
                mx.add("drums", gated_verb(hit, 0.11, 0.55), mx.at(b, sb), pan=0.05)
            for s in range(16):
                acc = [0.03, 0.012, 0.022, 0.012][s % 4]
                mx.add("drums", ehat(acc, tone=9500), mx.at(b, s * 0.25), pan=0.28)
            if b % 2 == 1 or b in B_:
                mx.add("drums", ehat(0.024, open_=True, tone=8000), mx.at(b, 3.5), pan=0.32)
            if b in B_ or b in A_:
                mx.add("drums", ehat(0.016, open_=True, tone=8000), mx.at(b, 1.5), pan=-0.3)
        elif b < 4:
            for s in range(16 if b >= 2 else 8):
                step = 0.25 if b >= 2 else 0.5
                mx.add("drums", ehat(0.02 if (s * step) % 1 == 0.5 else 0.012, tone=9500), mx.at(b, s * step), pan=0.3)
            if b == 3:
                for kb in (0, 2):
                    mx.add("drums", ekick(0.3, f0=120, f1=48, decay=8, click=0.0, tone=400), mx.at(b, kb))
        elif b in BRK:
            mx.add("drums", gated_verb(erim(0.035), 0.08, 0.4), mx.at(b, 3), pan=0.15)
            for e in range(1, 8, 2):
                mx.add("drums", ehat(0.01, tone=9500), mx.at(b, e * 0.5), pan=0.4)
            if b in (24, 25):   # 闷鼓慢慢回来
                for kb in range(4):
                    mx.add("drums", ekick(0.26 + 0.06 * (b - 24), f0=150, f1=50, decay=7, click=0.1, tone=350 + 600 * (b - 24) + 150 * kb), mx.at(b, kb))
        elif b == 31:
            for s in range(16):
                mx.add("drums", ehat([0.024, 0.01, 0.016, 0.01][s % 4], tone=9500), mx.at(b, s * 0.25), pan=0.3)
        # 科技滴答
        if b >= 4:
            pr = 0.16 if b in B_ else 0.1 if groove(b) else 0.05
            for s in range(16):
                if rng.random() < pr:
                    mx.add("amb", glitch(0.007), mx.at(b, s * 0.25), pan=float(rng.uniform(-0.7, 0.7)))

    # ---- 主奏：B 段共振滤波方波（滑音）+ FM 合成铃高八度叠奏；间奏比特粉碎的慢速回声动机头
    mono_line(mx, "lead", V2_MEL, 12, amp=0.024, pan=-0.1)
    play_line(mx, "bells", V2_MEL, 12, lambda n_, d, **k: synbell(n_ + 12, 1.0, amp=BELL_AMP), pan=0.3)
    mono_line(mx, "lead", [(n_, d * 2) for n_, d in V2_MEL[:8]], 22, amp=0.016, hi=2600, lo=500, k=4, crush=(5, 6), pan=0.12, gate=0.7)
    # 声呐「叮」（深海标志）
    for b_, beat_, note in ((0, 0, 90), (12, 0, 85), (20, 0, 88), (21, 2, 85), (23, 2, 83)):
        mx.add("lead", ping(note, 0.016), mx.at(b_, beat_), pan=0.15)
    # ---- 段落交界：噪声上扬 / 下沉、反向镲
    for b_ in (3, 11, 25):
        mx.add("fx", noise_sweep(bar, up=True, amp=0.03), mx.at(b_), pan=-0.2)
        mx.add("fx", noise_sweep(bar, up=True, amp=0.03), mx.at(b_) + 0.01, pan=0.2)
    for b_ in (4, 12, 26):
        c = rev_cymbal(bt * 2, 0.03)
        mx.add("fx", c, mx.at(b_) - len(c) / SR, pan=0.0)
    mx.add("fx", noise_sweep(bar * 1.5, up=False, amp=0.03), mx.at(20), pan=0.1)
    mx.add("fx", noise_sweep(bar, up=False, amp=0.02, hi=5000), mx.at(31), pan=-0.1)
    # ---- 深海底色（很轻）：带通「海」噪声、PWM 慢涌、玻璃 FM 铃
    am = mx.bus["amb"]
    n = tr.len
    w = sea_noise(n, 0.0015, 8)
    am.buf[:n, 0] += w
    am.buf[:n, 1] += np.roll(w, 9000)
    for b_, ch, pan in ((22, [57, 62, 66, 69], -0.15), (24, [54, 61, 65, 68], 0.15)):
        sw = pwm_pad([c + 12 for c in ch], bar * 2, amp=SWELL_AMP, cut=1800, a=bar * 0.9, r=bar * 0.9, rate=0.5, depth=0.3)
        mx.add("amb", sw, mx.at(b_), pan=pan)
    for b in range(bars):
        if rng.random() < 0.25:
            vc = V2_CH[V2_BARS[b][0][0]][1]
            mx.add("amb", glass(vc[int(rng.integers(1, 4))] + 24, 3.0, amp=0.006),
                   mx.at(b, float(rng.integers(0, 8)) / 2), pan=float(rng.uniform(-0.6, 0.6)))

    L = tr.len + tr.tail
    B = mx.bus
    # 句尾节拍重复（第 11 / 19 / 29 小节第 4 拍）：鼓、琶音、低音一起切
    for b_ in (11, 19, 29):
        for k in ("drums", "pluck", "bass"):
            stutter(B[k].buf, mx.at(b_), bt, [(3.0, 0.5, 1, 1.0), (3.5, 0.25, 2, 0.9), (3.75, 0.125, 2, 0.85)])
    # 声垫：共振低通分段扫频（引子打开 → A 平 → B 慢慢上扬 → 间奏收暗再打开 → 回归 → 末两小节合上接回引子）
    pts = [(0, 400), (4, 1800), (12, 1900), (20, 3200), (20.25, 700), (26, 2400), (30, 2200), (32, 400), (32 + L / SR / bar, 400)]
    xb = np.arange(L) / SR / bar
    cut = np.exp(np.interp(xb, [p_[0] for p_ in pts], [np.log(p_[1]) for p_ in pts]))
    for c in range(2):
        B["pad"].buf[:, c] = res_lp(B["pad"].buf[:, c], cut, q=2.2, block=256)
    # 侧链：groove 段每拍压下约 5 dB，其余浅
    depth = np.full(L, 0.12)
    for b in range(bars):
        if groove(b):
            depth[int(mx.at(b) * SR):int(mx.at(b + 1) * SR)] = 0.45
    depth = uniform_smooth(depth, int(0.2 * SR))
    B["pad"].buf *= pump_env(L, bt, depth, rel=0.6)[:, None]
    B["bass"].buf *= pump_env(L, bt, depth * 0.3)[:, None]
    # A 段 trance gate（十六分开合，关时留 15%）
    gate = np.ones(L)
    patt = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]
    s16 = bt / 4
    for b in A_:
        for s in range(16):
            if not patt[s]:
                i0 = int((mx.at(b) + s * s16) * SR)
                gate[i0:i0 + int(s16 * SR)] = 0.15
    gate = uniform_smooth(gate, int(0.004 * SR))
    B["pad"].buf *= gate[:, None]
    B["pluck"].buf += pingpong(B["pluck"].buf.mean(axis=1), 0.75 * bt, fb=0.3, taps=5, tone=3000) * 0.3
    B["lead"].buf += pingpong(B["lead"].buf.mean(axis=1), 0.5 * bt, fb=0.32, taps=5, tone=3400) * 0.32
    B["bells"].buf += pingpong(B["bells"].buf.mean(axis=1), 0.75 * bt, fb=0.3, taps=4, tone=3500) * 0.25
    mx.balance(V2_BAL)
    out = (reverb(B["drums"].buf, 0.5, 9.0, 0.08, 7000) + B["bass"].buf
           + reverb(B["pad"].buf + B["pluck"].buf + B["lead"].buf + B["bells"].buf, 2.2, 2.2, 0.22, 5000)
           + reverb(B["fx"].buf, 2.5, 2.0, 0.3, 6000)
           + reverb(B["amb"].buf, 5.0, 1.0, 0.45, 4000))
    finish_loop_fx(out, tr.len, tr.tail, "archive_v2",
                   post=lambda d: tape_loop(d, drive=1.15, wow_ms=0.15, flutter_ms=0.01, hi=14000))
    TRANSPOSE = 0


if __name__ == "__main__":
    import sys
    args = sys.argv[1:]
    if "--skip" in args:   # --skip a,b：这几首照样算，只是不写文件（见文件头）
        k = args.index("--skip")
        SKIP.update(args[k + 1].split(","))
        del args[k:k + 2]
    which = args or ["title", "shop", "stingers", "opening", "boss_cues", "result_loops", "deploy", "archive_v2"]   # archive（V0）/ archive_v1 已不进游戏，要试听时点名生成
    for w in which:
        globals()["make_" + w]()
