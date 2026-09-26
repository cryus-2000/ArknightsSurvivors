"""战斗配乐 v3（2026-09-26 用户选定 demo C：哥特暗黑摇滚 + 电子，参考 mudeth《Machine in the Walls》的风格参数；
旋律与 riff 全部原创：标题主旋律 / 灯火动机 / B 主题 / Boss 主题都是本作自己的）。

肉鸽音乐要无限循环：战斗与 Boss 曲不再是固定长度的循环，而是 8 小节一句的「乐句」，sfx.gd 在每句结束时
按局势挑下一句（不紧挨着重复），所以永远不会按固定顺序重来。每句文件 = 0.1 秒静音预留 + 8 小节正文 + 1.6 秒余音。
输出到 audio/music/：
  battle{1,2,3}_{A,B,C,D,E}_{base,pulse,drive}.ogg   战斗三段 × 五句 × 三层
      段：battle1 D 小调 144 BPM / battle2 E 小调 144 BPM / battle3 升 F 小调 150 BPM（越来越重）
      句：A 和弦墙 + 主奏对位 / B 标题主旋律副歌 / C 灯火动机（适合平静）/ D 半速间奏 / E B 主题 + 三度和声
      层：base 平静（低音、管风琴、合唱「呜」、羽管键琴、管风琴旋律）/ pulse 交战（双轨节奏吉他墙、低音八分、鼓）/
          drive 激战（高八度吉他、主奏吉他、管风琴全音栓、合唱「啊」、镲、双踩）
  battle{1,2,3}_danger.ogg                          危险层（8 小节，每句重新对齐开播）：高音管风琴小二度快颤 + 滴答 + 低音失真渐强
  boss_{A,B,D,C}_full.ogg                            中期 Boss《海嗣之主》D 弗里吉亚 150 BPM：riff / 主题 / 半速间奏 / 高潮
  final_{A,B,C,D}_{p1,p2}.ogg                        最终 Boss《深蓝之树》150 BPM：灯火动机 / 标题主旋律 / Boss 主题对峙 / 主旋律高潮；p2 二阶段叠加
响度目标（BS.1770，五句拼起来测）：平静 -20.5 / 交战 -17.5 / 激战 -15.5 LUFS；Boss -15；最终 -15（二阶段 -13.5）。
依赖 numpy / scipy / soundfile（不需要 ffmpeg）。重新生成：cd game/tools && python gen_music_battle.py [battle boss final]
"""
import os
import sys

import numpy as np
import soundfile as sf
from scipy.ndimage import uniform_filter1d
from scipy.signal import butter, fftconvolve, lfilter, sosfilt

import gen_music as G   # 复用人声合唱 voice() 与主题（THEME / TITLE_MEL）

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUTDIR = os.path.join(HERE, "..", "audio", "music")
rng = np.random.default_rng(144)


# ============================================================ DSP 基础
def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def lp(x, fc, order=2):
    return sosfilt(butter(order, min(fc, SR / 2 - 300), fs=SR, output="sos"), x, axis=0)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x, axis=0)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x, axis=0)


def peq(x, f0, gain_db, q=0.9):
    """RBJ 峰值均衡"""
    A = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = np.array([1 + al * A, -2 * np.cos(w0), 1 - al * A])
    a = np.array([1 + al / A, -2 * np.cos(w0), 1 - al / A])
    return lfilter(b / a[0], a / a[0], x, axis=0)


def env(n, a, r):
    return G.env(n, a, r)


def st(x, pan=0.0):
    return np.stack([x * np.sqrt(0.5 * (1 - pan)), x * np.sqrt(0.5 * (1 + pan))], 1)


def hum(s=0.003):
    return float(rng.uniform(-s, s))


# ---- 限带振荡器（PolyBLEP）。同一个音里的几种波形共用相位，否则基波随机相消、音量忽大忽小
def _blep(t, dt):
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def phase_of(freq, ph0=None):
    dt = np.minimum(np.asarray(freq, dtype=float) / SR, 0.45)
    return (np.cumsum(dt) + (rng.random() if ph0 is None else ph0)) % 1.0, dt


def saw_from(ph, dt):
    """基波为 -(2/π)·sin(2πφ)"""
    return 2.0 * ph - 1.0 - _blep(ph, dt)


def square_from(ph, dt, pw=0.5):
    """基波为 +(4/π)·sin(2πφ)"""
    y = np.where(ph < pw, 1.0, -1.0)
    y += _blep(ph, dt)
    y -= _blep((ph + 1.0 - pw) % 1.0, dt)
    return y


def saw_bl(freq):
    return saw_from(*phase_of(freq))


# ============================================================ 响度（BS.1770 K 加权，门限积分）
def _kw(x):
    import math
    G_, Q, fc = 3.99984385397, 0.7071752369554193, 1681.9744509555319
    A = 10 ** (G_ / 40)
    w0 = 2 * math.pi * fc / SR
    al = math.sin(w0) / (2 * Q)
    b = [A * ((A + 1) + (A - 1) * math.cos(w0) + 2 * math.sqrt(A) * al), -2 * A * ((A - 1) + (A + 1) * math.cos(w0)),
         A * ((A + 1) + (A - 1) * math.cos(w0) - 2 * math.sqrt(A) * al)]
    a = [(A + 1) - (A - 1) * math.cos(w0) + 2 * math.sqrt(A) * al, 2 * ((A - 1) - (A + 1) * math.cos(w0)),
         (A + 1) - (A - 1) * math.cos(w0) - 2 * math.sqrt(A) * al]
    y = lfilter(np.array(b) / a[0], np.array(a) / a[0], x, axis=0)
    Q2, fc2 = 0.5003270373253953, 38.13547087613982
    w0 = 2 * math.pi * fc2 / SR
    al = math.sin(w0) / (2 * Q2)
    a2 = np.array([1 + al, -2 * math.cos(w0), 1 - al])
    return lfilter(np.array([1, -2, 1.0]) / a2[0], a2 / a2[0], y, axis=0)


def lufs(x):
    if x.ndim == 1:
        x = np.stack([x, x], 1)
    p = np.sum(_kw(x) ** 2, axis=1)
    blk, hop = int(0.4 * SR), int(0.1 * SR)
    if len(p) <= blk:
        return -0.691 + 10 * np.log10(np.mean(p) + 1e-12)
    c = np.concatenate([[0.0], np.cumsum(p)])
    s = np.arange(0, len(p) - blk, hop)
    z = (c[s + blk] - c[s]) / blk
    l_ = -0.691 + 10 * np.log10(z + 1e-12)
    g = z[l_ > -70]
    if len(g) == 0:
        return -99.0
    rel = -0.691 + 10 * np.log10(np.mean(g)) - 10
    return -0.691 + 10 * np.log10(np.mean(z[(l_ > -70) & (l_ > rel)]) + 1e-12)


def bands(x):
    m = x.mean(axis=1)
    sp = np.abs(np.fft.rfft(m)) ** 2
    fr = np.fft.rfftfreq(len(m), 1 / SR)
    tot = sp.sum()
    return [round(float(100 * sp[(fr >= lo) & (fr < hi)].sum() / tot), 1)
            for lo, hi in [(20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 20000)]]


def speaker_drop(x):
    """手机 / 笔记本外放（250 Hz 高通）比全频少多少响度"""
    return lufs(x) - lufs(hp(x, 250, 4))


# ============================================================ 效果
def make_ir(secs, decay, tone, predelay=0.018):
    n = int(secs * SR)
    t = tt(n)
    irs = []
    for _ in range(2):
        ir = rng.standard_normal(n) * np.exp(-t * decay)
        ir = lp(ir, tone)
        ir[: int(predelay * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        irs.append(ir)
    return irs


def reverb_wet(x, irs):
    return np.stack([fftconvolve(x[:, c], irs[c])[: len(x)] for c in range(2)], 1)


def delay_wet(x, secs, fb=0.3, taps=5, tone=3800):
    d = int(secs * SR)
    y = np.zeros_like(x)
    cur = x.copy()
    for k in range(1, taps + 1):
        cur = lp(cur, tone) * (fb if k > 1 else 1.0)
        cur = cur[:, ::-1]   # 乒乓
        if k * d < len(x):
            y[k * d:] += cur[: len(x) - k * d]
    return y


def limiter(x, ceiling=0.93, look=0.003, rel=0.07):
    """前视峰值限制器（单文件曲目防削顶）：峰值附近平滑压低，释放按块指数恢复"""
    from scipy.ndimage import maximum_filter1d, minimum_filter1d
    L = max(1, int(look * SR))
    g = np.minimum(1.0, ceiling / np.maximum(maximum_filter1d(np.max(np.abs(x), axis=1), size=2 * L + 1), 1e-9))
    g = uniform_filter1d(minimum_filter1d(g, size=2 * L + 1), size=2 * L + 1)
    blk = 32
    m = len(g) // blk * blk
    gb = g[:m].reshape(-1, blk).min(axis=1)
    coef = np.exp(-blk / (rel * SR))
    out = np.empty_like(gb)
    cur = 1.0
    for i, v in enumerate(gb):
        cur = v if v < cur else v + (cur - v) * coef
        out[i] = cur
    gs = np.minimum(np.concatenate([np.repeat(out, blk), np.full(len(g) - m, out[-1])]), g)
    return x * gs[:, None]


# ============================================================ 乐器：鼓、合唱、滴答
def kick(v=1.0, dur=0.42, f0=165, f1=47, click=0.35, drive=1.8):
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(f1 + (f0 - f1) * np.exp(-t * 32)) / SR) * np.exp(-t * 8.5)
    knock = np.sin(2 * np.pi * np.cumsum(190 + 80 * np.exp(-t * 60)) / SR) * np.exp(-t * 55) * 0.35
    y = np.tanh((body + knock) * drive) / np.tanh(drive)
    clk = hp(rng.standard_normal(n), 2800) * np.exp(-t * 380) * click
    return (y + clk) * env(n, 0.0005, 0.02) * v


def hat(v=1.0, open_=False):
    dur = 0.45 if open_ else 0.07
    n = int(dur * SR)
    t = tt(n)
    metal = sum(np.sign(np.sin(2 * np.pi * f * t + rng.random() * 6.28)) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)) / 6
    x = 0.6 * hp(metal, 7000, 4) + 0.4 * hp(rng.standard_normal(n), 8000, 4)
    e = np.exp(-t * (8 if open_ else 62)) * np.minimum(1, t / 0.0008)
    return lp(x, 14500) * e * v


def tom(pitch=140, v=1.0, dur=0.55):
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(pitch * (1 + 0.38 * np.exp(-t * 16))) / SR) * np.exp(-t * 6.5)
    nz = bp(rng.standard_normal(n), 300, 3200) * np.exp(-t * 38) * 0.3
    return np.tanh((body + nz) * 1.4) * env(n, 0.0005, 0.05) * v


def crash(v=1.0, dur=3.2):
    n = int(dur * SR)
    t = tt(n)
    e = np.exp(-t * 1.35) * np.minimum(1, t / 0.002)
    ch = [(lp(hp(rng.standard_normal(n), 3000), 13000) * 0.7 + bp(rng.standard_normal(n), 5000, 9000) * 0.5) * e for _ in range(2)]
    return np.stack(ch, 1) * v


def choir(notes, dur, a=0.8, r=1.2, morph=True):
    L = G.voice(notes, dur, amp=1.0, a=a, r=r, morph=morph)
    R = G.voice(notes, dur, amp=1.0, a=a, r=r, morph=morph)
    return hp(np.stack([L, R], 1), 170)


def tick(nt, v=1.0):
    n = int(0.12 * SR)
    t = tt(n)
    ph, dt = phase_of(np.full(n, midi(nt)))
    y = lp(square_from(ph, dt) * 0.6 + np.sin(2 * np.pi * ph), 2400)
    return hp(y, 300) * np.minimum(1, t / 0.002) * np.exp(-t * 38) * v


# ============================================================ 乐器：乐队（v3 哥特暗黑摇滚）
def string_src(nt, dur, mute=False, pick=0.17):
    """加法合成的拨弦：拨弦位置梳状 + 高次谐波衰减更快 + 轻微非谐性 + 拨片噪声（音高精确，不用 Karplus-Strong）"""
    n = int(dur * SR)
    t = tt(n)
    f = midi(nt)
    s = np.zeros(n)
    for k in range(1, max(1, min(26, int((SR / 2 - 800) / f))) + 1):
        a = abs(np.sin(np.pi * k * pick)) / k
        dec = (1.2 + 0.75 * k) * (5.0 if mute else 1.0)
        s += a * np.sin(2 * np.pi * f * k * np.sqrt(1 + 0.00012 * k * k) * t + rng.random() * 6.28) * np.exp(-t * dec)
    s += hp(rng.standard_normal(n), 2500) * np.exp(-t * 320) * 0.25
    return s


def amp_sim(x, gain=26.0, bias=0.15, cab=4500.0):
    """吉他音箱：中频推 → 非对称削波两级 → 箱体（低频共振、220 Hz 厚度、1 kHz 去鼻音、临场感、高频陡降）"""
    y = hp(x, 90)
    y = peq(y, 700, 4.0, 0.8)
    y = np.tanh(gain * y + bias) - np.tanh(bias)
    y = lp(y, 7000)
    y = np.tanh(2.5 * y)
    y = hp(y, 75, 2)
    y = peq(y, 110, 3.0, 0.7)
    y = peq(y, 220, 6.0, 0.8)
    y = peq(y, 400, 3.0, 1.2)
    y = peq(y, 1000, -3.0, 1.4)
    y = peq(y, 1800, 2.0, 1.2)
    return lp(lp(y, cab, 2), cab * 1.1, 2)


def power_chord(root, dur, mute=False, vel=1.0, detune=0.0, pick=0.17):
    """强力和弦（根音 + 五度 + 八度；闷音只弹根音 + 五度），扫弦错开几毫秒，一起进音箱"""
    n = int(dur * SR)
    x = np.zeros(n + int(0.02 * SR))
    for i, nt in enumerate([root, root + 7] if mute else [root, root + 7, root + 12]):
        s = string_src(nt + detune, dur, mute=mute, pick=pick)
        o = int((0.004 + 0.003 * rng.random()) * i * SR)
        x[o:o + len(s)] += s[: len(x) - o]
    y = amp_sim(x[:n] * vel * (0.55 if mute else 0.45))
    return y * env(n, 0.001, 0.012 if mute else 0.03)


def gtr(S, bus, events):
    """双轨节奏吉他：同一段弹两遍（音高 ±4 音分、拨弦位置不同、时间 ±8 毫秒），硬左右。events: (时刻, 根音, 时长, 闷音, 力度)"""
    for side, pan in ((0, -1.0), (1, 1.0)):
        for t0, root, dur, mute, vel in events:
            S.add(bus, power_chord(root, dur, mute, vel * rng.uniform(0.92, 1.0), detune=(0.04 if side else -0.04),
                                   pick=(0.21 if side else 0.15)), t0 + rng.uniform(-0.008, 0.008) + (0.005 if side else 0.0), pan=pan)


def bass_gtr(nt, dur, mute=False, vel=1.0, drive=2.2):
    n = int(dur * SR)
    t = tt(n)
    f = midi(nt)
    s = np.zeros(n)
    for k in range(1, 13):
        if f * k > 6000:
            break
        s += abs(np.sin(np.pi * k * 0.25)) / k ** 0.9 * np.sin(2 * np.pi * f * k * t) * np.exp(-t * (0.8 + 0.5 * k) * (4.0 if mute else 1.0))
    s = np.tanh(drive * s) / np.tanh(drive)
    return lp(s, 2800) * env(n, 0.003, 0.03) * vel


REG_SOFT = (0.3, 1.0, 0.45, 0.0, 0.2, 0.0, 0.0)     # 管风琴音栓：16' 8' 4' 2⅔' 2' 1⅓' 1'
REG_FULL = (0.6, 1.0, 0.7, 0.35, 0.4, 0.2, 0.15)
REG_PEDAL = (1.0, 0.8, 0.3, 0.1, 0.1, 0.0, 0.0)
REG_HIGH = (0.0, 0.6, 1.0, 0.5, 0.6, 0.3, 0.3)


def organ(notes, dur, a=0.04, r=0.35, reg=REG_FULL, trem=5.8, depth=0.035):
    """管风琴（加法音栓），左右声道各一套轻微失谐 + 颤音做空间感，起音带一点键噪"""
    n = int(dur * SR)
    t = tt(n)
    ch = []
    for side in (-1, 1):
        s = np.zeros(n)
        for nt in notes:
            f = midi(nt) * (1 + side * 0.0009)
            for rr, g in zip((0.5, 1, 2, 3, 4, 6, 8), reg):
                if g > 0 and f * rr < SR / 2 - 1000:
                    s += g * np.sin(2 * np.pi * f * rr * t + rng.random() * 6.28)
        ch.append(s * (1 + depth * np.sin(2 * np.pi * trem * t + (0 if side < 0 else 1.6))))
    x = np.stack(ch, 1) / np.sqrt(len(notes) * 3) + st(hp(rng.standard_normal(n), 3000) * np.exp(-t * 400) * 0.08)
    return lp(x, 7000) * env(n, a, r)[:, None]


def syn_organ(freq, age):
    """管风琴单音旋律（phrase 用）"""
    out = []
    for side in (-1, 1):
        s = np.zeros(len(freq))
        for rr, g in zip((0.5, 1, 2, 3, 4), (0.4, 1.0, 0.6, 0.25, 0.3)):
            ph, _ = phase_of(freq * rr * (1 + side * 0.0009))
            s += g * np.sin(2 * np.pi * ph)
        out.append(s)
    return lp(np.stack(out, 1), 6500) * 0.5


def harpsi(nt, dur=1.0, vel=1.0):
    """羽管键琴：拨弦点靠近端点、衰减快，叠一组高八度 4' 弦"""
    s = string_src(nt, dur, pick=0.08) + 0.45 * string_src(nt + 12, dur, pick=0.08)
    return hp(lp(s, 9000), 150) * env(len(s), 0.001, 0.08) * np.exp(-tt(len(s)) * 1.2) * vel


def kick_rock(v=1.0):
    return kick(v, dur=0.55, f0=135, f1=40, click=0.55, drive=2.2)


def snare_rock(v=1.0):
    n = int(0.45 * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 22) + 0.6 * np.sin(2 * np.pi * 330 * t) * np.exp(-t * 30)
    nz = rng.standard_normal(n)
    wires = bp(nz, 1500, 9000) * np.exp(-t * 11) + bp(nz, 300, 1500) * np.exp(-t * 20) * 0.5
    return np.tanh((body * 0.8 + wires) * 1.4) * env(n, 0.0005, 0.04) * v


def ride(v=1.0, dur=1.4):
    n = int(dur * SR)
    t = tt(n)
    s = sum(np.sin(2 * np.pi * f * t + rng.random() * 6.28) * np.exp(-t * d) for f, d in
            ((3120, 3.0), (4470, 3.5), (5390, 4.0), (6710, 5.0), (8210, 6.0))) * 0.18
    s = s + hp(rng.standard_normal(n), 5000) * np.exp(-t * 6) * 0.3 + np.sin(2 * np.pi * 2600 * t) * np.exp(-t * 40) * 0.3
    return lp(s, 9500) * env(n, 0.0005, 0.1) * v


def syn_lead(freq, age):
    """主奏吉他：锯齿 + 方波进音箱（揉弦、滑音由 phrase 给）"""
    ph, dt = phase_of(freq)
    return st(amp_sim((saw_from(ph, dt) * 0.6 + square_from(ph, dt) * 0.3) * 0.35, gain=16.0, cab=5200))


# ============================================================ 旋律
def phrase(notes, beat, synth, glide=0.035, attack=0.012, release=0.2, legato_dip=0.82,
           vib_rate=5.3, vib_depth=0.006, vib_delay=0.22, transpose=0):
    """单音旋律：相邻音连奏时滑音、不重新起音；返回立体声信号"""
    evs = []
    pos = 0.0
    for nt, b in notes:
        if nt is not None:
            evs.append([pos * beat, b * beat, nt + transpose])
        pos += b
    n = int((pos * beat + release + 0.3) * SR)
    freq = np.full(n, midi(evs[0][2]))
    amp = np.zeros(n)
    age = np.zeros(n)
    g = int(glide * SR)
    a = max(1, int(attack * SR))
    r = int(release * SR)
    for k, (t0, d, nt) in enumerate(evs):
        i0 = int(t0 * SR)
        i1 = min(n, int((t0 + d) * SR))
        f = midi(nt)
        cp = k > 0 and abs(evs[k - 1][0] + evs[k - 1][1] - t0) < 1e-4
        cn = k + 1 < len(evs) and abs(t0 + d - evs[k + 1][0]) < 1e-4
        if cp and g > 0:
            f0 = midi(evs[k - 1][2])
            m = min(g, i1 - i0)
            freq[i0:i0 + m] = f0 * (f / f0) ** np.sin(np.linspace(0, np.pi / 2, m))
            freq[i0 + m:] = f
        else:
            freq[i0:] = f
        e = np.ones(i1 - i0)
        m = min(a, len(e))
        e[:m] = np.linspace(legato_dip if cp else 0.0, 1.0, m)
        amp[i0:i1] = e
        if not cn:
            j = min(n, i1 + r)
            amp[i1:j] = np.linspace(1.0, 0.0, j - i1) ** 1.6
        age[i0:] = tt(n - i0)
    amp = uniform_filter1d(amp, int(0.004 * SR))
    vib = 1 + vib_depth * np.clip((age - vib_delay) / 0.3, 0, 1) * np.sin(2 * np.pi * vib_rate * tt(n))
    return synth(freq * vib, age) * amp[:, None]


MEL = list(G.TITLE_MEL)                          # 标题主旋律，8 小节
THEME = list(G.THEME[:12]) + [(70, 2), (69, 2)]  # 灯火动机，4 小节
THEME2 = list(G.THEME[:12]) + [(62, 2), (61, 2)]  # 第二遍末小节 D → C#，落在 A 和弦上
# B 主题：沿用灯火动机的「1 1 1.5 0.5」节奏，在 VI–VII 上逐级爬升，第 7 小节到 A5 高点
B_MEL = [(65, 1), (70, 1), (74, 1.5), (72, 0.5), (67, 1), (72, 1), (76, 1.5), (74, 0.5),
         (76, 1.5), (74, 0.5), (72, 1), (69, 1), (74, 2), (76, 1), (77, 1),
         (77, 1), (74, 1), (77, 1.5), (79, 0.5), (76, 1), (72, 1), (76, 1.5), (79, 0.5),
         (81, 2), (77, 1), (74, 1), (76, 2), (73, 2)]


# ============================================================ 编排容器
class Song:
    def __init__(self, bpm, bars, tail=5.0):
        self.bpm = bpm
        self.beat = 60 / bpm
        self.bar = self.beat * 4
        self.bars = bars
        self.len = int(round(SR * self.bar * bars))
        self.n = self.len + int(SR * tail)
        self.bus = {}

    def at(self, bar, beat=0.0):
        return (bar * 4 + beat) * self.beat

    def add(self, bus, sig, t, pan=0.0, gain=1.0):
        B = self.bus.setdefault(bus, np.zeros((self.n, 2)))
        i = int(round(t * SR))
        if i >= self.n:
            return
        if sig.ndim == 1:
            sig = st(sig, pan)
        sig = sig.copy()
        fo = min(int(0.005 * SR), len(sig) // 4)
        fi = min(13, len(sig) // 4)
        if fo > 0:
            sig[-fo:] *= np.linspace(1, 0, fo)[:, None]
        if fi > 0:
            sig[:fi] *= np.linspace(0, 1, fi)[:, None]
        if i < 0:   # 从小节线之前开始的（倒放镲、渐强）：前半截卷到循环末尾
            m = min(-i, len(sig))
            B[self.len + i: self.len + i + m] += sig[:m] * gain
            sig = sig[m:]
            i = 0
        j = min(self.n, i + len(sig))
        B[i:j] += sig[: j - i] * gain


def write_ogg(name, data, q=0.62):
    """Vorbis（libsndfile；compression_level 0.62 ≈ 质量 3.8）。一次写整段会崩，分块写"""
    path = os.path.join(OUTDIR, name + ".ogg")
    data = np.clip(data, -1, 1).astype(np.float32)
    with sf.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS", compression_level=q) as f:
        for i in range(0, len(data), 8192):
            f.write(data[i:i + 8192])
    back = sf.info(path).frames
    assert back == len(data), f"{name}: 编码后长度 {back} ≠ {len(data)}"
    print(f"  {name}.ogg  {len(data) / SR:.2f}s  {os.path.getsize(path) // 1024} KB")


def gain_to(x, target):
    return 10 ** ((target - lufs(x)) / 20)


# ============================================================ v3 乐句：8 小节一句，拼接成无限循环（sfx.gd 按局势挑下一句）
PRE = 0.1      # 每个乐句文件开头的静音预留（秒）：sfx.gd 靠它把下一句精确接到上一句末尾
TAIL = 1.6     # 乐句结束后的余音（秒）：下一句开始后它在另一组播放器里响完
CHORD = {"Dm": (38, [62, 65, 69]), "Bb": (46, [58, 62, 65]), "F": (41, [57, 60, 65]), "Gm": (43, [55, 58, 62]),
         "A": (45, [57, 61, 64]), "C": (48, [55, 60, 64]), "Eb": (39, [55, 58, 63]), "Am": (45, [57, 60, 64])}
TITLE8 = ["Dm", "Bb", "F", ("Gm", "A"), "Dm", "F", "Bb", "A"]
WALL8 = ["Dm", "Dm", "Bb", "C", "Dm", "F", "Eb", "A"]
BREAK8 = ["Dm", "Dm", "Eb", "Dm", "Dm", "Bb", "C", "A"]
BTHEME8 = ["Bb", "C", "Am", "Dm", "Bb", "C", "Dm", "A"]
# A 句主奏：和弦墙上的长音对位（原创），每小节两个二分音符
WALL_LEAD = [(74, 2), (72, 2), (74, 2), (77, 2), (77, 2), (74, 2), (76, 2), (79, 2),
             (81, 2), (77, 2), (81, 4), (79, 2), (75, 2), (76, 2), (73, 2)]
BOSS_MEL = [(62, 0.5), (63, 0.5), (62, 1), (70, 1), (69, 1), (67, 1.5), (65, 0.5), (63, 1), (62, 1),
            (62, 0.5), (63, 0.5), (65, 1), (67, 1), (69, 1), (70, 2), (69, 2)]   # Boss 主题（v1 起沿用），4 小节
BOSS_A8 = ["Dm", "Eb", "Dm", "C", "Dm", "Eb", "Bb", "A"]
BOSS_D8 = ["Dm", "Eb", "Dm", "Eb", "Bb", "C", "Bb", "A"]
BOSS_C8 = ["Gm", "Eb", "Dm", "Dm", "Gm", "Eb", "Bb", "A"]
LEAD_KW = dict(glide=0.06, attack=0.006, release=0.3, vib_rate=5.6, vib_depth=0.011, vib_delay=0.18)


def chords_of(prog, bar):
    c = prog[bar % len(prog)]
    return c if isinstance(c, tuple) else (c,)


def harmonize(mel, prog):
    """按和弦给旋律配下方三度 / 六度（长音才换，短音保持）"""
    rank = {3: 0, 4: 0, 8: 1, 9: 1, 5: 2, 7: 3}
    raw, pos = [], 0.0
    for nt, b in mel:
        if nt is None:
            raw.append([None, b])
        else:
            cs = chords_of(prog, int(pos // 4))
            ch = cs[min(len(cs) - 1, int((pos % 4) / (4 / len(cs))))]
            tones = sorted({v + 12 * k for v in CHORD[ch][1] for k in (-2, -1, 0, 1)})
            cands = [t for t in tones if (nt - t) in rank]
            if (b >= 1 or not raw or raw[-1][0] is None) and cands:
                h = min(cands, key=lambda t: (rank[nt - t], nt - t))
            else:
                h = raw[-1][0] if raw else None
            raw.append([h, b])
        pos += b
    out = []
    for h, b in raw:
        if out and out[-1][0] == h:
            out[-1][1] += b
        else:
            out.append([h, b])
    return [tuple(x) for x in out]


def drums(S, groove, energy):
    """交战层鼓组。wall / chorus / verse / half / riff；最后一小节第 4 拍嗵鼓过门（下一句是哪句都接得上）"""
    for bar in range(S.bars):
        last = bar == S.bars - 1
        if groove == "half":
            kicks, snares = [(0, 1.0), (1.5, 0.8)], [(2, 1.0)]
            cym = [(0, "ride", 0.85), (2, "ride", 0.75)]
        elif groove == "verse":
            kicks, snares = [(0, 0.85), (2.5, 0.65)], [(1, 0.65), (3, 0.65)]
            cym = [(e * 0.5, "hat", (0.5 if e % 2 else 0.3) * (1.2 if energy else 1.0)) for e in range(8)]
        elif groove == "chorus":
            kicks = [(0, 1.0), (1.5, 0.8), (2, 0.9)] + ([(3.5, 0.6)] if energy >= 1 else [])
            snares = [(1, 1.0), (3, 1.0)]
            cym = [(b_, "ride", 0.9 if b_ % 2 == 0 else 0.7) for b_ in range(4)]
        else:   # wall / riff
            kicks = [(0, 1.0), (2, 0.9)] + ([(2.5, 0.7)] if bar % 2 else []) + ([(0.5, 0.6), (2.5, 0.7)] if energy >= 2 else [])
            if groove == "riff":
                kicks = [(0, 1.0), (1.5, 0.8), (2.5, 0.85), (3.5, 0.6)]
            snares = [(1, 1.0), (3, 1.0)]
            cym = [(b_, "ride", 0.9 if b_ % 2 == 0 else 0.7) for b_ in range(4)]
            if energy >= 1:
                cym += [(b_ + 0.5, "hat", 0.45) for b_ in range(4)]
        for b_, v in kicks:
            if not (last and b_ >= 3):
                S.add("p_kick", kick_rock(v), S.at(bar, b_))
        for b_, v in snares:
            if not (last and b_ >= 3):
                S.add("p_snare", snare_rock(v), S.at(bar, b_))
        for b_, kind, v in cym:
            if not (last and b_ >= 3):
                S.add("p_hats", ride(v * 0.8) if kind == "ride" else hat(v), S.at(bar, b_) + hum(0.002), pan=0.25)
        if last:
            for k in range(4):
                S.add("p_toms", tom(150 - 14 * k, 0.8 if groove != "verse" else 0.55), S.at(bar, 3 + k * 0.25), pan=0.4 - 0.25 * k)


def band_song(prog, groove, bpm, tr=0, energy=0, harpsi_arp=False, base_mel=None, lead=None, lead_tr=0,
              lead_bus="d_lead", harm=None, organ_calls=()):
    """一句 8 小节乐队编排。轨名前缀即层：b_ 平静 / p_ 交战 / d_ 激战"""
    S = Song(bpm, 8, tail=TAIL)
    bt = S.beat
    for bar in range(8):
        cs = chords_of(prog, bar)
        for ci, ch in enumerate(cs):
            root, tri = CHORD[ch]
            root += tr
            tri = [x + tr for x in tri]
            b0 = ci * 4 / len(cs)
            beats = 4 / len(cs)
            t0 = S.at(bar, b0)
            dur = beats * bt
            # ---- 平静层：低音长音 + 管风琴（间奏是踏板低音）+ 合唱「呜」+ 羽管键琴八分琶音
            S.add("b_bass", bass_gtr(root - 12, dur + 0.05, vel=0.8, drive=1.4), t0)
            if groove == "half":
                S.add("b_organ", organ([root - 12, root], dur + 0.25, a=0.08, r=0.3, reg=REG_PEDAL), t0)
                S.add("b_choir", choir(tri, dur + 0.7, a=0.45, r=0.7, morph=False), t0)
            else:
                S.add("b_organ", organ(tri, dur + 0.25, a=0.05, r=0.3, reg=REG_SOFT), t0)
                S.add("b_choir", choir([x + 12 for x in tri], dur + 0.7, a=0.45, r=0.7, morph=False), t0)
            if harpsi_arp:
                arp = [tri[0], tri[1], tri[2], tri[0] + 12, tri[2], tri[1], tri[2], tri[0] + 12]
                for k in range(int(beats * 2)):
                    S.add("b_harpsi", harpsi(arp[k % 8] + 12, 0.9, 0.9 if k % 2 == 0 else 0.7), t0 + k * 0.5 * bt, pan=0.4)
            # ---- 交战层：双轨节奏吉他（长音和弦墙）+ 低音八分
            if groove in ("wall",):
                ev = [(t0, root, 2.5 * bt, False, 1.0), (S.at(bar, b0 + 2.5), root, 1.5 * bt, False, 0.9)] if beats == 4 else [(t0, root, dur, False, 1.0)]
            elif groove == "riff":
                ev = [(S.at(bar, b0 + a_), root, l_ * bt, m_, v_) for a_, l_, m_, v_ in
                      ((0, 1.5, False, 1.0), (1.5, 0.5, True, 0.9), (2, 0.5, True, 0.9), (2.5, 1.5, False, 0.95))]
            elif groove == "chorus":
                ev = [(S.at(bar, b0 + k * 2), root, 2 * bt, False, 1.0 if k == 0 else 0.92) for k in range(max(1, int(beats // 2)))]
            elif groove == "verse":
                ev = [(t0, root, dur, False, 0.5)]
            else:   # half
                ev = ([(t0, root, 1.5 * bt, False, 1.0), (S.at(bar, b0 + 1.5), root, 0.5 * bt, True, 0.9), (S.at(bar, b0 + 2), root, 2 * bt, False, 0.95)]
                      if ch == "Dm" else [(t0, root, dur, False, 1.0)])
            gtr(S, "p_gtr", ev)
            step = 1.0 if groove == "half" else 0.5
            pat = [0, 0, 12, 0, 0, 0, 12, 0] if (energy >= 1 and groove != "half") else [0] * 8
            for e in range(int(beats / step)):
                S.add("p_bass", bass_gtr(root - 12 + pat[e % 8], step * bt * 0.92, vel=1.0 if e % 2 == 0 else 0.85), S.at(bar, b0 + e * step))
            # ---- 激战层：高八度吉他（同节奏）+ 管风琴全音栓 + 合唱「啊」
            gtr(S, "d_gtr", [(t, r + 12, d, m, v * 0.85) for t, r, d, m, v in ev if not m])
            S.add("d_organ", organ(tri + [tri[0] - 12], dur + 0.2, a=0.02, r=0.25, reg=REG_FULL), t0)
            S.add("d_choir", choir([x + 12 for x in tri], dur + 0.6, a=0.25, r=0.6, morph=True), t0)
    drums(S, groove, energy)
    # 激战层：句首 / 第 5 小节镲；间奏四分镲；重段落的双踩
    S.add("d_fx", crash(0.85), S.at(0))
    S.add("d_fx", crash(0.6), S.at(4))
    if groove == "half":
        for bar in range(8):
            for b_ in range(4):
                S.add("d_fx", crash(0.22, 1.0), S.at(bar, b_), pan=0.2)
    if energy >= 2 or groove == "half":
        for bar in (3, 7):
            for k in range(8):
                if not (bar == 7 and k >= 4):
                    S.add("d_kick", kick_rock(0.65 if k % 2 == 0 else 0.5), S.at(bar, 2 + k * 0.25))
    # 旋律：平静层管风琴（轻）、激战层主奏吉他（+ 下方三度和声）、管风琴呼应
    if base_mel:
        S.add("b_mel", phrase(base_mel, bt, syn_organ, attack=0.03, release=0.3, transpose=tr), 0.0)
    if lead:
        S.add(lead_bus, phrase(lead, bt, syn_lead, transpose=tr + lead_tr, **LEAD_KW), 0.0)
    if harm:
        S.add("d_lead", phrase(harm, bt, syn_lead, transpose=tr + lead_tr, **LEAD_KW), 0.0, gain=0.55)
    for bar, notes in organ_calls:
        S.add("b_mel", phrase(notes, bt, syn_organ, attack=0.03, release=0.5, transpose=tr), S.at(bar))
    return S


def danger_song(tr, bpm):
    """危险层（8 小节，和声中性）：高音管风琴小二度快颤 + 16 分滴答 + 低音失真小二度渐强"""
    S = Song(bpm, 8, tail=TAIL)
    tonic = 62 + tr
    for b in range(0, 8, 2):
        d = S.bar * 2 + 0.2
        S.add("z_org", organ([tonic + 12, tonic + 13], d, a=S.bar * 1.2, r=0.3, reg=REG_HIGH, trem=7.5, depth=0.35), S.at(b))
        n = int(d * SR)
        x = saw_bl(np.full(n, midi(tonic - 24))) + saw_bl(np.full(n, midi(tonic - 23)))
        S.add("z_gtr", st(amp_sim(x * 0.3) * (tt(n) / d) ** 1.5 * env(n, 0.01, 0.2)), S.at(b))
    for s in range(8 * 16):
        S.add("z_tick", tick(tonic + 12, 1.0 if s % 4 == 0 else 0.45), S.at(0, s * 0.25), pan=0.25 if s % 2 else -0.25)
    return S


# ============================================================ 混音
TARGETS = {
    "b_bass": -20.0, "b_organ": -24.0, "b_choir": -26.5, "b_harpsi": -26.5, "b_mel": -21.5,
    "p_gtr": -17.5, "p_bass": -19.5, "p_kick": -18.5, "p_snare": -19.5, "p_hats": -29.0, "p_toms": -24.0, "p_lead": -18.5,
    "d_gtr": -19.5, "d_lead": -18.5, "d_organ": -25.0, "d_choir": -24.5, "d_fx": -25.5, "d_kick": -22.0,
    "z_org": -24.0, "z_tick": -28.0, "z_gtr": -27.0,
}
SENDS = {"b_organ": 0.45, "b_choir": 0.45, "b_harpsi": 0.3, "b_mel": 0.4, "p_gtr": 0.08, "p_snare": 0.22, "p_toms": 0.25,
         "p_hats": 0.08, "p_kick": 0.04, "p_lead": 0.25, "d_gtr": 0.1, "d_lead": 0.25, "d_organ": 0.45, "d_choir": 0.45,
         "d_fx": 0.3, "z_org": 0.45, "z_tick": 0.2, "z_gtr": 0.2}


def bus_gains(songs):
    """同名轨在所有乐句里拼起来测响度，同一个增益用到每一句（句与句之间音量一致）"""
    names = sorted({k for S in songs for k in S.bus})
    return {k: gain_to(np.concatenate([S.bus[k] for S in songs if k in S.bus]), TARGETS[k]) for k in names}


def layer_mix(S, prefixes, gains, irs):
    bus = {k: S.bus[k] * gains[k] for k in S.bus if k.startswith(prefixes)}
    if not bus:
        return np.zeros((S.n, 2))
    mix = sum(bus.values())
    rev_in = sum(bus[k] * SENDS.get(k, 0.0) for k in bus)
    mix = mix + reverb_wet(hp(rev_in, 190), irs) * 0.5
    for k in ("p_lead", "d_lead"):
        if k in bus:
            mix = mix + delay_wet(bus[k], 0.75 * S.beat, 0.3) * 0.16
    return hp(mix, 28)


def solve_gain(fn, target, lo=0.02, hi=20.0):
    """二分找增益 g，使 fn(g)（响度，随 g 单调增）= target"""
    for _ in range(40):
        g = np.sqrt(lo * hi)
        if fn(g) > target:
            hi = g
        else:
            lo = g
    return np.sqrt(lo * hi)


def write_seg(name, data):
    """乐句文件 = 0.1 秒静音预留 + 8 小节正文 + 余音（尾端 0.6 秒淡出）"""
    x = np.concatenate([np.zeros((int(round(PRE * SR)), 2)), data])
    k = int(0.6 * SR)
    x[-k:] *= np.linspace(1, 0, k)[:, None] ** 2
    pk = np.max(np.abs(x))
    if pk > 0.97:
        x = limiter(x, 0.95)
    write_ogg(name, x, q=0.66)


def body(x, S):
    return x[: S.len]


# ============================================================ 战斗三段
SECTIONS = {   # 三段升调、越来越重；第三段提速
    "battle1": dict(tr=0, bpm=144.0, energy=0),
    "battle2": dict(tr=2, bpm=144.0, energy=1),
    "battle3": dict(tr=4, bpm=150.0, energy=2),
}


def battle_segments(tr, bpm, energy):
    hi = 12 if tr <= 2 else 0
    return {
        "A": band_song(WALL8, "wall", bpm, tr, energy, harpsi_arp=True, lead=WALL_LEAD),
        "B": band_song(TITLE8, "chorus", bpm, tr, energy, harpsi_arp=True, base_mel=MEL, lead=MEL),
        "C": band_song(TITLE8, "verse", bpm, tr, energy, base_mel=THEME + THEME2, lead=THEME + THEME2, lead_tr=hi),
        "D": band_song(BREAK8, "half", bpm, tr, energy),
        "E": band_song(BTHEME8, "wall", bpm, tr, energy, harpsi_arp=True, base_mel=B_MEL, lead=B_MEL, harm=harmonize(B_MEL, BTHEME8)),
    }


def make_battle(which=None):
    for name, cfg in SECTIONS.items():
        if which and name not in which:
            continue
        songs = battle_segments(cfg["tr"], cfg["bpm"], cfg["energy"])
        dz = danger_song(cfg["tr"], cfg["bpm"])
        gains = bus_gains(list(songs.values()) + [dz])
        irs = make_ir(3.4, 2.2, 6000)
        lay = {s: {L: layer_mix(S, P, gains, irs) for L, P in (("base", "b_"), ("pulse", "p_"), ("drive", "d_"))} for s, S in songs.items()}
        dang = layer_mix(dz, "z_", gains, irs)
        cat = {L: np.concatenate([body(lay[s][L], songs[s]) for s in songs]) for L in ("base", "pulse", "drive")}
        gb = gain_to(cat["base"], -20.5)
        gp = solve_gain(lambda g: lufs(cat["base"] * gb + cat["pulse"] * g), -17.5)
        gd = solve_gain(lambda g: lufs(cat["base"] * gb + cat["pulse"] * gp + cat["drive"] * g), -15.5)
        combat = cat["base"] * gb + cat["pulse"] * gp
        dd = np.tile(body(dang, dz), (len(combat) // dz.len + 1, 1))[: len(combat)]
        gz = solve_gain(lambda g: lufs(combat + dd * g), lufs(combat) + 1.0)
        full = combat + cat["drive"] * gd
        print(f"[{name}] 平静 {lufs(cat['base'] * gb):.1f} / 交战 {lufs(combat):.1f} / 激战 {lufs(full):.1f} / +危险 {lufs(full + dd * gz):.1f} LUFS"
              f" | 激战频段 {bands(full)} | 外放掉 {speaker_drop(full):.1f} LU | 全叠峰值 {20 * np.log10(np.max(np.abs(full + dd * gz))):.1f} dBFS")
        for s in songs:
            for L, g in (("base", gb), ("pulse", gp), ("drive", gd)):
                write_seg(f"{name}_{s}_{L}", lay[s][L] * g)
        write_seg(f"{name}_danger", dang * gz)


# ============================================================ 中期 Boss《海嗣之主》D 弗里吉亚 150 BPM：四句（riff / 主题 / 半速间奏 / 高潮）
def make_boss():
    bpm = 150.0
    songs = {
        "A": band_song(BOSS_A8, "riff", bpm, energy=1),
        "B": band_song(BOSS_A8, "chorus", bpm, energy=1, lead=BOSS_MEL + BOSS_MEL, base_mel=[(n - 12, b) for n, b in BOSS_MEL + BOSS_MEL]),
        "D": band_song(BOSS_D8, "half", bpm, energy=1, organ_calls=[(b, BOSS_MEL[:5]) for b in (0, 2, 4, 6)]),
        "C": band_song(BOSS_C8, "wall", bpm, energy=2, lead=BOSS_MEL + BOSS_MEL, lead_tr=12,
                       harm=harmonize(BOSS_MEL + BOSS_MEL, BOSS_C8)),
    }
    gains = bus_gains(list(songs.values()))
    irs = make_ir(3.2, 2.4, 6000)
    lay = {s: layer_mix(S, ("b_", "p_", "d_"), gains, irs) for s, S in songs.items()}
    cat = np.concatenate([body(lay[s], songs[s]) for s in songs])
    g = gain_to(cat, -15.0)
    print(f"[boss] {lufs(cat * g):.1f} LUFS | 频段 {bands(cat * g)} | 外放掉 {speaker_drop(cat * g):.1f} LU")
    for s in songs:
        write_seg(f"boss_{s}_full", lay[s] * g)


# ============================================================ 最终 Boss《深蓝之树》D 小调 150 BPM：四句 × 两层（二阶段叠加）
def make_final():
    bpm = 150.0
    songs = {
        "A": band_song(TITLE8, "chorus", bpm, energy=1, harpsi_arp=True, lead=THEME + THEME2, lead_tr=12, lead_bus="p_lead"),
        "B": band_song(TITLE8, "chorus", bpm, energy=1, harpsi_arp=True, lead=MEL, lead_bus="p_lead"),
        "C": band_song(BOSS_A8, "wall", bpm, energy=2, lead=BOSS_MEL + BOSS_MEL, lead_tr=12, lead_bus="p_lead"),
        "D": band_song(TITLE8, "wall", bpm, energy=2, lead=MEL, lead_tr=12, lead_bus="p_lead", harm=harmonize(MEL, TITLE8)),
    }
    gains = bus_gains(list(songs.values()))
    irs = make_ir(3.2, 2.4, 6000)
    lay = {s: {"p1": layer_mix(S, ("b_", "p_"), gains, irs), "p2": layer_mix(S, "d_", gains, irs)} for s, S in songs.items()}
    c1 = np.concatenate([body(lay[s]["p1"], songs[s]) for s in songs])
    c2 = np.concatenate([body(lay[s]["p2"], songs[s]) for s in songs])
    g1 = gain_to(c1, -15.0)
    g2 = solve_gain(lambda g: lufs(c1 * g1 + c2 * g), -13.5)
    print(f"[final] 一阶段 {lufs(c1 * g1):.1f} / 二阶段 {lufs(c1 * g1 + c2 * g2):.1f} LUFS | 频段 {bands(c1 * g1 + c2 * g2)}"
          f" | 外放掉 {speaker_drop(c1 * g1 + c2 * g2):.1f} LU")
    for s in songs:
        write_seg(f"final_{s}_p1", lay[s]["p1"] * g1)
        write_seg(f"final_{s}_p2", lay[s]["p2"] * g2)


if __name__ == "__main__":
    which = sys.argv[1:] or ["battle", "boss", "final"]
    for w in which:
        if w.startswith("battle") and w != "battle":
            make_battle([w])
        else:
            globals()["make_" + w]()
