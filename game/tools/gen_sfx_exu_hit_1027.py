# 能天使「不叮」命中音两版 + 对照录像：A 闷响（低频噗 + 带通噪声），B 短碎响（高通噪声短促碎裂，无音高）
# 每段：同一节奏的普攻 12 发（三条轮换）+ 新命中音；枪声分别用 现在 main / 原作 P / Q / R
import os, subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = r"E:\ArknightsSurvivors"
FF = r"D:\Anaconda\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
SR = 44100
REV = os.path.join(ROOT, "build", "exu_orig_review")
rng = np.random.default_rng(7)


def load(path):
    raw = subprocess.run([FF, "-loglevel", "error", "-i", path, "-f", "f32le", "-ac", "1", "-ar", str(SR), "-"], capture_output=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def env(n, atk, dec):
    t = np.arange(n) / SR
    return np.minimum(t / atk, 1.0) * np.exp(-t / dec)


def hit_a():   # 闷响：80–160 Hz 下滑的短促「噗」+ 300–1800 Hz 带通噪声，无持续音高
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    f = 160 - 80 * t / t[-1]
    thump = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, 0.018)
    noise = sosfilt(butter(2, [300, 1800], "bandpass", fs=SR, output="sos"), rng.standard_normal(n)) * env(n, 0.001, 0.012)
    return (0.8 * thump + 0.6 * noise / np.abs(noise).max()).astype(np.float32)


def hit_b():   # 短碎响：2–7 kHz 高通噪声，两下极短颗粒（像子弹打碎东西），没有单一音高
    n = int(0.07 * SR)
    noise = sosfilt(butter(2, [2000, 7000], "bandpass", fs=SR, output="sos"), rng.standard_normal(n))
    e = env(n, 0.0008, 0.008) + 0.5 * np.roll(env(n, 0.0008, 0.006), int(0.012 * SR))
    body = sosfilt(butter(2, [200, 900], "bandpass", fs=SR, output="sos"), rng.standard_normal(n)) * env(n, 0.001, 0.015)
    out = noise / np.abs(noise).max() * e * 0.7 + body / np.abs(body).max() * 0.35
    return out.astype(np.float32)


def put(buf, clip, t, g=1.0):
    i = int(t * SR); j = min(len(buf), i + len(clip))
    buf[i:j] += clip[: j - i] * g


def seq(atk, hit):
    buf = np.zeros(int(SR * 5.0), np.float32)
    t = 0.4
    for k in range(12):
        put(buf, atk[k % 3], t)
        put(buf, hit, t + 0.08, 0.55)   # 命中音压低，让枪声当主角
        t += 0.35
    pk = np.abs(buf).max()
    return buf / pk * 0.89 if pk > 0.89 else buf


def main_atk():
    out = []
    for n in ("atk", "atk_b", "atk_c"):
        p = os.path.join(HERE, "src", "origin_main_op_exusiai_" + n + ".wav")
        out.append(load(p))
    return out


old_hit = load(os.path.join(HERE, "src", "origin_main_op_exusiai_hit.wav"))
HA, HB = hit_a(), hit_b()
for name, h in (("hit_A_闷响.wav", HA), ("hit_B_碎响.wav", HB)):
    wavfile.write(os.path.join(HERE, name), SR, h)

guns = [("现在 main 枪声", main_atk())] + [(f"原作 {v} 枪声", [load(os.path.join(REV, f"{v}_{n}.ogg")) for n in ("atk", "atk_b", "atk_c")]) for v in "PQR"]
segs = [("对照：现在 main 枪声 + 旧命中音（叮）", seq(guns[0][1], old_hit))]
for g, atk in guns:
    segs.append((g + " + 新命中 A 闷响", seq(atk, HA)))
    segs.append((g + " + 新命中 B 碎响", seq(atk, HB)))

font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 44)
small = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 28)
parts = []
for i, (label, audio) in enumerate(segs):
    img = Image.new("RGB", (960, 540), (14, 22, 32))
    d = ImageDraw.Draw(img)
    d.text((50, 210), f"{i + 1}. {label}", font=font, fill=(235, 240, 245))
    d.text((50, 300), "普攻 12 发（三条轮换）+ 命中", font=small, fill=(160, 180, 200))
    png, wav, mp4 = (os.path.join(HERE, f"seg{i}.{e}") for e in ("png", "wav", "mp4"))
    img.save(png); wavfile.write(wav, SR, audio)
    subprocess.run([FF, "-loglevel", "error", "-y", "-loop", "1", "-i", png, "-i", wav, "-shortest", "-c:v", "libx264", "-tune", "stillimage",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", mp4], check=True)
    parts.append(mp4)
lst = os.path.join(HERE, "list.txt")
open(lst, "w", encoding="utf-8").write("".join(f"file '{p}'\n" for p in parts))
final = os.path.join(HERE, "能天使命中音_不叮.mp4")
subprocess.run([FF, "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", final], check=True)
for f in os.listdir(HERE):
    if f.startswith("seg") or f == "list.txt":
        os.remove(os.path.join(HERE, f))
print(final, os.path.getsize(final))
