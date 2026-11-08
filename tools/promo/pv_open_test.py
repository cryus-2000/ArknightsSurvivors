# -*- coding: utf-8 -*-
"""片头硬切试作（用户 11-08 先试一镜）：照住（第一镜尾）→ 扎水（单图小动作，取水面裂开前 0.9 秒）→ 硬切 → 水下下沉（单图小动作）。
画面走 pv_pixelize：统一调色板 32 色、6×6 像素格、12 帧/秒。声音：Sonniss 授权素材（海浪 + 入水冲击气泡），不放任何生物叫声。
  python tools/promo/pv_open_test.py <scratchpad> <输出 mp4> [px] [colors] [step]
"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, finish
from pv_pixelize import build_palette, pixelize
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
S, OUTMP4 = sys.argv[1], sys.argv[2]
PX = int(sys.argv[3]) if len(sys.argv) > 3 else 6
NC = int(sys.argv[4]) if len(sys.argv) > 4 else 32
STEP = int(sys.argv[5]) if len(sys.argv) > 5 else 5
LIB = "E:/ArknightsSurvivors/build/sfx_lib/sonniss_gdc2026/extracted/"
SR = 48000


def run(*a):
    subprocess.run([FF, "-loglevel", "error", "-y", *a], check=True)


def frames(name, mp4):
    d = os.path.join(S, "fr_" + name)
    if not os.path.isdir(d):
        os.makedirs(d)
        run("-i", mp4, os.path.join(d, "%03d.png"))
    return sorted(glob.glob(os.path.join(d, "*.png")))


lit = sorted(glob.glob(os.path.join(S, "fr_lit", "*.png")))
dive = frames("t_dive", os.path.join(S, "t_dive.mp4"))
sink = frames("t_sink", os.path.join(S, "t_sink.mp4"))
# (帧列表, 源起秒, 时长秒)
SHOTS = [(lit, 0.6, 1.2), (dive, 0.0, 0.9), (sink, 0.0, 3.2)]
plan = []
for fs, t0, dur in SHOTS:
    n = int(round(dur * FPS))
    plan += [fs[min(len(fs) - 1, int((t0 + k / FPS) * 24))] for k in range(n)]
CUT = int(round((1.2 + 0.9) * FPS))           # 硬切进水下的帧
pal = build_palette([Image.open(plan[i]) for i in range(0, len(plan), 12)], NC, PX)
OUT = os.path.join(S, "fr_test_%d_%d_%d" % (PX, NC, STEP))
os.makedirs(OUT, exist_ok=True)
last = None
for i, p in enumerate(plan):
    if i % STEP == 0 or i == CUT or last is None:   # 切点那一帧立刻换，不等步进
        last = pixelize(Image.open(p).resize((W, H), Image.LANCZOS), pal, PX)
    finish(last, i).save(os.path.join(OUT, "f%04d.png" % i))
DUR = len(plan) / FPS


def load(rel, t0=0.0, dur=None):
    p = os.path.join(S, "_snd.wav")
    a = ["-ss", str(t0), "-i", LIB + rel]
    if dur:
        a += ["-t", str(dur)]
    run(*a, "-ac", "2", "-ar", str(SR), p)
    return wavfile.read(p)[1].astype(np.float32) / 32768


def lp(x, fc):
    sos = butter(4, fc, "low", fs=SR, output="sos")
    return sosfilt(sos, x, axis=0)


mix = np.zeros((int(DUR * SR) + SR, 2), np.float32)
c = int((1.2 + 0.9) * SR)
waves = load("Just Sound Effects - Rocky Coast of Norway/WATRWave_Soft Waves Cliffs_JSE_RCoN_Stereo.wav", 3.0, DUR + 1)
wind = load("344 Audio - Elemental Palette Designed Vol. 1/WINDDsgn_Wind, Rush, Whoosh, Long x5 01_344 Audio_Elemental Palette Designed Vol 1.wav", 0.0, DUR + 1)
hit = load("Epic Stock Media - Elemental Mutation Whooshes and Impacts/WATRImpt_Impact Water Deep Submerge Bubble Drown Ship Hit 05_ESM_EMWI.wav")
# 水面上：海浪 + 风；入水后：同一条海浪低通到 400 Hz、压低（水下闷声）
fit = lambda a: np.resize(a, (len(mix), 2))           # 素材比片段短就循环
waves, wind = fit(waves), fit(wind)
above = waves * 0.8 + wind * 0.25
below = lp(waves, 400) * 0.9
n = min(len(above), len(mix))
xf = int(0.03 * SR)
g = np.clip((np.arange(n) - c) / xf, 0, 1)[:, None]
mix[:n] += above[:n] * (1 - g) + below[:n] * g
# 入水冲击：峰值对准硬切点
pk = int(np.argmax(np.abs(hit).sum(1)))
s0 = max(0, c - pk)
mix[s0:s0 + len(hit)] += hit[: len(mix) - s0] * 1.0
mix = mix[: int(DUR * SR)]
mix /= max(1e-6, np.abs(mix).max() / 0.89)
wav = os.path.join(S, "_test_mix.wav")
wavfile.write(wav, SR, (mix * 32767).astype(np.int16))
run("-framerate", str(FPS), "-i", os.path.join(OUT, "f%04d.png"), "-i", wav, "-c:v", "libx264", "-crf", "20",
    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", OUTMP4)
print("ok", DUR, "hit peak at %.2fs in clip" % (pk / SR))
