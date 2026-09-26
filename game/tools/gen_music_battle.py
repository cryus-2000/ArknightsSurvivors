"""战斗配乐 v2.0（方向 B：电子 + 管弦混合，2026-09-26 用户选定，demo 见 Claude outputs/bgm_demo_0926）。

输出到 audio/music/：
  battle{1,2,3}_{base,drive,danger}.ogg   战斗三段：《潮起》D 小调 /《逆流》E 小调 /《灯火长明》升 F 小调（标题曲的调），
                                          126 BPM；base / drive 32 小节循环，danger 8 小节循环
  perc_{half,full,epic}.ogg               打击乐 8 小节循环（无音高，三段各用一种律动，即各段的 pulse 层）
  boss.ogg                                中期 Boss《海嗣之主》D 弗里吉亚 140 BPM，32 小节（含半速间奏）
  final.ogg / final_p2.ogg                最终 Boss《深蓝之树》140 BPM，32 小节；p2 是二阶段加强层（与 final 同步叠加）
  cue_rise.ogg / cue_hit.ogg              换段提示：一小节上行扫频（结尾对齐小节线）/ 落点冲击
每段四层同速同步（sfx.gd 按小节线开关）：
  base   跳弓固定音型 + 低音弦乐 + 低音铜管 + 合唱「呜」+ 主旋律（圆号 / 轻弦乐）+ 轻太鼓   —— 平静
  pulse  打击乐（perc_*）                                                                 —— 交战
  drive  弦乐全奏旋律 + 合成低音（侧链）+ 铜管短奏 + 中提琴琶音 + 合唱「啊」+ 门限合成器 + 镲 / 过门 —— 激战
  danger 高音颤弓小二度 + 滴答脉冲 + 低音嗡鸣（不再用心跳，心跳交给音效）                    —— 危险
32 小节 = 4 个 8 小节乐段：灯火动机（gen_music.THEME）→ 标题主旋律 → B 主题（新写）→ 标题主旋律高潮。
响度目标（BS.1770 积分）：平静 -20.5 / 交战 ≈ -17.5 / 激战 -15.5 LUFS；Boss -15；最终 -15（二阶段 ≈ -13.5）。
所有循环都是整小节的精确采样数（126 BPM 一小节 84000 采样，140 BPM 75600），尾巴回卷到开头。
依赖 numpy / scipy / soundfile（不需要 ffmpeg）。重新生成：cd game/tools && python gen_music_battle.py [perc battle boss final cues]
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
rng = np.random.default_rng(126)


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


def ensemble(freq, voices=5, spread=0.12, width=1.4):
    """多声部失谐合奏（弦乐 / 铜管 / 超级锯齿），各声部左右铺开"""
    freq = np.asarray(freq, dtype=float)
    n = len(freq)
    L = np.zeros(n)
    R = np.zeros(n)
    for k in range(voices):
        u = k / (voices - 1) - 0.5 if voices > 1 else 0.0
        drift = 1 + 0.0015 * np.sin(2 * np.pi * (0.15 + 0.35 * rng.random()) * tt(n) + rng.random() * 6.28)
        s = saw_bl(freq * 2 ** (u * spread / 12) * drift)
        p = u * width
        L += s * np.sqrt(0.5 * (1 - p))
        R += s * np.sqrt(0.5 * (1 + p))
    return np.stack([L, R], 1) / np.sqrt(voices)


SWEEP_CUTS = np.array([180, 300, 500, 800, 1300, 2100, 3400, 5500, 9000], float)


def lp_sweep(x, cut):
    """时变低通：几条固定截止频率的低通按对数频率插值（向量化近似）"""
    cut = np.clip(np.asarray(cut, dtype=float), SWEEP_CUTS[0], SWEEP_CUTS[-1])
    lc = np.log(cut)
    lcs = np.log(SWEEP_CUTS)
    lo_i = max(0, int(np.searchsorted(lcs, lc.min())) - 1)
    hi_i = max(lo_i + 1, min(len(lcs) - 1, int(np.searchsorted(lcs, lc.max()))))
    cuts = SWEEP_CUTS[lo_i:hi_i + 1]
    lcs = lcs[lo_i:hi_i + 1]
    ys = np.stack([lp(x, c) for c in cuts])
    idx = np.clip(np.searchsorted(lcs, lc) - 1, 0, len(lcs) - 2)
    fr = np.clip((lc - lcs[idx]) / (lcs[idx + 1] - lcs[idx]), 0, 1)
    ar = np.arange(len(x))
    if x.ndim == 2:
        fr = fr[:, None]
    return ys[idx, ar] * (1 - fr) + ys[idx + 1, ar] * fr


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


def duck_env(n, times, depth=0.45, rel=0.15, att=0.006):
    """侧链：按底鼓时间点做音量凹陷（打击乐在另一层，时间点照它的节奏型算）"""
    g = np.ones(n)
    a = int(att * SR)
    L = int(rel * SR * 4)
    shape = np.concatenate([1 - depth * np.linspace(0, 1, a), 1 - depth * np.exp(-np.arange(L) / (rel * SR))])
    for t in times:
        i = int(t * SR)
        if 0 <= i < n:
            j = min(n, i + len(shape))
            g[i:j] = np.minimum(g[i:j], shape[: j - i])
    return g


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


# ============================================================ 乐器：打击
def kick(v=1.0, dur=0.42, f0=165, f1=47, click=0.35, drive=1.8):
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(f1 + (f0 - f1) * np.exp(-t * 32)) / SR) * np.exp(-t * 8.5)
    knock = np.sin(2 * np.pi * np.cumsum(190 + 80 * np.exp(-t * 60)) / SR) * np.exp(-t * 55) * 0.35
    y = np.tanh((body + knock) * drive) / np.tanh(drive)
    clk = hp(rng.standard_normal(n), 2800) * np.exp(-t * 380) * click
    return (y + clk) * env(n, 0.0005, 0.02) * v


def snare(v=1.0, dur=0.38, tone=182):
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * tone * t) * np.exp(-t * 28) + 0.5 * np.sin(2 * np.pi * tone * 1.68 * t) * np.exp(-t * 38)
    nz = rng.standard_normal(n)
    noise = bp(nz, 1800, 9500) * np.exp(-t * 15) + bp(nz, 450, 1800) * np.exp(-t * 26) * 0.45
    return (body * 0.6 + noise) * env(n, 0.0005, 0.03) * v


def clap(v=1.0):
    n = int(0.4 * SR)
    t = tt(n)
    nz = bp(rng.standard_normal(n), 950, 6500)
    e = np.zeros(n)
    for k, off in enumerate((0.0, 0.010, 0.021)):
        i = int(off * SR)
        e[i:] += np.exp(-t[: n - i] * 190) * (0.75 if k < 2 else 1.0)
    i = int(0.021 * SR)
    e[i:] += np.exp(-t[: n - i] * 16) * 0.3
    return nz * e * v


def hat(v=1.0, open_=False):
    dur = 0.45 if open_ else 0.07
    n = int(dur * SR)
    t = tt(n)
    metal = sum(np.sign(np.sin(2 * np.pi * f * t + rng.random() * 6.28)) for f in (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)) / 6
    x = 0.6 * hp(metal, 7000, 4) + 0.4 * hp(rng.standard_normal(n), 8000, 4)
    e = np.exp(-t * (8 if open_ else 62)) * np.minimum(1, t / 0.0008)
    return lp(x, 14500) * e * v


def shaker(v=1.0):
    n = int(0.1 * SR)
    t = tt(n)
    return bp(rng.standard_normal(n), 4200, 11000) * np.minimum(1, t / 0.009) * np.exp(-t * 42) * v


def tom(pitch=140, v=1.0, dur=0.55):
    n = int(dur * SR)
    t = tt(n)
    body = np.sin(2 * np.pi * np.cumsum(pitch * (1 + 0.38 * np.exp(-t * 16))) / SR) * np.exp(-t * 6.5)
    nz = bp(rng.standard_normal(n), 300, 3200) * np.exp(-t * 38) * 0.3
    return np.tanh((body + nz) * 1.4) * env(n, 0.0005, 0.05) * v


def taiko(v=1.0, pitch=58, dur=1.1):
    n = int(dur * SR)
    t = tt(n)
    f = pitch * (1 + 0.5 * np.exp(-t * 24))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.2)
    over = np.sin(2 * np.pi * np.cumsum(f * 2.27) / SR) * np.exp(-t * 9) * 0.35
    slap = bp(rng.standard_normal(n), 350, 3500) * np.exp(-t * 34) * 0.55
    return (np.tanh((body + over) * 1.6) * 0.85 + slap) * env(n, 0.0008, 0.05) * v


def crash(v=1.0, dur=3.2):
    n = int(dur * SR)
    t = tt(n)
    e = np.exp(-t * 1.35) * np.minimum(1, t / 0.002)
    ch = [(lp(hp(rng.standard_normal(n), 3000), 13000) * 0.7 + bp(rng.standard_normal(n), 5000, 9000) * 0.5) * e for _ in range(2)]
    return np.stack(ch, 1) * v


def rev_crash(v=1.0, dur=2.0):
    return crash(v, dur)[::-1].copy()


def impact(v=1.0):
    n = int(2.8 * SR)
    t = tt(n)
    boom = np.sin(2 * np.pi * np.cumsum(30 + 75 * np.exp(-t * 2.8)) / SR) * np.exp(-t * 1.5)
    body = np.sin(2 * np.pi * np.cumsum(95 + 70 * np.exp(-t * 18)) / SR) * np.exp(-t * 6) * 0.55
    crack = lp(hp(rng.standard_normal(n), 250), 6000) * np.exp(-t * 8) * 0.55
    return (np.tanh((boom + body) * 1.5) * 0.8 + crack) * env(n, 0.0008, 0.3) * v


def noise_riser(dur, v=1.0):
    n = int(dur * SR)
    x = tt(n) / dur
    s = np.stack([rng.standard_normal(n), rng.standard_normal(n)], 1)
    y = lp_sweep(s, 400 + 7500 * x ** 2)
    return hp(y, 300) * (x ** 2)[:, None] * v


def sweep(dur, n0=50, n1=86, v=1.0):
    n = int(dur * SR)
    x = tt(n) / dur
    s = ensemble(midi(n0) * (midi(n1) / midi(n0)) ** (x ** 2), voices=5, spread=0.35)
    return hp(lp_sweep(s, 350 + 7000 * x ** 2), 200) * (x ** 2)[:, None] * v


# ============================================================ 乐器：音高
def spic(nt, vel=1.0, dur=0.17, bright=1.0):
    """跳弓：短促、带弓噪的合奏锯齿"""
    n = int(dur * SR)
    t = tt(n)
    x = ensemble(np.full(n, midi(nt)), voices=4, spread=0.16, width=0.8)
    y = lp_sweep(x, 1300 * bright + 2800 * np.exp(-t * 22) * vel)
    bow = bp(rng.standard_normal(n), 2000, 6000) * np.exp(-t * 90) * 0.05
    e = np.minimum(1, t / 0.003) * np.exp(-t * 15)
    return hp(y + bow[:, None], 85) * e[:, None] * vel


def low_strings(nt, dur, a=0.25, r=0.8):
    """低音提琴 + 正弦垫底：长音根音"""
    n = int(dur * SR)
    x = ensemble(np.full(n, midi(nt)), voices=4, spread=0.12, width=0.6)
    ph, _ = phase_of(np.full(n, midi(nt)))
    y = lp(x, 1100) + st(np.sin(2 * np.pi * ph)) * 0.55
    return hp(y, 32) * env(n, a, r)[:, None]


def bass_synth(nt, dur, cut_lo=420, cut_hi=2000, decay=10.0, drive=2.3, sub=0.55):
    """合成低音：锯齿 + 同相正弦，滤波包络 + 饱和（小喇叭靠泛音「听见」低音）"""
    n = int(dur * SR)
    t = tt(n)
    ph, dt = phase_of(np.full(n, midi(nt)))
    s = saw_from(ph, dt) - sub * np.sin(2 * np.pi * ph)
    y = lp_sweep(s, cut_lo + (cut_hi - cut_lo) * np.exp(-t * decay))
    y = np.tanh(y * drive) / np.tanh(drive)
    return lp(y, 3200) * env(n, 0.004, 0.035)


def brass(notes, dur, a=0.02, r=0.3, swell=False, bright=1.0):
    n = int(dur * SR)
    t = tt(n)
    x = np.zeros((n, 2))
    for nt in notes:
        f = midi(nt) * (1 - 0.012 * np.exp(-t * 40))   # 起音略低、迅速爬到正音
        x += ensemble(f, voices=3, spread=0.09, width=0.9)
    if swell:
        cut = 350 + 2200 * bright * (t / dur) ** 1.6
        e = env(n, dur * 0.7, r) * (0.35 + 0.65 * (t / dur) ** 1.2)
    else:
        cut = 700 + 2800 * bright * np.exp(-t * 3.2) + 500 * bright
        e = env(n, a, r)
    y = np.tanh(lp_sweep(x, cut) * 1.3)
    return hp(y, 90) * e[:, None] / np.sqrt(len(notes))


def choir(notes, dur, a=0.8, r=1.2, morph=True):
    L = G.voice(notes, dur, amp=1.0, a=a, r=r, morph=morph)
    R = G.voice(notes, dur, amp=1.0, a=a, r=r, morph=morph)
    return hp(np.stack([L, R], 1), 170)


def gated(notes, dur, beat, pat):
    """16 分门限和弦（电子律动铺底）"""
    n = int(dur * SR)
    x = np.zeros((n, 2))
    for nt in notes:
        x += ensemble(np.full(n, midi(nt)), voices=3, spread=0.25, width=1.3)
    x = hp(lp(x, 3300), 260) / np.sqrt(len(notes))
    g = np.zeros(n)
    step = beat / 4
    for k in range(int(dur / step) + 1):
        if pat[k % len(pat)]:
            g[int(k * step * SR): min(n, int((k + 0.7) * step * SR))] = 1.0
    return x * uniform_filter1d(g, int(0.004 * SR))[:, None]


def tremolo(notes, dur, rate, a=0.6, r=0.6):
    """颤弓（按 16 分音符速度起伏），偏亮的桥边音色"""
    n = int(dur * SR)
    t = tt(n)
    x = np.zeros((n, 2))
    for nt in notes:
        x += ensemble(np.full(n, midi(nt)), voices=4, spread=0.1, width=1.0)
    x = peq(hp(lp(x, 7000), 400), 2600, 4.0)
    am = 0.45 + 0.55 * np.abs(np.sin(np.pi * rate * t))
    return x * (am * env(n, a, r))[:, None] / np.sqrt(len(notes))


def tick(nt, v=1.0):
    n = int(0.12 * SR)
    t = tt(n)
    ph, dt = phase_of(np.full(n, midi(nt)))
    y = lp(square_from(ph, dt) * 0.6 + np.sin(2 * np.pi * ph), 2400)
    return hp(y, 300) * np.minimum(1, t / 0.002) * np.exp(-t * 38) * v


# ---- 单音旋律合成器（给 phrase 用）：输入逐采样频率与「距本音起音的时间」
def syn_strings(freq, age):
    return peq(hp(lp(ensemble(freq, voices=6, spread=0.17, width=1.2), 6000), 210), 1900, 2.5)


def syn_strings_soft(freq, age):
    return peq(hp(lp(ensemble(freq, voices=6, spread=0.15, width=1.0), 3600), 200), 1200, 1.5)


def syn_horn(freq, age, bright=1.0):
    x = ensemble(freq, voices=3, spread=0.07, width=0.7)
    cut = 450 + 2300 * bright * (1 - np.exp(-age / 0.07)) * (0.75 + 0.25 * np.exp(-age / 0.6))
    return lp(hp(np.tanh(lp_sweep(x, cut) * 1.3), 100), 4200)


def syn_supersaw(freq, age):
    return hp(lp(ensemble(freq, voices=7, spread=0.32, width=1.5), 7000), 320)


def syn_trombone(freq, age):
    return syn_horn(freq, age, 0.7)


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


# ============================================================ 乐曲素材（D 小调原型，各段整体移调）
TITLE_PROG = [[("Dm", 4)], [("Bb", 4)], [("F", 4)], [("Gm", 2), ("A", 2)],
              [("Dm", 4)], [("F", 4)], [("Bb", 4)], [("Asus", 2), ("A", 2)]]
B_PROG = [[("Bb", 4)], [("C", 4)], [("Am", 4)], [("Dm", 4)], [("Bb", 4)], [("C", 4)], [("Dm", 4)], [("Asus", 2), ("A", 2)]]
TITLE_BASS = [[(38, 4)], [(34, 4)], [(41, 4)], [(43, 2), (45, 2)], [(38, 4)], [(41, 4)], [(34, 4)], [(33, 4)]]
B_BASS = [[(34, 4)], [(36, 4)], [(33, 4)], [(38, 4)], [(34, 4)], [(36, 4)], [(38, 4)], [(33, 4)]]
LOOP_PROG = TITLE_PROG * 2 + B_PROG + TITLE_PROG
LOOP_BASS = TITLE_BASS * 2 + B_BASS + TITLE_BASS
VOI = {"Dm": [57, 62, 65, 69], "Bb": [58, 62, 65, 70], "F": [57, 60, 65, 69], "Gm": [58, 62, 67, 70],
       "A": [57, 61, 64, 69], "Asus": [57, 62, 64, 69], "C": [60, 64, 67, 72], "Am": [57, 60, 64, 69]}
MEL = list(G.TITLE_MEL)                          # 标题主旋律，8 小节
THEME = list(G.THEME[:12]) + [(70, 2), (69, 2)]  # 灯火动机，4 小节
THEME2 = list(G.THEME[:12]) + [(62, 2), (61, 2)]  # 第二遍末小节 D → C#，落在 A 和弦上
# B 主题（新写）：沿用灯火动机的「1 1 1.5 0.5」节奏，在 VI–VII 上逐级爬升，第 7 小节到 A5 高点
B_MEL = [(65, 1), (70, 1), (74, 1.5), (72, 0.5), (67, 1), (72, 1), (76, 1.5), (74, 0.5),
         (76, 1.5), (74, 0.5), (72, 1), (69, 1), (74, 2), (76, 1), (77, 1),
         (77, 1), (74, 1), (77, 1.5), (79, 0.5), (76, 1), (72, 1), (76, 1.5), (79, 0.5),
         (81, 2), (77, 1), (74, 1), (76, 2), (73, 2)]
TROMBONE_B = [(50, 4), (52, 4), (48, 4), (53, 4), (50, 4), (52, 4), (53, 4), (49, 4)]   # B 段长号：和弦三音一小节一个
SPIC_ACC = {0: 0, 3: 12, 6: 7, 8: 0, 11: 12, 14: 7}   # 16 分跳弓：3+3+2 重音，重音处跳八度 / 五度
GATE = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1]


def at_beat(bars_list, bar, beat):
    pos = 0.0
    for item, b in bars_list[bar]:
        if beat < pos + b:
            return item
        pos += b
    return bars_list[bar][-1][0]


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


def mixdown(S, stems, targets, sends, rev, rev_level, duck=None, kicks=(), delays=None):
    """各轨按响度目标定增益 → 按层分组（每层自带自己的混响）→ 尾巴回卷到开头，返回 {层: 立体声}"""
    irs = make_ir(**rev)
    out = {}
    for stem, names in stems.items():
        bus = {}
        for k in names:
            if k not in S.bus:
                continue
            x = S.bus[k]
            if duck and k in duck:
                x = x * duck_env(len(x), kicks, duck[k])[:, None]
            bus[k] = x * 10 ** ((targets[k] - lufs(x)) / 20)
        if not bus:
            continue
        mix = sum(bus.values())
        rev_in = sum(bus[k] * s for k, s in sends.items() if k in bus)
        if not isinstance(rev_in, int):
            mix = mix + reverb_wet(hp(rev_in, 190), irs) * rev_level
        for k, (beats, fb, wet) in (delays or {}).items():
            if k in bus:
                mix = mix + delay_wet(bus[k], beats * S.beat, fb) * wet
        mix = hp(mix, 28)
        data = mix[: S.len].copy()
        data[: S.n - S.len] += mix[S.len:]
        out[stem] = data
    return out


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


# ============================================================ 打击乐循环（pulse 层，8 小节，三段共用一种律动）
PERC_LUFS = {"perc_half": -21.2, "perc_full": -20.3, "perc_epic": -19.8}


def perc_pattern(name):
    """返回 [(小节, 拍, 乐器, 力度, 参数)]；底鼓时间也给同段的合成低音做侧链"""
    ev = []
    for bar in range(8):
        fill = 2.5 if bar == 7 else (3.0 if (bar == 3 and name == "perc_epic") else 99.0)
        if name == "perc_half":        # 半速：底鼓 1 / 3 拍后半，大军鼓在第 3 拍
            for b_, v in ((0, 1.0), (2.5, 0.8)):
                ev.append((bar, b_, "kick", v))
            if bar % 4 == 3:
                ev.append((bar, 3.75, "kick", 0.55))
            ev.append((bar, 2, "snare", 1.0))
            ev.append((bar, 0, "taiko", 0.8))
            if bar % 2 == 1:
                ev += [(bar, 3.5, "taiko_hi", 0.5), (bar, 3.75, "taiko_hi", 0.6)]
            for e in range(8):
                ev.append((bar, e * 0.5, "hat", 0.8 if e % 2 else 0.45))
        elif name == "perc_full":      # 全速：底鼓 1 / 3 / 3 后半，军鼓 2 / 4，16 分镲
            for b_, v in ((0, 1.0), (2, 0.9), (2.75, 0.6)):
                ev.append((bar, b_, "kick", v))
            if bar % 2 == 1:
                ev.append((bar, 1.5, "kick", 0.5))
            for b_ in (1, 3):
                ev.append((bar, b_, "snare", 1.0))
            for b_ in (0, 2):
                ev.append((bar, b_, "taiko", 0.7))
            if bar % 2 == 1:
                ev += [(bar, 3.5, "taiko_hi", 0.5), (bar, 3.75, "taiko_hi", 0.6)]
            for s in range(16):
                ev.append((bar, s * 0.25, "hat_open" if (s == 14 and bar % 2 == 1) else "hat", 0.85 if s % 2 else 0.5))
            for s in range(16):
                ev.append((bar, s * 0.25, "shaker", 0.6 if s % 2 == 0 else 0.4))
        else:                          # 史诗：切分底鼓 + 太鼓八分合奏 + 16 分镲
            for b_, v in ((0, 1.0), (1.5, 0.7), (2, 0.9), (3.5, 0.65)):
                ev.append((bar, b_, "kick", v))
            for b_ in (1, 3):
                ev.append((bar, b_, "snare", 1.0))
            ev += [(bar, 2.75, "snare", 0.3), (bar, 3.25, "snare", 0.25)]
            for e, (kind, v) in enumerate((("taiko", 0.8), ("taiko_hi", 0.4), ("taiko_hi", 0.55), ("taiko_hi", 0.4),
                                           ("taiko", 0.7), ("taiko_hi", 0.4), ("taiko_hi", 0.55), ("taiko_hi", 0.5))):
                ev.append((bar, e * 0.5, kind, v))
            for s in range(16):
                ev.append((bar, s * 0.25, "hat", 0.9 if s % 2 else 0.55))
        ev = [e for e in ev if e[1] < fill]
        if fill < 4:                   # 过门：16 分嗵鼓下行 + 太鼓
            k = 0
            b_ = fill
            while b_ < 4:
                ev.append((bar, b_, "tom", 150 - 9 * k))
                if k % 2 == 0:
                    ev.append((bar, b_, "taiko_hi", 0.6))
                k += 1
                b_ += 0.25
    return ev


def perc_kicks(name, bars, bpm=126):
    beat = 60 / bpm
    ks = [(b * 4 + bt) * beat for b, bt, kind, _ in perc_pattern(name) if kind == "kick"]
    return [t + rep * 8 * 4 * beat for rep in range(bars // 8 + 1) for t in ks]


def make_perc():
    for name in PERC_LUFS:
        S = Song(126, 8, tail=3.0)
        for bar, b_, kind, v in perc_pattern(name):
            t = S.at(bar, b_) + (hum(0.002) if kind in ("hat", "shaker") else 0.0)
            if kind == "kick":
                S.add("kick", kick(v), t)
            elif kind == "snare":
                S.add("snare", snare(v, tone=176), t)
                if v > 0.5:
                    S.add("snare", clap(0.6 * v), t + 0.004, pan=0.1)
            elif kind == "taiko":
                S.add("taiko", taiko(v, 56), t)
            elif kind == "taiko_hi":
                S.add("taiko", taiko(v, 80 + rng.uniform(-3, 3), 0.5), t, pan=rng.uniform(-0.3, 0.3))
            elif kind == "hat":
                S.add("hats", hat(v), t, pan=0.35)
            elif kind == "hat_open":
                S.add("hats", hat(v, open_=True), t, pan=0.35)
            elif kind == "shaker":
                S.add("hats", shaker(v), t + (0.012 if (b_ * 4) % 2 else 0.0), pan=-0.35)
            elif kind == "tom":
                S.add("taiko", tom(v, 1.0), t, pan=0.4 - 0.005 * (150 - v))
        stems = mixdown(S, {"all": ["kick", "snare", "taiko", "hats"]},
                        targets={"kick": -18.5, "snare": -19.5, "taiko": -20.0, "hats": -28.0},
                        sends={"snare": 0.14, "taiko": 0.25, "hats": 0.06, "kick": 0.03},
                        rev=dict(secs=3.0, decay=2.6, tone=6500), rev_level=0.5)
        x = stems["all"]
        x *= gain_to(x, PERC_LUFS[name])
        write_ogg(name, x)


# ============================================================ 战斗三段
SECTIONS = {
    "battle1": dict(tr=0, perc="perc_half", energy=0),
    "battle2": dict(tr=2, perc="perc_full", energy=1),
    "battle3": dict(tr=4, perc="perc_epic", energy=2),
}
SEC_TARGETS = {
    # base
    "celli": -21.0, "lowstr": -23.0, "lowbrass": -26.0, "choir_oo": -27.0, "melody_b": -21.5, "horn8vb": -27.0, "taiko_b": -26.0,
    # drive
    "strings": -19.5, "lead": -24.5, "bass": -20.5, "stabs": -23.5, "violas": -24.5, "violins": -24.0, "choir_ah": -24.0,
    "gate": -27.0, "trombone": -24.0, "fx": -23.0,
    # danger
    "trem": -24.0, "ticks": -27.0, "drone": -28.0,
}
SEC_STEMS = {
    "base": ["celli", "lowstr", "lowbrass", "choir_oo", "melody_b", "horn8vb", "taiko_b"],
    "drive": ["strings", "lead", "bass", "stabs", "violas", "violins", "choir_ah", "gate", "trombone", "fx"],
}
SEC_SENDS = {"celli": 0.14, "lowbrass": 0.25, "choir_oo": 0.4, "melody_b": 0.32, "horn8vb": 0.3, "taiko_b": 0.25,
             "strings": 0.3, "lead": 0.25, "stabs": 0.25, "violas": 0.2, "violins": 0.22, "choir_ah": 0.4, "gate": 0.15,
             "trombone": 0.3, "fx": 0.3, "trem": 0.35, "ticks": 0.2, "drone": 0.3}


def make_section(name, tr, perc, energy):
    S = Song(126, 32)
    bt = S.beat
    kicks = perc_kicks(perc, 32)
    ev = 0.8 + 0.1 * energy   # 跳弓力度随段落提高
    for bar in range(32):
        cyc = bar // 8
        pos = 0.0
        for chord, beats in LOOP_PROG[bar]:
            t0 = S.at(bar, pos)
            dur = beats * bt
            v = [n_ + tr for n_ in VOI[chord]]
            root = at_beat(LOOP_BASS, bar, pos) + tr
            # ---- base：低音弦乐根音 + 低音铜管（每段首两小节渐强）+ 合唱「呜」
            S.add("lowstr", low_strings(root, dur + 0.3), t0)
            S.add("lowbrass", brass([root + 12, root + 19], dur + 0.25, swell=(bar % 8 == 0 and pos == 0), bright=0.8, r=0.25), t0)
            S.add("choir_oo", choir(v, dur + 0.9, a=0.5, r=0.9, morph=False), t0)
            # ---- drive：铜管短奏（第 1 / 3 乐段每小节两下，第 2 / 4 乐段每和弦一下）
            if cyc in (0, 2):
                for b_ in (0, 2.5):
                    if b_ < beats:
                        S.add("stabs", brass(v, 0.32, a=0.008, r=0.14, bright=1.2), S.at(bar, pos + b_))
            else:
                S.add("stabs", brass(v, 0.45, a=0.008, r=0.2, bright=1.1), t0)
            # ---- drive：中提琴 16 分琶音（第 2–4 乐段）、门限合成器（第 2 / 4 乐段）、合唱「啊」（第 3 / 4 乐段）
            if cyc >= 1:
                idx = [0, 1, 2, 3, 2, 1, 2, 3]
                for k in range(int(beats * 4)):
                    S.add("violas", spic(v[idx[k % 8]], 0.95 if k % 4 == 0 else 0.6, dur=0.14), t0 + k * 0.25 * bt, pan=0.3)
            if cyc in (1, 3):
                S.add("gate", gated([n_ + 12 for n_ in v[:3]], dur, bt, GATE), t0)
            if cyc >= 2:
                S.add("choir_ah", choir(v, dur + 0.9, a=0.25, r=0.9, morph=True), t0)
            # ---- drive：第 1 乐段小提琴 16 分音型（高八度，和弦音上下行）
            if cyc == 0:
                pat = [0, 1, 2, 3, 2, 3, 1, 2]
                for k in range(int(beats * 4)):
                    S.add("violins", spic(v[pat[k % 8]] + 12, 0.9 if k % 4 == 0 else 0.55, dur=0.12, bright=1.2), t0 + k * 0.25 * bt, pan=0.35)
            pos += beats
        # ---- base：大提琴跳弓 16 分固定音型（全程）
        for s in range(16):
            b_ = s * 0.25
            r = at_beat(LOOP_BASS, bar, b_) + tr + 12
            vel = (1.0 if s in SPIC_ACC else 0.55) * ev
            S.add("celli", spic(r + SPIC_ACC.get(s, 0), vel), S.at(bar, b_) + hum(), pan=-0.15)
        # ---- base：轻太鼓（每两小节一下）
        if bar % 2 == 0:
            S.add("taiko_b", taiko(0.8, 55), S.at(bar))
        # ---- drive：合成低音八分（侧链跟打击乐层的底鼓）
        pat = [0, 0, 0, 12, 0, 0, 12, 0] if energy == 0 else [0, 0, 12, 0, 0, 12, 0, 12]
        for e in range(8):
            nt = at_beat(LOOP_BASS, bar, e * 0.5) + tr + pat[e]
            S.add("bass", bass_synth(nt, 0.5 * bt * 0.88, cut_hi=1900 + 350 * energy), S.at(bar, e * 0.5))
    # ---- 旋律
    top = max(n_ for n_, _ in MEL if n_ is not None) + tr
    s_oct = 12 if top + 12 <= 89 else 0      # 第 4 乐段高八度（太高就不翻，靠配器加厚）
    # base：第 1 乐段圆号灯火动机；第 2 / 4 乐段轻弦乐主旋律 + 圆号低八度；第 3 乐段轻弦乐 B 主题
    S.add("melody_b", phrase(THEME + THEME2, bt, lambda f, a: syn_horn(f, a, 0.8), attack=0.05, release=0.35, transpose=tr), S.at(0))
    for c0 in (8, 24):
        S.add("melody_b", phrase(MEL, bt, syn_strings_soft, attack=0.06, release=0.35, transpose=tr), S.at(c0))
        S.add("horn8vb", phrase(MEL, bt, syn_horn, attack=0.03, release=0.3, transpose=tr - 12), S.at(c0))
    S.add("melody_b", phrase(B_MEL, bt, syn_strings_soft, attack=0.06, release=0.35, transpose=tr), S.at(16))
    # drive：第 2 乐段弦乐同度加强；第 3 乐段弦乐 B 主题 + 长号；第 4 乐段弦乐（高八度）+ 超级锯齿
    S.add("strings", phrase(MEL, bt, syn_strings, attack=0.05, release=0.3, transpose=tr), S.at(8))
    S.add("strings", phrase(B_MEL, bt, syn_strings, attack=0.05, release=0.3, transpose=tr), S.at(16))
    S.add("trombone", phrase(TROMBONE_B, bt, syn_trombone, attack=0.08, release=0.4, transpose=tr), S.at(16))
    S.add("strings", phrase(MEL, bt, syn_strings, attack=0.04, release=0.4, transpose=tr + s_oct), S.at(24))
    S.add("lead", phrase(MEL, bt, syn_supersaw, attack=0.01, release=0.3, transpose=tr + s_oct), S.at(24))
    # ---- drive：段落衔接（每个乐段开头镲，结尾一小节渐强 + 倒放镲；第 4 乐段开头冲击）
    for c in range(4):
        S.add("fx", crash(0.9), S.at(c * 8))
        S.add("fx", noise_riser(S.bar, 0.8), S.at(c * 8 + 7))
        S.add("fx", rev_crash(0.7, S.bar), S.at(c * 8) - S.bar)
    S.add("fx", impact(0.9), S.at(24))
    stems = mixdown(S, SEC_STEMS, SEC_TARGETS, SEC_SENDS, rev=dict(secs=3.2, decay=2.5, tone=6500), rev_level=0.5,
                    duck={"bass": 0.4, "gate": 0.45}, kicks=kicks, delays={"lead": (0.5, 0.25, 0.14)})
    stems["danger"] = make_danger(tr)
    return stems


def make_danger(tr):
    """危险层（8 小节，主音持续音上的高音颤弓小二度 + 滴答 + 低音嗡鸣；和声中性，任何和弦上都「不安」）"""
    S = Song(126, 8, tail=3.0)
    bt = S.beat
    tonic = 62 + tr
    for b in range(0, 8, 2):
        S.add("trem", tremolo([tonic + 12, tonic + 13], S.bar * 2 + 0.3, rate=126 / 60 * 4 / 2, a=S.bar * 1.2, r=0.4), S.at(b))
        S.add("drone", brass([tonic - 12, tonic - 11], S.bar * 2 + 0.2, swell=True, bright=0.6, r=0.3), S.at(b))
    for s in range(8 * 16):
        S.add("ticks", tick(tonic, 1.0 if s % 4 == 0 else 0.45), S.at(0, s * 0.25), pan=0.25 if s % 2 else -0.25)
    out = mixdown(S, {"danger": ["trem", "ticks", "drone"]}, SEC_TARGETS, SEC_SENDS,
                  rev=dict(secs=3.2, decay=2.5, tone=6500), rev_level=0.5)
    return out["danger"]


def fit_section(stems, perc_x):
    """定整体增益：平静（base）-20.5、激战（base + pulse + drive）-15.5 LUFS；danger 比交战叠加后高约 1 LU"""
    n = len(stems["base"])
    p = np.tile(perc_x, (n // len(perc_x) + 1, 1))[:n]
    stems["base"] = stems["base"] * gain_to(stems["base"], -20.5)
    lo, hi = 0.05, 8.0
    for _ in range(40):
        g = np.sqrt(lo * hi)
        if lufs(stems["base"] + p + stems["drive"] * g) > -15.5:
            hi = g
        else:
            lo = g
    stems["drive"] = stems["drive"] * np.sqrt(lo * hi)
    combat = stems["base"] + p
    d = stems["danger"]
    dd = np.tile(d, (n // len(d) + 1, 1))[:n]
    lo, hi = 0.02, 8.0
    target = lufs(combat) + 1.0
    for _ in range(40):
        g = np.sqrt(lo * hi)
        if lufs(combat + dd * g) > target:
            hi = g
        else:
            lo = g
    stems["danger"] = d * np.sqrt(lo * hi)
    return p


def report(name, stems, p):
    n = len(stems["base"])
    d = np.tile(stems["danger"], (n // len(stems["danger"]) + 1, 1))[:n]
    states = {"平静": stems["base"], "交战": stems["base"] + p, "激战": stems["base"] + p + stems["drive"],
              "激战+危险": stems["base"] + p + stems["drive"] + d}
    full = states["激战+危险"]
    print(f"[{name}] " + " / ".join(f"{k} {lufs(x):.1f}" for k, x in states.items())
          + f" LUFS | 激战频段 {bands(states['激战'])} | 外放掉 {speaker_drop(states['激战']):.1f} LU"
          + f" | 全叠峰值 {20 * np.log10(np.max(np.abs(full))):.1f} dBFS")


def make_battle(which=None):
    percs = {}
    for k in PERC_LUFS:
        percs[k] = sf.read(os.path.join(OUTDIR, k + ".ogg"), always_2d=True)[0]
    for name, cfg in SECTIONS.items():
        if which and name not in which:
            continue
        stems = make_section(name, **cfg)
        p = fit_section(stems, percs[cfg["perc"]])
        report(name, stems, p)
        for k in ("base", "drive", "danger"):
            write_ogg(f"{name}_{k}", stems[k])


# ============================================================ 中期 Boss《海嗣之主》D 弗里吉亚 140 BPM 32 小节
# A 固定音型 → B 主题两遍 → D 半速间奏（圆号呼应主题头、铜管渐强蓄力）→ C 高潮（主题高八度）。Boss 战可能拖得很长，循环做长一点
BOSS_MEL = [(62, 0.5), (63, 0.5), (62, 1), (70, 1), (69, 1), (67, 1.5), (65, 0.5), (63, 1), (62, 1),
            (62, 0.5), (63, 0.5), (65, 1), (67, 1), (69, 1), (70, 2), (69, 2)]   # 旧版 Boss 主题，4 小节
BOSS_PROG = ([["Dm"], ["Eb"], ["Dm"], ["C"], ["Dm"], ["Eb"], ["Bb"], ["A"]] * 2
             + [["Dm"], ["Eb"], ["Dm"], ["Eb"], ["Bb"], ["C"], ["Bb"], ["A"]]
             + [["Gm"], ["Eb"], ["Dm"], ["Dm"], ["Gm"], ["Eb"], ["Bb"], ["A"]])
BOSS_ROOT = {"Dm": 38, "Eb": 39, "C": 36, "Bb": 34, "A": 33, "Gm": 43}
BOSS_VOI = {"Dm": [57, 62, 65, 69], "Eb": [58, 63, 67, 70], "C": [55, 60, 64, 67], "Bb": [58, 62, 65, 70],
            "A": [57, 61, 64, 69], "Gm": [58, 62, 67, 70]}


def epic_drums(S, bar, fill_from=99.0, v=1.0, half=False):
    """史诗鼓组；half=True 为半速（底鼓 1 / 3 拍后半、军鼓第 3 拍、八分镲）"""
    if half:
        ev = [(0, "kick", 1.0), (2.5, "kick", 0.8), (2, "snare", 1.0), (0, "taiko", 0.8)]
        ev += [(e * 0.5, "hat", 0.7 if e % 2 else 0.4) for e in range(8)]
    else:
        ev = [(0, "kick", 1.0), (1.5, "kick", 0.7), (2, "kick", 0.9), (3.5, "kick", 0.65), (1, "snare", 1.0), (3, "snare", 1.0)]
        for e in range(8):
            ev.append((e * 0.5, "taiko" if e % 4 == 0 else "taiko_hi", 0.75 if e % 4 == 0 else 0.45))
        for s in range(16):
            ev.append((s * 0.25, "hat", 0.9 if s % 2 else 0.55))
    for b_, kind, vv in ev:
        if b_ >= fill_from:
            continue
        t = S.at(bar, b_)
        if kind == "kick":
            S.add("kick", kick(vv * v), t)
        elif kind == "snare":
            S.add("snare", snare(vv * v), t)
            S.add("snare", clap(0.55 * vv * v), t + 0.004, pan=0.1)
        elif kind == "taiko":
            S.add("taiko", taiko(vv * v, 56), t)
        elif kind == "taiko_hi":
            S.add("taiko", taiko(vv * v, 82 + rng.uniform(-3, 3), 0.5), t, pan=rng.uniform(-0.3, 0.3))
        else:
            S.add("hats", hat(vv * v), t + hum(0.002), pan=0.35)
    k = 0
    b_ = fill_from
    while b_ < 4:
        S.add("taiko", tom(150 - 9 * k, v), S.at(bar, b_), pan=0.4 - 0.1 * k)
        if k % 2 == 0:
            S.add("taiko", taiko(0.6 * v, 70, 0.5), S.at(bar, b_), pan=-0.2)
        k += 1
        b_ += 0.25


def epic_kicks(S, bars, half_bars=()):
    return [S.at(b, x) for b in range(bars) for x in ((0, 2.5) if b in half_bars else (0, 1.5, 2, 3.5))]


def make_boss():
    S = Song(140, 32)
    bt = S.beat
    for bar in range(32):
        ch = BOSS_PROG[bar][0]
        v = BOSS_VOI[ch]
        root = BOSS_ROOT[ch]
        sec = bar // 8          # 0 A / 1 B / 2 D 间奏 / 3 C 高潮
        brk = sec == 2
        # 跳弓固定音型：弗里吉亚色彩（Dm 上第 2 个重音落在降二级）
        for s in range(16):
            off = SPIC_ACC.get(s, 0)
            if s == 11 and ch == "Dm":
                off = 1
            S.add("celli", spic(root + 12 + off, (1.0 if s in SPIC_ACC else 0.55) * (0.7 if brk else 1.0)), S.at(bar, s * 0.25) + hum(), pan=-0.15)
        S.add("lowstr", low_strings(root, S.bar + 0.3), S.at(bar))
        S.add("lowbrass", brass([root + 12, root + 19], S.bar + 0.2, swell=brk, bright=0.9, r=0.2), S.at(bar))
        if not brk:
            for b_ in (0, 1.5, 3):
                S.add("stabs", brass(v, 0.3, a=0.008, r=0.14, bright=1.25), S.at(bar, b_))
            for e in range(8):
                pat = [0, 0, 12, 0, 1 if ch == "Dm" else 0, 0, 12, 0]
                S.add("bass", bass_synth(root + pat[e], 0.5 * bt * 0.88, cut_hi=2300), S.at(bar, e * 0.5))
        S.add("choir", choir([n_ + 12 for n_ in v[1:]] if sec == 3 else v, S.bar + 0.8, a=0.6 if brk else 0.3, r=0.8, morph=(sec == 3)), S.at(bar))
        if sec == 3:
            idx = [0, 1, 2, 3, 2, 1, 2, 3]
            for k in range(16):
                S.add("violas", spic(v[idx[k % 8]] + 12, 0.9 if k % 4 == 0 else 0.55, dur=0.12, bright=1.2), S.at(bar, k * 0.25), pan=0.3)
        epic_drums(S, bar, fill_from=2.0 if bar % 8 == 7 else 99.0, v=0.85 if sec == 0 else 1.0, half=brk)
    # 主题：B 段弦乐 + 圆号低八度（两遍）；D 段圆号每两小节呼应一次主题头；C 段弦乐高八度 + 超级锯齿 + 圆号原位
    for c0 in (8, 12):
        S.add("melody", phrase(BOSS_MEL, bt, syn_strings, attack=0.03, release=0.25), S.at(c0))
        S.add("horns", phrase(BOSS_MEL, bt, syn_horn, attack=0.02, release=0.25, transpose=-12), S.at(c0))
    for c0 in (16, 18, 20, 22):
        S.add("horns", phrase(BOSS_MEL[:5], bt, syn_horn, attack=0.03, release=0.5), S.at(c0))
    for c0 in (24, 28):
        S.add("melody", phrase(BOSS_MEL, bt, syn_strings, attack=0.03, release=0.3, transpose=12), S.at(c0))
        S.add("lead", phrase(BOSS_MEL, bt, syn_supersaw, attack=0.01, release=0.25, transpose=12), S.at(c0))
        S.add("horns", phrase(BOSS_MEL, bt, syn_horn, attack=0.02, release=0.25), S.at(c0))
    for c in (0, 8, 24):
        S.add("fx", crash(0.9), S.at(c))
    S.add("fx", crash(0.5), S.at(16))
    for c in (7, 15, 23, 31):
        S.add("fx", noise_riser(S.bar, 0.8 if c != 23 else 1.0), S.at(c))
    S.add("fx", rev_crash(0.8, S.bar), S.at(24) - S.bar)
    S.add("fx", impact(0.9), S.at(24))
    kicks = epic_kicks(S, 32, half_bars=range(16, 24))
    stems = mixdown(S, {"all": list(S.bus.keys())},
                    targets={"celli": -21.0, "lowstr": -24.0, "lowbrass": -24.5, "stabs": -22.5, "choir": -24.5, "bass": -20.5,
                             "violas": -25.0, "melody": -19.0, "horns": -22.5, "lead": -24.5, "kick": -19.0, "snare": -20.0,
                             "taiko": -20.5, "hats": -28.5, "fx": -23.0},
                    sends={"celli": 0.14, "lowbrass": 0.25, "stabs": 0.25, "choir": 0.4, "violas": 0.2, "melody": 0.3,
                           "horns": 0.3, "lead": 0.25, "snare": 0.14, "taiko": 0.25, "fx": 0.3},
                    rev=dict(secs=3.0, decay=2.6, tone=6500), rev_level=0.5, duck={"bass": 0.4}, kicks=kicks,
                    delays={"lead": (0.5, 0.25, 0.14)})
    x = stems["all"]
    x = limiter(x * gain_to(x, -15.0))
    print(f"[boss] {lufs(x):.1f} LUFS | 频段 {bands(x)} | 外放掉 {speaker_drop(x):.1f} LU | 峰值 {20 * np.log10(np.max(np.abs(x))):.1f} dBFS")
    write_ogg("boss", x)


# ============================================================ 最终 Boss《深蓝之树》140 BPM 32 小节（一阶段 + 二阶段加强层）
FINAL_PROG = TITLE_PROG + TITLE_PROG + [[("Dm", 4)], [("Eb", 4)], [("Dm", 4)], [("C", 4)],
                                        [("Dm", 4)], [("Eb", 4)], [("Bb", 4)], [("A", 4)]] + TITLE_PROG
FINAL_BASS = TITLE_BASS * 2 + [[(38, 4)], [(39, 4)], [(38, 4)], [(36, 4)], [(38, 4)], [(39, 4)], [(34, 4)], [(33, 4)]] + TITLE_BASS
VOI_F = dict(VOI, Eb=[58, 63, 67, 70])


def make_final():
    S = Song(140, 32)
    bt = S.beat
    for bar in range(32):
        cyc = bar // 8
        pos = 0.0
        for chord, beats in FINAL_PROG[bar]:
            t0 = S.at(bar, pos)
            dur = beats * bt
            v = VOI_F[chord]
            root = at_beat(FINAL_BASS, bar, pos)
            S.add("lowstr", low_strings(root, dur + 0.3), t0)
            S.add("lowbrass", brass([root + 12, root + 19], dur + 0.2, bright=0.9, r=0.2), t0)
            S.add("choir", choir(v, dur + 0.8, a=0.3, r=0.8, morph=(cyc >= 2)), t0)
            for b_ in (0, 2.5):
                if b_ < beats:
                    S.add("stabs", brass(v, 0.3, a=0.008, r=0.14, bright=1.2), S.at(bar, pos + b_))
            # 二阶段：高音合唱、小提琴 16 分、门限合成器、每拍铜管
            S.add("p2_choir", choir([n_ + 12 for n_ in v[1:]], dur + 0.8, a=0.2, r=0.8, morph=True), t0)
            pat = [0, 1, 2, 3, 2, 3, 1, 2]
            for k in range(int(beats * 4)):
                S.add("p2_violins", spic(v[pat[k % 8]] + 12, 0.9 if k % 4 == 0 else 0.55, dur=0.12, bright=1.2), t0 + k * 0.25 * bt, pan=0.35)
            S.add("p2_gate", gated([n_ + 12 for n_ in v[:3]], dur, bt, GATE), t0)
            for b_ in range(int(beats)):
                S.add("p2_stabs", brass(v, 0.25, a=0.006, r=0.12, bright=1.3), S.at(bar, pos + b_))
            pos += beats
        for s in range(16):
            r = at_beat(FINAL_BASS, bar, s * 0.25) + 12
            S.add("celli", spic(r + SPIC_ACC.get(s, 0), 1.0 if s in SPIC_ACC else 0.55), S.at(bar, s * 0.25) + hum(), pan=-0.15)
        for e in range(8):
            nt = at_beat(FINAL_BASS, bar, e * 0.5) + [0, 0, 12, 0, 0, 12, 0, 12][e]
            S.add("bass", bass_synth(nt, 0.5 * bt * 0.88, cut_hi=2400), S.at(bar, e * 0.5))
        epic_drums(S, bar, fill_from=2.0 if bar % 8 == 7 else 99.0)
        for e in range(8):   # 二阶段：太鼓八分加倍
            S.add("p2_taiko", taiko(0.55 if e % 2 else 0.8, 64 if e % 2 else 52, 0.6), S.at(bar, e * 0.5 + 0.25), pan=0.2 if e % 2 else -0.2)
    # 旋律：灯火动机（圆号）→ 标题主旋律（弦乐 + 圆号低八度）→ Boss 主题（铜管，与我方旋律对峙）→ 标题主旋律高潮
    S.add("horns", phrase(THEME + THEME2, bt, syn_horn, attack=0.03, release=0.3), S.at(0))
    S.add("melody", phrase(MEL, bt, syn_strings, attack=0.04, release=0.3), S.at(8))
    S.add("horns", phrase(MEL, bt, syn_horn, attack=0.03, release=0.3, transpose=-12), S.at(8))
    for c0 in (16, 20):
        S.add("horns", phrase(BOSS_MEL, bt, syn_horn, attack=0.02, release=0.25), S.at(c0))
        S.add("melody", phrase(BOSS_MEL, bt, syn_strings, attack=0.03, release=0.25, transpose=12), S.at(c0))
    S.add("melody", phrase(MEL, bt, syn_strings, attack=0.04, release=0.4, transpose=12), S.at(24))
    S.add("p2_lead", phrase(MEL, bt, syn_supersaw, attack=0.01, release=0.3, transpose=12), S.at(24))
    S.add("horns", phrase(MEL, bt, syn_horn, attack=0.03, release=0.3), S.at(24))
    for c in range(4):
        S.add("fx", crash(0.9), S.at(c * 8))
        S.add("fx", noise_riser(S.bar, 0.8), S.at(c * 8 + 7))
    S.add("fx", impact(0.9), S.at(24))
    kicks = epic_kicks(S, 32)
    base_names = [k for k in S.bus if not k.startswith("p2_")]
    p2_names = [k for k in S.bus if k.startswith("p2_")]
    targets = {"celli": -21.0, "lowstr": -24.0, "lowbrass": -24.5, "stabs": -23.0, "choir": -24.0, "bass": -20.5, "melody": -19.0,
               "horns": -22.0, "kick": -19.0, "snare": -20.0, "taiko": -20.5, "hats": -28.5, "fx": -23.0,
               "p2_choir": -23.5, "p2_violins": -24.5, "p2_gate": -26.5, "p2_stabs": -24.0, "p2_taiko": -22.5, "p2_lead": -23.5}
    sends = {"celli": 0.14, "lowbrass": 0.25, "stabs": 0.25, "choir": 0.4, "melody": 0.3, "horns": 0.3, "snare": 0.14, "taiko": 0.25,
             "fx": 0.3, "p2_choir": 0.4, "p2_violins": 0.2, "p2_gate": 0.15, "p2_stabs": 0.25, "p2_taiko": 0.25, "p2_lead": 0.25}
    stems = mixdown(S, {"final": base_names, "final_p2": p2_names}, targets, sends, rev=dict(secs=3.0, decay=2.6, tone=6500),
                    rev_level=0.5, duck={"bass": 0.4, "p2_gate": 0.45}, kicks=kicks, delays={"p2_lead": (0.5, 0.25, 0.14)})
    a = stems["final"]
    g = gain_to(a, -15.0)
    a = a * g
    b = stems["final_p2"] * g
    lo, hi = 0.05, 8.0     # 二阶段叠上去约 -13.5
    for _ in range(40):
        m = np.sqrt(lo * hi)
        if lufs(a + b * m) > -13.5:
            hi = m
        else:
            lo = m
    b = b * np.sqrt(lo * hi)
    print(f"[final] 一阶段 {lufs(a):.1f} / 二阶段 {lufs(a + b):.1f} LUFS | 频段 {bands(a + b)} | 外放掉 {speaker_drop(a + b):.1f} LU"
          f" | 峰值 {20 * np.log10(np.max(np.abs(a + b))):.1f} dBFS")
    write_ogg("final", a)
    write_ogg("final_p2", b)


# ============================================================ 换段提示（叠加短乐句，不循环）
def make_cues():
    bar = 240 / 126
    n = int(SR * bar)
    x = np.zeros((n, 2))
    x += sweep(bar, 50, 86, 1.0)
    x += noise_riser(bar, 0.9)
    x += rev_crash(0.8, bar)
    k = int(0.004 * SR)
    x[-k:] *= np.linspace(1, 0, k)[:, None]
    x *= gain_to(x, -19.0)
    write_ogg("cue_rise", x)
    n = int(SR * 3.2)
    y = np.zeros((n, 2))
    imp = st(impact(1.0))
    y[: len(imp)] += imp
    y += crash(0.9, 3.2)
    irs = make_ir(2.8, 2.6, 6500)
    y = y + reverb_wet(hp(y, 190), irs) * 0.3
    y *= env(n, 0.001, 0.8)[:, None]
    y *= gain_to(y, -18.0)
    write_ogg("cue_hit", y)


if __name__ == "__main__":
    which = sys.argv[1:] or ["perc", "battle", "boss", "final", "cues"]
    for w in which:
        if w.startswith("battle") and w != "battle":
            make_battle([w])
        else:
            globals()["make_" + w]()
