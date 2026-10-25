# -*- coding: utf-8 -*-
"""Boss 逐幕演示 mp4（给用户在手机上看，docs/142b §9）：截图流程同 tools/probes/boss_act_gifs.py
（--autotest --bossacts=<spec>，副屏 / 屏幕外、静音、每 3 帧一张），再用 imageio_ffmpeg 的 ffmpeg 编成 H.264 yuv420p，
帧率按日志里的游戏时间算（= 实时；自测每 3 帧约合 0.15 秒游戏时间，约 6.5 帧 / 秒），裁中间 80% 宽的 16:9、缩到 960 宽，无音轨。一次只开 1 个 Godot。

    python tools/probes/boss_act_videos.py ishar knight_boss iberia
    python tools/probes/boss_act_videos.py --video-only ishar        # 不重跑，用已有截图重编
输出 build/boss_acts/<spec>.mp4
"""
import os, subprocess, sys, tempfile
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "probes"))
import boss_act_gifs as bag

W = 960


def encode(spec, out):
    import imageio_ffmpeg
    fs = sorted(f for f in os.listdir(out) if f.startswith("shot_acts_") and f.endswith(".png"))
    if not fs:
        print(spec, "没有截图")
        return None
    tmp = tempfile.mkdtemp(prefix="bossvid_")
    h = int(W * 9 / 16) // 2 * 2
    for i, f in enumerate(fs):
        im = Image.open(os.path.join(out, f)).convert("RGB")
        w0, h0 = im.size
        cw, ch = int(w0 * 0.8), int(w0 * 0.8 * 9 / 16)
        x0, y0 = (w0 - cw) // 2, max(0, (h0 - ch) // 2)
        im.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, h), Image.LANCZOS).save(os.path.join(tmp, "f%04d.png" % i))
    dst = os.path.join(bag.OUT, spec.replace("+", "_") + ".mp4")
    # 实时帧率 = 张数 / 游戏时长（登场 t=150 到最后一行 BOSSACTS gate 的 t）
    import re
    ts = [float(x) for x in re.findall(r"BOSSACTS gate t=([0-9.]+)", open(os.path.join(out, "run.log"), encoding="utf-8", errors="replace").read())]
    fps = len(fs) / max(1.0, (ts[-1] - 150.0)) if ts else 10.0
    cmd = [imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", "%.3f" % fps, "-i", os.path.join(tmp, "f%04d.png"),
           "-c:v", "libx264", "-pix_fmt", "yuv420p", "-preset", "slow", "-crf", "23", "-movflags", "+faststart", "-an", dst]
    subprocess.run(cmd, check=True)
    for f in os.listdir(tmp):
        os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)
    print(dst, "%.1f MB" % (os.path.getsize(dst) / 1048576.0), len(fs), "帧", "%.1f 帧/秒" % fps)
    return dst


def main():
    args = sys.argv[1:]
    only = "--video-only" in args
    specs = [a for a in args if not a.startswith("--")] or ["ishar", "knight_boss", "iberia"]
    os.makedirs(bag.OUT, exist_ok=True)
    for spec in specs:
        out = os.path.join(bag.OUT, spec.replace("+", "_"))
        if not only:
            out, _ = bag.run(spec)
        encode(spec, out)


if __name__ == "__main__":
    main()
