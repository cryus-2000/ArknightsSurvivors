#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""歌蕾蒂娅 S3 收尾小水爆（fx/gl_s3_pop，11-07 用户「S3 最后缺一个漩涡压缩之后小型爆炸的特效」）开 / 关对照：
图鉴演示（tests/elite_demo_shot.tscn，S3 模式 2，精二；S3 精二才解锁）30 帧原速连存，左关右开拼 mp4；
另出收尾那一段的 0.5 倍慢放 mp4 和逐拍定格条。GCP 虚拟机上跑，本机不开 Godot。

用法（仓库根目录）：python3 tools/gl_s3_pop_rec.py --out $MEDIA [--start 2 --secs 14]
"""
import argparse, glob, os, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

try:
    import imageio_ffmpeg as _iff
    FF = _iff.get_ffmpeg_exe()   # 虚拟机镜像上没有系统 ffmpeg（render_prep 装的是 imageio-ffmpeg）
except Exception:
    FF = "ffmpeg"

GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "gl_s3_pop")
COLS = [("现在（细水柱收尾）", ["--bal=fx/gl_s3_pop=0"]), ("新版（压缩 → 小水爆）", ["--bal=fx/gl_s3_pop=1"])]
W, H = 640, 360


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def shoot(ci, start, n):
    fdir = os.path.join(BUILD, "c%d" % ci)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=gladiia", "--shot_stage=2", "--shot_mode=2", "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=%d" % W, "--shot_h=%d" % H] + COLS[ci][1]
    out, err, _ = GR.run_godot(args, 900)
    fs = sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    print("c%d" % ci, len(fs), "帧", GR.script_errors(out, err)[:3], flush=True)
    return fs


def label(im, text, f):
    d = ImageDraw.Draw(im)
    d.rectangle((6, 6, 18 + int(d.textlength(text, font=f)), 38), fill=(0, 0, 0))
    d.text((12, 8), text, fill=(255, 255, 255), font=f)


def enc(fdir, mp4, fps):
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", str(fps), "-i", os.path.join(fdir, "f_%04d.png"),
                    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", mp4], check=True)
    print("mp4", mp4, os.path.getsize(mp4) // 1024, "KB", flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.environ.get("MEDIA", os.path.join(ROOT, "build", "gl_s3_pop_out")))
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--secs", type=float, default=14.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cols = [shoot(ci, a.start, int(a.secs * 30)) for ci in range(2)]
    m = min(len(c) for c in cols)
    if m == 0:
        return
    f = font(20)
    fdir = os.path.join(BUILD, "sheet")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    diffs = []
    for i in range(m):
        ims = [Image.open(c[i]).convert("RGB") for c in cols]
        diffs.append(int((np.abs(np.asarray(ims[0], np.int16) - np.asarray(ims[1], np.int16)).sum(axis=2) > 40).sum()))
        sheet = Image.new("RGB", (W * 2 + 4, H), (12, 12, 16))
        for ci, im in enumerate(ims):
            label(im, "歌蕾蒂娅 S3 精二 · " + COLS[ci][0], f)
            sheet.paste(im, (ci * (W + 4), 0))
        sheet.save(os.path.join(fdir, "f_%04d.png" % i))
    enc(fdir, os.path.join(a.out, "gladiia_s3_pop.mp4"), 30)
    # 收尾段：两栏差异最早出现的地方前 0.5 秒起 1.5 秒，0.5 倍慢放 + 逐拍（每 2 帧一张）定格条（2 倍局部）
    hit = [i for i, d in enumerate(diffs) if d > 30]
    if hit:
        s0 = max(0, hit[0] - 15)
        s1 = min(m, s0 + 45)
        sd = os.path.join(BUILD, "slow")
        shutil.rmtree(sd, ignore_errors=True)
        os.makedirs(sd)
        for j, i in enumerate(range(s0, s1)):
            shutil.copy(os.path.join(fdir, "f_%04d.png" % i), os.path.join(sd, "f_%04d.png" % j))
        enc(sd, os.path.join(a.out, "gladiia_s3_pop_slow05.mp4"), 15)
        fr = list(range(hit[0] - 2, min(m, hit[0] + 22), 2))
        strip = Image.new("RGB", (240 * len(fr), 360), (12, 12, 16))
        for k, i in enumerate(fr):
            for ci in range(2):
                im = Image.open(cols[ci][i]).convert("RGB").crop((W // 2 - 60, H // 2 - 70, W // 2 + 60, H // 2 + 20)).resize((240, 180), Image.NEAREST)
                strip.paste(im, (k * 240, ci * 180))
        strip.save(os.path.join(a.out, "gladiia_s3_pop_beats.png"))
        print("收尾差异起点帧", hit[0], flush=True)


if __name__ == "__main__":
    main()
