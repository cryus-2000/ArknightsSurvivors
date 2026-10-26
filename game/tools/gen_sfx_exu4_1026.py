"""能天使音效第四轮（docs/113 §18，10-26 用户 itch 5559c3e62「能天使的音效是不是还是没有替换」）。
查证：新枪声（ae4f5be91）确实在包里、也确实在播（--sfxstat：atk 三条轮换、s1 / s2 / s3 / big / hit 全走专属文件，没有借用）；
问题是 A 套选了消音枪，rms100 -19.7 / -16.8 dBFS，叠上普攻 -11 dB 后播放电平约 -31 dB，比命中 -18、击杀 -16、拾取 -19 低 12 dB 以上，
密集战斗里还会被 DUCK（优先级 2、同时 ≥12 个在响再降 6 dB）。所以听起来「没换」。

本轮：枪声改「更脆更响」——取不带消音的 g7（自动步枪 punchy）/ g10（游戏用射击音）/ g9（步枪点射），2–6 kHz 抬 +5 dB，尾部收到 0.11 s，
rms100 对齐 -9.5 dBFS（叠 -11 dB = 约 -20.5，和命中 / 击杀同档）；命中改「弹着点脆响 + 金属叮」；技能连射用同一套样本重拼，响度同步抬。
alt = 科幻版（g11 / g8 / g13：偏电子的尾音）。OP_PRIO 另在 sfx.gd 把能天使普攻 / 命中提到优先级 3（不被 DUCK、满槽时不先被丢）。

运行：python game/tools/gen_sfx_exu4_1026.py                 写对比音频 build/sfx_review_1024/exu4/（before / after / alt，含 12 连射与带背景的混音）
      python game/tools/gen_sfx_exu4_1026.py --apply [after|alt] 写进 game/audio/sfx/（单声道 44.1 kHz 16 位 wav）
"""
import os, sys, subprocess
import numpy as np
import soundfile as sf
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
GUN = os.path.join(ROOT, "build", "sfx_review_1024", "gun")
OUT = os.path.join(ROOT, "build", "sfx_review_1024", "exu4")
SFX = os.path.join(HERE, "..", "audio", "sfx")
SR = 44100
RNG = np.random.default_rng(1026)
SETS = {"after": ["g7", "g10", "g9"], "alt": ["g11", "g8", "g13"]}


def rd_ogg(n):
    x, _ = sf.read(os.path.join(GUN, n + ".ogg"), dtype="float64")
    return x.mean(1) if x.ndim > 1 else x


def rd_wav(n, rev=None):
    """rev = 提交号时从 git 读（对比用的「改前」固定读 ae4f5be91 的文件，原始命中叮声读首次接入的 547edc5f1，重跑不受已写入文件影响）"""
    if rev:
        import io
        b = subprocess.run(["git", "show", "%s:game/audio/sfx/%s.wav" % (rev, n)], cwd=HERE, capture_output=True).stdout
        x, sr = sf.read(io.BytesIO(b), dtype="float64")
    else:
        x, sr = sf.read(os.path.join(SFX, n + ".wav"), dtype="float64")
    return x.mean(1) if x.ndim > 1 else x


def rms100(x):
    fr = int(0.1 * SR)
    if len(x) <= fr:
        return 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)
    return max(20 * np.log10(np.sqrt((x[i:i + fr] ** 2).mean()) + 1e-9) for i in range(0, len(x) - fr, fr // 2))


def to_rms(x, tgt):
    x = x * 10 ** ((tgt - rms100(x)) / 20)
    cap = 10 ** (-1 / 20)
    return cap * np.tanh(x / cap) if np.abs(x).max() > cap else x


def shift(x, p):
    return np.interp(np.arange(int(len(x) / p)) * p, np.arange(len(x)), x)


def crisp(x, length=0.11, boost=0.9):
    """抬 2–6 kHz（脆）+ 收短尾部"""
    hp = sosfilt(butter(2, 2200, btype="high", fs=SR, output="sos"), x)
    y = x + boost * hp
    y = y[:int(length * SR)].copy()
    fo = int(0.03 * SR)
    y[-fo:] *= np.linspace(1, 0, fo)
    return y


def stack(x, times, gains, pitches):
    mix = np.zeros(int((max(times) + len(x) / SR + 0.25) * SR))
    for t, g, p in zip(times, gains, pitches):
        y = shift(x, p) * g
        s = int(t * SR)
        mix[s:s + len(y)] += y
    return mix


def burst(x, n, g0, g1, a, b, last=0.0):
    times, t = [], 0.0
    for k in range(n):
        times.append(t)
        t += a + (b - a) * (k / max(1, n - 1))
    gains = [g0 + (g1 - g0) * k / max(1, n - 1) for k in range(n)]
    pitches = list(RNG.uniform(0.94, 1.06, n))
    if last > 0:
        gains[-1] *= 10 ** (last / 20)
        pitches[-1] = 0.82
    return stack(x, times, gains, pitches)


def click():
    n = int(0.05 * SR)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * 2200 * t) * np.exp(-t * 90) * 0.5 + RNG.normal(0, 1, n) * np.exp(-t * 400) * 0.35


def build(key):
    names = SETS[key]
    atk = [to_rms(crisp(rd_ogg(g)), -9.5) for g in names]
    main = crisp(rd_ogg(names[1]))
    # 命中（10-26 修：原来叠了一声「枪声前 35 ms 升调」的弹着点脆响，听起来像第二声枪响 = 用户听到的「新旧枪声叠在一起」）：
    # 只留金属叮（首次接入的 Kenney impactMetal_light，4 kHz 低通、0.12 s），响度抬到 -11 dBFS，不再带任何枪声成分
    ping = rd_wav("op_exusiai_hit", "547edc5f1")
    hit = to_rms(ping[:int(0.14 * SR)].copy(), -11.0)
    s1 = np.concatenate([click(), np.zeros(int(0.06 * SR)), burst(main, 3, 0.85, 0.85, 0.075, 0.075)])
    s2 = burst(main, 6, 0.7, 1.0, 0.1, 0.055)
    s3 = burst(main, 18, 0.75, 1.0, 0.065, 0.038, last=3.0)
    big = np.concatenate([burst(main, 9, 0.75, 0.95, 0.055, 0.042), np.zeros(int(0.12 * SR)), shift(main, 0.78) * 1.4])
    return {"atk": atk[0], "atk_b": atk[1], "atk_c": atk[2], "hit": hit,
            "s1": to_rms(s1, -10.0), "s2": to_rms(s2, -9.0), "s3": to_rms(s3, -8.0), "big": to_rms(big, -9.5)}


def now_set():
    return {k: rd_wav("op_exusiai_" + k, "ae4f5be91") for k in ("atk", "atk_b", "atk_c", "hit", "s1", "s2", "s3", "big")}


VOL = {"atk": -11.0, "hit": -12.0, "s1": -4.0, "s2": -4.0, "s3": -2.0, "big": -6.0}   # 游戏里的播放音量：OP_VOL + OP_DB（命中 -2）


def gain(x, db):
    return x * 10 ** (db / 20)


def demo(S, tag):
    """6 秒战斗片段：普攻 3 次 / 秒（三条轮换，音高 ±9%）、命中约 2.5 次 / 秒，加背景（击杀 / 拾取 / 通用命中）；按游戏里的播放音量混"""
    r = np.random.default_rng(7)
    L = 6.0
    mix = np.zeros(int((L + 1.2) * SR))
    names = ["atk", "atk_b", "atk_c"]
    k = 0
    t = 0.2
    while t < L:
        x = shift(S[names[k % 3]], r.uniform(0.91, 1.09))
        s = int(t * SR)
        mix[s:s + len(x)] += gain(x, VOL["atk"])
        k += 1
        t += 0.35
    t = 0.45
    while t < L:
        x = shift(S["hit"], r.uniform(0.9, 1.1))
        s = int(t * SR)
        mix[s:s + len(x)] += gain(x, VOL["hit"])
        t += r.uniform(0.25, 0.55)
    for nm, db, rate in (("kill", -8.0, 4.0), ("pickup", -8.0, 5.0), ("hit", -6.0, 2.0)):
        x = rd_wav(nm)
        t = r.uniform(0, 0.3)
        while t < L:
            s = int(t * SR)
            mix[s:s + len(x)] += gain(x, db)
            t += r.exponential(1.0 / rate)
    return mix


def skills_demo(S):
    gap = np.zeros(int(0.5 * SR))
    parts = []
    for k in ("s1", "s2", "s3", "big"):
        parts += [gain(S[k], VOL[k]), gap]
    return np.concatenate(parts)


def wr(path, x):
    peak = np.abs(x).max()
    if peak > 0.95:
        x = x / peak * 0.95
    sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")


def apply(key):
    S = build(key)
    for k, v in S.items():
        sf.write(os.path.join(SFX, "op_exusiai_%s.wav" % k), v.astype(np.float32), SR, subtype="PCM_16")
    print("已写入", key, {k: round(rms100(v), 1) for k, v in S.items()})


def main():
    if "--apply" in sys.argv:
        apply(sys.argv[sys.argv.index("--apply") + 1] if len(sys.argv) > sys.argv.index("--apply") + 1 else "after")
        return
    os.makedirs(OUT, exist_ok=True)
    sets = {"before": now_set(), "after": build("after"), "alt": build("alt")}
    for tag, S in sets.items():
        wr(os.path.join(OUT, tag + "_combat.ogg"), demo(S, tag))
        wr(os.path.join(OUT, tag + "_skills.ogg"), skills_demo(S))
        for k in ("atk", "atk_b", "atk_c", "hit"):
            wr(os.path.join(OUT, "%s_%s.ogg" % (tag, k)), S[k])
        print(tag, {k: round(rms100(v), 1) for k, v in S.items()})


if __name__ == "__main__":
    main()
