"""原创配乐合成（v0.9）：深海氛围 + 紧张战斗，多曲目 + 动态分层。

输出到 audio/music/：
  title.ogg                     标题《潮底灯火》D 小调 72 BPM
  explore_base / pulse / drive / danger.ogg   战斗《深潮》四层同长同步，游戏按局势叠加
  boss.ogg                      中期 Boss《海嗣之主》D 弗里吉亚 132 BPM
  final.ogg                     最终 Boss《深蓝之树》D 和声小调 140 BPM
  shop.ogg                      商人《灯下小憩》F 大调 92 BPM
  win.ogg / lose.ogg            结算短乐句（不循环）
全部为原创旋律与编曲，合成方式：减法/FM/Karplus-Strong + 卷积混响。
"""
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
import subprocess, os, wave

SR = 44100
rng = np.random.default_rng(7)
HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "audio", "music")
os.makedirs(OUTDIR, exist_ok=True)


# ============================================================ 基础
def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


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
        i = int(start * SR)
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
    wav = "/tmp/claude-0/_m.wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(data, -1, 1) * 32767).astype(np.int16).tobytes())
    dst = os.path.join(OUTDIR, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", dst], check=True)
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
    out = out[:n]
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


# ============================================================ 1. 标题《潮底灯火》
def make_title():
    tr = Track(72, 16, tail=5.0)
    prog = [[50, 57, 62, 65, 69], [46, 53, 58, 62, 65], [41, 48, 53, 57, 60], [45, 52, 57, 61, 64]]  # Dm Bb F A
    bass = [38, 34, 41, 33]
    for b in range(0, 16, 2):
        ch = prog[(b // 2) % 4]
        tr.add(pad(ch, tr.bar * 2 + 1.5, bright=800, amp=0.016, a=1.8, r=1.8), tr.at(b))
        tr.add(sub(bass[(b // 2) % 4], tr.bar * 2, amp=0.12, a=0.6, r=1.0), tr.at(b))
        if b >= 8:
            tr.add(choir([n + 12 for n in ch[2:]], tr.bar * 2 + 1.0, amp=0.008), tr.at(b), pan=0.2)
    # 拨弦分解和弦（钢琴感）
    for b in range(16):
        ch = prog[(b // 2) % 4]
        arp = [ch[0] + 12, ch[2], ch[3], ch[4], ch[3], ch[2]]
        for k, note in enumerate(arp):
            tr.add(pluck(note, 1.4, amp=0.05, bright=0.4), tr.at(b, k * 4 / 6), pan=np.sin(k) * 0.4)
    # 主题：第 5–8 小节铃声，第 9–14 小节弦乐
    play_melody(tr, THEME, 4, lambda n, d, **k: bell(n + 12, d + 1.2, amp=0.05))
    play_melody(tr, THEME, 9, lambda n, d, **k: strings([n], d, amp=0.03, a=0.25, r=0.6))
    n = tr.len
    w = wash(n, 0.025, 450, 5)
    tr.buf[:n, 0] += w
    tr.buf[:n, 1] += np.roll(w, 4000)
    finish(tr, "title", verb=(3.2, 1.8, 0.45))


# ============================================================ 2. 战斗《深潮》四层
def make_explore():
    bars = 16
    prog = [[50, 57, 62, 65], [46, 53, 58, 62], [48, 55, 60, 64], [45, 52, 57, 60],   # Dm Bb C Am
            [50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 57, 61]]   # Dm Bb Gm A
    roots = [38, 34, 36, 33, 38, 34, 31, 33]

    def base():
        tr = Track(104, bars)
        for b in range(0, bars, 2):
            ch = prog[b // 2]
            tr.add(pad(ch, tr.bar * 2 + 1.2, bright=700, amp=0.018, a=1.0, r=1.2), tr.at(b))
            tr.add(sub(roots[b // 2], tr.bar * 2, amp=0.13, a=0.3, r=0.6), tr.at(b))
        # 远处的铃声动机（稀疏）
        motif = [74, 72, 69, 70]
        for b in range(0, bars, 4):
            for k, note in enumerate(motif):
                tr.add(bell(note, 2.2, amp=0.035), tr.at(b + 1, k * 0.75), pan=0.3)
        n = tr.len
        w = wash(n, 0.03, 500, 8)
        tr.buf[:n, 0] += w
        tr.buf[:n, 1] += np.roll(w, 3000)
        return tr

    def pulse():
        tr = Track(104, bars)
        for b in range(bars):
            r = roots[b // 2]
            for e in range(8):
                note = r + (12 if e in (3, 6) else 0) + (7 if e == 5 else 0)
                tr.add(reese(note + 12, tr.beat * 0.45, amp=0.07, cut=700), tr.at(b, e * 0.5))
            for beat in (0, 2):
                tr.add(kick(0.32), tr.at(b, beat))
            for s16 in range(16):
                tr.add(hat(0.018 if s16 % 2 else 0.03), tr.at(b, s16 * 0.25), pan=0.35)
        return tr

    def drive():
        tr = Track(104, bars)
        for b in range(bars):
            ch = prog[b // 2]
            for beat in (0, 1.5, 2, 3.5) if b % 2 else (0, 2, 2.75):
                tr.add(kick(0.42), tr.at(b, beat))
            for beat in (1, 3):
                tr.add(snare(0.2), tr.at(b, beat))
            for e in range(8):
                tr.add(hat(0.04, open_=(e == 7)), tr.at(b, e * 0.5), pan=-0.3)
            # 16 分音符琶音
            arp = [ch[0] + 24, ch[1] + 12, ch[2] + 12, ch[3] + 12]
            for s16 in range(16):
                tr.add(pluck(arp[(s16 * 3) % 4], 0.35, amp=0.035, bright=0.7), tr.at(b, s16 * 0.25), pan=0.4 * np.sin(s16))
            if b % 4 == 3:
                tr.add(riser(tr.bar, 0.04), tr.at(b))
            if b % 4 == 0:
                tr.add(cymbal(0.05), tr.at(b), pan=0.2)
        # 战斗旋律（第 1–8 小节 与 9–16 小节变化）
        mel = [(74, 1.5), (72, 0.5), (69, 1), (72, 1), (70, 2), (67, 2),
               (72, 1.5), (70, 0.5), (69, 1), (67, 1), (69, 4),
               (74, 1.5), (72, 0.5), (69, 1), (72, 1), (77, 2), (76, 2),
               (74, 1), (72, 1), (70, 1), (67, 1), (69, 4)]
        play_melody(tr, mel, 0, lambda n, d, **k: lead(n, d, amp=0.04))
        play_melody(tr, mel, 8, lambda n, d, **k: strings([n, n - 12], d, amp=0.028, a=0.08, r=0.3, bright=3000))
        return tr

    def danger():
        tr = Track(104, bars)
        for b in range(0, bars, 2):
            r = roots[b // 2]
            # 低音弦乐小二度颤音 + 高音不协和合唱
            tr.add(strings([r + 12, r + 13], tr.bar * 2 + 0.5, amp=0.02, a=0.6, r=0.6, bright=1200, trem=8), tr.at(b))
            tr.add(choir([r + 36, r + 37], tr.bar * 2, amp=0.006, a=1.0, r=1.0), tr.at(b), pan=0.3)
        for b in range(bars):
            tr.add(heartbeat(0.3), tr.at(b, 0))
            tr.add(heartbeat(0.3), tr.at(b, 2))
        return tr

    layers = {"explore_base": base(), "explore_pulse": pulse(), "explore_drive": drive(), "explore_danger": danger()}
    # 四层用同一增益，保证叠加时相对音量正确
    g = 0.9
    for name, trk in layers.items():
        finish(trk, name, verb=(2.4, 2.6, 0.3), gain=g)


# ============================================================ 3. 中期 Boss《海嗣之主》
def make_boss():
    tr = Track(132, 16)
    # D 弗里吉亚：Dm – Eb – Dm – C / Dm – Eb – Bb – A
    prog = [[50, 57, 62, 65], [51, 58, 63, 67], [50, 57, 62, 65], [48, 55, 60, 64],
            [50, 57, 62, 65], [51, 58, 63, 67], [46, 53, 58, 62], [45, 52, 57, 61]]
    roots = [26, 27, 26, 24, 26, 27, 22, 21]
    for b in range(16):
        ch = prog[b // 2]
        r = roots[b // 2]
        # 16 分音符驱动低音
        for s16 in range(16):
            note = r + 12 + (12 if s16 % 8 == 6 else 0)
            tr.add(reese(note, tr.beat * 0.22, amp=0.09, cut=900), tr.at(b, s16 * 0.25))
        # 太鼓 + 军鼓
        for beat in (0, 0.75, 1.5, 2, 3, 3.5):
            tr.add(taiko(0.45 if beat in (0, 2) else 0.3, 62 if beat in (0, 2) else 85), tr.at(b, beat))
        for beat in (1, 3):
            tr.add(snare(0.22), tr.at(b, beat))
        for e in range(8):
            tr.add(hat(0.035), tr.at(b, e * 0.5), pan=0.3)
        # 铜管重音
        if b % 2 == 0:
            tr.add(brass([n + 12 for n in ch], tr.beat * 1.2, amp=0.035), tr.at(b, 0), pan=-0.2)
            tr.add(brass([n + 12 for n in ch], tr.beat * 0.6, amp=0.03), tr.at(b, 1.5), pan=0.2)
        if b % 2 == 0:
            tr.add(strings([n + 12 for n in ch], tr.bar * 2, amp=0.014, a=0.3, r=0.4, trem=16), tr.at(b))
        if b >= 8 and b % 2 == 0:
            tr.add(choir([ch[1] + 12, ch[2] + 12, ch[3] + 12], tr.bar * 2, amp=0.012), tr.at(b), pan=0.1)
        if b % 4 == 0:
            tr.add(cymbal(0.07), tr.at(b))
    mel = [(62, 0.5), (63, 0.5), (62, 1), (70, 1), (69, 1), (67, 1.5), (65, 0.5), (63, 1), (62, 1),
           (62, 0.5), (63, 0.5), (65, 1), (67, 1), (69, 1), (70, 2), (69, 2)]
    play_melody(tr, mel, 4, lambda n, d, **k: lead(n + 12, d, amp=0.035, bright=3500))
    play_melody(tr, mel, 12, lambda n, d, **k: strings([n + 12, n], d, amp=0.03, a=0.05, r=0.2, bright=3500))
    finish(tr, "boss", verb=(2.0, 3.0, 0.25))


# ============================================================ 4. 最终 Boss《深蓝之树》
def make_final():
    tr = Track(140, 24)
    # D 和声小调：Dm – Bb – Gm – A7 / Dm – F – Eb – A
    prog = [[50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 55, 61],
            [50, 57, 62, 65], [41, 48, 53, 57], [39, 46, 51, 55], [45, 52, 57, 61],
            [50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 55, 58], [45, 52, 55, 61]]
    roots = [26, 22, 19, 21, 26, 17, 15, 21, 26, 22, 19, 21]
    for b in range(24):
        ch = prog[b // 2]
        r = roots[b // 2]
        for s16 in range(16):
            tr.add(reese(r + 12 + (7 if s16 % 4 == 3 else 0), tr.beat * 0.22, amp=0.085, cut=1000), tr.at(b, s16 * 0.25))
        for beat in (0, 0.5, 1.5, 2, 2.5, 3.5):
            tr.add(kick(0.4), tr.at(b, beat))
        for beat in (1, 3):
            tr.add(snare(0.24), tr.at(b, beat))
            tr.add(taiko(0.3, 90), tr.at(b, beat + 0.5))
        for s16 in range(16):
            tr.add(hat(0.03 if s16 % 2 else 0.045), tr.at(b, s16 * 0.25), pan=-0.3)
        if b % 2 == 0:
            tr.add(choir([n + 12 for n in ch], tr.bar * 2, amp=0.016, a=0.5), tr.at(b))
            tr.add(strings([n + 12 for n in ch], tr.bar * 2, amp=0.013, trem=16), tr.at(b), pan=0.2)
            tr.add(brass([n + 12 for n in ch[:3]], tr.beat * 1.0, amp=0.04), tr.at(b))
        if b % 4 == 0:
            tr.add(cymbal(0.08), tr.at(b))
        if b % 8 == 7:
            tr.add(riser(tr.bar, 0.06), tr.at(b))
    # 引用「灯火动机」：和声小调变形（升 C）
    theme2 = [(n if n != 60 else 61, d) for n, d in THEME]
    play_melody(tr, theme2, 4, lambda n, d, **k: lead(n + 12, d * 0.999, amp=0.04, bright=3800))
    play_melody(tr, theme2, 12, lambda n, d, **k: brass([n + 12, n], d, amp=0.03))
    play_melody(tr, theme2, 18, lambda n, d, **k: bell(n + 24, d + 1.0, amp=0.04))
    finish(tr, "final", verb=(2.2, 2.8, 0.28))


# ============================================================ 5. 商人《灯下小憩》
def make_shop():
    tr = Track(92, 8)
    prog = [[53, 57, 60, 64], [50, 53, 57, 60], [46, 50, 53, 57], [48, 52, 55, 60]]  # Fmaj7 Dm7 Bbmaj7 C
    roots = [41, 38, 34, 36]
    for b in range(8):
        ch = prog[b % 4]
        tr.add(pad(ch, tr.bar + 0.8, bright=1200, amp=0.012, a=0.5, r=0.8), tr.at(b))
        tr.add(sub(roots[b % 4], tr.beat * 1.5, amp=0.1), tr.at(b))
        tr.add(sub(roots[b % 4] + 7, tr.beat * 1.0, amp=0.07), tr.at(b, 2))
        for k in (1, 3):
            tr.add(pluck(ch[1] + 12, 0.6, amp=0.04, bright=0.3), tr.at(b, k), pan=-0.3)
            tr.add(pluck(ch[3] + 12, 0.6, amp=0.035, bright=0.3), tr.at(b, k + 0.02), pan=0.3)
        for e in range(8):
            tr.add(hat(0.012), tr.at(b, e * 0.5 + (0.08 if e % 2 else 0)), pan=0.4)
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


if __name__ == "__main__":
    import sys
    which = sys.argv[1:] or ["title", "explore", "boss", "final", "shop", "stingers"]
    for w in which:
        globals()["make_" + w]()
