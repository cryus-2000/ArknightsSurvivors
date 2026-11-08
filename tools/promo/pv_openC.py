# -*- coding: utf-8 -*-
"""片头 C（11-09 整夜：v5 修片——水下关键帧重出去章鱼黑影，k67 只用到水花炸开、硬切进水下；到第 78 小节为止，后段另接）。
以下沿用 v5 说明：片头 v5（用户 11-09 定稿分镜：深海版、删灯室、删第 5 格）。
  第一镜（pv_open1 帧，原样）→ 硬切背侧特写 → 摇臂升高（k24）→ 光束压入海（k46）→ 俯冲入水（k67）
  → 顺光柱下潜（k78）→ 转正俯视（k89）→ 海床光圈（k910）→ 77 drop 闪白 + 方舟幸存者 logo → 78 水月实机 + 名字条
声音：Veo 环境音（低吼可以有），按画面起点放、0.15 秒交叉淡化；配乐 battle2 从入水那一刻（第 74 小节）低通进，77 全开。
画面：生成段统一 4×4 像素化 96 色（同第一镜）；logo 用游戏 logo_mark.png 整数倍最近邻；实机不调色。
  python tools/promo/pv_open4.py <scratchpad> <输出 mp4>
"""
import glob, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageFont
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from pv2d import W, H, FPS, BAR, finish
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
S, OUTMP4 = sys.argv[1], sys.argv[2]
SR = 48000
SH1 = 3 * BAR
# 配乐前（只有环境音，长度自由）
PRE = [("k24", 0.05, 1.9, 1.6), ("k24", 3.6, 8.0, 1.6),   # 1.9–3.6 秒 Veo 硬给海嗣长嘴（两次都有），剪掉
        ("k46", 0.05, 4.0, 1.6), ("k67c", 0.05, 1.9, 1.4)]   # 水花炸开处硬切
# 配乐 74–77（三小节，入水后），各段倍速按时长凑满
POST = [("k78c", 0.05, 4.0, None), ("k89c", 0.05, 4.0, None), ("k910", 0.05, 4.0, None)]
POST_DUR = [1.0 * BAR, 1.0 * BAR, 1.0 * BAR]
GAME = os.path.join(S, "pv_v5", "E_seg_01_win_t000.3.mp4")
GAME_T0, GAME_DUR = 4.0, 0.0   # 片头只到第 78 小节


def run(*a):
    subprocess.run([FF, "-loglevel", "error", "-y", *a], check=True)


def frames(name, src=None, t0=None, dur=None):
    d = os.path.join(S, "fr_" + name)
    if not os.path.isdir(d):
        os.makedirs(d)
        a = []
        if t0 is not None:
            a += ["-ss", str(t0)]
        a += ["-i", src or os.path.join(S, name + ".mp4")]
        if dur is not None:
            a += ["-t", str(dur)]
        run(*a, os.path.join(d, "%04d.png"))
    return sorted(glob.glob(os.path.join(d, "*.png")))


def audio(name, t0, t1, speed, pad=0.15):
    p = os.path.join(S, "_a4_%s.wav" % name)
    t0 = max(0.0, t0 - pad * speed); t1 = t1 + pad * speed
    af = "atempo=%.4f" % speed if speed <= 2 else "atempo=2,atempo=%.4f" % (speed / 2)
    run("-ss", str(t0), "-to", str(t1), "-i", os.path.join(S, name + ".mp4"), "-vn", "-af", af, "-ar", str(SR), "-ac", "2", p)
    return wavfile.read(p)[1].astype(np.float32) / 32768


def fade(a, n=7200):
    n = min(n, len(a) // 4)
    r = np.linspace(0, 1, n)[:, None]
    a[:n] *= r; a[-n:] *= r[::-1]
    return a


def pixel(im, px=4):
    s = im.convert("RGB").resize((W // px, H // px), Image.BOX)
    s = s.quantize(colors=96, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    return s.resize((W, H), Image.NEAREST)


plan = []          # (kind, payload)
amb, amb_t = [], []
s1 = sorted(glob.glob(os.path.join(S, "fr_open", "*.png")))
plan += [("done", p) for p in s1[: int(round(SH1 * FPS))]]
cut = 2 * BAR
amb_t.append(0.0); amb.append(fade(audio("sfx2_climb", 0, 4.0, 4.0 / cut)))
amb_t.append(cut); amb.append(fade(audio("sfx2_lit", 6.25, 6.25 + BAR + 0.02, 1.0)))


def add(name, t0, t1, sp):
    fs = frames(name)
    amb_t.append(len(plan) / FPS)
    n = int(round((t1 - t0) / sp * FPS))
    for k in range(n):
        plan.append(("gen", fs[min(len(fs) - 1, int((t0 + k / FPS * sp) * 24))]))
    amb.append(fade(audio(name, t0, t1, sp)))


for name, t0, t1, sp in PRE:
    add(name, t0, t1, sp)
T_MUSIC = len(plan) / FPS                    # 入水 = 第 74 小节
for (name, t0, t1, _), dur in zip(POST, POST_DUR):
    add(name, t0, t1, (t1 - t0) / dur)
T_LOGO = len(plan) / FPS                     # = 第 77 小节
NLOGO = int(round(BAR * FPS))
plan += [("logo", k) for k in range(NLOGO)]
gfs = []
NG = 0
plan += [("game", (gfs[min(len(gfs) - 1, int(k / FPS * 60))], k)) for k in range(NG)]

# ---- logo 素材 ----
logo = Image.open(os.path.join(ROOT, "game/art/ui/title_deep/logo_mark.png")).convert("RGBA")
LG = logo.resize((logo.width * 3, logo.height * 3), Image.NEAREST)
last_gen = Image.open([p for k, p in plan if k == "gen"][-1]).convert("RGB").resize((W, H))
LOGO_BG = ImageEnhance.Brightness(pixel(last_gen)).enhance(0.25).filter(ImageFilter.GaussianBlur(6))
fb = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 58); fs_ = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 24)

OUT = os.path.join(S, "fr_C")
os.makedirs(OUT, exist_ok=True)
for i, (kind, p) in enumerate(plan):
    outp = os.path.join(OUT, "v%04d.png" % i)
    if kind == "done":
        Image.open(p).save(outp); continue
    if kind == "gen":
        fr = pixel(Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS))
        n_before_logo = int(round(T_LOGO * FPS)) - i
        if n_before_logo <= 6:                       # 77 前 6 帧闪白
            fr = Image.blend(fr, Image.new("RGB", (W, H), (245, 248, 250)), (7 - n_before_logo) / 7)
        finish(fr, i).save(outp); continue
    if kind == "logo":
        k = p
        z = 1.0 + 0.04 * k / NLOGO                  # logo 极慢推近
        lg = LG.resize((int(LG.width * z) // 3 * 3 or LG.width, int(LG.height * z) // 3 * 3 or LG.height), Image.NEAREST)
        fr = LOGO_BG.convert("RGBA")
        lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); lay.paste(lg, ((W - lg.width) // 2, (H - lg.height) // 2), lg)
        fr.alpha_composite(lay.filter(ImageFilter.GaussianBlur(16))); fr.alpha_composite(lay)
        fr = fr.convert("RGB")
        if k < 8:                                    # 从白里落出来
            fr = Image.blend(Image.new("RGB", (W, H), (245, 248, 250)), fr, k / 8)
        if NLOGO - k <= 3:
            fr = Image.blend(fr, Image.new("RGB", (W, H), (0, 0, 0)), (4 - (NLOGO - k)) / 4)
        finish(fr, i).save(outp); continue
    if kind == "game":                               # 实机不调色、不加遮幅；名字条左上，1.6 秒后淡出
        gp, k = p
        fr = Image.open(gp).convert("RGB").resize((W, H))
        a = 1.0 if k < 1.6 * FPS else max(0.0, 1 - (k - 1.6 * FPS) / 18)
        a = min(a, k / 8)
        if a > 0:
            lay = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(lay)
            x, y = 110, 150
            d.text((x, y), "水月", font=fb, fill=(240, 245, 250, int(255 * a)))
            d.text((x + 150, y + 28), "MIZUKI", font=fs_, fill=(120, 220, 230, int(255 * a)))
            d.line((x, y + 84, x + int(380 * min(1, k / 12)), y + 84), fill=(120, 220, 230, int(255 * a)), width=3)
            fr = Image.alpha_composite(fr.convert("RGBA"), lay).convert("RGB")
        fr.save(outp)
NF = len(plan); DUR = NF / FPS

# ---- 混音 ----
mix = np.zeros((int(DUR * SR) + SR, 2), np.float32)
t = np.arange(len(mix)) / SR
for a, t0 in zip(amb, amb_t):
    pos = max(0, int((t0 - 0.15) * SR)); L_ = min(len(a), len(mix) - pos)
    mix[pos:pos + L_] += a[:L_] * 0.9
duck = np.clip(1 - (t - T_MUSIC) / (T_LOGO - T_MUSIC) * 0.6, 0.4, 1.0)
duck[t >= T_LOGO] = 0.15
mix *= duck[:, None]
sr, mus = wavfile.read(os.path.join(S, "open_music.wav"))
mus = mus.astype(np.float32) / 32768
m0 = int(4 * BAR * SR)                        # open_music 从第 70 小节起 → 74
seg = mus[m0:]
out = np.zeros_like(seg); blk = SR // 50; zi = None
for b in range(0, len(seg), blk):
    u = min(1.0, (b / SR) / (3 * BAR))
    fc = 300 * (20000 / 300) ** (u ** 1.6)
    sos = butter(2, min(fc, SR / 2 - 100), "low", fs=SR, output="sos")
    if zi is None:
        zi = np.zeros((sos.shape[0], 2, 2))
    y = np.empty_like(seg[b:b + blk])
    for c in range(2):
        y[:, c], zi[:, :, c] = sosfilt(sos, seg[b:b + blk, c], zi=zi[:, :, c])
    out[b:b + blk] = y * (0.25 + 0.75 * u ** 1.3)
p0 = int(T_MUSIC * SR); L_ = min(len(out), len(mix) - p0)
mix[p0:p0 + L_] += out[:L_]
# open_music 只到第 77 小节；77 以后接 battle2 后续（若有 full_music.wav），否则保持最后一段淡出
full = os.path.join(S, "music_77.wav")
if os.path.exists(full):
    sr2, m2 = wavfile.read(full); m2 = m2.astype(np.float32) / 32768
    q0 = int(T_LOGO * SR); L2 = min(len(m2), len(mix) - q0)
    mix[q0:q0 + L2] += m2[:L2]
mix = mix[: int(DUR * SR)]
mix /= max(1e-6, np.abs(mix).max() / 0.89)
wav = os.path.join(S, "_mix_C.wav")
wavfile.write(wav, SR, (mix * 32767).astype(np.int16))
run("-framerate", str(FPS), "-i", os.path.join(OUT, "v%04d.png"), "-i", wav, "-c:v", "libx264", "-crf", "22", "-preset", "slow",
    "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k", "-shortest", OUTMP4)
print("frames", NF, "dur %.2f" % DUR, "music_in %.2f" % T_MUSIC, "logo %.2f" % T_LOGO)
