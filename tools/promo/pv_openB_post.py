# -*- coding: utf-8 -*-
"""片头 B 后期：Blender 渲染帧（pv_openB_hd2d.py，30 帧 960×540）→ 60 帧 1920×1080，整幅 4×4 像素化（全片同一套 64 色调色板），
第 77 小节闪白 + 方舟幸存者 logo（logo_mark ×3 最近邻），遮幅 + 颗粒（pv2d.finish）。
声音：声呐（合成：1150 Hz 衰减正弦 + 两次回声，第 0.25 / 2.25 / 4.25 小节，与声呐圈同步）、水下低鸣（Sonniss 授权素材低通），
配乐 battle2 第 74 小节低通闷进 → 77 全开（open_music.wav 第 70 小节起；music_77.wav 第 77 小节起）。
总长 8 小节（第 70–78 小节）。
  python tools/promo/pv_openB_post.py <渲染帧目录> <scratchpad> <输出 mp4>
"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image, ImageFilter, ImageEnhance
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, finish
from pv_pixelize import build_palette, pixelize
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
RD, S, OUTMP4 = sys.argv[1], sys.argv[2], sys.argv[3]
LIB = "E:/ArknightsSurvivors/build/sfx_lib/sonniss_gdc2026/extracted/"
SR = 48000
B = lambda bars: int(round(bars * BAR * FPS))
NF, N3D = B(8), B(7)
rf = sorted(glob.glob(os.path.join(RD, "b*.png")))
assert len(rf) >= N3D // 2, len(rf)
PX = 4
pal = build_palette([Image.open(rf[i]).resize((W, H), Image.LANCZOS) for i in range(0, len(rf), 20)], 64, PX)
logo = Image.open(os.path.join(ROOT, "game/art/ui/title_deep/logo_mark.png")).convert("RGBA")
LG = logo.resize((logo.width * 3, logo.height * 3), Image.NEAREST)
OUT = os.path.join(S, "fr_openB")
os.makedirs(OUT, exist_ok=True)
last = None
for i in range(N3D):
    j = min(len(rf) - 1, i // 2)
    if i % 2 == 0 or last is None:
        last = pixelize(Image.open(rf[j]).convert("RGB").resize((W, H), Image.LANCZOS), pal, PX)
    fr = last
    n = N3D - i
    if n <= 6:                                   # 77 前 6 帧闪白
        fr = Image.blend(fr, Image.new("RGB", (W, H), (236, 242, 248)), (7 - n) / 7)
    finish(fr, i).save(os.path.join(OUT, "o%04d.png" % i))
LOGO_BG = ImageEnhance.Brightness(last).enhance(0.3).filter(ImageFilter.GaussianBlur(5))
for k in range(NF - N3D):
    i = N3D + k
    fr = LOGO_BG.convert("RGBA")
    lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); lay.paste(LG, ((W - LG.width) // 2, (H - LG.height) // 2), LG)
    fr.alpha_composite(lay.filter(ImageFilter.GaussianBlur(14))); fr.alpha_composite(lay)
    fr = fr.convert("RGB")
    if k < 9:
        fr = Image.blend(Image.new("RGB", (W, H), (236, 242, 248)), fr, k / 9)
    finish(fr, i).save(os.path.join(OUT, "o%04d.png" % i))
DUR = NF / FPS


# ---- 声音 ----
def load(rel, dur):
    p = os.path.join(S, "_sndB.wav")
    subprocess.run([FF, "-loglevel", "error", "-y", "-i", LIB + rel, "-t", str(dur), "-ac", "2", "-ar", str(SR), p], check=True)
    a = wavfile.read(p)[1].astype(np.float32) / 32768
    return np.resize(a, (int(dur * SR), 2))


def lp(x, fc, order=4):
    return sosfilt(butter(order, fc, "low", fs=SR, output="sos"), x, axis=0)


n = int(DUR * SR) + SR
mix = np.zeros((n, 2), np.float32)
t = np.arange(n) / SR
# 水下低鸣：太空舱底噪低通 + 魔法嗡鸣，开头 1 小节淡入，第 77 小节后退到 30%
hum = lp(load("Cinematic Sound Design - Sci-Fi Drones/Roomtone Space Ship Interior Muted.wav", DUR + 1), 500) * 1.4
dr = lp(load("Alexander Kopeikin - Emotion and Magic/magic, drone, tension, spellbound, evanescence-002.wav", DUR + 1), 1800) * 0.5
env = np.clip(t / BAR, 0, 1) * np.where(t < 7 * BAR, 1.0, 0.3)
mix += (hum[:n] + dr[:n]) * env[:, None]
# 声呐：合成
def ping(f0=1150.0, L=2.4):
    tt = np.arange(int(L * SR)) / SR
    s = np.sin(2 * np.pi * (f0 * tt - 30 * tt * tt)) * np.exp(-tt / 0.32) * np.minimum(1, tt / 0.004)
    out = s.copy()
    for d, g in ((0.42, 0.38), (0.86, 0.16), (1.3, 0.07)):
        k = int(d * SR); out[k:] += s[: len(s) - k] * g
    return lp(out, 3200, 2) * 0.55
P = ping()
for bars in (0.25, 2.25, 4.25):
    p0 = int(bars * BAR * SR); L = min(len(P), n - p0)
    mix[p0:p0 + L] += np.stack([P[:L], P[:L]], 1)
# 配乐：第 74 小节起低通闷进，77 全开
sr, mus = wavfile.read(os.path.join(S, "open_music.wav")); mus = mus.astype(np.float32) / 32768
seg = mus[int(4 * BAR * SR): int(7 * BAR * SR)]
out = np.zeros_like(seg); blk = SR // 50; zi = None
for b in range(0, len(seg), blk):
    u = min(1.0, (b / SR) / (3 * BAR))
    sos = butter(2, min(300 * (20000 / 300) ** (u ** 1.6), SR / 2 - 100), "low", fs=SR, output="sos")
    if zi is None:
        zi = np.zeros((sos.shape[0], 2, 2))
    y = np.empty_like(seg[b:b + blk])
    for c in range(2):
        y[:, c], zi[:, :, c] = sosfilt(sos, seg[b:b + blk, c], zi=zi[:, :, c])
    out[b:b + blk] = y * (0.22 + 0.78 * u ** 1.3)
p0 = int(4 * BAR * SR); mix[p0:p0 + len(out)] += out[: n - p0]
sr2, m2 = wavfile.read(os.path.join(S, "music_77.wav")); m2 = m2.astype(np.float32) / 32768
q0 = int(7 * BAR * SR); L2 = min(len(m2), n - q0); mix[q0:q0 + L2] += m2[:L2]
mix = mix[: int(DUR * SR)]
mix /= max(1e-6, np.abs(mix).max() / 0.89)
wav = os.path.join(S, "_mix_openB.wav")
wavfile.write(wav, SR, (mix * 32767).astype(np.int16))
subprocess.run([FF, "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(OUT, "o%04d.png"), "-i", wav,
                "-c:v", "libx264", "-crf", "18", "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", OUTMP4], check=True)
print("frames", NF, "dur %.3f" % DUR)
