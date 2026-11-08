# -*- coding: utf-8 -*-
"""片头 v3（用户 11-08：同一只海嗣一路下沉、9 张参考帧逐段首尾帧生成、配乐一层一层进、不要海嗣吼声）。
画面：
  第一镜（pv_open1 帧，原样）→ seg1–7（Veo 首尾帧，约 2 倍速，只有环境音）
  → seg8 镜头下摇露出海嗣潮 = 配乐第 75 小节进（闷，低通）→ 海嗣潮拉远（pv_open 的 swarm 段）→ 77 闪白、配乐全开
声音：每段用 Veo 自带环境音（同倍速、atempo 保音高）；第一镜用同首尾帧重出的无吼声环境音；
      配乐 battle2 从第 75 小节起，低通 300 Hz → 77 全开，音量同步拉起；环境音在 76–77 退下去。
  python tools/promo/pv_open2.py <scratchpad> <输出 mp4>
scratchpad 里要有：fr_open/（第一镜帧）、seg1..8.mp4、fr_swarm/、sfx2_climb.mp4、sfx2_lit.mp4、open_music.wav（第 70 小节起）
"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, expo_out, finish
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
S, OUTMP4 = sys.argv[1], sys.argv[2]
SR = 48000
# (段, 源起, 源止, 倍速)
SEGS = [("seg1", 0.3, 3.9, 2.0), ("seg2", 0.2, 4.0, 2.0), ("seg3", 0.0, 4.0, 2.2), ("seg4", 0.0, 4.0, 2.0),
        ("seg5", 0.0, 4.0, 2.6), ("seg6", 0.0, 4.0, 2.2), ("seg7", 0.0, 4.0, 2.2)]
SEG8 = ("seg8", 0.0, 4.0, 4.0 / BAR)          # 正好一小节（75–76）
SH1 = 2 * BAR + BAR                            # 第一镜 4.93 秒


def run(*a):
    subprocess.run([FF, "-loglevel", "error", "-y", *a], check=True)


def frames(name):
    d = os.path.join(S, "fr_" + name)
    if not os.path.isdir(d):
        os.makedirs(d)
        run("-i", os.path.join(S, name + ".mp4"), os.path.join(d, "%03d.png"))
    return sorted(glob.glob(os.path.join(d, "*.png")))


def audio(name, t0, t1, speed):
    p = os.path.join(S, "_a_%s.wav" % name)
    run("-ss", str(t0), "-to", str(t1), "-i", os.path.join(S, name + ".mp4"), "-vn", "-af",
        "atempo=%.4f" % speed if speed <= 2 else "atempo=2,atempo=%.4f" % (speed / 2), "-ar", str(SR), "-ac", "2", p)
    return wavfile.read(p)[1].astype(np.float32) / 32768


def pixel(im, px=4):
    s = im.convert("RGB").resize((W // px, H // px), Image.BOX)
    s = s.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    return s.resize((W, H), Image.NEAREST)


def fade(a, n=480):
    n = min(n, len(a) // 4)
    r = np.linspace(0, 1, n)[:, None]
    a[:n] *= r; a[-n:] *= r[::-1]
    return a


OUT = os.path.join(S, "fr_v3")
os.makedirs(OUT, exist_ok=True)
plan = []                                       # 每输出帧：(源图路径, 是否已成品)
s1 = sorted(glob.glob(os.path.join(S, "fr_open", "*.png")))
plan += [(p, True) for p in s1[: int(round(SH1 * FPS))]]
amb = []
# 第一镜环境音：爬升 4 秒压到 72 重拍 + 照住那声从 6.25 秒起
cut = 2 * BAR
amb.append(fade(audio("sfx2_climb", 0, 4.0, 4.0 / cut)))
amb.append(fade(audio("sfx2_lit", 6.25, 6.25 + BAR + 0.02, 1.0)))
for name, t0, t1, sp in SEGS + [SEG8]:
    fs = frames(name)
    n = int(round((t1 - t0) / sp * FPS))
    for k in range(n):
        src_t = t0 + k / FPS * sp
        plan.append((fs[min(len(fs) - 1, int(src_t * 24))], False))
    amb.append(fade(audio(name, t0, t1, sp)))
T_MUSIC = len(plan) / FPS                       # 第 75 小节落在这里（seg8 开头）
T_MUSIC -= int(round(SEG8[2] / SEG8[3] * FPS)) / FPS
sw = sorted(glob.glob(os.path.join(S, "fr_swarm", "*.png")))
nsw = int(round(BAR * FPS))
start_sw = len(plan)
for k in range(nsw):
    plan.append((sw[min(len(sw) - 1, int(0.2 * 24 + k / FPS * 24))], ("swarm", k, nsw)))

for i, (p, done) in enumerate(plan):
    outp = os.path.join(OUT, "v%04d.png" % i)
    if done is True:
        Image.open(p).save(outp); continue
    im = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS)
    if isinstance(done, tuple):                 # 海嗣潮拉远 1.4 → 1.0 + 末 8 帧闪白
        _, k, n = done
        u = expo_out(k / n)
        z = 1.4 - 0.4 * u
        cw, ch = W / z, H / z
        im = im.crop((int((W - cw) / 2), int((H - ch) / 2 + 60 * (1 - u)), int((W + cw) / 2), int((H + ch) / 2 + 60 * (1 - u)))).resize((W, H), Image.LANCZOS)
        fr = pixel(im)
        if n - k <= 8:
            fr = Image.blend(fr, Image.new("RGB", (W, H), (245, 248, 250)), (8 - (n - k)) / 8)
    else:
        fr = pixel(im)
    finish(fr, i).save(outp)
NF = len(plan)
DUR = NF / FPS

# ---- 混音 ----
mix = np.zeros((int(DUR * SR) + SR, 2), np.float32)
pos = 0
for a in amb:                                  # 环境音首尾相接
    mix[pos:pos + len(a)] += a * 0.9
    pos += len(a) - 240
# 环境音在配乐进来后一小节内退到 35%
t = np.arange(len(mix)) / SR
duck = np.clip(1 - (t - (T_MUSIC + BAR)) / BAR * 0.65, 0.35, 1.0)
mix *= duck[:, None]
sr, mus = wavfile.read(os.path.join(S, "open_music.wav"))
mus = mus.astype(np.float32) / (32768 if mus.dtype == np.int16 else 1)
if mus.ndim == 1:
    mus = np.stack([mus, mus], 1)
assert sr == SR, sr
m0 = int(5 * BAR * SR)                          # open_music 从第 70 小节起 → 第 75 小节
seg = mus[m0:]
# 低通 300 Hz → 全开（77），按 20 ms 一块换系数；音量 0.25 → 1
out = np.zeros_like(seg)
blk = SR // 50
zi = None
for b in range(0, len(seg), blk):
    tt = b / SR
    u = min(1.0, tt / (2 * BAR))
    fc = 300 * (20000 / 300) ** (u ** 1.6)
    sos = butter(2, min(fc, SR / 2 - 100), "low", fs=SR, output="sos")
    if zi is None:
        zi = np.zeros((sos.shape[0], 2, 2))
    y = np.empty_like(seg[b:b + blk])
    for c in range(2):
        y[:, c], zi[:, :, c] = sosfilt(sos, seg[b:b + blk, c], zi=zi[:, :, c])
    out[b:b + blk] = y * (0.25 + 0.75 * u ** 1.3)
p0 = int(T_MUSIC * SR)
L = min(len(out), len(mix) - p0)
mix[p0:p0 + L] += out[:L]
mix = mix[: int(DUR * SR)]
mix /= max(1e-6, np.abs(mix).max() / 0.89)
wavfile.write(os.path.join(S, "_mix_v3.wav"), SR, (mix * 32767).astype(np.int16))
run("-framerate", str(FPS), "-i", os.path.join(OUT, "v%04d.png"), "-i", os.path.join(S, "_mix_v3.wav"),
    "-c:v", "libx264", "-crf", "22", "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", OUTMP4)
print("frames", NF, "dur %.2f" % DUR, "music_in %.2f" % T_MUSIC)
