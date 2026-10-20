"""乌尔比安锁链 v2 候选（docs/113 §10，用户 10-21「锁链声音不太明显」）：在 import_sfx_cc0.py 的处理上留一部分 4 kHz 以上的链节声
（目标占比 2 / 3 / 4%）、响度抬 2–3 dB、掷锚叠低频「哐」、收链加清楚的起音；再按局内音量离线混一段 5 秒样本（配乐 + 同队其他音效）对比。
只写 <主仓库>/build/sfx_candidates/，不改 game/audio/sfx/。运行：python game/tools/gen_ulpianus_v2.py
"""
import os, sys
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "import_sfx_cc0.py"), encoding="utf-8").read()
sys.argv = [sys.argv[0]]   # 不带 --apply：工具段里的 SFX 指向暂存目录，这里只用 ALT_OUT
exec(src[:src.index("K_IMP = ")])
rng = np.random.default_rng(10212)
SFX_GAME = os.path.normpath(os.path.join(HERE, "..", "audio", "sfx"))
MUSIC = os.path.normpath(os.path.join(HERE, "..", "audio", "music"))


def hi_share(x, f0=4000.0):
    X = np.abs(np.fft.rfft(x * np.hanning(len(x)))) ** 2
    fr = np.fft.rfftfreq(len(x), 1 / SR)
    return float(X[fr > f0].sum() / max(1e-12, X.sum()))


def bandpass(x, lo, hi, order=4):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def chain_parts(x, ratio, fc=3000):
    """链身（同 chain_tone）与 3–7 kHz 的链节高频，分开返回，按目标占比混"""
    r = repitch(x, ratio)
    body = lowpass(r, fc, 8)
    return body + lowpass(body, 800, 4) * 1.5, bandpass(r, 3000, 7000)


def tune(build, hi_target):
    """二分高频增益，使成品（含「哐」/「咔」与起音处理）4 kHz 以上占比 = hi_target"""
    lo_g, hi_g = 0.0, 6.0
    for _ in range(30):
        gn = (lo_g + hi_g) / 2
        if hi_share(build(gn)) < hi_target:
            lo_g = gn
        else:
            hi_g = gn
    return build(lo_g)


def safe(x, cap_db=-1.0):
    """叠层后峰值超过 cap_db 就整体降，不削波"""
    cap = 10 ** (cap_db / 20)
    pk = np.abs(x).max()
    return x * (cap / pk) if pk > cap else x


def punch(x, ms=30.0, gain=1.7):
    """起音：头 ms 毫秒放大、之后 40 ms 回到 1"""
    n1, n2 = int(ms / 1000 * SR), int(0.04 * SR)
    e = np.ones(len(x))
    e[:n1] = gain
    e[n1:n1 + n2] = np.linspace(gain, 1.0, len(e[n1:n1 + n2]))
    return x * e


def onset(x, thr_db=-18.0):
    """第一个比全段峰值低 thr_db 以内的采样点"""
    pk = np.abs(x).max()
    return int(np.argmax(np.abs(x) >= pk * 10 ** (thr_db / 20)))


def klang(gain):
    """掷锚出手的低频「哐」：85→42 Hz 冲击 + 150 Hz 铁鸣 + 短低噪"""
    return gain * pad(thud(0.32, 85, 42, 10), metal(0.45, 150, 6, bright=0.4) * 0.35, lp(N(0.12), 700) * env(0.12, 0.001, 30) * 0.4)


def click(gain):
    """收链起音的链节「咔」"""
    return gain * lowpass(metal(0.06, 1100, 60, bright=0.5), 3500, 4)


kl = load("fs108265_klakmart_chains/108265-hq.mp3")
nt = load("fs387240_nettimato_chain/387240-hq.mp3")
raw1 = cut(kl, 18.00, 0.60, 0.002, 0.12)
raw1 = raw1[max(0, onset(raw1) - int(0.003 * SR)):]
raw3 = cut(nt, 8.76, 0.52, 0.002, 0.12)
raw3 = raw3[max(0, onset(raw3) - int(0.003 * SR)):]

# 现用：s1 rms -15.6、s3 -16.6（docs/113 §8）
VARS = {"A": (0.02, 2.0, 0.6), "B": (0.03, 2.5, 0.8), "C": (0.04, 3.0, 1.0)}   # 高频占比、抬多少 dB、「哐」/「咔」强度
out = {}
b1, h1 = chain_parts(raw1, 0.8)
b3, h3 = chain_parts(raw3, 0.75, 2600)   # 收链这段几乎全在 4 kHz 以上（99.97%），链身要降得更低才压得到目标以下
for k, (hs, up, kg) in VARS.items():
    def mk1(gn):
        c = punch(b1 + gn * h1)
        return hp(c / (np.abs(c).max() + 1e-9), 35, 1)

    def mk3(gn):
        c = punch(b3 + gn * h3, 25.0, 1.9)
        return hp(c / (np.abs(c).max() + 1e-9), 35, 1)

    # 响度只按锁链本身对齐（「哐」/「咔」另叠，不占锁链的响度），高频占比按成品算
    def fin1(gn):
        c = level(mk1(gn), -15.6 + up)
        kl_ = klang(1.0)
        kl_ = kl_ * 10 ** ((-15.6 + up - 4.0 + 3.0 * kg - rms100(kl_)) / 20)
        return safe(pad(kl_, at(c, 0.025)))

    def fin3(gn):
        c = level(mk3(gn), -16.6 + up)
        ck = click(1.0)
        ck = ck * 10 ** ((-16.6 + up - 6.0 + 3.0 * kg - rms100(ck)) / 20)
        return safe(pad(c, ck))

    s1 = tune(fin1, hs)
    s3 = tune(fin3, hs)
    alt("ulpianus_v2_%s_s1" % k, s1)
    alt("ulpianus_v2_%s_s3" % k, s3)
    print("   %s: 4 kHz 以上 s1 %.1f%% / s3 %.1f%%" % (k, 100 * hi_share(s1), 100 * hi_share(s3)))
    out[k] = (s1, s3)


# ---------------------------------------------------------------- 5 秒局内混音样本
# 局内音量：Sfx.vol_target −4 dB × 音乐总线 0.8，音效总线 0.9（settings.gd 缺省）；战斗曲激战三层（base + pulse + drive）全开。
# 同队：乌尔比安（队长）+ 能天使 + 推进之王，事件频率取 docs/113 §2 的实测；1.0 s 掷锚（s1，−4 dB），3.2 s 收链（s3，−2 dB）。
def wav(name):
    x, sr = sf.read(os.path.join(SFX_GAME, name + ".wav"))
    return x if x.ndim == 1 else x.mean(axis=1)


def pitched(x, p):
    if abs(p - 1.0) < 1e-3:
        return x
    n = int(len(x) / p)
    return np.interp(np.arange(n) * p, np.arange(len(x)), x)


DUR = 5.0
mus = np.zeros(int(DUR * SR))
for layer in ("base", "pulse", "drive"):
    m, msr = sf.read(os.path.join(MUSIC, "battle1_A_%s.ogg" % layer))
    m = m.mean(axis=1) if m.ndim > 1 else m
    if msr != SR:
        m = resample_poly(m, SR, msr)
    m = m[int(0.1 * SR):int(0.1 * SR) + len(mus)]
    mus[:len(m)] += m
mus *= 10 ** (-4 / 20) * 0.8

ev_rng = np.random.default_rng(5)
BG = [("kill", -8.0, 8.0, 0.08), ("hit", -9.0, 3.0, 0.08), ("pickup", -14.0, 3.0, 0.05), ("enemy_bite", -13.0, 4.0, 0.07),
      ("op_exusiai_atk", -11.0, 2.0, 0.09), ("op_exusiai_hit", -12.0, 6.0, 0.10), ("op_siege_atk", -11.0, 0.6, 0.0),
      ("op_siege_hit", -10.0, 0.55, 0.0), ("op_ulpianus_atk", -10.0, 0.9, 0.05)]
bg_events = []
for name, db, rate, pv in BG:
    t = ev_rng.uniform(0, 1.0 / rate)
    while t < DUR:
        bg_events.append((t, name, db, ev_rng.uniform(1 - pv, 1 + pv)))
        t += ev_rng.exponential(1.0 / rate)


def mix(s1, s3, tag):
    sfx = np.zeros(len(mus) + SR)
    for t, name, db, p in bg_events:
        x = pitched(wav(name), p) * 10 ** (db / 20)
        st = int(t * SR)
        sfx[st:st + len(x)] += x[:len(sfx) - st]
    for t, x, db in ((1.0, s1, -4.0), (3.2, s3, -2.0)):
        st = int(t * SR)
        sfx[st:st + len(x)] += x * 10 ** (db / 20)
    y = mus + sfx[:len(mus)] * 0.9
    y = np.tanh(y / 0.95) * 0.95   # 总线软限幅（防削波，听感与引擎限幅器接近）
    alt("ulpianus_v2_mix_%s" % tag, y)


mix(np.zeros(16), np.zeros(16), "bg")   # 只有背景（对照：锁链被淹多少）
mix(wav("op_ulpianus_s1"), wav("op_ulpianus_s3"), "now")
for k, (s1, s3) in out.items():
    mix(s1, s3, k)
print("掷锚在 1.0 s，收链在 3.2 s ->", ALT_OUT)
