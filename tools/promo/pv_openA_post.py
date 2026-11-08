# -*- coding: utf-8 -*-
"""片头 A 后期：Blender 帧（第 70–77 小节，690 帧）+ 77–78 闪白 / logo，2.39:1 遮幅 + 颗粒 + 暗角，配声音，出 mp4。
总长严格 8 小节（8×BAR）：第 0–7 小节片头，第 7 小节（battle2 第 77 小节 drop）起 logo，到第 8 小节（= 第 78 小节，后段从这里接）。
声音：前 4 小节只有水下低鸣（Sonniss 授权环境素材低通）；第 74 小节起 battle2 低通闷进、77 全开到 78。
  python tools/promo/pv_openA_post.py <Blender 帧目录> <scratchpad> <输出 mp4>
"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, finish
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
FR, S, OUTMP4 = sys.argv[1], sys.argv[2], sys.argv[3]
SR = 48000
LIB = "E:/ArknightsSurvivors/build/sfx_lib/sonniss_gdc2026/extracted/"
NF7 = int(round(7 * BAR * FPS))
NF = int(round(8 * BAR * FPS))
frames = sorted(glob.glob(os.path.join(FR, "f*.png")))
assert len(frames) >= NF7 - 2, len(frames)

logo = Image.open(os.path.join(ROOT, "game/art/ui/title_deep/logo_mark.png")).convert("RGBA")
LG = logo.resize((logo.width * 3, logo.height * 3), Image.NEAREST)
LG_A = np.asarray(LG)[..., 3:4].astype(np.float32) / 255
# logo 染成淡蓝白（原图偏灰白），像素保留
lg_rgb = np.asarray(LG)[..., :3].astype(np.float32)
lg_rgb = lg_rgb * np.array([0.92, 0.96, 1.0])
last = Image.open(frames[min(len(frames), NF7) - 1]).convert("RGB").resize((W, H))
LOGO_BG = ImageEnhance.Brightness(last).enhance(0.35).filter(ImageFilter.GaussianBlur(10))
OUT = os.path.join(S, "fr_openA")
os.makedirs(OUT, exist_ok=True)
WHITE = Image.new("RGB", (W, H), (226, 236, 246))
for i in range(NF):
    if i < NF7:
        fr = Image.open(frames[min(i, len(frames) - 1)]).convert("RGB")
        if fr.size != (W, H):
            fr = fr.resize((W, H), Image.LANCZOS)
        n = NF7 - i
        if n <= 8:                                     # 77 前 8 帧推白
            fr = Image.blend(fr, WHITE, (9 - n) / 9)
    else:
        k = i - NF7
        z = 1.0 + 0.03 * k / (NF - NF7)
        bg = LOGO_BG.resize((int(W * z), int(H * z)), Image.LANCZOS)
        bg = bg.crop(((bg.width - W) // 2, (bg.height - H) // 2, (bg.width - W) // 2 + W, (bg.height - H) // 2 + H))
        a = np.asarray(bg).astype(np.float32)
        x0, y0 = (W - LG.width) // 2, (H - LG.height) // 2
        reg = a[y0:y0 + LG.height, x0:x0 + LG.width]
        a[y0:y0 + LG.height, x0:x0 + LG.width] = reg * (1 - LG_A) + lg_rgb * LG_A
        glow = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        fr = glow
        if k < 10:                                      # 从白里落出
            fr = Image.blend(WHITE, fr, k / 10)
        if NF - i <= 4:                                 # 末 4 帧压黑，接后段
            fr = Image.blend(fr, Image.new("RGB", (W, H), (0, 0, 0)), (5 - (NF - i)) / 5)
    finish(fr, i).save(os.path.join(OUT, "a%04d.png" % i))

# ---- 声音 ----
DUR = NF / FPS
L = int(DUR * SR)


def load(rel, t0=0.0):
    p = os.path.join(S, "_sndA.wav")
    subprocess.run([FF, "-loglevel", "error", "-y", "-ss", str(t0), "-i", LIB + rel, "-t", str(DUR + 1), "-ac", "2", "-ar", str(SR), p], check=True)
    return np.resize(wavfile.read(p)[1].astype(np.float32) / 32768, (L, 2))


def lp(x, fc, order=4):
    return sosfilt(butter(order, fc, "low", fs=SR, output="sos"), x, axis=0)


t = np.arange(L) / SR
drone = lp(load("Cinematic Sound Design - Sci-Fi Drones/Roomtone Space Ship Interior Muted.wav"), 500) * 1.2
waves = lp(load("Just Sound Effects - Rocky Coast of Norway/WATRWave_Soft Waves Cliffs_JSE_RCoN_Stereo.wav", 5.0), 260) * 0.8
amb = (drone + waves) * np.clip(t / 1.0, 0, 1)[:, None]
amb *= np.clip(1 - (t - 6 * BAR) / BAR * 0.7, 0.3, 1.0)[:, None]
sr, m70 = wavfile.read(os.path.join(S, "open_music.wav")); m70 = m70.astype(np.float32) / 32768
sr2, m77 = wavfile.read(os.path.join(S, "music_77.wav")); m77 = m77.astype(np.float32) / 32768
mus = np.zeros((L, 2), np.float32)
a0 = int(4 * BAR * SR); a1 = int(7 * BAR * SR)
seg = m70[a0:a1]
out = np.zeros_like(seg); blk = SR // 50; zi = None
for b in range(0, len(seg), blk):
    u = min(1.0, (b / SR) / (3 * BAR))
    fc = 260 * (20000 / 260) ** (u ** 1.8)
    sos = butter(2, min(fc, SR / 2 - 100), "low", fs=SR, output="sos")
    if zi is None:
        zi = np.zeros((sos.shape[0], 2, 2))
    y = np.empty_like(seg[b:b + blk])
    for c in range(2):
        y[:, c], zi[:, :, c] = sosfilt(sos, seg[b:b + blk, c], zi=zi[:, :, c])
    out[b:b + blk] = y * (0.2 + 0.8 * u ** 1.4)
mus[a0:a0 + len(out)] += out[:L - a0]
L2 = min(len(m77), L - a1); mus[a1:a1 + L2] += m77[:L2]
mix = amb + mus
mix /= max(1e-6, np.abs(mix).max() / 0.89)
wav = os.path.join(S, "_mixA.wav")
wavfile.write(wav, SR, (mix * 32767).astype(np.int16))
os.makedirs(os.path.dirname(OUTMP4), exist_ok=True)
subprocess.run([FF, "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", os.path.join(OUT, "a%04d.png"), "-i", wav, "-c:v", "libx264", "-crf", "17",
                "-preset", "slow", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", OUTMP4], check=True)
print("ok", OUTMP4, NF, "%.3f s" % DUR)
