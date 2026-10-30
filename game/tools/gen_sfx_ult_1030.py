"""终结技专属音效候选（docs/205 §3，10-30 用户「需要专属音效」）：20 人 × 3 套，每套 charge 蓄力 / cast 出手 / impact 冲击，
连续打击类另有 hit（每次命中按节流响一下）。A = 厚重写实（程序合成的物理质感）、B = 能量感（更亮、带音高）、
C = 现有音色加工（该干员现有 op_<干员>_* 技能 / 命中音降调、叠低频重做）。全部程序合成或加工本仓库现有合成 / CC0 文件，不含原作音频。

运行：python game/tools/gen_sfx_ult_1030.py            → <主仓库>/build/ult_sfx/<A|B|C>/ult_<干员>_<槽>.wav
      python game/tools/gen_sfx_ult_1030.py --apply A [--pick texas=B,exusiai=C]   → 写进 game/audio/sfx/（每人按 pick 取那一套，其余用 --apply 那套）
响度：峰值 -1 dBFS，最响 100 ms RMS 按槽对齐（charge -14 / cast -12 / impact -9 / hit -15 dBFS），游戏里的播放音量在 data/ult_audio.json。
"""
import argparse, os, subprocess, wave
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, "gen_sfx_ops.py"), encoding="utf-8").read()
exec(src[:src.index("SAVED = []")])   # 工具函数（T / N / bp / lp / hp / env / swell / tone / sweep_noise / bell / metal / thud / crackle / verb / at / pad / sat）
exec(src[src.index("def chain("):src.index("def whisper(")])   # chain / chord
exec(src[src.index("def whisper("):].split("\n\n\n")[0])   # whisper
SFX = os.path.join(HERE, "..", "audio", "sfx")
try:
    common = subprocess.run(["git", "rev-parse", "--git-common-dir"], cwd=HERE, capture_output=True, text=True).stdout.strip()
    ROOT = os.path.dirname(os.path.abspath(os.path.join(HERE, common)))
except OSError:
    ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "build", "ult_sfx")
RMS = {"charge": -14.0, "cast": -12.0, "impact": -9.0, "hit": -15.0}


# ---------------------------------------------------------------- 本批工具
def ld(name):
    """读现有音效（单声道 float）"""
    x, sr = sf.read(os.path.join(SFX, name + ".wav"))
    x = x if x.ndim == 1 else x.mean(1)
    if sr != SR:
        x = np.interp(np.arange(0, len(x), sr / SR), np.arange(len(x)), x)
    return x / (np.abs(x).max() + 1e-9)


def pitch(x, k):
    """变速变调（k < 1 更低更长）"""
    return np.interp(np.arange(0, len(x) - 1, k), np.arange(len(x)), x)


def fit(x, sec):
    """循环铺满 / 截到 sec 秒"""
    n = int(sec * SR)
    return np.tile(x, n // len(x) + 1)[:n]


def rev(x):
    return x[::-1].copy()


def sub(sec, f0=70, f1=32, decay=4.0):
    """低频下沉（冲击的体感）"""
    return tone(sec, f0, f1) * env(sec, 0.002, decay)


def burst(sec, cut=3000, decay=8.0):
    """爆炸噪声体"""
    return lp(N(sec), cut) * env(sec, 0.0008, decay)


def rumble(sec, cut=220, decay=3.0):
    return lp(N(sec), cut, 4) * env(sec, 0.02, decay) * 2.5


def riser(sec, f0, f1, kind="saw", cut=4000):
    """蓄力上扬：音高上扫 + 噪声涌起"""
    return lp(tone(sec, f0, f1, kind), cut) * swell(sec, 0.92) * 0.5 + bp(N(sec), 800, 6000) * swell(sec, 0.95) * 0.25


def suck(sec, lo=300, hi=5000):
    """反向吸入（蓄力）：倒放的爆炸噪声"""
    return rev(sweep_noise(sec, hi, lo, 0.5) * env(sec, 0.002, 4.0 / sec))


def whoosh(sec, f0, f1, q=0.5):
    return sweep_noise(sec, f0, f1, q) * swell(sec, 0.5)


def slash(sec=0.18, f0=5200, f1=1400):
    return pad(sweep_noise(sec, f0, f1, 0.3) * env(sec, 0.002, 14), hp(N(0.01), 4000) * env(0.01, 0.0002, 200) * 0.6)


def ring(sec, f, decay=3.0, bright=0.6):
    return metal(sec, f, decay, bright=bright)


def splash(sec, cut=5000, decay=5.0):
    """水花：带通噪声 + 气泡颗粒"""
    x = bp(N(sec), 400, cut) * env(sec, 0.005, decay)
    return x + crackle(sec, 140, 1200, 4000, decay) * 0.4


def crack(sec=0.6, decay=6.0):
    """地裂 / 碎石：低频闷响 + 砾石噼啪"""
    return pad(rumble(sec, 180, decay) * 0.8, crackle(sec, 220, 900, 5000, decay) * 0.7, thud(sec, 90, 40, decay * 2))


def zap(sec, f0, f1):
    """电弧 / 光束：方波扫频过带通 + 噪声颤动"""
    t = T(sec)
    x = tone(sec, f0, f1, "sq") * (0.7 + 0.3 * np.sin(2 * np.pi * 37 * t))
    return bp(x, 300, 7000) * 0.5 + bp(N(sec), 2000, 9000) * 0.15


def drone(sec, f, mod=0.5):
    t = T(sec)
    return np.sin(2 * np.pi * f * t + 2.5 * np.sin(2 * np.pi * f * 2.01 * t)) * (0.8 + 0.2 * np.sin(2 * np.pi * mod * t))


def seq(parts):
    """[(秒, 片段), …] 叠起来"""
    return pad(*[at(x, s) for s, x in parts])


def fadeio(x, a=0.01, r=0.08):
    ai, ri = int(a * SR), int(r * SR)
    x = x.copy()
    if ai:
        x[:ai] *= np.linspace(0, 1, ai)
    if ri and ri < len(x):
        x[-ri:] *= np.linspace(1, 0, ri)
    return x


def rms100(x):
    w = int(0.1 * SR)
    if len(x) <= w:
        return np.sqrt(np.mean(x ** 2) + 1e-12)
    c = np.cumsum(np.concatenate([[0], x ** 2]))
    return np.sqrt(np.max(c[w:] - c[:-w]) / w + 1e-12)


CAP = {"charge": 1.0, "impact": 1.6}   # 蓄力取最后 1 秒（上扬在尾）、冲击取前 1.6 秒


def write(path, x, slot):
    x = hp(x, 35, 1)
    if slot in CAP and len(x) > CAP[slot] * SR:
        n = int(CAP[slot] * SR)
        x = x[-n:] if slot == "charge" else x[:n]
    nz = np.where(np.abs(x) > np.abs(x).max() * 0.004)[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.03 * SR))]
    x = fadeio(x, 0.002, min(0.05, len(x) / SR / 4))
    x = x / (np.abs(x).max() + 1e-9)
    g = 10 ** (RMS[slot] / 20) / rms100(x)   # 对齐响度
    x = x * g
    pk = np.abs(x).max()
    if pk > 0.89:   # 软限幅到 -1 dBFS
        x = np.tanh(x / pk * 1.6) / np.tanh(1.6) * 0.89
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    return len(x) / SR


# ---------------------------------------------------------------- 20 人（docs/198 §4）
# 每个函数返回 {槽: 波形}；v = "A" / "B" / "C"
def texas(v):
    """剑雨：先连闪画刀痕（蓄力时刀刃出鞘的颤鸣），停半拍一齐斩开，再沿刀痕落剑雨"""
    if v == "A":
        ch = pad(ring(0.8, 1900, 2.5, 0.5) * swell(0.8, 0.9) * 0.6, suck(0.7, 1500, 7000) * 0.6)
        ca = seq([(i * 0.07, slash(0.14, 6000 - i * 400, 1800)) for i in range(6)])
        im = pad(seq([(0, slash(0.3, 7000, 900)), (0.01, slash(0.3, 5000, 700) * 0.8)]), ring(1.2, 1250, 2.2, 0.55) * 0.5, sub(0.6, 90, 40, 6) * 0.7, burst(0.4, 2500, 10) * 0.5)
        hi = pad(ring(0.25, 2400, 14, 0.5) * 0.6, hp(N(0.02), 3000) * env(0.02, 0.0002, 160))
    elif v == "B":
        ch = pad(riser(0.8, 600, 2400, "tri", 6000), bell(0.8, 1568, 3, 2.0, 1.0) * swell(0.8, 0.9) * 0.3)
        ca = seq([(i * 0.07, zap(0.08, 3000 - i * 200, 1200) * env(0.08, 0.001, 30)) for i in range(6)])
        im = pad(zap(0.35, 4000, 300) * env(0.35, 0.001, 8), bell(1.0, 784, 3, 3.0, 2.0) * 0.4, sub(0.6, 110, 40, 5) * 0.8, burst(0.5, 6000, 9) * 0.4)
        hi = bell(0.18, 2093, 20, 3.5, 1.5) * 0.7
    else:
        a = ld("op_texas_atk")
        ch = pad(rev(pitch(a, 0.6)) * 0.7, ring(0.7, 1700, 3, 0.4) * swell(0.7, 0.9) * 0.4)
        ca = seq([(i * 0.07, pitch(a, 1.1 - i * 0.05) * 0.8) for i in range(6)])
        im = pad(pitch(a, 0.5), pitch(ld("op_texas_hit"), 0.6) * 0.8, sub(0.6, 90, 40, 6) * 0.8)
        hi = pitch(ld("op_texas_hit"), 1.2) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def exusiai(v):
    """连射：锁定滴答 → 上膛 → 2.5 秒爆裂弹（hit 每发一枪）→ 最后一发收尾"""
    if v == "A":
        ch = seq([(i * 0.12, bell(0.08, 2637, 30, 1.0, 0.3) * 0.4) for i in range(5)] + [(0, riser(0.7, 200, 900, "saw", 2500) * 0.6)])
        ca = pad(metal(0.12, 900, 30, bright=0.5), at(metal(0.1, 1300, 35, bright=0.5), 0.09), at(thud(0.1, 200, 120, 30) * 0.5, 0.09))
        im = pad(burst(0.6, 3500, 9), sub(0.6, 100, 40, 6), crackle(0.5, 200, 1500, 6000, 7) * 0.6)
        hi = pad(ld("op_exusiai_atk") * 0.9, at(burst(0.12, 2500, 30) * 0.5, 0.02))
    elif v == "B":
        ch = pad(riser(0.7, 400, 1800, "sq", 3500), seq([(i * 0.1, bell(0.07, 3136, 30, 1.0, 0.2) * 0.4) for i in range(7)]))
        ca = pad(zap(0.18, 600, 2200) * env(0.18, 0.001, 12), metal(0.12, 1100, 30, bright=0.5) * 0.7)
        im = pad(zap(0.4, 2500, 200) * env(0.4, 0.001, 7), burst(0.5, 6000, 9) * 0.7, sub(0.5, 120, 40, 6))
        hi = pad(ld("op_exusiai_atk_b") * 0.8, bell(0.1, 1760, 30, 2.0, 1.0) * 0.25)
    else:
        ch = pad(rev(pitch(ld("op_exusiai_s3"), 0.8)) * 0.8, riser(0.6, 300, 1200, "saw", 3000) * 0.4)
        ca = ld("op_exusiai_s2")
        im = pad(pitch(ld("op_exusiai_big"), 0.7), sub(0.6, 100, 40, 6) * 0.8)
        hi = pad(ld("op_exusiai_atk_c"), pitch(ld("op_exusiai_hit"), 0.9) * 0.5)
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def skalter(v):
    """吐息光束：海嗣升起张口聚光 → 粗激光慢扫一整圈（3.4 秒，cast 带整条光束声）→ 收尾大爆；沿线连爆走 hit"""
    sweep = 3.8
    if v == "A":
        ch = pad(drone(0.9, 55) * swell(0.9, 0.9) * 0.8, suck(0.8, 200, 3000) * 0.6, whisper(0.9, 600, 1800) * swell(0.9, 0.8) * 0.3)
        beam = pad(lp(N(sweep), 900, 4) * 1.6, drone(sweep, 82, 0.8) * 0.5, bp(N(sweep), 2000, 5000) * 0.15) * np.clip(T(sweep) / 0.15, 0, 1) * np.clip((sweep - T(sweep)) / 0.3, 0, 1)
        ca = pad(burst(0.4, 2000, 8) * 0.9, beam * 0.8)
        im = pad(burst(1.0, 2500, 5), sub(1.0, 70, 28, 3), rumble(1.2, 200, 2.5), splash(0.8, 3000, 5) * 0.4)
        hi = pad(burst(0.3, 1800, 14) * 0.8, thud(0.2, 120, 50, 18))
    elif v == "B":
        ch = pad(chord(0.9, [220, 277, 330], "tri") * swell(0.9, 0.9) * 0.8, riser(0.9, 110, 660, "saw", 3000) * 0.6)
        t = T(sweep)
        beam = (bp(tone(sweep, 330, 300, "saw"), 200, 4000) * 0.4 + chord(sweep, [165, 247], "tri") * 0.5 + bp(N(sweep), 3000, 8000) * 0.12) * (0.85 + 0.15 * np.sin(2 * np.pi * 9 * t))
        beam *= np.clip(t / 0.1, 0, 1) * np.clip((sweep - t) / 0.3, 0, 1)
        ca = pad(zap(0.3, 2400, 400) * env(0.3, 0.001, 9), beam)
        im = pad(zap(0.6, 2000, 100) * env(0.6, 0.001, 5), chord(1.0, [110, 165, 220], "saw") * env(1.0, 0.002, 3) * 0.5, sub(1.0, 80, 28, 3), burst(0.8, 5000, 6) * 0.5)
        hi = pad(bell(0.25, 880, 12, 1.5, 2.0) * 0.4, burst(0.2, 3000, 18) * 0.6)
    else:
        s3 = ld("op_skadi_s3") if os.path.exists(os.path.join(SFX, "op_skadi_s3.wav")) else ld("skill")
        ch = pad(rev(pitch(s3, 0.7)) * 0.7, drone(0.8, 55) * swell(0.8, 0.9) * 0.5)
        beam = pitch(ld("cue_beam_start"), 0.8)
        lp_ = np.tile(beam, int(sweep * SR / len(beam)) + 1)[:int(sweep * SR)] * np.clip((sweep - T(sweep)) / 0.3, 0, 1)
        ca = pad(lp_ * 0.7, lp(N(sweep), 700, 4) * 1.0 * np.clip((sweep - T(sweep)) / 0.3, 0, 1))
        im = pad(pitch(ld("ishar_land_break"), 0.85) if os.path.exists(os.path.join(SFX, "ishar_land_break.wav")) else pitch(ld("boom"), 0.6), sub(0.9, 70, 28, 3))
        hi = pitch(ld("cue_beam_hit"), 0.9) * 0.8
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def kaltsit(v):
    """Mon3tr 冲锋 → 身体发红发白（熔毁蓄压）→ 三圈真实伤害依次炸开（hit 每圈）"""
    if v == "A":
        ch = pad(drone(0.9, 55) * swell(0.9, 0.9), riser(0.9, 150, 900, "saw", 2500) * 0.5)
        ca = pad(whoosh(0.4, 600, 2500), rip(0.2, 4200, 1500) * 0.7, at(thud(0.15, 150, 70, 20) * 0.6, 0.25))
        im = pad(burst(0.9, 3000, 6), sub(0.9, 90, 30, 4), np.sin(2 * np.pi * 220 * T(0.9) + 6 * env(0.9, 0.001, 8) * np.sin(2 * np.pi * 330 * T(0.9))) * env(0.9, 0.001, 5) * 0.3)
        hi = pad(burst(0.35, 2500, 10) * 0.8, sub(0.35, 80, 35, 8) * 0.8)
    elif v == "B":
        ch = pad(tone(0.9, 300, 2400, "sq") * swell(0.9, 0.95) * 0.12, drone(0.9, 110, 3.0) * swell(0.9, 0.9) * 0.6, bell(0.9, 1318, 3, 1.0, 0.2) * swell(0.9, 0.9) * 0.2)
        ca = pad(zap(0.35, 500, 2600) * swell(0.35, 0.6), rip(0.18, 4800, 1800) * 0.6)
        im = pad(zap(0.5, 3000, 200) * env(0.5, 0.001, 6), burst(0.9, 5000, 6) * 0.8, sub(0.9, 100, 30, 4), bell(1.0, 659, 3, 3.0, 2.5) * 0.25)
        hi = pad(zap(0.2, 1800, 300) * env(0.2, 0.001, 14) * 0.6, burst(0.3, 4000, 12) * 0.6)
    else:
        ch = pitch(ld("op_kaltsit_s3"), 0.8)
        ca = pad(pitch(ld("op_kaltsit_atk"), 0.7), whoosh(0.35, 500, 2000) * 0.5)
        im = pad(pitch(ld("op_kaltsit_big"), 0.7), sub(0.9, 80, 30, 4) * 0.7)
        hi = pitch(ld("op_kaltsit_big"), 1.1) * 0.7
    # d61028742 起 Mon3tr 先跃到落点再蓄力 0.6 秒才爆（出手到冲击实测 0.9 秒）：出手音 = 跃起 + 落地一下 + 0.6 秒蓄压，尾巴正好接冲击
    pre = {"A": riser(0.6, 120, 1100, "saw", 3000) + drone(0.6, 55) * swell(0.6, 0.95) * 0.6,
           "B": tone(0.6, 400, 3200, "sq") * swell(0.6, 0.97) * 0.12 + bell(0.6, 1760, 1.0, 1.0, 0.2) * swell(0.6, 0.95) * 0.3 + drone(0.6, 110, 6.0) * swell(0.6, 0.95) * 0.5,
           "C": fit(pitch(ld("op_kaltsit_s3"), 1.2), 0.6) * swell(0.6, 0.95)}[v]
    ca = seq([(0, ca[:int(0.3 * SR)]), (0.28, thud(0.2, 160, 60, 18) * 0.7), (0.3, pre * 0.8)])
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def ulpianus(v):
    """巨锚：掷锚（锁链哗啦）→ 沿锁链冲过去 → 落地裂地四圈（hit 每圈碎石）"""
    if v == "A":
        ch = pad(heavy_chain(0.8) * 0.7, rumble(0.9, 150, 1.0) * swell(0.9, 0.9) * 0.6)
        ca = pad(whoosh(0.5, 300, 1400) * 0.8, heavy_chain(0.5, 12) * 0.8)
        im = pad(thud(0.9, 80, 30, 4) * 1.0, crack(1.1, 3.5), ring(1.0, 180, 3, 0.5) * 0.4)
        hi = crack(0.4, 9)
    elif v == "B":
        ch = pad(drone(0.9, 41, 0.3) * swell(0.9, 0.9), heavy_chain(0.8) * 0.5, whisper(0.9, 500, 1500) * swell(0.9, 0.8) * 0.3)
        ca = pad(sweep_noise(0.5, 200, 2000, 0.4) * swell(0.5, 0.7), heavy_chain(0.5, 14) * 0.6, splash(0.4, 2500, 7) * 0.4)
        im = pad(sub(1.0, 60, 25, 3) * 1.2, burst(0.8, 1800, 5), splash(0.9, 2500, 4) * 0.5, crack(0.9, 4) * 0.6)
        hi = pad(burst(0.3, 1500, 12), splash(0.25, 2500, 12) * 0.5)
    else:
        ch = pitch(ld("ulp_charge_loop"), 0.85)
        ca = pad(ld("op_ulpianus_s1"), ld("ulp_release") * 0.6)
        im = pad(pitch(ld("op_ulpianus_big"), 0.75), sub(0.9, 70, 28, 3) * 0.8)
        hi = pitch(ld("op_ulpianus_big"), 1.2) * 0.6
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def skadi(v):
    """巨剑下劈 → 劈开处立起一道大浪，0.8 秒推过屏幕"""
    if v == "A":
        ch = pad(whoosh(0.8, 300, 1200) * 0.6, ring(0.8, 220, 2, 0.5) * swell(0.8, 0.9) * 0.5, lp(N(0.8), 400) * swell(0.8, 0.9) * 0.8)
        ca = pad(sweep_noise(0.3, 2000, 300, 0.5) * env(0.3, 0.003, 8), thud(0.3, 100, 40, 10))
        wave_ = lp(N(1.4), 2500, 3) * swell(1.4, 0.35) + splash(1.4, 4000, 2.5) * 0.4
        im = pad(sub(0.8, 80, 30, 4), burst(0.5, 2500, 8) * 0.7, wave_ * 0.9)
        hi = splash(0.25, 4000, 14) * 0.8
    elif v == "B":
        ch = pad(chord(0.8, [147, 220, 294], "tri") * swell(0.8, 0.9) * 0.6, riser(0.8, 200, 800, "saw", 2000) * 0.4)
        ca = pad(sweep_noise(0.3, 3000, 400, 0.4) * env(0.3, 0.002, 9), ring(0.6, 330, 4, 0.5) * 0.5)
        wave_ = bp(N(1.3), 300, 6000) * swell(1.3, 0.3) + chord(1.3, [73, 110], "saw") * swell(1.3, 0.3) * 0.3
        im = pad(sub(0.8, 90, 30, 4), wave_)
        hi = pad(splash(0.2, 5000, 16) * 0.6, bell(0.15, 1175, 20, 1.5, 1.0) * 0.2)
    else:
        ch = rev(pitch(ld("op_skadi_s2"), 0.7)) * 0.8
        ca = pitch(ld("op_skadi_s2"), 0.8)
        im = pad(pitch(ld("op_skadi_big"), 0.7), lp(N(1.2), 2000, 3) * swell(1.2, 0.3) * 0.6)
        hi = pitch(ld("op_skadi_hit"), 0.8) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def gladiia(v):
    """海渊漩涡：1.2 秒越转越快地把敌人拖到中心（cast 带漩涡声）→ 潮水从中心爆开"""
    vx = 1.4
    t = T(vx)
    if v == "A":
        ch = pad(lp(N(0.8), 600) * swell(0.8, 0.9), whoosh(0.8, 200, 900) * 0.5)
        swirl = bp(N(vx), 300, 2500) * (0.6 + 0.4 * np.sin(2 * np.pi * (2 + 6 * t / vx) * t)) * swell(vx, 0.9)
        ca = pad(swirl, lp(N(vx), 300, 3) * swell(vx, 0.9) * 1.2)
        im = pad(splash(1.0, 4000, 4) * 0.9, sub(0.9, 80, 30, 4), burst(0.6, 2500, 7) * 0.6)
        hi = splash(0.2, 3000, 18) * 0.5
    elif v == "B":
        ch = pad(chord(0.8, [196, 233, 294], "tri") * swell(0.8, 0.9) * 0.5, suck(0.8, 300, 3000) * 0.5)
        swirl = bp(tone(vx, 200, 900, "saw"), 200, 3000) * 0.3 * swell(vx, 0.95) + bp(N(vx), 500, 4000) * (0.6 + 0.4 * np.sin(2 * np.pi * (3 + 9 * t / vx) * t)) * swell(vx, 0.9) * 0.6
        ca = swirl
        im = pad(splash(1.0, 6000, 4), zap(0.4, 1500, 150) * env(0.4, 0.001, 6) * 0.6, sub(0.9, 90, 30, 4))
        hi = bell(0.15, 1397, 25, 1.5, 1.0) * 0.3
    else:
        s3 = ld("op_gladiia_s3") if os.path.exists(os.path.join(SFX, "op_gladiia_s3.wav")) else ld("tentacle")
        ch = rev(pitch(s3, 0.7)) * 0.7
        ca = pad(fit(pitch(s3, 0.8), vx) * swell(vx, 0.9), lp(N(vx), 300, 3) * swell(vx, 0.9))
        im = pad(pitch(ld("boom"), 0.7) * 0.8, splash(0.9, 4000, 4) * 0.7)
        hi = splash(0.2, 3000, 18) * 0.5
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def angelina(v):
    """重力奇点：0.6 秒吸起悬空 → 停 0.3 秒 → 全部砸向地面"""
    if v == "A":
        ch = pad(suck(0.9, 150, 2500) * 0.7, drone(0.9, 49, 0.4) * swell(0.9, 0.9) * 0.6)
        ca = pad(tone(0.9, 80, 400, "tri") * swell(0.9, 0.8) * 0.5, sweep_noise(0.9, 400, 2500, 0.5) * swell(0.9, 0.8) * 0.5)
        im = pad(thud(0.8, 90, 30, 5) * 1.2, crack(0.9, 4.5), burst(0.5, 2000, 8) * 0.5)
        hi = thud(0.2, 140, 60, 20) * 0.7
    elif v == "B":
        t = T(0.9)
        ch = pad(chord(0.9, [262, 311, 392], "tri") * swell(0.9, 0.9) * 0.6, np.sin(2 * np.pi * 70 * t + 3 * np.sin(2 * np.pi * 3 * t)) * swell(0.9, 0.9) * 0.6)
        ca = pad(tone(0.9, 300, 1200, "sq") * swell(0.9, 0.8) * 0.12, bell(0.9, 1047, 2, 1.0, 0.5) * swell(0.9, 0.8) * 0.3, rev(burst(0.6, 4000, 6)) * 0.4)
        im = pad(zap(0.5, 1200, 80) * env(0.5, 0.001, 6) * 0.8, sub(0.9, 110, 28, 4) * 1.1, burst(0.7, 4000, 6) * 0.6)
        hi = bell(0.2, 523, 12, 2.0, 1.0) * 0.4
    else:
        s3 = ld("op_angelina_s3") if os.path.exists(os.path.join(SFX, "op_angelina_s3.wav")) else ld("skill")
        ch = rev(pitch(s3, 0.7))
        ca = pitch(s3, 0.6)
        im = pad(pitch(ld("boom"), 0.6), crack(0.8, 5) * 0.6)
        hi = thud(0.2, 140, 60, 20) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def eyjafjalla(v):
    """火山：地面龟裂 0.4 秒 → 巨大火柱喷出 → 熔岩块落满一圈（hit 每块落地）"""
    if v == "A":
        ch = pad(rumble(0.9, 160, 0.5) * swell(0.9, 0.9), crackle(0.9, 120, 900, 4000, 1.0) * swell(0.9, 0.9) * 0.6)
        ca = pad(crack(0.5, 6), lp(N(0.5), 1500) * swell(0.5, 0.95) * 0.6)
        im = pad(burst(1.2, 2200, 3.5) * 1.0, sub(1.0, 70, 28, 3), crackle(1.2, 300, 1200, 6000, 3) * 0.6)
        hi = pad(thud(0.25, 110, 45, 16) * 0.8, crackle(0.25, 200, 1500, 5000, 14) * 0.5)
    elif v == "B":
        ch = pad(riser(0.9, 120, 600, "saw", 1800) * 0.8, crackle(0.9, 200, 1500, 6000, 1.0) * swell(0.9, 0.9) * 0.4)
        ca = pad(sweep_noise(0.6, 300, 3000, 0.6) * swell(0.6, 0.7), tone(0.6, 90, 180, "saw") * swell(0.6, 0.7) * 0.3)
        im = pad(sweep_noise(1.2, 3000, 400, 0.6) * env(1.2, 0.002, 3) * 1.0, sub(1.0, 80, 28, 3), crackle(1.2, 400, 2000, 8000, 3) * 0.6)
        hi = pad(burst(0.2, 4000, 18) * 0.6, crackle(0.2, 300, 2000, 7000, 16) * 0.5)
    else:
        ch = rev(pitch(ld("op_eyjafjalla_s3"), 0.7))
        ca = pitch(ld("op_eyjafjalla_s3"), 0.8)
        im = pad(pitch(ld("op_eyjafjalla_big"), 0.65), sub(1.0, 70, 28, 3) * 0.7)
        hi = pitch(ld("op_eyjafjalla_hit"), 0.85) * 0.8
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def wisadel(v):
    """地毯式炮击：架炮后仰（装填）→ 6 排由近到远推进（hit 每发）→ 余震"""
    def clk(f):
        return pad(metal(0.12, f, 35, bright=0.5) * 0.6, hp(N(0.02), 2000) * env(0.02, 0.0003, 120))
    if v == "A":
        ch = pad(clk(700), at(clk(950), 0.18), at(clk(1200), 0.36), at(metal(0.4, 160, 6, bright=0.5) * 0.6, 0.45), tone(0.9, 45, 70) * swell(0.9, 0.8) * 0.6)
        ca = pad(thud(0.3, 140, 45, 12), burst(0.3, 2500, 14) * 0.8, hp(N(0.04), 2000) * env(0.04, 0.0005, 70) * 0.6)
        im = pad(burst(0.9, 2500, 5) * 1.0, sub(0.9, 80, 28, 3.5), rumble(1.0, 160, 3))
        hi = pad(thud(0.3, 110, 40, 12) * 0.8, burst(0.3, 3500, 12) * 0.7)
    elif v == "B":
        ch = pad(clk(900), at(clk(1300), 0.2), tone(0.9, 2400, 3600) * swell(0.9, 0.9) * 0.06, riser(0.9, 80, 320, "saw", 1500) * 0.5)
        ca = pad(zap(0.25, 1500, 200) * env(0.25, 0.001, 12), thud(0.3, 160, 50, 12))
        im = pad(burst(0.9, 5000, 5), zap(0.5, 1800, 100) * env(0.5, 0.001, 6) * 0.5, sub(0.9, 90, 28, 3.5))
        hi = pad(burst(0.25, 5000, 14) * 0.7, thud(0.25, 130, 45, 14) * 0.6)
    else:
        ch = ld("op_wisadel_s3")
        ca = ld("op_wisadel_atk")
        im = pad(pitch(ld("op_wisadel_big"), 0.75), ld("op_wisadel_quake") * 0.7)
        hi = ld("op_wisadel_hit") * 0.8
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def specter_unchained(v):
    """巨锯：举锯（引擎拉起）→ 围着她转 3 秒（cast 带锯声）；hit 每圈切到"""
    dur = 3.1
    t = T(dur)
    if v == "A":
        ch = pad(tone(0.8, 40, 120, "saw") * swell(0.8, 0.9) * 0.4, metal(0.5, 300, 6, bright=0.5) * 0.4, lp(N(0.8), 800) * swell(0.8, 0.9) * 0.5)
        saw = lp(tone(dur, 120, 140, "saw"), 1800) * (0.7 + 0.3 * np.sin(2 * np.pi * 4 * t)) * 0.5 + bp(N(dur), 1500, 5000) * (0.5 + 0.5 * np.sin(2 * np.pi * 4 * t) ** 2) * 0.3
        ca = saw * np.clip(t / 0.08, 0, 1) * np.clip((dur - t) / 0.25, 0, 1)
        im = pad(rip(0.4, 5000, 900), metal(0.8, 220, 4, bright=0.55) * 0.6, sub(0.6, 90, 35, 5) * 0.8)
        hi = pad(rip(0.12, 4500, 1500) * 0.7, metal(0.15, 900, 25, bright=0.5) * 0.3)
    elif v == "B":
        ch = pad(chord(0.8, [110, 131, 165], "saw") * swell(0.8, 0.9) * 0.3, riser(0.8, 80, 400, "saw", 2000) * 0.5)
        saw = chord(dur, [92, 138], "saw") * 0.4 + bp(N(dur), 2500, 7000) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * 2 * t))) * 0.3
        ca = lp(saw, 4000) * np.clip(t / 0.08, 0, 1) * np.clip((dur - t) / 0.25, 0, 1)
        im = pad(zap(0.4, 3000, 400) * env(0.4, 0.001, 8), metal(0.8, 300, 4, bright=0.6) * 0.5, sub(0.6, 100, 35, 5))
        hi = rip(0.12, 5500, 2000) * 0.7
    else:
        s2 = ld("op_specter_unchained_s3")
        ch = rev(pitch(s2, 0.7)) * 0.7
        a = ld("op_specter_unchained_atk")
        ca = pad(seq([(i * 0.25, pitch(a, 0.85) * 0.8) for i in range(12)]), lp(N(dur), 500, 3) * 0.3 * np.clip((dur - t) / 0.25, 0, 1))
        im = pad(pitch(s2, 0.75), sub(0.6, 90, 35, 5) * 0.7)
        hi = pitch(a, 1.1) * 0.6
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def mizuki(v):
    """巨型触手：地下蠕动 → 破土横扫半圆 → 小触手钻出抓漏网（hit）"""
    if v == "A":
        ch = pad(lp(N(0.9), 300, 3) * swell(0.9, 0.9) * 1.2, whisper(0.9, 400, 1200) * swell(0.9, 0.8) * 0.4, splash(0.9, 1500, 1.5) * swell(0.9, 0.9) * 0.4)
        ca = pad(crack(0.5, 7) * 0.8, sweep_noise(0.6, 250, 1500, 0.5) * swell(0.6, 0.5))
        im = pad(sweep_noise(0.5, 2500, 300, 0.5) * env(0.5, 0.002, 6), sub(0.7, 80, 30, 5), splash(0.6, 2500, 6) * 0.8)
        hi = pad(splash(0.2, 2000, 18) * 0.8, thud(0.15, 160, 70, 25) * 0.5)
    elif v == "B":
        ch = pad(chord(0.9, [185, 196, 277], "tri") * swell(0.9, 0.9) * 0.5, whisper(0.9, 900, 2800) * swell(0.9, 0.8) * 0.4)
        ca = pad(tone(0.6, 60, 180, "saw") * swell(0.6, 0.5) * 0.3, sweep_noise(0.6, 400, 2500, 0.5) * swell(0.6, 0.5))
        im = pad(sweep_noise(0.5, 3500, 400, 0.4) * env(0.5, 0.002, 6), chord(0.8, [92, 98], "saw") * env(0.8, 0.002, 4) * 0.5, sub(0.7, 90, 30, 5))
        hi = pad(bell(0.18, 740, 15, 2.5, 2.0) * 0.4, splash(0.15, 2000, 20) * 0.5)
    else:
        ch = rev(pitch(ld("op_mizuki_s3"), 0.7))
        ca = pitch(ld("tentacle"), 0.6)
        im = pad(pitch(ld("op_mizuki_s3"), 0.6), sub(0.7, 80, 30, 5) * 0.7)
        hi = pitch(ld("op_mizuki_hit"), 0.8)
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def saria(v):
    """砸地重拳：举拳蓄力 0.2 秒 → 一拳砸地、拳风冲击环 → 十道琥珀裂纹一节节炸开（hit）"""
    if v == "A":
        ch = pad(lp(N(0.7), 500) * swell(0.7, 0.95) * 0.9, ring(0.7, 520, 3, 0.4) * swell(0.7, 0.9) * 0.3)
        ca = pad(whoosh(0.25, 500, 1800), thud(0.2, 120, 60, 16) * 0.5)
        im = pad(thud(0.9, 75, 28, 4) * 1.3, crack(1.0, 4), burst(0.4, 2000, 10) * 0.6)
        hi = pad(crackle(0.25, 260, 1500, 6000, 14) * 0.7, thud(0.2, 140, 60, 20) * 0.5)
    elif v == "B":
        ch = pad(chord(0.7, [330, 415, 494], "tri") * swell(0.7, 0.95) * 0.5, riser(0.7, 120, 500, "saw", 1500) * 0.5)
        ca = pad(whoosh(0.25, 800, 3000), bell(0.3, 988, 10, 3.5, 2.0) * 0.3)
        im = pad(thud(0.9, 90, 28, 4) * 1.2, bell(1.0, 659, 3, 3.5, 2.5) * 0.35, burst(0.6, 4000, 7) * 0.6, crackle(0.8, 300, 2000, 8000, 4) * 0.4)
        hi = pad(bell(0.2, 1319, 18, 3.5, 2.0) * 0.4, crackle(0.2, 300, 2000, 7000, 16) * 0.5)
    else:
        ch = rev(pitch(ld("op_saria_s3"), 0.7))
        ca = pitch(ld("op_saria_atk"), 0.7)
        im = pad(pitch(ld("op_saria_hit"), 0.5), crack(0.9, 4) * 0.7, sub(0.8, 80, 28, 4) * 0.8)
        hi = pitch(ld("op_saria_hit"), 0.9) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def suzuran(v):
    """忍冬化作白光瞬身飞出，留下一条斩痕 → 停半拍斩痕炸开"""
    if v == "A":
        ch = pad(bell(0.8, 1760, 2.5, 1.0, 0.3) * swell(0.8, 0.9) * 0.4, whisper(0.8, 1500, 4500) * swell(0.8, 0.9) * 0.4, suck(0.7, 1500, 7000) * 0.4)
        ca = pad(sweep_noise(0.3, 7000, 1500, 0.3) * env(0.3, 0.002, 9), ring(0.5, 2200, 5, 0.5) * 0.3)
        im = pad(seq([(0, slash(0.3, 6500, 900)), (0.03, slash(0.3, 5000, 800) * 0.7)]), burst(0.6, 3500, 7) * 0.8, sub(0.6, 100, 40, 6) * 0.8)
        hi = slash(0.12, 6000, 2500) * 0.6
    elif v == "B":
        ch = pad(chord(0.8, [880, 1109, 1319], "tri") * swell(0.8, 0.9) * 0.4, bell(0.8, 2637, 3, 1.0, 0.2) * swell(0.8, 0.9) * 0.2)
        ca = pad(zap(0.25, 5000, 1500) * env(0.25, 0.001, 10) * 0.7, bell(0.4, 1760, 8, 2.0, 1.0) * 0.4)
        im = pad(zap(0.4, 4000, 300) * env(0.4, 0.001, 7) * 0.7, bell(1.0, 880, 3, 3.0, 2.0) * 0.4, burst(0.6, 6000, 7) * 0.6, sub(0.6, 110, 40, 6) * 0.7)
        hi = bell(0.15, 2349, 25, 2.0, 1.0) * 0.4
    else:
        ch = rev(pitch(ld("op_suzuran_s3"), 0.7)) * 0.8
        ca = pitch(ld("op_irene_atk"), 0.9)
        im = pad(pitch(ld("op_suzuran_s3"), 0.6), burst(0.5, 3000, 8) * 0.6, sub(0.6, 100, 40, 6) * 0.7)
        hi = pitch(ld("op_suzuran_hit"), 0.9) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def logos(v):
    """咒域铺开、敌人头上浮现咒文（0.5 秒）→ 念出一词，标记同时爆裂"""
    if v == "A":
        ch = pad(whisper(0.9, 500, 1600) * swell(0.9, 0.85) * 0.8, drone(0.9, 65, 0.3) * swell(0.9, 0.9) * 0.5)
        ca = pad(seq([(i * 0.05, bell(0.2, 400 + 37 * i, 14, 2.0, 1.5) * 0.3) for i in range(9)]), lp(N(0.6), 900) * swell(0.6, 0.9) * 0.5)
        im = pad(rev(burst(0.25, 3000, 10)) * 0.6, at(pad(burst(0.7, 2500, 6), sub(0.7, 70, 28, 4)), 0.22))
        hi = pad(burst(0.15, 2500, 25) * 0.6, bell(0.1, 330, 30, 2.0, 1.5) * 0.3)
    elif v == "B":
        ch = pad(chord(0.9, [147, 156, 208], "saw") * swell(0.9, 0.9) * 0.35, whisper(0.9, 900, 2800) * swell(0.9, 0.85) * 0.4)
        ca = pad(seq([(i * 0.055, bell(0.3, 659 * (1.06 ** i), 8, 1.5, 2.0) * 0.25) for i in range(9)]))
        im = pad(rev(zap(0.25, 3000, 200)) * 0.5, at(pad(chord(1.0, [73, 78, 104], "saw") * env(1.0, 0.002, 3) * 0.6, burst(0.6, 5000, 7) * 0.7, sub(0.7, 80, 28, 4)), 0.22))
        hi = bell(0.12, 1047, 30, 2.0, 2.0) * 0.4
    else:
        ch = rev(pitch(ld("op_logos_s3"), 0.75))
        ca = ld("op_logos_s1")
        im = pad(pitch(ld("op_logos_big"), 0.7), sub(0.7, 70, 28, 4) * 0.7)
        hi = pitch(ld("op_logos_hit"), 0.85) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def hoshiguma(v):
    """盾「般若」砸进地面、全场嘲讽 → 挡 1.5 秒（盾面发红、裂纹扩大）→ 盾甲反震炸开一大圈"""
    if v == "A":
        ch = pad(metal(0.9, 140, 2, bright=0.55) * 0.6, lp(N(0.9), 400) * swell(0.9, 0.9) * 0.7)
        ca = pad(thud(0.5, 110, 40, 8) * 1.2, metal(1.2, 180, 2.5, bright=0.55) * 0.7, crack(0.6, 6) * 0.5)
        im = pad(metal(1.2, 120, 2.5, bright=0.6) * 0.7, burst(0.9, 2200, 5), sub(0.9, 75, 28, 3.5), crack(0.8, 5) * 0.5)
        hi = pad(metal(0.3, 520, 12, bright=0.5) * 0.6, thud(0.15, 160, 70, 25) * 0.5)
    elif v == "B":
        ch = pad(chord(0.9, [98, 147, 196], "saw") * swell(0.9, 0.9) * 0.35, metal(0.9, 160, 2, bright=0.5) * 0.4)
        ca = pad(thud(0.5, 120, 40, 8), bell(1.2, 220, 2.5, 3.5, 2.5) * 0.4, rumble(1.5, 200, 1.5) * 0.6)
        im = pad(zap(0.5, 1500, 100) * env(0.5, 0.001, 6) * 0.6, bell(1.2, 165, 3, 3.5, 3.0) * 0.4, burst(0.9, 4000, 5) * 0.8, sub(0.9, 90, 28, 3.5))
        hi = bell(0.2, 659, 15, 3.5, 2.0) * 0.4
    else:
        h = ld("op_hoshiguma_hit")
        ch = rev(pitch(h, 0.5)) * 0.7
        ca = pad(pitch(h, 0.55), thud(0.5, 110, 40, 8) * 0.8)
        im = pad(pitch(h, 0.4), burst(0.9, 2200, 5) * 0.8, sub(0.9, 75, 28, 3.5) * 0.8)
        hi = pitch(h, 1.0) * 0.6
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def siege(v):
    """高高跃起（风声上扬）→ 0.6 秒后巨锤砸地，冲击波横扫、碎石飞溅"""
    if v == "A":
        ch = pad(lp(N(0.8), 600) * swell(0.8, 0.9) * 0.7, metal(0.4, 300, 6, bright=0.5) * 0.3)
        ca = sweep_noise(0.7, 400, 2600, 0.5) * swell(0.7, 0.85)
        im = pad(thud(0.9, 70, 26, 4) * 1.3, metal(1.0, 210, 3, bright=0.6) * 0.5, crack(1.0, 4) * 0.8, burst(0.4, 2000, 10) * 0.5)
        hi = crackle(0.3, 260, 1200, 5000, 12) * 0.7
    elif v == "B":
        s1 = horn(0.25, 220) * 0.6
        ch = pad(s1, at(horn(0.5, 330) * 0.7, 0.2))
        ca = sweep_noise(0.7, 600, 3500, 0.5) * swell(0.7, 0.85)
        im = pad(thud(0.9, 80, 26, 4) * 1.2, bell(1.0, 262, 3, 3.5, 2.5) * 0.35, burst(0.7, 4000, 6) * 0.7, crack(0.8, 5) * 0.5)
        hi = pad(crackle(0.25, 260, 1500, 6000, 14) * 0.5, bell(0.15, 1047, 25, 3.5, 1.0) * 0.2)
    else:
        ch = ld("op_siege_s1_soft") if os.path.exists(os.path.join(SFX, "op_siege_s1_soft.wav")) else ld("op_siege_s1")
        ca = pitch(ld("op_siege_s2"), 0.85)
        im = pad(pitch(ld("op_siege_big"), 0.7), crack(0.9, 4) * 0.6)
        hi = pitch(ld("op_siege_hit"), 0.9) * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def irene(v):
    """前方卷起狂风 → 冲进风里连斩 5–6 刀（hit）→ 瞬身回原地 → 手炮一枪在风眼炸开"""
    if v == "A":
        ch = pad(whoosh(0.9, 300, 1500) * 0.8, lp(N(0.9), 500) * swell(0.9, 0.9) * 0.6)
        ca = pad(sweep_noise(1.0, 400, 3000, 0.6) * swell(1.0, 0.4), seq([(0.15 + i * 0.12, slash(0.14, 6000, 1800) * 0.6) for i in range(6)]))
        im = pad(thud(0.2, 160, 60, 20) * 0.6, at(pad(burst(0.8, 2800, 6), sub(0.8, 85, 30, 4)), 0.03))
        hi = slash(0.12, 6000, 2000) * 0.6
    elif v == "B":
        ch = pad(chord(0.9, [294, 370, 440], "tri") * swell(0.9, 0.9) * 0.4, whoosh(0.9, 500, 2500) * 0.6)
        ca = pad(sweep_noise(1.0, 600, 4000, 0.6) * swell(1.0, 0.4), seq([(0.15 + i * 0.12, zap(0.08, 3500, 1200) * env(0.08, 0.001, 30) * 0.5) for i in range(6)]))
        im = pad(bell(0.9, 587, 3, 3.0, 2.0) * 0.4, burst(0.8, 5000, 6), sub(0.8, 95, 30, 4))
        hi = pad(slash(0.1, 7000, 2500) * 0.5, bell(0.1, 1760, 30, 2.0, 1.0) * 0.2)
    else:
        ch = rev(pitch(ld("op_irene_s1"), 0.7))
        ca = pad(pitch(ld("op_irene_s1"), 0.8), seq([(0.15 + i * 0.12, ld("op_irene_atk") * 0.6) for i in range(6)]))
        im = pad(pitch(ld("op_irene_big"), 0.75), sub(0.8, 85, 30, 4) * 0.7)
        hi = ld("op_irene_hit") * 0.7
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def lappland(v):
    """原地狂舞连斩，四圈双刃剑气向四面飞出（间隔 0.25 秒，hit 每圈）"""
    if v == "A":
        ch = pad(seq([(i * 0.15, slash(0.15, 4000, 1500) * 0.4) for i in range(5)]), whisper(0.8, 800, 2400) * swell(0.8, 0.9) * 0.3)
        ca = seq([(i * 0.25, pad(sweep_noise(0.3, 5000, 900, 0.4) * env(0.3, 0.003, 9), ring(0.3, 1700 + 120 * i, 9, 0.5) * 0.3)) for i in range(4)])
        im = pad(slash(0.35, 6500, 800), ring(0.9, 1100, 3, 0.55) * 0.4, sub(0.5, 100, 40, 7) * 0.7)
        hi = slash(0.1, 5500, 2000) * 0.5
    elif v == "B":
        ch = pad(chord(0.8, [233, 277, 349], "saw") * swell(0.8, 0.9) * 0.3, riser(0.8, 300, 1200, "saw", 3500) * 0.4)
        ca = seq([(i * 0.25, pad(zap(0.2, 4000, 800) * env(0.2, 0.001, 12), bell(0.3, 1397 * (1.12 ** i), 10, 2.0, 1.5) * 0.3)) for i in range(4)])
        im = pad(zap(0.35, 4500, 400) * env(0.35, 0.001, 8), bell(0.8, 698, 4, 3.0, 2.0) * 0.4, sub(0.5, 110, 40, 7) * 0.7)
        hi = bell(0.12, 2794, 30, 2.0, 1.0) * 0.3
    else:
        a = ld("op_lappland_atk") if os.path.exists(os.path.join(SFX, "op_lappland_atk.wav")) else ld("swing")
        ch = rev(pitch(a, 0.6)) * 0.7
        ca = seq([(i * 0.25, pitch(a, 0.9 + 0.05 * i)) for i in range(4)])
        im = pad(pitch(a, 0.55), ring(0.8, 1100, 3, 0.5) * 0.4, sub(0.5, 100, 40, 7) * 0.7)
        hi = pitch(a, 1.2) * 0.5
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def lumen(v):
    """灯塔光柱升起（镜头上推）→ 光圈扩散灼烧 → 光柱持续 2 秒后熄灭（cast 带光柱嗡鸣）"""
    col = 2.4
    t = T(col)
    if v == "A":
        ch = pad(bell(0.9, 523, 2, 1.0, 0.3) * swell(0.9, 0.9) * 0.5, riser(0.9, 130, 520, "tri", 2500) * 0.5)
        hum = (drone(col, 131, 1.5) * 0.4 + bp(N(col), 1500, 5000) * 0.12) * np.clip(t / 0.2, 0, 1) * np.clip((col - t) / 0.4, 0, 1)
        ca = pad(rev(burst(0.3, 4000, 8)) * 0.5, hum)
        im = pad(sweep_noise(0.7, 500, 4000, 0.6) * env(0.7, 0.002, 5), sub(0.7, 90, 35, 5), bell(1.0, 392, 3, 1.0, 0.5) * 0.4)
        hi = pad(bp(N(0.15), 2000, 6000) * env(0.15, 0.002, 20) * 0.5, bell(0.12, 1568, 30, 1.0, 0.3) * 0.2)
    elif v == "B":
        ch = pad(chord(0.9, [523, 659, 784], "tri") * swell(0.9, 0.9) * 0.5, bell(0.9, 1568, 2, 1.0, 0.3) * swell(0.9, 0.9) * 0.3)
        hum = chord(col, [262, 392, 523], "tri") * 0.5 * np.clip(t / 0.15, 0, 1) * np.clip((col - t) / 0.4, 0, 1)
        ca = pad(bell(0.8, 1047, 3, 1.0, 0.5) * 0.4, hum)
        im = pad(chord(1.0, [196, 294, 392], "saw") * env(1.0, 0.002, 3) * 0.5, sweep_noise(0.6, 800, 5000, 0.5) * env(0.6, 0.002, 6) * 0.6, sub(0.7, 100, 35, 5) * 0.8)
        hi = bell(0.15, 2093, 25, 1.0, 0.3) * 0.3
    else:
        ch = rev(pitch(ld("op_lumen_s3"), 0.75)) * 0.8
        ca = pad(pitch(ld("izu_lamp_lit"), 0.8) * 0.6 if os.path.exists(os.path.join(SFX, "izu_lamp_lit.wav")) else ld("beacon_lit") * 0.6, (drone(col, 131, 1.5) * 0.4) * np.clip(t / 0.2, 0, 1) * np.clip((col - t) / 0.4, 0, 1))
        im = pad(pitch(ld("op_lumen_big"), 0.75), sub(0.7, 90, 35, 5) * 0.6)
        hi = pitch(ld("op_lumen_hit"), 0.9) * 0.6
    return {"charge": ch, "cast": ca, "impact": im, "hit": hi}


def rip(sec, f0, f1):
    return sweep_noise(sec, f0, f1, 0.25) * env(sec, 0.003, 22)


def horn(sec, f, a=0.03):
    x = tone(sec, f, f, "saw") + 0.5 * tone(sec, f * 1.003, f * 1.003, "saw")
    x = lp(x, f * 4.5, 2)
    return x * env(sec, a, 1.5) * np.clip(T(sec)[::-1] / 0.08, 0, 1)


def heavy_chain(sec, n=10, f0=520, f1=1300, decay=26.0):
    """粗锚链（低一些、钝一些，同 gen_sfx_candidates）"""
    return lp(chain(sec, n, f0, f1, decay), 3000)


OPS = [texas, exusiai, skalter, kaltsit, ulpianus, skadi, gladiia, angelina, eyjafjalla, wisadel, specter_unchained, mizuki,
       saria, suzuran, logos, hoshiguma, siege, irene, lappland, lumen]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", default="")
    ap.add_argument("--pick", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = set(a.only.split(",")) if a.only else None
    pick = dict(kv.split("=") for kv in a.pick.split(",") if kv)
    for v in "ABC":
        os.makedirs(os.path.join(OUT, v), exist_ok=True)
    for f in OPS:
        op = f.__name__
        if only and op not in only:
            continue
        for v in "ABC":
            if a.apply and v != pick.get(op, a.apply):
                continue
            d = f(v)
            info = []
            for slot, x in d.items():
                dst = os.path.join(SFX if a.apply else os.path.join(OUT, v), "ult_%s_%s.wav" % (op, slot))
                info.append("%s %.2f" % (slot, write(dst, np.asarray(x, dtype=np.float64), slot)))
            print(op, v, " / ".join(info))


if __name__ == "__main__":
    main()
