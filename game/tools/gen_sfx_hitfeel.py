"""打击感音效（docs/53 §5 的四个正式音，16-bit 单声道 44.1 kHz wav，输出 audio/sfx/）：
  op_logos_hit  逻各斯「言」命中：墨滴落纸（短促的湿「嗒」+ 下坠的水珠音）+ 一缕低语余音，≤ 0.15 秒，和 op_logos_atk 同一音色族（whisper 两个共振峰）
  kill_big      大体型 / 精英倒下的血肉层：比 kill 更湿更沉——饱和的次低频体积「咚」+ 低通湿裂 + 一个翻涌的气泡，0.42 秒
  kill_shell    甲壳类倒下：壳裂（高频碎裂瞬态 + 非谐短泛音）+ 一串碎块落地的干脆小点，0.48 秒
  hurt_heavy    主控挨 Boss 重击的次低频层：50 → 36 Hz 饱和「咚」+ 中频撞击 + 短暂的高频耳鸣（配 900 Hz 低通压配乐），0.85 秒
全部程序合成、每个音各自固定种子（重做一个不会动别的），复用 gen_sfx_events 的滤波 / 包络 / 写盘。
运行：python game/tools/gen_sfx_hitfeel.py [音名 ...]
"""
import sys
import numpy as np
from gen_sfx_events import SR, T, lp, hp, bp, env, glide, at, save


def _fade_in(x, sec):
    k = max(1, int(sec * SR))
    x[:k] *= np.linspace(0, 1, k)
    return x


def op_logos_hit():
    """墨滴：一声湿而短的「嗒」（低通噪声瞬态）+ 水珠下坠的正弦（520→170 Hz）+ 落点低闷 + 低语余音（1400 / 3400 Hz 两共振峰的气声，缓慢起伏）"""
    rng = np.random.default_rng(530)
    d = 0.15
    n = int(d * SR)
    t = T(d)
    plip = bp(rng.standard_normal(n), 700, 2600) * env(d, 0.0005, 0.012)
    drop = glide(0.05, 520, 170) * env(0.05, 0.001, 0.016)
    thud = np.tanh(2.0 * glide(0.08, 160, 80)) * env(0.08, 0.001, 0.022)
    ws = rng.standard_normal(n)
    wob = 0.6 + 0.4 * np.sin(2 * np.pi * 7.0 * t)
    whisper = (bp(ws, 1400, 1960) + bp(ws, 2700, 3400) * 0.6) * wob * np.minimum(t / 0.02, 1.0) * np.exp(-np.maximum(t - 0.03, 0) / 0.05)
    return plip * 1.0 + at(drop, 0.004, n) * 0.55 + at(thud, 0.0, n) * 0.7 + whisper * 0.45


def kill_big():
    """血肉层：饱和次低频体积「咚」（110→42 Hz）+ 低通湿裂（900 Hz 以下的噪声、快攻慢放）+ 0.07 秒后一个翻涌的气泡 + 几粒湿的碎点"""
    rng = np.random.default_rng(531)
    d = 0.42
    n = int(d * SR)
    body = np.tanh(2.2 * glide(0.3, 110, 42)) * env(0.3, 0.002, 0.07)
    splat = lp(rng.standard_normal(n), 900) * env(d, 0.001, 0.05)
    bubble = glide(0.16, 95, 230) * (0.7 + 0.3 * np.sin(2 * np.pi * 31 * T(0.16))) * env(0.16, 0.004, 0.05)
    bits = np.zeros(n)
    for p in rng.integers(int(0.03 * SR), int(0.3 * SR), 7):
        bits[p] = rng.uniform(0.3, 1.0) * rng.choice([-1, 1])
    bits = lp(bits, 1800) * 20.0 * env(d, 0.001, 0.12)
    return at(body, 0.0, n) * 1.0 + splat * 1.1 + at(bubble, 0.07, n) * 0.5 + bits * 0.35


def kill_shell():
    """壳裂：高频碎裂瞬态（2–7 kHz）+ 非谐短泛音（基频 880 Hz 的 1 / 2.76 / 5.4 倍，快衰减）+ 小闷响；之后一串碎块落地（0.06–0.42 秒，带通 1.5–5 kHz 的稀疏脉冲，渐稀渐轻）"""
    rng = np.random.default_rng(532)
    d = 0.48
    n = int(d * SR)
    crack = bp(rng.standard_normal(n), 2000, 7000) * env(d, 0.0003, 0.012)
    t = T(0.12)
    ring = sum(np.sin(2 * np.pi * 880 * p * t + rng.uniform(0, 6.28)) * np.exp(-t / (0.03 / (1 + i))) * 0.6 ** i
               for i, p in enumerate((1.0, 2.76, 5.40, 8.93)))
    knock = np.tanh(1.8 * glide(0.07, 220, 90)) * env(0.07, 0.001, 0.02)
    debris = np.zeros(n)
    ks = np.sort(rng.integers(int(0.06 * SR), int(0.42 * SR), 11))
    for k in ks:
        debris[k] = rng.uniform(0.4, 1.0) * rng.choice([-1, 1]) * (1.0 - 0.6 * k / n)
    debris = bp(debris, 1500, 5200) * 14.0
    return crack * 0.7 + at(ring, 0.0, n) * 0.9 + at(knock, 0.0, n) * 1.0 + debris * 1.0


def hurt_heavy():
    """次低频层：52→36 Hz 饱和「咚」（慢放 0.2 秒）+ 160→60 Hz 中频撞击 + 250 Hz 以下噪声冲击 + 4.6 kHz 耳鸣（0.05 秒内起、0.3 秒衰减，很轻）"""
    rng = np.random.default_rng(533)
    d = 0.85
    n = int(d * SR)
    t = T(d)
    sub = np.tanh(2.5 * glide(d, 52, 36)) * env(d, 0.003, 0.2)
    mid = np.tanh(1.6 * glide(0.14, 160, 60)) * env(0.14, 0.001, 0.035)
    rumble = lp(rng.standard_normal(n), 250) * env(d, 0.001, 0.06)
    tinnitus = np.sin(2 * np.pi * 4600 * t) * np.minimum(t / 0.05, 1.0) * np.exp(-t / 0.3) * 0.08
    return sub * 1.0 + at(mid, 0.0, n) * 0.7 + rumble * 2.0 + tinnitus


SOUNDS = {"op_logos_hit": op_logos_hit, "kill_big": kill_big, "kill_shell": kill_shell, "hurt_heavy": hurt_heavy}
PEAK = {"op_logos_hit": 0.80, "kill_big": 0.89, "kill_shell": 0.85, "hurt_heavy": 0.90}

if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        x = hp(SOUNDS[name](), 30, 1)
        save(name, x, peak=PEAK[name])
