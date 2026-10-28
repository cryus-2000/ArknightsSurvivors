# -*- coding: utf-8 -*-
"""分享卡拍照式出场的录像（10-28 用户「分享卡出来的动效能不能跟拍照一样」）：tests/settlement_btn_rec --share 逐帧存图 → H.264 mp4。
三段：桌面 1280×720 原速（点分享 → 保存 → 关）→ 同一段出场的 1/3 慢放 → 手机横屏 1480×720（--touch）原速。
录屏时音频是静音驱动，快门声按出场帧（快门帘合拢的第一帧）离线混进原速段。录完即删帧目录。
输出主仓库 build/settle_redesign/share_photo.mp4。用法：python tools/probes/share_photo_rec.py
"""
import os, sys, glob, shutil, subprocess, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

TOOLS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
OUT = os.path.join(GR.common_root(), "build", "settle_redesign")
W, H, FPS = 1480, 720, 30


def run(name, res, extra):
    d = os.path.join(OUT, "raw_share_%s" % name, "f")
    shutil.rmtree(os.path.dirname(d), ignore_errors=True)
    os.makedirs(d)
    out, err, to = GR.run_godot([GR.find_godot(), "--path", GAME, "--resolution", res, "--fixed-fps", str(FPS),
                                 "res://tests/settlement_btn_rec.tscn", "--", "--shotdir=" + d, "--share"] + extra, 300)
    fr = sorted(glob.glob(os.path.join(d, "rec_*.png")))
    errs = [l for l in (out + err).splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    if to or not fr or errs:
        print(name, "失败", to, "\n".join(errs[:10]))
    return fr


def open_frame(fr):
    """快门帘合拢：画面上下两条同时变黑的第一帧"""
    for i, p in enumerate(fr):
        im = np.asarray(Image.open(p).convert("L"), dtype=float)
        if im[:40].mean() < 3 and im[-40:].mean() < 3 and i > 5:
            return max(0, i - 1)
    return 0


def main():
    import imageio_ffmpeg
    GR.ensure_imported(GAME)
    os.makedirs(OUT, exist_ok=True)
    desk = run("desktop", "1280x720", [])
    phone = run("phone", "1480x720", ["--touch"])
    o1, o2 = open_frame(desk), open_frame(phone)
    f = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 16) if os.path.exists(r"C:\Windows\Fonts\msyh.ttc") else ImageFont.load_default()
    segs = [(desk, "桌面 16:9 · 原速", 1, o1)]
    segs.append((desk[max(0, o1 - 3):o1 + 36], "出场 1/3 慢放", 3, None))
    segs.append((phone, "手机横屏（触屏）· 原速", 1, o2))
    path = os.path.join(OUT, "share_photo.mp4")
    wav = os.path.join(OUT, "share_photo_audio.wav")
    # 音轨：快门声放到每个原速段的出场帧
    with wave.open(os.path.join(GAME, "audio", "sfx", "ui_shutter.wav")) as w:
        sr = w.getframerate()
        sh = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(float) / 32767 * 10 ** (-4 / 20)
    total = sum(len(s[0]) * s[2] for s in segs)
    aud = np.zeros(int(total / FPS * sr) + len(sh))
    at = 0
    for fr, _, rep, of in segs:
        if of is not None:
            i = int((at + of) / FPS * sr)
            aud[i:i + len(sh)] += sh
        at += len(fr) * rep
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes((np.clip(aud, -1, 1) * 32767).astype(np.int16).tobytes())
    proc = subprocess.Popen([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-", "-i", wav,
                             "-vf", "scale=out_color_matrix=bt709:out_range=tv", "-c:v", "libx264", "-preset", "slow", "-crf", "20",
                             "-pix_fmt", "yuv420p", "-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709",
                             "-color_range", "tv", "-c:a", "aac", "-b:a", "96k", "-shortest", "-movflags", "+faststart", path], stdin=subprocess.PIPE)
    for fr, label, rep, _ in segs:
        for p in fr:
            im = Image.open(p).convert("RGB")
            canvas = Image.new("RGB", (W, H), (0, 0, 0))
            canvas.paste(im, ((W - im.width) // 2, (H - im.height) // 2))
            dr = ImageDraw.Draw(canvas)
            lb = "分享卡拍照式出场  ·  " + label
            dr.rectangle((0, 0, dr.textlength(lb, font=f) + 16, 24), fill=(0, 0, 0))
            dr.text((8, 2), lb, fill=(255, 220, 140), font=f)
            for _ in range(rep):
                proc.stdin.write(canvas.tobytes())
    proc.stdin.close()
    proc.wait()
    os.remove(wav)
    for n in ("desktop", "phone"):
        shutil.rmtree(os.path.join(OUT, "raw_share_%s" % n), ignore_errors=True)   # 帧目录用完即删（含导出的分享卡图）
    print("写出", path, "%.1f MB" % (os.path.getsize(path) / 1048576), "出场帧", o1, o2)


if __name__ == "__main__":
    main()
