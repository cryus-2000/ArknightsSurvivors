#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""维什戴尔红色体积雾送审录像（11-06，fx/wd_fog_v / fx/wd_smoke）：图鉴演示（tests/elite_demo_shot.tscn）精二逐招连拍，
三栏同一招同一时刻对齐：① 11-05 第四版淡薄雾（wd_fog_v=0）② 红色体积雾（缺省）③ 体积雾 + 第三版式烟团（wd_smoke=1）；
每招一行（普攻 / S1 / S2 / S3），拼成 30 帧原速 mp4（原色，不缩放颜色）。本机串行、窗口在屏幕外、静音（godot_runner）。

  python tools/wd_fog_rec.py --out "E:/ArknightsSurvivors/Claude outputs/wisadel_fog_1106" [--secs 4] [--reuse]
"""
import argparse, glob, os, shutil, subprocess, sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "wd_fog")
MODES = [(3, "普攻 炮击"), (0, "S1 定点清算"), (1, "S2 饱和复仇"), (2, "S3 爆裂黎明")]
COLS = [("v4", ["--bal=fx/wd_fog_v=0"], "① 现在（11-05 淡薄雾）"), ("v5", [], "② 红色体积雾"), ("v5s", ["--bal=fx/wd_smoke=1"], "③ 体积雾 + 烟团")]
W, H = 1280, 720
CROP = (320, 140, 960, 500)   # 640 × 360 局部（演示里维什戴尔在画面中间偏左，炮击落点在右）


def font(sz):
    for p in ("C:/Windows/Fonts/msyh.ttc", "msyh.ttc"):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


def shoot(mode, col, extra, start, n, reuse):
    fdir = os.path.join(BUILD, "m%d_%s" % (mode, col))
    if reuse and len(glob.glob(os.path.join(fdir, "f_*.png"))) >= n:
        return sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=wisadel", "--shot_stage=2", "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=%d" % W, "--shot_h=%d" % H,
            "--bal=fx/px_plane=1", "--bal=growth/late_shape=1"] + extra
    out, err, to = GR.run_godot(args, 900)
    open(os.path.join(BUILD, "log_m%d_%s.txt" % (mode, col)), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    errs = GR.script_errors(out, err)
    if errs:
        print("脚本错误", mode, col, errs[:3])
    return sorted(glob.glob(os.path.join(fdir, "f_*.png")))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--secs", type=float, default=4.0)
    ap.add_argument("--reuse", action="store_true")
    a = ap.parse_args()
    n = int(a.secs * 30)
    os.makedirs(BUILD, exist_ok=True)
    fr = {}
    for mode, _ in MODES:
        for col, extra, _ in COLS:
            fr[(mode, col)] = shoot(mode, col, extra, a.start, n, a.reuse)
            print("m%d %s %d 帧" % (mode, col, len(fr[(mode, col)])), flush=True)
    m = min(len(v) for v in fr.values())
    if m == 0:
        sys.exit("没有帧")
    cw, ch = CROP[2] - CROP[0], CROP[3] - CROP[1]
    lab_h, row_lab = 40, 150
    sheet_w = row_lab + cw * len(COLS)
    sheet_h = lab_h + ch * len(MODES)
    tmp = os.path.join(BUILD, "sheet")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    fb, fs = font(24), font(22)
    for i in range(m):
        im = Image.new("RGB", (sheet_w, sheet_h), (12, 12, 14))
        d = ImageDraw.Draw(im)
        for ci, (_, _, name) in enumerate(COLS):
            d.text((row_lab + ci * cw + 12, 6), name, fill=(235, 235, 235), font=fb)
        for ri, (mode, mname) in enumerate(MODES):
            d.text((10, lab_h + ri * ch + ch // 2 - 12), mname, fill=(235, 235, 235), font=fs)
            for ci, (col, _, _) in enumerate(COLS):
                src = Image.open(fr[(mode, col)][i]).convert("RGB").crop(CROP)
                im.paste(src, (row_lab + ci * cw, lab_h + ri * ch))
        im.save(os.path.join(tmp, "s_%04d.png" % i))
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    mp4 = os.path.join(a.out, "wisadel_fog_e2.mp4")
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "s_%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", mp4], check=True)
    print(mp4)


if __name__ == "__main__":
    main()
