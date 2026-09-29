"""Boss 专属事件音效（通用大招 cue 覆盖不到的，协调人 9/30 派）：输出 audio/sfx/<名字>.wav，16-bit 单声道。
  cocoon_form     偏执泡影结茧：黏稠的包裹声 + 低鸣收紧
  shell_break     外壳被打破（破茧）：脆裂 + 碎片散落 + 释放的气流
  cocoon_revive   茧超时自行复活（蜕变）：黏膜撕开 + 上扬的不祥和弦
  izu_lamp_lit    伊祖米克灯柱点亮：石灯「轰」地着火 + 暖光绽开
  izu_absorb      伊祖米克吸收子代叠层：吞咽 + 低频鼓胀
  izu_wave_count  全场地波倒计时：2.0 秒持续音（和预警时长 boss/izumik_wave_charge 对齐），脉冲越来越快、音高上扬；
                  和「全场」cue 的起手警报区分——这个是躲避窗口的读秒
  apop_pause      凋亡损伤满条、技力暂停：能量泄掉的下滑 + 闷锁
  apop_resume     技力恢复：上扬的充能 + 轻铃
  stake_hit       骑士冲锋撞桩、长枪脱手：金属重撞 + 冰裂 + 长枪落地弹跳
  stake_shatter   冰枪桩到期碎裂：一串冰晶崩落
  carmen_sword    卡门换剑：长剑出鞘
用法：cd game/tools && python gen_sfx_boss_events.py [名字 ...]
"""
import sys

import numpy as np

from gen_sfx_events import SR, T, lp, hp, bp, env, glide, sweep, at, tinkles, save


def R(k):
    return np.random.default_rng(700 + k)


def cocoon_form():
    r = R(1); d = 1.4; n = int(d * SR); t = T(d)
    goo = lp(r.standard_normal(n), 700) * (1 + np.sin(2 * np.pi * 9 * t)) * np.minimum(t / 0.3, 1) * np.exp(-np.maximum(t - 0.9, 0) / 0.2)
    drone = sum(np.sin(2 * np.pi * f * t) * g for f, g in ((110, 1), (116.5, 0.8), (220, 0.3))) * (t / d) ** 0.7 * np.minimum((d - t) / 0.2, 1)
    return goo * 1.5 + drone * 0.5


def shell_break():
    r = R(2); d = 1.1; n = int(d * SR)
    crack = bp(r.standard_normal(n), 1200, 8000) * env(d, 0.0005, 0.03)
    shards = tinkles(r, n, 0.02, 0.6, 30, 1500, 6000) * np.exp(-T(d) / 0.3)
    thump = np.tanh(2 * glide(0.35, 120, 50)) * env(0.35, 0.002, 0.08)
    gust = sweep(r, 0.8, 400, 2400, 0.5) * env(0.8, 0.05, 0.25)
    return crack * 1.2 + shards * 0.5 + at(thump, 0, n) + at(gust, 0.05, n) * 0.8


def cocoon_revive():
    r = R(3); d = 1.5; n = int(d * SR); t = T(d)
    tear = lp(r.standard_normal(n), 1500) * env(d, 0.01, 0.12) * (1 + np.sin(2 * np.pi * 23 * t))
    chord_t = np.maximum(t - 0.2, 0)
    ch = sum(np.sin(2 * np.pi * f * t * (1 + 0.15 * np.minimum(chord_t / 0.8, 1))) for f in (147, 208, 311)) * np.minimum(chord_t / 0.3, 1) * np.exp(-np.maximum(chord_t - 0.6, 0) / 0.4) * (t >= 0.2)
    return tear + ch * 0.3


def izu_lamp_lit():
    r = R(4); d = 1.1; n = int(d * SR); t = T(d)
    whoomp = lp(r.standard_normal(n), 900) * env(d, 0.02, 0.15) * 1.5
    crackle = hp(tinkles(r, n, 0.05, 0.8, 20, 2000, 5000), 1500) * 0.4
    glow = sum(np.sin(2 * np.pi * f * t) for f in (392, 587.3, 784)) * np.minimum(np.maximum(t - 0.08, 0) / 0.1, 1) * np.exp(-t / 0.45) * 0.2
    return whoomp + crackle + glow


def izu_absorb():
    r = R(5); d = 0.8; n = int(d * SR)
    gulp = glide(0.25, 300, 90) * env(0.25, 0.005, 0.08)
    swell = np.tanh(2 * glide(d, 55, 70)) * np.sin(np.pi * T(d) / d) ** 1.2
    wet = lp(r.standard_normal(n), 500) * env(d, 0.01, 0.2)
    return at(gulp, 0, n) * 0.8 + swell * 0.8 + wet * 0.8


def izu_wave_count():
    d = 2.0; t = T(d)
    # 脉冲间隔 0.4 → 0.1 秒，音高 330 → 660 Hz，整体渐强；最后 0.1 秒收掉，留给「全场」命中音
    x = np.zeros(len(t)); tt, gap = 0.0, 0.4
    while tt < d - 0.12:
        k = tt / d; f = 330 * 2 ** k
        b = sum(np.sin(2 * np.pi * f * m * T(0.08)) * g for m, g in ((1, 1), (2, 0.4), (3, 0.15))) * env(0.08, 0.002, 0.03)
        x += at(b * (0.5 + 0.5 * k), tt, len(t))
        tt += gap; gap = max(0.1, gap * 0.85)
    bed = np.sin(2 * np.pi * 110 * t * (1 + 0.5 * t / d)) * (t / d) ** 1.5 * 0.25
    return (x + bed) * np.minimum((d - t) / 0.1, 1)


def apop_pause():
    d = 0.9; t = T(d)
    drain = glide(d, 880, 110) * env(d, 0.005, 0.35)
    lock = np.tanh(2 * glide(0.2, 160, 90)) * env(0.2, 0.002, 0.05)
    return drain * 0.7 + at(lock, 0.55, len(t))


def apop_resume():
    d = 0.8; t = T(d)
    rise = glide(0.5, 220, 880) * env(0.5, 0.01, 0.4) * np.minimum(T(0.5) / 0.3, 1)
    ding = sum(np.sin(2 * np.pi * f * T(0.4)) for f in (1175, 1760)) * env(0.4, 0.002, 0.12)
    return at(rise, 0, len(t)) * 0.6 + at(ding, 0.42, len(t)) * 0.4


def stake_hit():
    r = R(8); d = 1.3; n = int(d * SR)
    clang = sum(np.sin(2 * np.pi * f * T(d)) * np.exp(-T(d) / tau) for f, tau in ((420, 0.4), (1130, 0.25), (2270, 0.15), (3710, 0.08))) * 0.5
    crack = bp(r.standard_normal(n), 1500, 7000) * env(d, 0.0005, 0.04)
    thump = np.tanh(2 * glide(0.3, 110, 50)) * env(0.3, 0.002, 0.08)
    bounce = np.zeros(n)
    for k, (tt, g) in enumerate(((0.45, 0.5), (0.68, 0.3), (0.84, 0.18))):
        bounce += at(sum(np.sin(2 * np.pi * f * T(0.15)) for f in (780, 1650)) * env(0.15, 0.001, 0.03) * g, tt, n)
    return clang + crack + at(thump, 0, n) + bounce


def stake_shatter():
    r = R(9); d = 0.9; n = int(d * SR)
    crack = bp(r.standard_normal(n), 2000, 8000) * env(d, 0.0005, 0.025)
    fall = tinkles(r, n, 0.02, 0.75, 45, 2000, 8000) * np.exp(-T(d) / 0.35)
    return crack * 0.9 + fall * 0.7


def carmen_sword():
    r = R(10); d = 0.7; n = int(d * SR); t = T(d)
    slide = bp(r.standard_normal(n), 2500, 9000) * np.minimum(t / 0.3, 1) * np.exp(-np.maximum(t - 0.35, 0) / 0.03)
    ring = sum(np.sin(2 * np.pi * f * t) * g for f, g in ((2890, 0.6), (4410, 0.3), (6220, 0.15))) * np.maximum(0, np.sign(t - 0.35)) * np.exp(-np.maximum(t - 0.35, 0) / 0.25)
    return slide * 0.6 + ring * 0.6


SOUNDS = {k: v for k, v in globals().items() if k in ("cocoon_form", "shell_break", "cocoon_revive", "izu_lamp_lit", "izu_absorb", "izu_wave_count",
                                                       "apop_pause", "apop_resume", "stake_hit", "stake_shatter", "carmen_sword")}

if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        save(name, SOUNDS[name]())
