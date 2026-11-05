#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""水月终结技转平面送审（docs/261 §8）：并排对照 + 带音效的新版视频，只用 Python + ffmpeg，不开 Godot。

输入：
  原版实录 <主仓库>/Claude outputs/render-ult-mizuki-orig/u_mizuki_31.mp4（GCP ult_rec.py --clips u_mizuki --sfx，integ-1105，开关关）
  新版逐帧 <主仓库>/Claude outputs/ult_px_mizuki_1105/new_frames/（tools/ult_px_mizuki_gif.py 出，15 fps）
  候选音效 <主仓库>/Claude outputs/ult_px_mizuki_1105/sfx/{A,B}/ult_mizuki_*.wav（game/tools/gen_sfx_ult_seg_1030.py --only mizuki [--variant 2]）
输出（同目录）：
  ult_mizuki_before_after.gif / .mp4  左原版实录（含原声）、右新版示意，按冲击帧对齐，30 帧
  ult_mizuki_new_A.mp4 / _B.mp4       新版 + 候选音效 A / B（按 sfx_cues() 的时刻混音）
  sfx_cues.md                         音效清单（槽 / 文件 / 第几秒 / 音量）
"""
import glob, os, subprocess, sys, wave

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ult_px_mizuki_gif as G
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
OUT = os.path.join(G.MAIN, "Claude outputs", "ult_px_mizuki_1105")
ORIG = os.path.join(G.MAIN, "Claude outputs", "render-ult-mizuki-orig", "u_mizuki_31.mp4")
SR = 44100
FONT = "C:/Windows/Fonts/msyh.ttc"


def new_frames():
    return sorted(glob.glob(os.path.join(OUT, "new_frames", "f_*.png")))


def tl_index():
    """新版时间轴：每拍的 (阶段, 招式秒, 冲击帧拍)，以及几个关键拍号"""
    tl = G.timeline()
    i_cast = next(i for i, x in enumerate(tl) if x[0] == "cast")
    i_hf = next(i for i, x in enumerate(tl) if x[2] == 0)
    return tl, i_cast, i_hf


def sfx_cues():
    """[(槽, 新版第几秒（真实时间，15 fps 拍 / 15）, 说明)]：时刻对齐游戏里的触发点"""
    tl, i_cast, i_hf = tl_index()
    cues = [("sf", 0.0, "按 Q 超必杀暂停"), ("cast", i_cast / 15, "放出（起手慢放结束）")]
    JL = G.jellies()
    order = sorted(range(len(JL)), key=lambda i: JL[i]["d0"])
    for n, i in enumerate(order):   # 每只水母冒出一声（3 个音高轮换）
        t = JL[i]["d0"]
        k = next((j for j, x in enumerate(tl) if x[0] == "cast" and x[1] >= t), i_cast)
        cues.append(("rise_%d" % (n % 3 + 1), k / 15, "第 %d 只水母冒出" % (n + 1)))
    kc = next(j for j, x in enumerate(tl) if x[0] == "cast" and x[1] >= G.T_BURST - 0.45)
    cues.append(("compress", kc / 15, "一起压缩、全屏渐暗"))
    cues.append(("burst", i_hf / 15, "一起炸开 = 冲击帧第 1 拍（高潮，余音盖住慢放）"))
    for n in range(3):
        cues.append(("pop_%d" % (n + 1), (i_hf + 4 + 2 * n) / 15, "慢放里每只水母的小水泡"))
    ke = next(j for j, x in enumerate(tl) if x[0] == "cast" and x[1] >= G.T_BURST + 0.9)
    cues.append(("end", ke / 15, "收尾：涟漪退下去"))
    return cues


def read_wav(p):
    with wave.open(p) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float32) / 32767
    return x


def db(x):
    w = int(0.1 * SR)
    c = np.cumsum(np.concatenate([[0], x ** 2]))
    r = np.sqrt(np.max(c[w:] - c[:-w]) / w + 1e-12) if len(x) > w else np.sqrt(np.mean(x ** 2) + 1e-12)
    return 20 * np.log10(r)


def mix(cand, dur):
    buf = np.zeros(int(dur * SR) + SR, np.float32)
    rows = []
    for slot, t, why in sfx_cues():
        p = os.path.join(OUT, "sfx", cand, "ult_mizuki_%s.wav" % slot)
        if not os.path.exists(p):
            continue
        x = read_wav(p)
        i = int(t * SR)
        buf[i:i + len(x)] += x[:len(buf) - i]
        rows.append((slot, os.path.basename(p), t, db(x), len(x) / SR, why))
    pk = np.abs(buf).max()
    if pk > 0.95:
        buf = buf / pk * 0.95
    path = os.path.join(OUT, "_mix_%s.wav" % cand)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((buf * 32767).astype(np.int16).tobytes())
    return path, rows


def phone_sim(path):
    """手机扬声器频响示意：200 Hz 以下 4 阶高通（试听用，不进游戏）"""
    from scipy.signal import butter, sosfilt
    x = read_wav(path)
    y = sosfilt(butter(4, 200, "highpass", fs=SR, output="sos"), x).astype(np.float32)
    out = path.replace(".wav", "_phone.wav")
    with wave.open(out, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(y, -1, 1) * 32767).astype(np.int16).tobytes())
    return out


def main():
    fr = new_frames()
    n = len(fr)
    dur = n / 15
    # 新版 + 候选音效
    md = ["# 水月终结技 · 音效清单（docs/261 §8）\n", "时刻 = 新版送审视频里的秒（按 Q 起算，真实时间）；音量 = 文件本身最响 100 ms RMS（dBFS，docs/113 口径），游戏里按 ult_audio.json 的 vol 再调。\n"]
    NAMES = {"A": "深海水压（库内录音）", "B": "幻象（库内录音）", "C": "原作音源加厚 + 余音 + 压尖（用户 11-05 确认原作音源可用）"}
    for cand in ("A", "B", "C"):
        if not os.path.isdir(os.path.join(OUT, "sfx", cand)):
            continue
        wav, rows = mix(cand, dur)
        phone = phone_sim(wav)   # 手机外放模拟：200 Hz 以下扬声器出不来（4 阶高通）
        for w_, tag in ((wav, ""), (phone, "_phone")):
            mp4 = os.path.join(OUT, "ult_mizuki_new_%s%s.mp4" % (cand, tag))
            subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "15", "-i", os.path.join(OUT, "new_frames", "f_%04d.png"), "-i", w_,
                            "-vf", "fps=30", "-c:v", "libx264", "-crf", "22", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-shortest", mp4], check=True)
            print(mp4)
        md.append("\n## 候选 %s（%s）\n\n| 槽 | 文件 | 第几秒 | 音量 dBFS | 时长 s | 时机 |\n|---|---|---|---|---|---|\n" % (cand, NAMES[cand]))
        for slot, f, t, d, L, why in rows:
            md.append("| %s | sfx/%s/%s | %.2f | %.1f | %.2f | %s |\n" % (slot, cand, f, t, d, L, why))
    open(os.path.join(OUT, "sfx_cues.md"), "w", encoding="utf-8").write("".join(md))
    # 并排：原版实录按冲击帧对齐（原版里冲击帧 = 整屏最白的那一帧）
    tmp = os.path.join(OUT, "_orig")
    os.makedirs(tmp, exist_ok=True)
    for f in glob.glob(os.path.join(tmp, "*.png")):
        os.remove(f)
    subprocess.run([FF, "-y", "-loglevel", "error", "-i", ORIG, "-vf", "scale=640:360", os.path.join(tmp, "o_%04d.png")], check=True)
    of = sorted(glob.glob(os.path.join(tmp, "o_*.png")))
    lum = [np.asarray(Image.open(p).convert("L"), np.float32).mean() for p in of]
    o_hf = int(np.argmax(lum))
    _, _, i_hf = tl_index()
    n_hf30 = i_hf * 2
    pre, post = min(n_hf30, o_hf), min(n * 2 - n_hf30, len(of) - o_hf)
    fnt = ImageFont.truetype(FONT, 20)
    sbs = os.path.join(OUT, "_sbs")
    os.makedirs(sbs, exist_ok=True)
    for f in glob.glob(os.path.join(sbs, "*.png")):
        os.remove(f)
    gif = []
    for k in range(-pre, post):
        a = Image.open(of[o_hf + k]).convert("RGB")
        b = Image.open(fr[(n_hf30 + k) // 2]).convert("RGB").resize((640, 360), Image.LANCZOS)
        im = Image.new("RGB", (1284, 400), (10, 12, 18))
        im.paste(a, (0, 40))
        im.paste(b, (644, 40))
        d = ImageDraw.Draw(im)
        d.text((10, 8), "原版（integ-1105 实录）", fill=(230, 230, 230), font=fnt)
        d.text((654, 8), "新版（转平面，示意场景）", fill=(230, 230, 230), font=fnt)
        im.save(os.path.join(sbs, "s_%04d.png" % (k + pre)))
        if (k + pre) % 2 == 0:
            gif.append(im)
    t0 = (o_hf - pre) / 30
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(sbs, "s_%04d.png"), "-ss", "%.3f" % t0, "-i", ORIG,
                    "-map", "0:v", "-map", "1:a?", "-c:v", "libx264", "-crf", "22", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest",
                    os.path.join(OUT, "ult_mizuki_before_after.mp4")], check=True)
    q = [g.quantize(colors=255, method=Image.MEDIANCUT, dither=Image.NONE) for g in gif]
    q[0].save(os.path.join(OUT, "ult_mizuki_before_after.gif"), save_all=True, append_images=q[1:], duration=int(1000 / 15), loop=0, disposal=1)
    print("并排", len(gif), "拍；原版冲击帧第", o_hf, "帧")


if __name__ == "__main__":
    main()
