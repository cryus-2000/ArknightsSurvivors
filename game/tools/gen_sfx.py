"""原创音效合成：挥伞、命中、触手、受击、闪避、拾取、升级、技能、界面等。输出 16-bit 单声道 wav。"""
import numpy as np
from scipy.signal import butter, sosfilt
import wave, os

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio", "sfx")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(11)


def T(sec):
    return np.arange(int(sec * SR)) / SR


def bp(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=SR, output="sos"), x)


def lp(x, fc, order=2):
    return sosfilt(butter(order, fc, fs=SR, output="sos"), x)


def hp(x, fc, order=2):
    return sosfilt(butter(order, fc, btype="high", fs=SR, output="sos"), x)


def sweep_noise(sec, f0, f1, q=0.6):
    """带通扫频噪声（风声/挥砍）"""
    n = int(sec * SR)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    blk = 256
    for i in range(0, n, blk):
        f = f0 + (f1 - f0) * (i / n)
        lo, hi = max(40, f * (1 - q)), min(SR / 2 - 100, f * (1 + q))
        out[i:i + blk] = bp(noise[max(0, i - 1024):i + blk], lo, hi)[-min(blk, n - i):]
    return out


def tone(sec, f0, f1=None, kind="sin"):
    t = T(sec)
    f1 = f0 if f1 is None else f1
    f = f0 * (f1 / f0) ** (t / sec)
    ph = 2 * np.pi * np.cumsum(f) / SR
    if kind == "sin":
        return np.sin(ph)
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    return np.sign(np.sin(ph))


def env(sec, a=0.005, decay=10.0):
    t = T(sec)
    e = np.exp(-t * decay)
    ai = max(1, int(a * SR))
    e[:ai] *= np.linspace(0, 1, ai)
    return e


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    fade = min(len(x), 200)
    x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def pad(*xs):
    n = max(len(x) for x in xs)
    return sum(np.pad(x, (0, n - len(x))) for x in xs)


# 挥伞：短促的风切声
s = sweep_noise(0.2, 2500, 700, 0.5) * env(0.2, 0.02, 14)
save("swing", s, 0.7)

# 强化挥砍（唤醒）：更低沉的风切 + 金属清鸣
s = pad(sweep_noise(0.32, 1800, 300, 0.6) * env(0.32, 0.015, 8),
        tone(0.6, 1760) * env(0.6, 0.002, 7) * 0.35 + tone(0.6, 2637) * env(0.6, 0.002, 9) * 0.2)
save("swing_heavy", s, 0.8)

# 命中：闷击 + 碎裂噪声
thump = tone(0.12, 180, 55) * env(0.12, 0.001, 30)
crunch = hp(rng.standard_normal(int(0.05 * SR)), 1500) * env(0.05, 0.0005, 70) * 0.6
save("hit", pad(thump, crunch), 0.85)

# 击杀：湿润的破裂声
pop = bp(rng.standard_normal(int(0.18 * SR)), 300, 2200) * env(0.18, 0.001, 22)
save("kill", pad(pop, tone(0.1, 260, 90) * env(0.1, 0.001, 35) * 0.7), 0.7)

# 触手：黏湿的钻出声（低频咕噜 + 共振扫频）
gurgle = tone(0.35, 70, 140) * (0.6 + 0.4 * np.sin(2 * np.pi * 28 * T(0.35))) * env(0.35, 0.01, 7)
squelch = sweep_noise(0.3, 400, 1400, 0.3) * env(0.3, 0.02, 10) * 0.8
save("tentacle", pad(gurgle, squelch), 0.75)

# 受击：沉重的钝击 + 失真嗡鸣
t = T(0.28)
buzz = np.tanh(3 * tone(0.28, 110, 70, "tri")) * env(0.28, 0.001, 12)
save("hurt", pad(tone(0.15, 140, 50) * env(0.15, 0.001, 22), buzz * 0.6,
                 hp(rng.standard_normal(int(0.04 * SR)), 2000) * env(0.04, 0.0005, 60) * 0.5), 0.9)

# 闪避：向上扬起的空气声
save("dodge", sweep_noise(0.22, 600, 3200, 0.4) * env(0.22, 0.04, 9), 0.55)

# 拾取经验：小水滴声
save("pickup", tone(0.07, 1300, 2100) * env(0.07, 0.001, 45), 0.4)

# 灯油：温暖的上扬音
save("oil", pad(tone(0.45, 523) * env(0.45, 0.005, 6), tone(0.45, 784) * env(0.45, 0.06, 6) * 0.7,
                tone(0.45, 1046) * env(0.45, 0.12, 6) * 0.5), 0.55)

# 升级：D 小调琶音钟声
parts = []
for i, f in enumerate((587, 698, 880, 1175)):
    x = np.zeros(int(0.9 * SR))
    st = int(i * 0.07 * SR)
    b = tone(0.9 - i * 0.07, f) * env(0.9 - i * 0.07, 0.002, 5)
    x[st:st + len(b)] += b
    parts.append(x)
save("levelup", sum(parts), 0.6)

# 打开藏品：闪烁
x = np.zeros(int(0.8 * SR))
for i in range(7):
    f = rng.uniform(1800, 3600)
    st = int(i * 0.06 * SR)
    b = tone(0.35, f) * env(0.35, 0.001, 14)
    x[st:st + len(b)] += b * (1 - i * 0.08)
save("relic", x, 0.5)

# 技能发动：低沉涌起 + 高频微光
swell = lp(rng.standard_normal(int(1.0 * SR)), 300) * np.sin(np.pi * T(1.0) / 1.0) ** 2
shimmer = sum(tone(1.0, f) * env(1.0, 0.3, 3) for f in (880, 1320, 1760)) * 0.3
save("skill", pad(swell * 2.0, shimmer, tone(1.0, 55, 110) * np.sin(np.pi * T(1.0)) * 0.8), 0.8)

# 精英 / Boss 出现：低吼
roar = np.tanh(2.5 * (tone(1.2, 60, 45, "tri") + 0.5 * lp(rng.standard_normal(int(1.2 * SR)), 400)))
save("roar", roar * env(1.2, 0.15, 2.5), 0.85)

# 精英击破：爆裂
boom = tone(0.6, 90, 30) * env(0.6, 0.001, 6) + lp(rng.standard_normal(int(0.6 * SR)), 1200) * env(0.6, 0.001, 9) * 0.8
save("boom", boom, 0.9)

# 界面：移动光标 / 确认 / 开始
save("ui_move", tone(0.04, 1500) * env(0.04, 0.001, 60), 0.35)
save("ui_ok", pad(tone(0.12, 880) * env(0.12, 0.001, 25), tone(0.12, 1320) * env(0.12, 0.02, 25) * 0.6), 0.5)
save("start", pad(swell * 1.5, sum(tone(1.4, f) * env(1.4, 0.05, 2.5) for f in (293, 440, 587)) * 0.4), 0.8)

# 低血量：心跳（两下低频闷响）
def thump(sec, f):
    return tone(sec, f, f * 0.6) * env(sec, 0.004, 18)
hb = pad(thump(0.18, 70), np.concatenate([np.zeros(int(0.2 * SR)), thump(0.16, 62) * 0.7]))
save("heartbeat", lp(hb, 300), 0.9)
print("ok", sorted(os.listdir(OUT)))
