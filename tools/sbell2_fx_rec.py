#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""圣聆初雪（docs/403 §9）特效审片录像：图鉴演示（tests/fx_audit_shot.tscn，1280×720，--fixed-fps 30 逐帧 = 原速 30 帧、原色）逐招逐档录，
左上角标「招式 · 档位」，静音（不带音轨），拼成一个 mp4。照 typhon_fx_rec.py / typhon_fx_dir.py（docs/404 §8.1：demo_zoom 1.2 ≈ 实机战斗尺寸、
演示关敌人受击白闪 fx/hit_flash_mul=0）。

  python tools/sbell2_fx_rec.py all          全部：积雪 E0 → S1 E0/E1/E2 → S2 开阵 E1/E2 → S3 E2 → 免死 E2 → 终结技 E2
  python tools/sbell2_fx_rec.py one --stage 2 --mode 1 --secs 6 [--extra "--sbbless=3"]     单段（调试，留 png 帧在 build/sbell2_fx/fr_one_*）
  python tools/sbell2_fx_rec.py snow         积雪颜色截图（1 倍原尺寸 + 2 倍放大，给用户顺带确认）
输出 build/sbell2_fx/<名>.mp4。本机同时至多 2 个 Godot（--jobs 缺省 2），静音（--audio-driver Dummy），无窗口。
"""
import argparse, glob, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "sbell2_fx")
TIER = ["精零", "精一", "精二"]
MODE = {3: "特性「无垠的雪景」积雪", 0: "S1「铃音吹雪」", 1: "S2「霜涛覆岭」开阵", 2: "S3「群山俯首」", 4: "终结技「千分之一的心」", 5: "天赋「圣山的祝福」免死"}
ZOOM = 1.2
# (模式, 档, 秒, 额外参数)；模式 5 = 演示 S2 + 到点触发一次免死（调试参数 --sbbless）
GROUPS = {
    "all": [(3, 0, 5, []), (0, 0, 4, []), (0, 1, 4, []), (0, 2, 4, []), (1, 1, 7, []), (1, 2, 7, []), (2, 2, 7, []),
            (5, 2, 5, ["--sbbless=1.2"]), (4, 2, 6, [])],
}


def font(sz):
    from PIL import ImageFont
    for f in ["C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def label(fdir, text):
    from PIL import Image, ImageDraw
    fn = font(26)
    for p in sorted(glob.glob(os.path.join(fdir, "*.png"))):
        im = Image.open(p).convert("RGB")
        d = ImageDraw.Draw(im)
        d.rectangle((10, 10, 24 + int(d.textlength(text, font=fn)), 52), fill=(0, 0, 0))
        d.text((17, 14), text, font=fn, fill=(255, 255, 255))
        im.save(p)


def enc(fdir, pat, mp4):
    subprocess.run([FF, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(fdir, pat), "-an",
                    "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", mp4], check=True)


def gallery_clip(mode, stage, secs, tag, extra=(), keep=False, start=0.6):
    fdir = os.path.join(OUT, "fr_" + tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    n = int(secs * 30)
    gm = 1 if mode == 5 else mode
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/fx_audit_shot.tscn", "--",
            "--shot_op=sbell2", "--shot_stage=%d" % stage, "--shot_mode=%d" % gm, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=1280", "--shot_h=720",
            "--bal=fx/px_plane=1", "--bal=gallery/demo_zoom=%g" % ZOOM, "--bal=fx/hit_flash_mul=0", "--seed=11"] + list(extra)
    out, err, to = GR.run_godot(args, 1800)
    open(os.path.join(OUT, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    errs = GR.script_errors(out or "", err or "")
    nfr = len(glob.glob(os.path.join(fdir, "f_*.png")))
    mp4 = os.path.join(OUT, tag + ".mp4")
    if nfr:
        if not keep:
            label(fdir, "圣聆初雪 · %s · %s" % (MODE[mode], TIER[stage]))
        enc(fdir, "f_%04d.png", mp4)
    if not keep:
        shutil.rmtree(fdir, ignore_errors=True)
    print(tag, "帧", nfr, "脚本错误", errs[:3], "超时" if to else "", flush=True)
    return mp4, errs


def concat(parts, mp4):
    lst = os.path.join(OUT, "_concat.txt")
    with open(lst, "w", encoding="utf-8") as f:
        for p in parts:
            if os.path.exists(p):
                f.write("file '%s'\n" % p.replace("\\", "/"))
    subprocess.run([FF, "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", lst, "-an", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", mp4], check=True)
    os.remove(lst)
    print("→", mp4, "%.1f MB" % (os.path.getsize(mp4) / 1048576.0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["all", "one"])
    ap.add_argument("--stage", type=int, default=2)
    ap.add_argument("--mode", type=int, default=1)
    ap.add_argument("--secs", type=float, default=4.0)
    ap.add_argument("--start", type=float, default=0.6)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--extra", default="")
    ap.add_argument("--name", default="sbell2_fx_demo")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    ex = a.extra.split() if a.extra else []
    if a.cmd == "all":
        clips = GROUPS["all"]
        with ThreadPoolExecutor(a.jobs) as pool:
            res = list(pool.map(lambda c: gallery_clip(c[0], c[1], c[2], "all_%02d_m%d_e%d" % (clips.index(c), c[0], c[1]), list(c[3]) + ex), clips))
        concat([r[0] for r in res], os.path.join(OUT, a.name + ".mp4"))
    elif a.cmd == "one":
        gallery_clip(a.mode, a.stage, a.secs, "one_m%d_e%d" % (a.mode, a.stage), ex, keep=True, start=a.start)


if __name__ == "__main__":
    main()
