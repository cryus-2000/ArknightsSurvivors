"""干员专属音效合成（docs/28）：每位干员一套 普攻 atk / 命中 hit / 技能 s1 s2 s3，部分干员另有 big（大招落点）/ heal（凯尔希治疗）/ quake（维什戴尔余震）。
全部程序合成，按"原作印象"取音色，不使用任何游戏原始音频。输出 16-bit 单声道 wav 到 audio/sfx/op_<干员>_<类别>.wav。

运行：python game/tools/gen_sfx_ops.py        （需要 numpy + scipy）
调某一个音效：改对应函数后重跑即可，随机种子固定，其它文件不会变。
"""
import numpy as np
from scipy.signal import butter, sosfilt
import wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(28)


# ---------------------------------------------------------------- 基础工具
def T(sec):
    return np.arange(int(sec * SR)) / SR


def N(sec):
    return rng.standard_normal(int(sec * SR))


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def env(sec, a=0.005, decay=10.0):
    t = T(sec)
    e = np.exp(-t * decay)
    ai = max(1, int(a * SR))
    e[:ai] *= np.linspace(0, 1, ai)
    return e


def swell(sec, peak=0.7):
    """先涌起后回落的包络（peak 为峰值位置比例）"""
    t = T(sec) / sec
    return np.where(t < peak, (t / peak) ** 2, np.cos((t - peak) / (1 - peak) * np.pi / 2) ** 2)


def tone(sec, f0, f1=None, kind="sin"):
    t = T(sec)
    f1 = f0 if f1 is None else f1
    f = f0 * (f1 / f0) ** (t / sec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sin":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    return np.sign(np.sin(ph))


def sweep_noise(sec, f0, f1, q=0.6):
    """带通扫频噪声（风切 / 挥砍 / 水流）"""
    n = int(sec * SR)
    noise = rng.standard_normal(n + 1024)
    out = np.zeros(n)
    blk = 256
    for i in range(0, n, blk):
        f = f0 + (f1 - f0) * (i / n)
        lo, hi = max(40, f * (1 - q)), min(SR / 2 - 100, f * (1 + q))
        seg = bp(noise[i:i + blk + 1024], lo, hi)
        out[i:i + blk] = seg[1024:1024 + min(blk, n - i)]
    return out


def bell(sec, f, decay=6.0, ratio=3.5, index=2.0, a=0.002):
    """FM 钟声：铃铛 / 医疗提示 / 晶体"""
    t = T(sec)
    ie = np.exp(-t * decay * 1.6)
    return np.sin(2 * np.pi * f * t + index * ie * np.sin(2 * np.pi * f * ratio * t)) * env(sec, a, decay)


def metal(sec, f, decay=9.0, partials=(1.0, 2.76, 5.40, 8.93, 13.34), bright=0.7):
    """金属撞击：非谐泛音（锤 / 盾 / 剑身）"""
    t = T(sec)
    x = np.zeros(len(t))
    for i, p in enumerate(partials):
        x += np.sin(2 * np.pi * f * p * t + rng.uniform(0, 6.28)) * np.exp(-t * decay * (1 + i * 0.6)) * bright ** i
    return x * env(sec, 0.0005, 0.0)


def thud(sec, f0, f1, decay=18.0):
    return tone(sec, f0, f1) * env(sec, 0.001, decay)


def crackle(sec, rate=90.0, lo=1500, hi=7000, decay=5.0):
    """火焰噼啪：稀疏随机脉冲过带通"""
    n = int(sec * SR)
    x = np.zeros(n)
    k = rng.poisson(rate * sec)
    for p in rng.integers(0, n, k):
        x[p] = rng.uniform(0.3, 1.0) * rng.choice([-1, 1])
    return bp(x, lo, hi) * 8.0 * env(sec, 0.01, decay)


def verb(x, tail=0.35, mix=0.25, damp=3000):
    """简易混响：指数衰减噪声卷积（给技能音一点空间，普攻不用）"""
    ir = lp(N(tail), damp) * np.exp(-T(tail) * 6.0 / tail)
    ir[0] = 0
    wet = np.convolve(x, ir)[:len(x) + len(ir)]
    wet /= np.max(np.abs(wet)) + 1e-9
    dry = np.pad(x, (0, len(wet) - len(x)))
    dry /= np.max(np.abs(dry)) + 1e-9
    return dry * (1 - mix) + wet * mix


def at(x, sec, total=None):
    """把 x 放到 sec 秒处"""
    st = int(sec * SR)
    n = total and int(total * SR) or st + len(x)
    y = np.zeros(max(n, st + len(x)))
    y[st:st + len(x)] += x
    return y


def pad(*xs):
    n = max(len(x) for x in xs)
    return sum(np.pad(x, (0, n - len(x))) for x in xs)


def sat(x, k=2.0):
    return np.tanh(k * x) / np.tanh(k)


SAVED = []


def save(name, x, gain=0.85):
    x = hp(x, 35, 1)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    # 裁掉混响留下的听不见的尾巴（网页版包体）
    nz = np.where(np.abs(x) > 0.004)[0]
    if len(nz):
        x = x[:min(len(x), nz[-1] + int(0.03 * SR))]
    fade = min(len(x), 800)
    x[-fade:] *= np.linspace(1, 0, fade)
    path = os.path.join(OUT, "op_" + name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    SAVED.append(("op_" + name, len(x) / SR))


# ================================================================ 水月（特种）：伞 · 深海 · 镜像
# 普攻：收拢的伞划过——布面短促的"唰" + 一点湿润的水气
save("mizuki_atk", pad(sweep_noise(0.17, 3200, 900, 0.45) * env(0.17, 0.012, 16),
                       bp(N(0.1), 500, 1400) * env(0.1, 0.004, 40) * 0.35), 0.7)
# 命中：伞骨打实——闷响 + 湿润的啪
save("mizuki_hit", pad(thud(0.1, 210, 70, 32), bp(N(0.07), 900, 3500) * env(0.07, 0.0005, 55) * 0.6,
                       tone(0.08, 900, 300) * env(0.08, 0.001, 50) * 0.15), 0.8)
# S1 唤醒：倒吸一口气般的反向涌起 + 深处一声玻璃质的钟
s = pad(sweep_noise(0.45, 300, 2400, 0.5) * swell(0.45, 0.92) * 0.8,
        at(bell(0.9, 740, 4.5, 2.01, 1.2) * 0.55, 0.38), at(bell(0.9, 1110, 5, 2.01, 0.9) * 0.3, 0.4))
save("mizuki_s1", verb(s, 0.5, 0.3), 0.75)
# S2 囚徒困境：加速的心跳式脉冲 + 紧张的颤音
_bt = np.cumsum([0.0] + [0.17 * 0.8 ** i for i in range(5)])
beats = pad(*[at(thud(0.12, 90, 55, 26) * (0.6 + 0.08 * i), b) for i, b in enumerate(_bt)])
trem = tone(0.9, 1480) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * T(0.9))) * swell(0.9, 0.5) * 0.18
save("mizuki_s2", verb(pad(beats, trem), 0.4, 0.25), 0.8)
# S3 镜花水月：两组微失谐的钟声（镜像）+ 深海低鸣
t = T(1.6)
mir = sum(bell(1.6, f, 2.2, 1.5, 1.4, 0.03) * g for f, g in ((587, 0.5), (590.5, 0.5), (880, 0.35), (883, 0.35), (1318, 0.18)))
deep = tone(1.6, 73, 62) * swell(1.6, 0.25) * 0.6
save("mizuki_s3", verb(pad(mir, deep, sweep_noise(1.0, 400, 1800, 0.3) * swell(1.0, 0.8) * 0.3), 0.8, 0.35), 0.8)

# ================================================================ 斯卡蒂（近卫）：大剑 · 潮水
# 普攻：沉重大剑横扫——低频风切，尾部带水花
save("skadi_atk", pad(sweep_noise(0.26, 1400, 260, 0.55) * env(0.26, 0.03, 9),
                      at(bp(N(0.12), 1800, 5000) * env(0.12, 0.01, 22) * 0.3, 0.1)), 0.75)
# 命中：厚重的斩入——低沉的剁 + 水花
save("skadi_hit", pad(thud(0.14, 150, 45, 22), metal(0.18, 310, 18, bright=0.4) * 0.18,
                      bp(N(0.12), 1200, 4200) * env(0.12, 0.002, 30) * 0.5), 0.85)
# S1 潮涌斩：水涌上来
save("skadi_s1", verb(pad(sweep_noise(0.5, 250, 1600, 0.6) * swell(0.5, 0.75),
                          lp(N(0.5), 400) * swell(0.5, 0.6) * 1.2), 0.4, 0.25), 0.75)
# S2 重斩：高举大剑——剑身嗡鸣 + 上扬的蓄力
s = pad(metal(1.0, 196, 3.2, (1, 2.01, 3.02, 4.1), 0.5) * 0.5, sweep_noise(0.45, 400, 1800, 0.4) * swell(0.45, 0.95) * 0.6)
save("skadi_s2", verb(s, 0.5, 0.25), 0.75)
# S3 潮汐：巨浪升起——宽带噪声涌起 + 低频推力
s = pad(lp(N(1.5), 900) * swell(1.5, 0.45) * 1.4, sweep_noise(1.5, 200, 900, 0.7) * swell(1.5, 0.5) * 0.7,
        tone(1.5, 45, 70) * swell(1.5, 0.4) * 0.7)
save("skadi_s3", verb(s, 0.6, 0.3), 0.85)
# 重斩落点：大剑砸地 + 水墙拍下
s = pad(thud(0.5, 95, 32, 7), lp(N(0.7), 1500) * env(0.7, 0.002, 6) * 0.9,
        at(bp(N(0.4), 1500, 6000) * env(0.4, 0.01, 9) * 0.4, 0.04))
save("skadi_big", sat(s, 1.5), 0.9)

# ================================================================ 推进之王（先锋）：战锤 · 金属 · 号令
save("siege_atk", sweep_noise(0.2, 1100, 380, 0.5) * env(0.2, 0.02, 12), 0.65)
# 命中：锤头砸实——金属铿响 + 厚重闷击
save("siege_hit", pad(thud(0.14, 130, 50, 24), metal(0.35, 420, 11, bright=0.62) * 0.4,
                      hp(N(0.03), 2500) * env(0.03, 0.0005, 90) * 0.35), 0.85)
# S1 冲锋号令：短促的铜管号角（上行五度）
def horn(sec, f, a=0.03):
    x = tone(sec, f, f, "saw") + 0.5 * tone(sec, f * 1.003, f * 1.003, "saw")
    x = lp(x, f * 4.5, 2)
    return x * env(sec, a, 1.5) * np.clip(T(sec)[::-1] / 0.08, 0, 1)
s = pad(horn(0.2, 220) * 0.8, at(horn(0.5, 330), 0.17))
save("siege_s1", verb(s, 0.5, 0.3), 0.75)
# S2 空中锤：跃起——向上的风声（落地由 big 负责）
save("siege_s2", sweep_noise(0.32, 500, 2600, 0.5) * swell(0.32, 0.85), 0.6)
# S3 碎颅：低吼 + 锤柄收紧的金属摩擦
s = pad(np.tanh(2 * (tone(0.9, 82, 70, "tri") + 0.4 * lp(N(0.9), 500))) * swell(0.9, 0.3) * 0.7,
        bp(N(0.9), 2500, 6000) * swell(0.9, 0.5) * 0.25, metal(0.9, 260, 4, bright=0.5) * 0.3)
save("siege_s3", verb(s, 0.4, 0.2), 0.8)
# 空中锤落地：砸地 + 碎石
s = pad(thud(0.6, 80, 28, 6), lp(N(0.6), 900) * env(0.6, 0.001, 8), metal(0.5, 180, 8, bright=0.5) * 0.3,
        at(crackle(0.4, 60, 800, 4000, 7) * 0.6, 0.05))
save("siege_big", sat(s, 1.8), 0.9)

# ================================================================ 塞雷娅（重装）：盾拳 · 药剂 · 琥珀晶体
save("saria_atk", pad(sweep_noise(0.12, 900, 400, 0.5) * env(0.12, 0.01, 22), thud(0.1, 160, 90, 40) * 0.3), 0.6)
# 命中：盾面撞击——厚重钝响 + 一点金属
save("saria_hit", pad(thud(0.16, 120, 55, 20), metal(0.2, 520, 16, bright=0.45) * 0.22,
                      lp(N(0.05), 1800) * env(0.05, 0.0005, 60) * 0.4), 0.85)
# S1 急救：药剂瓶开启（轻"咔"）+ 医疗音
s = pad(hp(N(0.02), 3000) * env(0.02, 0.0005, 120) * 0.5, at(bell(0.5, 880, 8, 1.0, 0.3) * 0.6, 0.03),
        at(bell(0.6, 1318, 7, 1.0, 0.3) * 0.5, 0.11))
save("saria_s1", verb(s, 0.3, 0.2), 0.65)
# S2 药剂散布：喷雾嘶声 + 医疗音
s = pad(bp(N(0.6), 3000, 9000) * swell(0.6, 0.2) * 0.35, at(bell(0.6, 880, 6, 1.0, 0.3) * 0.5, 0.05),
        at(bell(0.6, 1175, 6, 1.0, 0.3) * 0.45, 0.13), at(bell(0.7, 1760, 6, 1.0, 0.3) * 0.35, 0.21))
save("saria_s2", verb(s, 0.35, 0.25), 0.65)
# S3 钙质化：晶柱升起——琥珀晶体的细碎清响 + 地底隆起
x = np.zeros(int(1.4 * SR))
for i in range(16):
    f = rng.uniform(2200, 4800)
    x += at(bell(0.4, f, 12, 2.4, 1.0) * rng.uniform(0.3, 0.7), i * 0.045 + rng.uniform(0, 0.02), 1.4)[:len(x)]
s = pad(x * 0.5, lp(N(1.2), 250) * swell(1.2, 0.3) * 1.3, tone(1.2, 55, 48) * swell(1.2, 0.3) * 0.5)
save("saria_s3", verb(s, 0.5, 0.3), 0.8)

# ================================================================ 铃兰（辅助）：狐火 · 铃铛 · 暖光
# 普攻：狐火放出——轻柔的"噗"+ 小铃
save("suzuran_atk", pad(sweep_noise(0.15, 700, 2000, 0.5) * env(0.15, 0.015, 18) * 0.7,
                        bell(0.3, 2349, 14, 3.0, 0.8) * 0.3), 0.55)
# 命中：狐火绽开——软爆 + 火苗
save("suzuran_hit", pad(bp(N(0.12), 600, 2500) * env(0.12, 0.002, 30) * 0.6, bell(0.2, 1760, 20, 2.0, 1.0) * 0.25,
                        crackle(0.12, 150, 2500, 7000, 20) * 0.3), 0.55)
# S1 狐火连珠：一串铃铛（五发）
s = pad(*[at(bell(0.35, f, 10, 3.0, 0.9), i * 0.055) for i, f in enumerate((1568, 1760, 2093, 2349, 2637))])
save("suzuran_s1", verb(s, 0.4, 0.25), 0.6)
# S2 暖光：温暖的和弦铺开 + 铃
t = T(1.5)
chord = sum(tone(1.5, f, f, "tri") * g for f, g in ((392, 0.5), (494, 0.4), (587, 0.35), (784, 0.2)))
s = pad(lp(chord, 2500) * swell(1.5, 0.35) * 0.7, at(bell(1.0, 1568, 4, 3.0, 0.7) * 0.35, 0.1),
        at(bell(1.0, 2349, 4, 3.0, 0.7) * 0.25, 0.25))
save("suzuran_s2", verb(s, 0.7, 0.35), 0.7)
# S3 狐火迷雾：成片的铃声 + 呼吸般的雾气
x = np.zeros(int(1.8 * SR))
for i in range(12):
    f = rng.choice([1568, 1760, 2093, 2349, 2637, 3136])
    x += at(bell(0.6, f, 6, 3.0, 0.7) * rng.uniform(0.3, 0.6), rng.uniform(0, 1.1), 1.8)[:len(x)]
s = pad(x, bp(N(1.8), 400, 2400) * swell(1.8, 0.4) * 0.5, lp(chord, 2000)[:int(1.5 * SR)] * swell(1.5, 0.4) * 0.3)
save("suzuran_s3", verb(s, 0.8, 0.4), 0.7)

# ================================================================ 艾雅法拉（术师）：火山弹 · 熔岩
# 普攻：熔岩弹抛出——"呼"的火焰声 + 噼啪
save("eyjafjalla_atk", pad(sweep_noise(0.22, 500, 1500, 0.7) * env(0.22, 0.02, 12), crackle(0.22, 120, 2000, 7000, 10) * 0.35), 0.6)
# 命中：熔岩弹炸开——低沉爆响 + 火星
save("eyjafjalla_hit", pad(thud(0.3, 120, 40, 12), lp(N(0.35), 2200) * env(0.35, 0.001, 12) * 0.8,
                           crackle(0.35, 200, 1800, 6000, 9) * 0.5), 0.85)
# S1 炽热：火焰腾起
s = pad(lp(N(0.7), 1600) * swell(0.7, 0.35) * 0.9, crackle(0.7, 220, 1500, 6000, 3) * 0.5,
        tone(0.7, 110, 160) * swell(0.7, 0.4) * 0.4)
save("eyjafjalla_s1", verb(s, 0.4, 0.25), 0.75)
# S2 点燃：大火球蓄力——压缩后释放
s = pad(sweep_noise(0.5, 200, 1200, 0.6) * swell(0.5, 0.9), tone(0.5, 70, 180) * swell(0.5, 0.9) * 0.6,
        at(crackle(0.4, 250, 1500, 6000, 7) * 0.6, 0.35))
save("eyjafjalla_s2", verb(s, 0.4, 0.25), 0.8)
# S3 火山：大地轰鸣——深远的次低频隆隆 + 岩层开裂
s = pad(lp(N(1.6), 180) * swell(1.6, 0.35) * 2.0, tone(1.6, 38, 30) * swell(1.6, 0.3) * 0.8,
        crackle(1.6, 50, 400, 2500, 1.5) * 0.6)
save("eyjafjalla_s3", sat(verb(s, 0.5, 0.2), 1.5), 0.9)
# 火山喷发（每一处）：熔岩柱冲天
s = pad(thud(0.5, 90, 35, 8), sweep_noise(0.45, 400, 2400, 0.7) * env(0.45, 0.005, 7) * 0.8,
        crackle(0.5, 260, 1500, 6000, 6) * 0.5)
save("eyjafjalla_big", sat(s, 1.6), 0.85)

# ================================================================ 凯尔希（医疗）：Mon3tr · 临床的冷静
# 普攻（Mon3tr 爪击）：生物机械的撕裂——两道锐利的刮擦 + 骨质的咔
def rip(sec, f0, f1):
    return sweep_noise(sec, f0, f1, 0.25) * env(sec, 0.003, 22)
save("kaltsit_atk", pad(rip(0.14, 4200, 1600), at(rip(0.12, 3600, 1300) * 0.7, 0.035),
                        thud(0.08, 180, 90, 40) * 0.5, hp(N(0.015), 3000) * env(0.015, 0.0003, 150) * 0.6), 0.7)
# 治疗：凯尔希的回复——单一的冷静正弦提示音（不张扬，每 3.5 秒一次）
save("kaltsit_heal", pad(bell(0.6, 1318, 7, 1.0, 0.15) * 0.6, at(bell(0.5, 1975, 8, 1.0, 0.15) * 0.3, 0.05)), 0.5)
# S1 医疗单元：三声上行的仪器提示
s = pad(*[at(tone(0.09, f) * env(0.09, 0.003, 12), i * 0.09) for i, f in enumerate((1175, 1397, 1760))])
save("kaltsit_s1", verb(s, 0.3, 0.2), 0.55)
# S2 战术协同：Mon3tr 充能——电子上扫 + 机械咬合
s = pad(tone(0.6, 180, 900, "saw") * swell(0.6, 0.85) * 0.3, lp(tone(0.6, 90, 450, "sq"), 1500) * swell(0.6, 0.85) * 0.3,
        at(metal(0.3, 700, 20, bright=0.5) * 0.5, 0.55))
save("kaltsit_s2", verb(lp(s, 5000), 0.4, 0.25), 0.7)
# S3 熔毁：危险的高压蓄能嗡鸣
t = T(1.2)
hum = np.sin(2 * np.pi * 55 * t + 3 * np.sin(2 * np.pi * 110 * t)) * swell(1.2, 0.8)
s = pad(hum * 0.7, tone(1.2, 300, 1200, "saw") * swell(1.2, 0.9) * 0.15, bp(N(1.2), 1000, 5000) * swell(1.2, 0.9) * 0.2)
save("kaltsit_s3", verb(lp(s, 6000), 0.4, 0.2), 0.8)
# 熔毁爆发：能量炸裂
s = pad(thud(0.7, 110, 30, 6), lp(N(0.7), 3000) * env(0.7, 0.001, 7) * 0.7,
        np.sin(2 * np.pi * 220 * T(0.7) + 6 * env(0.7, 0.001, 8) * np.sin(2 * np.pi * 330 * T(0.7))) * env(0.7, 0.001, 6) * 0.4)
save("kaltsit_big", sat(s, 2.0), 0.9)

# ================================================================ 维什戴尔（狙击）：重炮 · 余震 · 残影
# 普攻：炮弹出膛——短促有力的"咚" + 高频的爆裂
save("wisadel_atk", pad(thud(0.2, 140, 50, 20), hp(N(0.05), 1800) * env(0.05, 0.0005, 70) * 0.7,
                        lp(N(0.2), 1000) * env(0.2, 0.001, 18) * 0.5), 0.75)
# 命中：落点爆炸——比艾雅法拉更干、更锐
save("wisadel_hit", pad(thud(0.35, 100, 35, 11), lp(N(0.3), 4000) * env(0.3, 0.0005, 14) * 0.7,
                        hp(N(0.03), 3000) * env(0.03, 0.0003, 90) * 0.4), 0.85)
# 余震：地下传来的低闷回响
save("wisadel_quake", pad(lp(N(0.5), 160) * env(0.5, 0.02, 7) * 1.5, thud(0.5, 55, 35, 8) * 0.8), 0.8)
# S1 灰烬弹幕：装填——两声机械咔嗒
def clack(f):
    return pad(metal(0.12, f, 35, bright=0.5) * 0.6, hp(N(0.02), 2000) * env(0.02, 0.0003, 120))
save("wisadel_s1", verb(pad(clack(900), at(clack(1250), 0.12), at(thud(0.1, 200, 120, 40) * 0.4, 0.12)), 0.3, 0.2), 0.7)
# S2 凋零处刑：锁定重炮——低沉蓄压 + 瞄准的尖细高音
s = pad(tone(0.6, 60, 110, "tri") * swell(0.6, 0.9) * 0.8, tone(0.6, 2600, 3400) * swell(0.6, 0.9) * 0.08,
        at(clack(700), 0.52))
save("wisadel_s2", verb(s, 0.35, 0.2), 0.8)
# S3 饱和炮击：炮口压低——沉重机括 + 蓄势的低鸣
s = pad(metal(0.5, 180, 7, bright=0.5) * 0.5, at(clack(800), 0.05), at(clack(1000), 0.15),
        tone(0.9, 50, 75) * swell(0.9, 0.7) * 0.7, lp(N(0.9), 300) * swell(0.9, 0.7) * 0.8)
save("wisadel_s3", verb(s, 0.4, 0.2), 0.85)


# ================================================================ 第二批（2026-09-25）
def chain(sec, n=10, f0=1700, f1=2900, decay=38.0, spread=1.0):
    """锚链 / 铁链哗啦：一串随机时刻的小金属撞击"""
    x = np.zeros(int(sec * SR))
    for k in range(n):
        t0 = (k / n) * sec * spread + rng.uniform(0, sec / n * 0.8)
        hit = metal(0.09, rng.uniform(f0, f1), decay, bright=0.55) * rng.uniform(0.4, 1.0)
        st = int(min(t0, sec - 0.09) * SR)
        x[st:st + len(hit)] += hit[:len(x) - st]
    return x


def chord(sec, fs, kind="tri", det=0.004):
    """微失谐和弦（每音两根）"""
    return sum(tone(sec, f * (1 - det), kind=kind) + tone(sec, f * (1 + det), kind=kind) for f in fs) / (2 * len(fs))


def whisper(sec, lo=1400, hi=4200):
    """气声低语：两个共振峰带通噪声，音量缓慢起伏"""
    n = N(sec)
    t = T(sec)
    wob = 0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(5, 9) * t)
    return (bp(n, lo, lo * 1.4) + bp(n, hi * 0.8, hi) * 0.6) * wob


# ================================================================ 艾丽妮（近卫）：细剑 · 审判灯 · 伊比利亚
# 普攻：细剑刺出——极快的高频破风 + 剑身一点"叮"
save("irene_atk", pad(sweep_noise(0.1, 5200, 2600, 0.35) * env(0.1, 0.004, 30),
                      metal(0.22, 2350, 22, bright=0.45) * 0.28), 0.6)
# 命中：刺穿——短促的咔 + 轻闷响
save("irene_hit", pad(hp(N(0.03), 2500) * env(0.03, 0.0003, 110) * 0.8, thud(0.09, 320, 120, 38) * 0.6,
                      metal(0.12, 1650, 30, bright=0.4) * 0.2), 0.6)
# S1 疾风：一阵上扬的风 + 两声剑鸣
s = pad(sweep_noise(0.45, 700, 3800, 0.5) * swell(0.45, 0.7) * 0.8,
        at(metal(0.3, 2100, 14, bright=0.5) * 0.35, 0.22), at(metal(0.3, 2800, 14, bright=0.5) * 0.3, 0.3))
save("irene_s1", verb(s, 0.35, 0.25), 0.7)
# S2 碎潮：锥形重斩——厚重风切 + 水面碎开 + 剑身长鸣
s = pad(sweep_noise(0.35, 2600, 500, 0.55) * env(0.35, 0.02, 7),
        at(lp(N(0.4), 3200) * env(0.4, 0.002, 9) * 0.6, 0.08),
        at(metal(0.6, 980, 6, bright=0.55) * 0.3, 0.06), at(thud(0.2, 180, 60, 18) * 0.5, 0.08))
save("irene_s2", verb(s, 0.45, 0.25), 0.8)
# S3 审判：一声低沉的教堂钟 + 灯火涌起的大三和弦 + 环斩
bellk = metal(2.0, 147, 1.6, partials=(0.5, 1.0, 1.19, 1.5, 2.0, 2.52, 3.0), bright=0.75)
s = pad(bellk * 0.6, chord(1.6, [293.7, 370.0, 440.0], "tri") * swell(1.6, 0.35) * 0.35,
        at(sweep_noise(0.3, 3000, 700, 0.5) * env(0.3, 0.01, 9) * 0.6, 0.05))
save("irene_s3", verb(s, 0.9, 0.35), 0.85)
# 灯光轰击（每一下）：自上而下的光束 + 落点钝击 + 一点钟声余音
save("irene_big", pad(tone(0.18, 2600, 700) * env(0.18, 0.002, 14) * 0.35, at(thud(0.28, 150, 50, 14), 0.12),
                      at(lp(N(0.3), 2500) * env(0.3, 0.001, 14) * 0.5, 0.12),
                      at(metal(0.6, 588, 5, bright=0.5) * 0.18, 0.12)), 0.75)

# ================================================================ Logos（术师）：言灵 · 墨 · 巴别塔女妖
# 普攻：一句低语化作墨弹——气声 + 低沉的正弦底
save("logos_atk", pad(whisper(0.22) * env(0.22, 0.03, 10) * 0.8, tone(0.22, 180, 140) * env(0.22, 0.02, 12) * 0.35,
                      sweep_noise(0.22, 800, 2200, 0.4) * env(0.22, 0.02, 14) * 0.3), 0.55)
# S1 提喻：锁定——三全音的低鸣 + 贴耳的低语
s = pad(chord(1.0, [110.0, 155.6], "saw") * swell(1.0, 0.4) * 0.25, whisper(1.0, 1100, 3600) * swell(1.0, 0.5) * 0.5,
        lp(tone(1.0, 55, 52, "saw"), 400) * swell(1.0, 0.3) * 0.4)
save("logos_s1", verb(s, 0.6, 0.35), 0.75)
# S2 湮灭：反向吸入 → 空洞的一声"咚"，永久生效的"定音"
s = pad(sweep_noise(0.55, 300, 3000, 0.5) * swell(0.55, 0.98) * 0.6, at(thud(0.6, 90, 30, 7), 0.55),
        at(chord(0.9, [220.0, 233.1, 329.6], "saw") * env(0.9, 0.01, 4) * 0.2, 0.55))
save("logos_s2", verb(s, 0.8, 0.35), 0.85)
# S3 延展敏锐：墨色展开——宽阔的小调和声 + 长长的风 + 暗钟
s = pad(chord(1.8, [146.8, 174.6, 220.0, 293.7], "saw") * swell(1.8, 0.4) * 0.22,
        sweep_noise(1.8, 400, 2400, 0.4) * swell(1.8, 0.5) * 0.35,
        metal(1.8, 196, 2.2, partials=(0.5, 1.0, 1.21, 1.5, 2.0, 2.6), bright=0.6) * 0.35,
        whisper(1.8, 900, 3000) * swell(1.8, 0.6) * 0.3)
save("logos_s3", verb(s, 1.0, 0.4), 0.85)
# 湮灭处决：干脆的一声"断"——低金属 + 噪声爆 + 下坠的正弦
save("logos_big", pad(metal(0.25, 260, 16, bright=0.5) * 0.5, hp(N(0.05), 1500) * env(0.05, 0.0005, 60) * 0.6,
                      tone(0.3, 400, 60) * env(0.3, 0.002, 10) * 0.6), 0.7)

# ================================================================ 流明（医疗）：提灯 · 光 · 药剂
# 普攻：提灯放出光弹——玻璃质的"叮" + 轻轻的呼
save("lumen_atk", pad(bell(0.3, 1568, 14, 2.0, 0.8) * 0.5, sweep_noise(0.12, 1800, 4200, 0.4) * env(0.12, 0.01, 22) * 0.4), 0.5)
# 命中：光弹绽开——短亮的钟 + 细碎闪光
save("lumen_hit", pad(bell(0.25, 2093, 18, 3.0, 1.5) * 0.45, hp(N(0.12), 5000) * env(0.12, 0.001, 30) * 0.35,
                      thud(0.08, 260, 160, 40) * 0.25), 0.55)
# S1 净化之光：上行大调琶音钟声 + 一层微光
s = pad(*[at(bell(0.9, f, 5, 2.0, 0.8) * 0.35, i * 0.07) for i, f in enumerate([783.99, 987.77, 1174.66, 1567.98])])
s = pad(s, hp(N(0.9), 5500) * swell(0.9, 0.3) * 0.12)
save("lumen_s1", verb(s, 0.6, 0.35), 0.7)
# S2 领航灯：温暖的大调和弦慢慢亮起 + 一声钟（永久生效）
s = pad(chord(1.4, [392.0, 493.9, 587.3], "tri") * swell(1.4, 0.45) * 0.45, at(bell(1.2, 1174.66, 4, 2.0, 0.6) * 0.35, 0.25))
save("lumen_s2", verb(s, 0.7, 0.35), 0.75)
# S3 指引灯塔：深沉的灯塔钟 + 上扬的光之和弦 + 远处的雾笛
s = pad(metal(2.2, 196, 1.4, partials=(0.5, 1.0, 1.2, 1.5, 2.0, 2.5, 3.0), bright=0.7) * 0.5,
        chord(2.0, [392.0, 493.9, 587.3, 784.0], "tri") * swell(2.0, 0.5) * 0.3,
        lp(tone(1.6, 98, 98, "saw"), 700) * swell(1.6, 0.4) * 0.25,
        hp(N(2.0), 6000) * swell(2.0, 0.5) * 0.08)
save("lumen_s3", verb(s, 1.0, 0.4), 0.85)
# 光爆：灯塔熄灭前的一次爆发——明亮的爆 + 钟群 + 厚重落地
s = pad(hp(N(0.4), 2500) * env(0.4, 0.001, 9) * 0.6, thud(0.4, 140, 45, 10) * 0.7,
        bell(0.9, 1318.5, 5, 2.0, 1.0) * 0.25, at(bell(0.9, 1975.5, 5, 2.0, 1.0) * 0.2, 0.04))
save("lumen_big", verb(s, 0.5, 0.3), 0.85)

# ================================================================ 归溟幽灵鲨（特种）：锯刃 · 求生 · 深海
# 普攻：锯刃环斩——一圈带嗡鸣的锯齿风切
saw = lp(tone(0.28, 95, 130, "saw"), 1800) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * T(0.28)))
save("specter_unchained_atk", pad(sweep_noise(0.28, 900, 2600, 0.5) * swell(0.28, 0.45) * 0.7, saw * swell(0.28, 0.4) * 0.45,
                                  at(thud(0.1, 200, 80, 30) * 0.3, 0.12)), 0.65)
# S1 求生之技：重重一跳的心跳 + 喉咙里的低吼
growl = lp(tone(0.9, 70, 58, "saw") * (0.7 + 0.3 * np.sign(np.sin(2 * np.pi * 23 * T(0.9)))), 500)
s = pad(thud(0.2, 70, 45, 16), at(thud(0.2, 65, 40, 16) * 0.7, 0.18), growl * swell(0.9, 0.3) * 0.5)
save("specter_unchained_s1", verb(s, 0.4, 0.2), 0.8)
# S2 求生之渴：越来越快的心跳 + 被拉紧的高音（撑住博士）
s = pad(*[at(thud(0.16, 72, 44, 18) * (0.6 + 0.08 * k), 0.34 * (0.82 ** k) * k) for k in range(6)])
s = pad(s, tone(1.2, 900, 1500, "saw") * swell(1.2, 0.85) * 0.07, lp(N(1.2), 600) * swell(1.2, 0.8) * 0.3)
save("specter_unchained_s2", verb(s, 0.4, 0.25), 0.8)
# S3 求生之压：锯刃转速拉满——低吼 + 上扬的锯鸣 + 一声重斩
rev = lp(tone(0.9, 60, 180, "saw"), 2200) * (0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(np.linspace(20, 60, len(T(0.9)))) / SR))
s = pad(rev * swell(0.9, 0.85) * 0.5, growl * 0.4, at(sweep_noise(0.3, 2400, 500, 0.5) * env(0.3, 0.01, 10) * 0.7, 0.8),
        at(thud(0.3, 120, 40, 12) * 0.6, 0.82))
save("specter_unchained_s3", verb(sat(s, 1.5), 0.45, 0.25), 0.85)

# ================================================================ 乌尔比安（近卫）：船锚 · 锚链 · 深海猎人
# 普攻：抡锚——低沉的风 + 锚链一抖 + 砸地
save("ulpianus_atk", pad(sweep_noise(0.3, 900, 200, 0.55) * env(0.3, 0.04, 8) * 0.8, chain(0.2, 4, 1500, 2400) * 0.25,
                         at(thud(0.22, 110, 40, 16) * 0.8, 0.14), at(lp(N(0.2), 1800) * env(0.2, 0.001, 18) * 0.35, 0.14)), 0.7)
# S1 必须接触：掷锚——锚链长长哗啦 + 呼啸
s = pad(chain(0.55, 14, 1500, 3000) * 0.5, sweep_noise(0.5, 600, 1800, 0.5) * swell(0.5, 0.4) * 0.5)
save("ulpianus_s1", verb(s, 0.35, 0.2), 0.75)
# S2 必须坚守：锚身一声沉重的铁鸣 + 深海低鸣（永久生效）
s = pad(metal(1.4, 98, 2.5, bright=0.6) * 0.6, lp(tone(1.4, 49, 46, "saw"), 300) * swell(1.4, 0.3) * 0.4,
        chain(0.3, 5, 1200, 2000) * 0.2)
save("ulpianus_s2", verb(s, 0.6, 0.3), 0.8)
# S3 必须开辟：蓄力抡起——锚链急速收紧 + 上扬的风
s = pad(chain(0.6, 18, 1800, 3400, 45) * 0.45, sweep_noise(0.6, 250, 1500, 0.5) * swell(0.6, 0.95) * 0.7,
        lp(tone(0.6, 45, 70, "saw"), 300) * swell(0.6, 0.9) * 0.4)
save("ulpianus_s3", verb(s, 0.35, 0.2), 0.8)
# 锚落地：巨锚砸进海床——深沉冲击 + 碎石 + 水墙 + 铁鸣
s = pad(thud(0.7, 85, 28, 6), lp(N(0.6), 900) * env(0.6, 0.001, 7) * 0.9, at(crackle(0.5, 70, 800, 4000, 6) * 0.4, 0.04),
        at(lp(N(0.5), 3000) * env(0.5, 0.01, 8) * 0.35, 0.06), metal(0.9, 140, 5, bright=0.55) * 0.3)
save("ulpianus_big", sat(verb(s, 0.5, 0.25), 1.8), 0.95)

print("ok", len(SAVED))
for n, d in SAVED:
    print(f"  {n:<24} {d:.2f}s")
