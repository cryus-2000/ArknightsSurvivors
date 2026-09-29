"""Boss 大招固定音效（docs/38 §8.11）：六类共用的「起手 / 命中」+ 每只 Boss 一条专属音色（叠在起手音上）。
输出 audio/sfx/cue_<类别>_<start|hit>.wav 与 boss_<类型>.wav，由 Sfx.play_cue(类别, boss 类型, 阶段) 播放。
类别：land 落地 / charge 冲锋 / beam 光束 / melee 近身 / global 全场（只给必须冲刺类，全局最响）/ phase 阶段（只有起手）。
每声自带随机种子。用法：cd game/tools && python gen_sfx_cues.py [名字 ...]
"""
import sys

import numpy as np

from gen_sfx_events import SR, T, lp, hp, bp, env, glide, sweep, at, tinkles, save


def _rng(k):
    return np.random.default_rng(500 + k)


# ---------------------------------------------------------------- 六类共用
def land_start():   # 低沉蓄力嗡鸣：0.9 秒由弱到强，下方低频涌起
    r = _rng(1); d = 0.9; t = T(d)
    hum = sum(np.sin(2 * np.pi * f * t) * g for f, g in ((55, 1.0), (110, 0.5), (165, 0.25)))
    hum = np.tanh(1.5 * hum) * (t / d) ** 1.6
    rumble = lp(r.standard_normal(len(t)), 180, 4) * (t / d) ** 2 * 2.0
    return hum + rumble


def land_hit():     # 重击闷响
    r = _rng(2); d = 0.8; n = int(d * SR)
    body = np.tanh(2.0 * glide(d, 90, 38)) * env(d, 0.002, 0.16)
    crack = lp(r.standard_normal(n), 1800) * env(d, 0.001, 0.035)
    debris = lp(r.standard_normal(n), 500) * env(d, 0.01, 0.25) * 0.5
    return body * 1.3 + crack * 0.9 + debris


def charge_start():  # 蹄声 / 刃鸣逐渐加速：间隔 0.22 → 0.07 秒的蹄点 + 上扬刃鸣
    r = _rng(3); d = 1.0; n = int(d * SR); x = np.zeros(n)
    tt, gap = 0.0, 0.22
    while tt < d - 0.05:
        k = tt / d
        x += at(np.tanh(2 * glide(0.08, 140, 70)) * env(0.08, 0.002, 0.02) * (0.4 + 0.6 * k), tt, n)
        tt += gap
        gap = max(0.07, gap * 0.82)
    ring = glide(d, 900, 2400) * (T(d) / d) ** 2 * 0.25 + hp(sweep(r, d, 800, 3000, 0.3), 600) * (T(d) / d) ** 2 * 0.5
    return x + ring


def charge_hit():    # 撞击 + 风声
    r = _rng(4); d = 0.7; n = int(d * SR)
    impact = np.tanh(2.2 * glide(0.3, 120, 50)) * env(0.3, 0.002, 0.07)
    wind = sweep(r, d, 2600, 400, 0.5) * env(d, 0.01, 0.2)
    return at(impact, 0.0, n) * 1.2 + wind * 1.1


def beam_start():    # 高频充能：上扬的锯齿 + 颤音
    d = 0.9; t = T(d)
    f = 400 * (2600 / 400) ** (t / d)
    ph = np.cumsum(f) / SR
    saw = (2 * (ph % 1.0) - 1) * (1 + 0.3 * np.sin(2 * np.pi * 18 * t))
    return lp(saw, 5000) * (t / d) ** 1.4 * 0.7


def beam_hit():      # 光束贯穿：亮的嘶声 + 下滑的主音 + 低频推力
    r = _rng(6); d = 0.8; n = int(d * SR)
    hiss = bp(r.standard_normal(n), 2500, 9000) * env(d, 0.003, 0.25)
    tone = glide(d, 1800, 700) * env(d, 0.003, 0.3) * 0.5
    push = glide(d, 70, 45) * env(d, 0.005, 0.2)
    return hiss * 0.9 + tone + push


def melee_start():   # 拔刃 / 吸气：金属刮擦 + 气流上扬
    r = _rng(7); d = 0.5; n = int(d * SR)
    scrape = bp(r.standard_normal(n), 3000, 8000) * (T(d) / d) * np.exp(-np.maximum(T(d) - 0.35, 0) / 0.05)
    ring = sum(np.sin(2 * np.pi * f * T(d)) * g for f, g in ((2350, 0.5), (3610, 0.3))) * env(d, 0.25, 0.2)
    breath = sweep(r, d, 400, 1400, 0.6) * (T(d) / d) ** 1.5 * 0.8
    return scrape * 0.6 + ring * 0.3 + breath


def melee_hit():     # 挥砍
    r = _rng(8); d = 0.4; n = int(d * SR)
    whoosh = sweep(r, 0.25, 3500, 600, 0.5) * env(0.25, 0.005, 0.08)
    chop = np.tanh(2 * glide(0.15, 180, 90)) * env(0.15, 0.001, 0.03)
    return at(whoosh, 0.0, n) * 1.3 + at(chop, 0.05, n)


def global_start():  # 专属警报长音：两音交替的低鸣警报（1.8 秒），全局最响
    d = 1.8; t = T(d)
    f = np.where((t * 2.5) % 1.0 < 0.5, 220.0, 294.0)
    ph = np.cumsum(f) / SR
    sq = np.tanh(3 * np.sin(2 * np.pi * ph)) + 0.4 * np.sin(2 * np.pi * ph * 0.5)
    return lp(sq, 2200) * np.minimum(t / 0.1, 1.0) * np.minimum((d - t) / 0.2, 1.0)


def global_hit():    # 潮浪冲刷
    r = _rng(10); d = 1.6; n = int(d * SR); t = T(d)
    wash = sweep(r, d, 300, 2200, 0.8) * np.sin(np.pi * np.minimum(t / d, 1.0)) ** 0.7
    boom = np.tanh(1.8 * glide(d, 60, 35)) * env(d, 0.01, 0.4)
    return wash * 1.4 + boom


def phase_start():   # 阶段（通用底）：低吼 + 空间回响（专属咆哮由 boss_<类型> 叠上）
    r = _rng(11); d = 1.4; t = T(d)
    f = 70 * (48 / 70) ** (t / d)
    saw = 2 * ((np.cumsum(f) / SR) % 1.0) - 1
    growl = lp(np.tanh(2.5 * (saw + 0.3 * lp(r.standard_normal(len(t)), 200))), 900)
    x = growl * np.minimum(t / 0.15, 1.0) * np.exp(-np.maximum(t - 0.5, 0) / 0.4)
    return x + lp(at(x, 0.25, len(t)), 500) * 0.35


# ---------------------------------------------------------------- 每只 Boss 的专属音色（叠在起手音上，0.6–1.0 秒）
def boss_layer(kind, k):
    r = _rng(20 + k); d = 0.9; n = int(d * SR); t = T(d)
    if kind == "metal":       # 铁与石：低音金属共振
        return sum(np.sin(2 * np.pi * f * t) * np.exp(-t / tau) for f, tau in ((97, 0.5), (263, 0.3), (541, 0.18), (1133, 0.1))) * np.minimum(t / 0.01, 1)
    if kind == "bell":        # 圣徒：教堂钟（非整数泛音）
        f0 = 330 if k % 2 else 247
        return sum(np.sin(2 * np.pi * f0 * m * t) * g * np.exp(-t / (0.9 / m)) for m, g in ((1, 1), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12))) * np.minimum(t / 0.005, 1)
    if kind == "choir":       # 接潮：低沉的「呜」声合唱
        f0 = {0: 110, 1: 98, 2: 131}[k % 3]
        v = sum(np.sin(2 * np.pi * f0 * m * t * (1 + 0.004 * np.sin(2 * np.pi * 5 * t + m))) / m for m in range(1, 8))
        return bp(v, 250, 1100) * np.sin(np.pi * t / d) ** 1.5 * 2
    if kind == "bubble":      # 泡影：气泡破裂串
        x = np.zeros(n)
        for _ in range(16):
            c = r.uniform(0, 0.7); f0 = r.uniform(300, 1200); bd = r.uniform(0.03, 0.07)
            x += at(glide(bd, f0, f0 * 2.2) * env(bd, 0.002, bd / 3), c, n)
        return x
    if kind == "organic":     # 海嗣 / 伊莎玛拉：湿润的低频蠕动
        wob = lp(r.standard_normal(n), 400) * (1 + np.sin(2 * np.pi * 6 * t)) * np.sin(np.pi * t / d)
        return wob * 2.5 + np.sin(2 * np.pi * 55 * t) * np.sin(np.pi * t / d) * 0.5
    if kind == "ice":         # 最后的骑士：冰甲摩擦 + 冰晶
        return hp(tinkles(r, n, 0.0, 0.7, 25, 2500, 7000), 1500) * 0.6 + bp(r.standard_normal(n), 800, 3000) * env(d, 0.05, 0.25) * 0.7
    raise ValueError(kind)


BOSSES = {"path": ("metal", 0), "izumik": ("organic", 1), "iberia": ("bell", 2), "carmen": ("bell", 3),
          "bishop": ("choir", 4), "archon": ("choir", 5), "immortal": ("choir", 6), "paranoia": ("bubble", 7),
          "ishar": ("organic", 8), "knight_boss": ("ice", 9)}

SOUNDS = {"cue_land_start": land_start, "cue_land_hit": land_hit, "cue_charge_start": charge_start, "cue_charge_hit": charge_hit,
          "cue_beam_start": beam_start, "cue_beam_hit": beam_hit, "cue_melee_start": melee_start, "cue_melee_hit": melee_hit,
          "cue_global_start": global_start, "cue_global_hit": global_hit, "cue_phase_start": phase_start}
for _b, (_kind, _k) in BOSSES.items():
    SOUNDS["boss_" + _b] = (lambda kk=_kind, ii=_k: boss_layer(kk, ii))

if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        save(name, SOUNDS[name]())
