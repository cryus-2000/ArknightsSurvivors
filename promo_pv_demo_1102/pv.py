# -*- coding: utf-8 -*-
"""PV 小样拼片：python pv.py [--preview 秒,秒,…] → 合成 1920x1080 30 帧 + music.wav → out.mp4"""
import os, sys, json, glob, subprocess
import numpy as np
from PIL import Image
import imageio_ffmpeg as I
from fx import *
import cards

HERE = os.path.dirname(os.path.abspath(__file__))
B = 4 * P
CLIPS = json.load(open(os.path.join(HERE, "clips.json"), encoding="utf-8"))


def fr(t):
    return int(round(t * FPS))


# 段落时间（秒，按 music.py 的拼接点）
S2, S3, S4, REST, TITLE = 3.288, 14.796, 29.591, 36.167, 36.989
TL = [  # (起, 止, 种类, 参数)
    (0.0, S2, "clip", "open"),
    (S2, S2 + B, "card", "squad"),
    (S2 + B, S2 + 2.5 * B, "card", "operator"),
    (S2 + 2.5 * B, S2 + 5 * B, "clip", "squad"),
    (S2 + 5 * B, S3, "clip", "wheel"),
    (S3, S3 + B, "card", "lamp"),
    (S3 + B, S3 + 3 * B, "clip", "crowd"),
    (S3 + 3 * B, S3 + 5 * B, "clip", "ult_tx"),
    (S3 + 5 * B, S3 + 6.5 * B, "clip", "horde"),
    (S3 + 6.5 * B, S3 + 8.5 * B, "clip", "ult_mz"),
    (S3 + 8.5 * B, S4, "clip", "full"),
    (S4, S4 + 2 * B, "clip", "boss1"),
    (S4 + 2 * B, REST, "clip", "boss2"),
    (REST, TITLE, "black", None),
    (TITLE, 43.4, "card", "title"),
]
CARD = {"squad": cards.card_squad, "operator": cards.card_operator, "lamp": cards.card_lamp, "title": cards.card_title}
_cache = {}


def clip_frame(name, k):
    """clips.json: name → {dir, first}：片段第 k 帧 = dir/f{first+k}.jpg（越界取最后一帧）"""
    c = CLIPS[name]
    d = os.path.join(HERE, c["dir"])
    if d not in _cache:
        _cache[d] = sorted(glob.glob(os.path.join(d, "f*.jpg")))
    fs = _cache[d]
    i = min(len(fs) - 1, max(0, int(c["first"]) + k))
    return Image.open(fs[i]).convert("RGB")


def seg_at(f):
    for i, (a, b, kind, arg) in enumerate(TL):
        if fr(a) <= f < fr(b):
            return i
    return len(TL) - 1


def base_frame(i, f):
    a, b, kind, arg = TL[i]
    k = f - fr(a)
    if kind == "clip":
        return clip_frame(arg, k)
    if kind == "card":
        return CARD[arg](k / FPS).convert("RGB")
    return Image.new("RGB", (W, H), (0, 0, 0))


def render(f):
    i = seg_at(f)
    a, b, kind, arg = TL[i]
    k = f - fr(a)
    left = fr(b) - f
    img = base_frame(i, f)
    nxt = TL[i + 1] if i + 1 < len(TL) else None
    # 片段之间的硬切：切点上 1 帧闪白 + 镜头推一下（6 帧回落）
    if kind == "clip" and i > 0 and TL[i - 1][2] == "clip" and arg not in ("boss1",):
        img = punch(img, 1.0 + 0.05 * max(0.0, 1 - k / 6))
    # 卡 → 实机：最后 6 帧斜切条盖过来，实机前 6 帧斜切条扫走
    if kind == "card" and nxt is not None and nxt[2] == "clip" and arg != "lamp" and left <= 6:
        rgba = img.convert("RGBA")
        slash_bars(rgba, (6 - left) / FPS, 6 / FPS, [CYAN + (255,), PURPLE + (255,), INK + (255,)])
        img = rgba.convert("RGB")
    if kind == "clip" and i > 0 and TL[i - 1][2] == "card" and TL[i - 1][3] != "lamp" and k < 7:
        rgba = img.convert("RGBA")
        slash_bars(rgba, k / FPS, 7 / FPS, [CYAN + (255,), PURPLE + (255,), INK + (255,)], out=True)
        img = rgba.convert("RGB")
    # 灯火卡 → 人群：菱形从中心张开
    if kind == "clip" and i > 0 and TL[i - 1][3] == "lamp" and k < 9:
        prev = cards.card_lamp((fr(a) - fr(TL[i - 1][0]) + k) / FPS).convert("RGB")
        r = (W * 0.8) * ease_out(k / 9) + 1
        prev.paste(img, (0, 0), diamond_mask(r))
        rgba = prev.convert("RGBA")
        ImageDraw.Draw(rgba).polygon([(W / 2, H / 2 - r), (W / 2 + r, H / 2), (W / 2, H / 2 + r), (W / 2 - r, H / 2)], outline=CYAN + (255,), width=14)
        img = rgba.convert("RGB")
    arr = np.asarray(img)
    # 卡点闪白 / 反色
    if kind == "clip" and i > 0 and TL[i - 1][2] == "clip" and k < 2 and arg != "boss1":
        arr = flash(arr, 0.55 if k == 0 else 0.2)
    if arg == "boss1" and k < 4:   # 进高潮：反色两帧 + 闪白
        arr = invert(arr) if k < 2 else flash(arr, 0.6 if k == 2 else 0.25)
    if kind == "card" and k < 2 and arg in ("squad", "lamp"):
        arr = invert(arr) if k == 0 else arr
    if arg == "title" and k < 4:
        arr = flash(arr, [1.0, 0.7, 0.35, 0.12][k])
    if arg == "boss2" and k < 2:
        arr = flash(arr, 0.5 if k == 0 else 0.2)
    if arg == "open" and k < 8:   # 开场从黑淡入
        arr = (arr.astype(np.float32) * (k / 8)).astype(np.uint8)
    t = f / FPS
    if t > 42.6:   # 收尾淡出
        arr = (arr.astype(np.float32) * max(0.0, (43.4 - t) / 0.8)).astype(np.uint8)
    return arr


def main():
    nf = fr(43.4)
    if "--preview" in sys.argv:
        ts = [float(x) for x in sys.argv[sys.argv.index("--preview") + 1].split(",")]
        cols = 4
        rows = (len(ts) + cols - 1) // cols
        sh = Image.new("RGB", (480 * cols, 270 * rows))
        for j, t in enumerate(ts):
            sh.paste(Image.fromarray(render(fr(t))).resize((480, 270)), ((j % cols) * 480, (j // cols) * 270))
        sh.save(os.path.join(HERE, "preview.png"))
        return
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out.mp4")
    ff = I.get_ffmpeg_exe()
    cmd = [ff, "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "%dx%d" % (W, H), "-r", str(FPS), "-i", "-",
           "-i", os.path.join(HERE, "music.wav"), "-c:v", "libx264", "-preset", "slow", "-crf", "21", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", out]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for f in range(nf):
        p.stdin.write(render(f).tobytes())
        if f % 150 == 0:
            print("frame", f, "/", nf, flush=True)
    p.stdin.close()
    p.wait()
    print(out, os.path.getsize(out) / 2 ** 20, "MiB")


if __name__ == "__main__":
    main()
