"""1.1 新增事件的音效（16-bit 单声道 wav，输出 audio/sfx/）：
  knight_charge  骑士冲锋：冰面上的急冲（上扬的风切 + 冰碴碎响），冰霜拖尾
  knight_stab    骑士枪刺：短促的金属「锵」+ 冰光，连刺时连播
  knight_frost   寒冰领域：冰晶一圈爆开（一声闷响 + 一串细碎冰晶）
  hunt_warn      「围猎」预告横幅（合拢前 3 秒）：压下来的低吼 + 水下压迫，约 2.4 秒
  hunt_close     「围猎」合拢：四面水压收拢的「呜——嗡」，约 1.6 秒
  hunt_break     「围猎」突围：压力散开、向上释放的一口气，约 1.2 秒
  beacon_tick / beacon_lit / beacon_end  引航灯标：点燃进度嘀嗒 / 点燃光爆 / 30 秒安全区结束
  nerve_burst    神经损伤满格（真伤 + 眩晕）
  mire_splat     飘航者神经弹落地留溟痕
  ulp_charge_loop / ulp_release  乌尔比安 S3 手动蓄距离循环 / 松手释放
  atk_gate       手动普攻被闸门拦住的轻「咔」
  beacon_fizzle  灯标未点燃、45 秒熄灭
  enemy_nerve    浮海飘航者神经弹发射
  mire_clear     灯标点亮时清掉溟痕（叠在光爆下）
  enemy_acid     侵蚀酸弹（尖、辨识度优先）
  enemy_elite    远程精英开火
每声用自己的随机数种子：单独重做某一声不影响其他；gen_sfx.py 重跑复现不了现有音效，别为这些去重跑它。
用法：cd game/tools && python gen_sfx_events.py [名字 ...]
"""
import os
import sys
import wave

import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")


def T(sec):
    return np.arange(int(sec * SR)) / SR


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def env(sec, a, tau):
    t = T(sec)
    return np.minimum(t / max(a, 1e-4), 1.0) * np.exp(-t / tau)


def glide(sec, f0, f1):
    f = f0 * (f1 / f0) ** (T(sec) / sec)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def sweep(rng, sec, f0, f1, q=0.5):
    """带通扫频噪声（风切 / 水流）"""
    n = int(sec * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    for i in range(0, n, 256):
        f = f0 * (f1 / f0) ** (i / n)
        seg = bp(noise[max(0, i - 1024):i + 256], max(30, f * (1 - q)), min(SR / 2 - 100, f * (1 + q)))
        out[i:i + 256] = seg[-min(256, n - i):]
    return out


def at(x, sec, n):
    out = np.zeros(n)
    i = int(sec * SR)
    k = min(len(x), n - i)
    if k > 0:
        out[i:i + k] = x[:k]
    return out


def tinkles(rng, n, t0, t1, count, lo=2500, hi=7000, amp=1.0):
    """一串细碎冰晶：短促的高频正弦颗粒，随机频率与时刻"""
    out = np.zeros(n)
    for _ in range(count):
        c = rng.uniform(t0, t1)
        f = rng.uniform(lo, hi)
        d = rng.uniform(0.04, 0.12)
        g = np.sin(2 * np.pi * f * T(d)) * env(d, 0.001, d / 4) * rng.uniform(0.3, 1.0)
        out += at(g, c, n)
    return out * amp


def knight_charge():
    rng = np.random.default_rng(301)
    d = 0.65
    n = int(d * SR)
    wind = sweep(rng, d, 500, 2800, 0.45) * np.minimum(T(d) / 0.12, 1.0) * np.exp(-np.maximum(T(d) - 0.25, 0) / 0.12)
    body = lp(rng.standard_normal(n), 300) * env(d, 0.02, 0.15) * 1.5          # 蹬地的闷劲
    crackle = hp(tinkles(rng, n, 0.08, 0.55, 22, 3000, 8000), 2000)             # 冰碴
    return wind * 1.2 + body + crackle * 0.35


def knight_stab():
    rng = np.random.default_rng(302)
    d = 0.4
    n = int(d * SR)
    ring = sum(np.sin(2 * np.pi * f * T(d)) * env(d, 0.001, tau) * g
               for f, tau, g in ((1870, 0.09, 1.0), (3130, 0.06, 0.7), (4720, 0.045, 0.5), (6950, 0.03, 0.3)))
    air = sweep(rng, 0.12, 4000, 1500, 0.5) * env(0.12, 0.002, 0.04)
    return ring * 0.6 + at(air, 0.0, n) * 1.4 + hp(tinkles(rng, n, 0.02, 0.2, 6, 5000, 9000), 3000) * 0.25


def knight_frost():
    rng = np.random.default_rng(303)
    d = 0.9
    n = int(d * SR)
    thump = glide(0.25, 110, 55) * env(0.25, 0.003, 0.07)
    burst = bp(rng.standard_normal(n), 1500, 6000) * env(d, 0.002, 0.05)
    shards = tinkles(rng, n, 0.01, 0.7, 40, 2200, 7500)
    return at(thump, 0.0, n) * 1.2 + burst * 0.6 + shards * 0.45 * np.exp(-T(d) / 0.35)


def hunt_warn():
    """压下来的低吼：锯齿低音（75 → 52 Hz）轻失真后低通，喉音共振随时间合拢；底下是水压的低频涌动"""
    rng = np.random.default_rng(401)
    d = 2.4
    n = int(d * SR)
    t = T(d)
    f = 75 * (52 / 75) ** (t / d)
    ph = np.cumsum(f) / SR
    saw = 2 * (ph % 1.0) - 1
    growl = np.tanh(2.5 * (saw + 0.4 * lp(rng.standard_normal(n), 160)))
    # 喉音：带通中心 700 → 350 Hz 往下收
    throat = np.zeros(n)
    for i in range(0, n, 512):
        fc = 700 * (350 / 700) ** (i / n)
        seg = bp(growl[max(0, i - 2048):i + 512], fc * 0.6, fc * 1.5)
        throat[i:i + 512] = seg[-min(512, n - i):]
    shape = np.minimum(t / 0.35, 1.0) * np.exp(-np.maximum(t - 0.9, 0) / 0.6)
    pressure = lp(rng.standard_normal(n), 120, 4) * np.sin(np.pi * np.minimum(t / d, 1.0)) ** 1.5 * 3.0
    sub = glide(d, 48, 38) * np.sin(np.pi * t / d) ** 2
    x = lp(growl, 1400) * 0.5 * shape + throat * 0.9 * shape + pressure + sub * 0.6
    return x * np.minimum((d - t) / 0.3, 1.0)


def hunt_close():
    """四面水压收拢：低通噪声由宽到窄（1500 → 180 Hz）的吸入感，收拢一刻落一记低频「嗡」"""
    rng = np.random.default_rng(402)
    d = 1.6
    n = int(d * SR)
    t = T(d)
    rush = sweep(rng, 0.55, 1500, 180, 0.7) * np.minimum(T(0.55) / 0.35, 1.0) ** 2
    hit_t = 0.5
    wt = np.maximum(t - hit_t, 0)
    boom = glide(d, 70, 42) * np.minimum(wt / 0.02, 1.0) * np.exp(-wt / 0.4) * (t >= hit_t)
    boom = np.tanh(1.8 * boom) / np.tanh(1.8)
    swell = lp(rng.standard_normal(n), 220, 4) * np.minimum(wt / 0.05, 1.0) * np.exp(-wt / 0.5) * (t >= hit_t) * 2.5
    x = at(rush, 0.0, n) * 1.3 + boom + swell
    echo = lp(at(x, 0.3, n), 400) * 0.3
    return (x + echo) * np.minimum((d - t) / 0.3, 1.0)


def hunt_break():
    """突围：压力散开、往上释放——上扬的气泡风声 + 明亮的和弦余光（D 大三和弦，和配乐调性不打架）"""
    rng = np.random.default_rng(403)
    d = 1.2
    n = int(d * SR)
    t = T(d)
    rise = sweep(rng, 0.7, 250, 2600, 0.5) * np.minimum(T(0.7) / 0.1, 1.0) * np.exp(-T(0.7) / 0.35)
    bubbles = np.zeros(n)
    for _ in range(14):
        c = rng.uniform(0.02, 0.6)
        f0 = rng.uniform(500, 1400)
        bd = rng.uniform(0.04, 0.08)
        bubbles += at(glide(bd, f0, f0 * 1.8) * env(bd, 0.002, bd / 3) * rng.uniform(0.3, 1.0), c, n)
    shine = sum(np.sin(2 * np.pi * f * t) for f in (587.3, 740.0, 880.0, 1174.7)) * np.minimum(np.maximum(t - 0.15, 0) / 0.08, 1.0) * np.exp(-np.maximum(t - 0.15, 0) / 0.35) * (t >= 0.15)
    return at(rise, 0.0, n) * 1.2 + bubbles * 0.35 + shine * 0.12


def beacon_tick():
    """灯标点燃进度嘀嗒：短促柔和的铃音（游戏里按进度升调播放）"""
    d = 0.35
    t = T(d)
    return sum(np.sin(2 * np.pi * f * t) * g for f, g in ((1320, 1.0), (2640, 0.25), (3960, 0.1))) * env(d, 0.002, 0.08)


def beacon_lit():
    """点燃光爆：上扬气流 + 暖色 D 大三和弦绽开 + 低频闷响"""
    rng = np.random.default_rng(501)
    d = 1.3
    n = int(d * SR)
    t = T(d)
    rise = sweep(rng, 0.35, 300, 3000, 0.5) * np.minimum(T(0.35) / 0.3, 1.0) ** 2
    bloom_t = np.maximum(t - 0.3, 0)
    chord = sum(np.sin(2 * np.pi * f * t) for f in (293.7, 440.0, 587.3, 740.0, 880.0)) * np.minimum(bloom_t / 0.02, 1.0) * np.exp(-bloom_t / 0.5) * (t >= 0.3)
    thump = np.tanh(2 * glide(0.4, 110, 55)) * env(0.4, 0.002, 0.1)
    sparkle = hp(tinkles(rng, n, 0.3, 1.0, 18, 3000, 7000), 2000) * 0.3
    return at(rise, 0.0, n) * 0.9 + chord * 0.18 + at(thump, 0.3, n) * 0.9 + sparkle


def beacon_end():
    """30 秒安全区结束：两音下行（A → E）+ 余烬嘶声"""
    rng = np.random.default_rng(502)
    n = int(1.1 * SR)
    a = sum(np.sin(2 * np.pi * f * T(0.5)) * g for f, g in ((880, 1.0), (1760, 0.2))) * env(0.5, 0.005, 0.2)
    b = sum(np.sin(2 * np.pi * f * T(0.7)) * g for f, g in ((659.3, 1.0), (1318.5, 0.2))) * env(0.7, 0.005, 0.3)
    hiss = hp(rng.standard_normal(n), 3000) * env(1.1, 0.05, 0.3) * 0.15
    return at(a, 0.0, n) * 0.6 + at(b, 0.3, n) * 0.6 + hiss


def nerve_burst():
    """神经损伤满格（真伤 + 眩晕）：电击脆响 + 不协和的环形调制嗡鸣 + 耳鸣高音，和冰（冻结）/ 锁链（束缚）区分开"""
    rng = np.random.default_rng(503)
    d = 1.1
    n = int(d * SR)
    t = T(d)
    crack = bp(rng.standard_normal(n), 1500, 9000) * env(d, 0.0005, 0.02)
    buzz = np.sin(2 * np.pi * 180 * t) * np.sin(2 * np.pi * 247 * t) * (1 + 0.6 * np.sign(np.sin(2 * np.pi * 31 * t)))
    buzz = lp(np.tanh(3 * buzz), 3500) * env(d, 0.005, 0.28)
    tinnitus = np.sin(2 * np.pi * 5200 * t) * np.minimum(t / 0.05, 1.0) * np.exp(-t / 0.6) * 0.12
    low = np.tanh(2 * glide(0.3, 90, 50)) * env(0.3, 0.002, 0.08)
    return crack * 0.8 + buzz * 0.7 + tinnitus + at(low, 0.0, n) * 0.6


def mire_splat():
    """神经弹落地留溟痕：湿的「啪」+ 一个低沉气泡"""
    rng = np.random.default_rng(504)
    d = 0.45
    n = int(d * SR)
    splat = lp(rng.standard_normal(n), 1200) * env(d, 0.001, 0.04)
    bubble = glide(0.2, 180, 320) * env(0.2, 0.005, 0.06)
    return splat * 1.2 + at(bubble, 0.08, n) * 0.6


def ulp_charge_loop():
    """乌尔比安 S3 蓄距离：1 秒无缝循环的低鸣 + 颤动（游戏里按距离升 pitch_scale）。整数周期，首尾相接不爆音"""
    d = 1.0
    t = T(d)
    x = sum(np.sin(2 * np.pi * f * t) * g for f, g in ((110, 1.0), (220, 0.5), (330, 0.3), (440, 0.15)))
    x *= 1 + 0.25 * np.sin(2 * np.pi * 8 * t)
    return np.tanh(1.4 * x)


def ulp_release():
    """S3 松手释放：蓄力弹出的上扬气流 + 沉重的出手"""
    rng = np.random.default_rng(601)
    d = 0.8
    n = int(d * SR)
    whoosh = sweep(rng, 0.5, 300, 3000, 0.5) * env(0.5, 0.01, 0.15)
    thump = np.tanh(2 * glide(0.35, 140, 60)) * env(0.35, 0.002, 0.09)
    return at(whoosh, 0.0, n) * 1.2 + at(thump, 0.02, n)


def atk_gate():
    """手动普攻被闸门拦住（未解锁 / 锥内没人）：极短的木质「咔」，只提示按到了、不刺耳"""
    rng = np.random.default_rng(602)
    d = 0.08
    click = bp(rng.standard_normal(int(d * SR)), 900, 2500) * env(d, 0.0005, 0.008)
    knock = np.sin(2 * np.pi * 520 * T(d)) * env(d, 0.001, 0.012)
    return click + knock * 0.6


def beacon_fizzle():
    """灯标未点燃、45 秒熄灭：火苗噗噗几下灭掉 + 一缕嘶声，没有音调（和安全区结束的两音下行区分）"""
    rng = np.random.default_rng(603)
    d = 1.0
    n = int(d * SR)
    x = np.zeros(n)
    for k, (tt, g) in enumerate(((0.0, 1.0), (0.18, 0.7), (0.32, 0.45), (0.42, 0.3))):
        puff = lp(rng.standard_normal(int(0.1 * SR)), 900) * env(0.1, 0.003, 0.03) * g
        x += at(puff, tt, n)
    hiss = hp(rng.standard_normal(n), 3500) * np.maximum(T(d) - 0.35, 0) ** 0.5 * np.exp(-T(d) / 0.4) * 0.3
    return x + hiss


def enemy_nerve():
    """浮海飘航者神经弹发射：湿润的「嗖」+ 颤动的高音（像神经抽动），和普通吐射区分"""
    rng = np.random.default_rng(605)
    d = 0.35
    n = int(d * SR)
    t = T(d)
    thwip = sweep(rng, 0.18, 2200, 700, 0.5) * env(0.18, 0.002, 0.05)
    warble = np.sin(2 * np.pi * (1400 + 300 * np.sin(2 * np.pi * 38 * t)) * t) * env(d, 0.005, 0.08) * 0.35
    wet = lp(rng.standard_normal(n), 900) * env(d, 0.001, 0.02) * 0.6
    return at(thwip, 0.0, n) + warble + wet


def mire_clear():
    """灯标点亮时清掉溟痕：一层溶解的嘶声 + 渐亮的微光（叠在点亮光爆下面，只在确实清掉溟痕时播）"""
    rng = np.random.default_rng(606)
    d = 1.2
    n = int(d * SR)
    t = T(d)
    sizzle = bp(rng.standard_normal(n), 2500, 7000) * np.sin(np.pi * np.minimum(t / d, 1.0)) * np.exp(-t / 0.6)
    shimmer = sum(np.sin(2 * np.pi * f * t) for f in (1175, 1480, 1760)) * np.minimum(t / 0.4, 1.0) * np.exp(-t / 0.5) * 0.12
    return sizzle * 0.8 + shimmer


def enemy_acid():
    """侵蚀酸弹（喷吐者抛射 / 投嗣育母追踪弹 / 站桩吐酸）：尖、辨识度优先——短促上扬的「噗咻」+ 高频酸液嘶嘶声"""
    rng = np.random.default_rng(607)
    d = 0.4
    n = int(d * SR)
    pwik = glide(0.09, 900, 2600) * env(0.09, 0.001, 0.035)
    sizzle = bp(rng.standard_normal(n), 4500, 11000) * np.exp(-T(d) / 0.12) * (1 + 0.5 * np.sin(2 * np.pi * 60 * T(d)))
    wet = lp(rng.standard_normal(int(0.05 * SR)), 1500) * env(0.05, 0.001, 0.01)
    return at(pwik, 0.0, n) * 0.9 + sizzle * 0.6 + at(wet, 0.0, n) * 0.7


def enemy_elite():
    """远程精英开火：有分量的「咚」+ 金属共鸣（比普通吐射低、厚）"""
    rng = np.random.default_rng(608)
    d = 0.45
    n = int(d * SR)
    thoom = np.tanh(2.2 * glide(0.25, 160, 70)) * env(0.25, 0.002, 0.07)
    ring = sum(np.sin(2 * np.pi * f * T(d)) * np.exp(-T(d) / tau) for f, tau in ((620, 0.12), (1370, 0.07))) * 0.3
    puff = bp(rng.standard_normal(n), 800, 3000) * env(d, 0.002, 0.04) * 0.6
    return at(thoom, 0.0, n) + ring + puff


SOUNDS = {"knight_charge": knight_charge, "knight_stab": knight_stab, "knight_frost": knight_frost,
          "hunt_warn": hunt_warn, "hunt_close": hunt_close, "hunt_break": hunt_break,
          "beacon_tick": beacon_tick, "beacon_lit": beacon_lit, "beacon_end": beacon_end, "nerve_burst": nerve_burst, "mire_splat": mire_splat,
          "ulp_charge_loop": ulp_charge_loop, "ulp_release": ulp_release, "atk_gate": atk_gate, "beacon_fizzle": beacon_fizzle,
          "enemy_nerve": enemy_nerve, "mire_clear": mire_clear,
          "enemy_acid": enemy_acid, "enemy_elite": enemy_elite}


def save(name, x, peak=0.89):
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    fade = min(len(x), 200)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    print(name, round(len(x) / SR, 2), "s")


if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        save(name, SOUNDS[name]())
