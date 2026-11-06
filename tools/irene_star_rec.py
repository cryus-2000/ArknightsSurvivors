#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""艾丽妮普攻星光画法（fx/ir_atk_star，11-07 用户「更喜欢旧版带星光的，现在太象是激光了」）三栏对照：
图鉴演示（tests/elite_demo_shot.tscn，普攻模式 3）30 帧原速连存，左「旧版（转平面前）」/ 中「现在（光锥）」/ 右「新版（星光）」，
精零 / 精一 / 精二各一段 mp4；另出一张定格三栏 + 2 倍局部（给用户确认「星光」指哪种）。GCP 虚拟机上跑，本机不开 Godot。

用法（仓库根目录）：python3 tools/irene_star_rec.py --out $MEDIA [--start 2 --secs 5]
"""
import argparse, glob, os, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as GR

GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "irene_star")
COLS = [("旧版（转平面前）", ["--bal=fx/px_plane=0"]),
        ("现在（光锥）", ["--bal=fx/px_plane=1", "--bal=fx/ir_atk_star=0"]),
        ("新版（星光）", ["--bal=fx/px_plane=1", "--bal=fx/ir_atk_star=1"])]
TIER = {0: "精零", 1: "精一", 2: "精二"}
W, H = 640, 360


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
              "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc"):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def shoot(tier, ci, start, n):
    fdir = os.path.join(BUILD, "e%d_c%d" % (tier, ci))
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=irene", "--shot_stage=%d" % tier, "--shot_mode=3", "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=%d" % W, "--shot_h=%d" % H] + COLS[ci][1]
    out, err, _ = GR.run_godot(args, 900)
    errs = GR.script_errors(out, err)
    fs = sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    print("e%d c%d" % (tier, ci), len(fs), "帧", errs[:3], flush=True)
    return fs


def label(im, text, f):
    d = ImageDraw.Draw(im)
    d.rectangle((6, 6, 18 + int(d.textlength(text, font=f)), 38), fill=(0, 0, 0))
    d.text((12, 8), text, fill=(255, 255, 255), font=f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.environ.get("MEDIA", os.path.join(ROOT, "build", "irene_star_out")))
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--secs", type=float, default=5.0)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    n = int(a.secs * 30)
    f = font(20)
    for tier in (0, 1, 2):
        cols = [shoot(tier, ci, a.start, n) for ci in range(3)]
        m = min(len(c) for c in cols)
        if m == 0:
            continue
        fdir = os.path.join(BUILD, "sheet_e%d" % tier)
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        # 定格：中栏和右栏差得最多的那一帧（刺击最显眼）
        best, bk = -1, 0
        for i in range(m):
            sheet = Image.new("RGB", (W * 3 + 8, H), (12, 12, 16))
            ims = [Image.open(c[i]).convert("RGB") for c in cols]
            for k, im in enumerate(ims):
                label(im, "%s %s" % (TIER[tier], COLS[k][0]), f)
                sheet.paste(im, (k * (W + 4), 0))
            sheet.save(os.path.join(fdir, "f_%04d.png" % i))
            e = int((np.abs(np.asarray(ims[1], np.int16) - np.asarray(ims[0], np.int16)).sum(axis=2) > 60).sum())
            if e > best:
                best, bk = e, i
        mp4 = os.path.join(a.out, "irene_atk_star_e%d.mp4" % tier)
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, "f_%04d.png"),
                        "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", mp4], check=True)
        print("mp4", mp4, flush=True)
        # 定格三栏 + 下方 2 倍局部（以她为中心裁 320×120）
        st = Image.open(os.path.join(fdir, "f_%04d.png" % bk))
        big = Image.new("RGB", (st.width, H + 240 + 8), (12, 12, 16))
        big.paste(st, (0, 0))
        for k in range(3):
            im = Image.open(cols[k][bk]).convert("RGB").crop((W // 2 - 160, H // 2 - 80, W // 2 + 160, H // 2 + 40)).resize((640, 240), Image.NEAREST)
            big.paste(im, (k * (W + 4), H + 8))
        big.save(os.path.join(a.out, "irene_atk_star_e%d_still.png" % tier))


if __name__ == "__main__":
    main()
