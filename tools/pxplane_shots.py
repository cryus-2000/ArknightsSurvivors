#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""转平面试验（docs/246 斯卡蒂 / docs/255 流明，fx/px_plane）的看图工具（--op 选干员，缺省 skadi）。本机 Windows，窗口在屏幕外、静音（godot_runner），一次只开 1 个 Godot（串行）。

  demo  图鉴演示模式（tests/elite_demo_shot.tscn）逐招连拍：三种画法（0 当前游戏 / 2 旧做法原样贴 / 1 转平面）× 精英档，
        同一招同一时刻对齐（同一演示、同一帧号），拼「三栏对比」：每招一张 + 2 倍局部；另拼三档并排（只转平面版）。
  rec   同种子同一局 8:00 起 20 秒，fx/px_plane = 0 / 1 各跑一遍（--realtime，30 帧原速）拼左关右开 mp4；同局收 TRACE 逐行比。
  trace 只比 TRACE（--fixed-fps 60 非实时）：fx/px_plane = 0 / 1 / 2 三局两两比。

用法（仓库根目录）：
    python tools/pxplane_shots.py demo --out "E:/ArknightsSurvivors/Claude outputs/px_plane_skadi_1105"
    python tools/pxplane_shots.py rec  --out ... --seed 11 --from 480 --secs 20
    python tools/pxplane_shots.py trace --seed 23 --maxt 300 --extra "--elite2 --sptest"
"""
import argparse, glob, os, shutil, subprocess, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "pxplane")
LOGS = os.path.join(BUILD, "logs")
OPS = {"skadi": ("斯卡蒂", {3: "普攻", 0: "S1 迅捷打击·γ型", 1: "S2 跃浪击", 2: "S3 涌潮悲歌"}),
       "lumen": ("流明", {3: "普攻 荧光", 0: "S1 沐雨", 1: "S2 沛霖", 2: "S3 灯火不灭"})}
OP = "skadi"
MODE_NAME = dict(OPS[OP][1])
MODE_KEY = {3: "atk", 0: "s1", 1: "s2", 2: "s3"}
MODE_TIERS = {3: [0, 1, 2], 0: [0, 1, 2], 1: [1, 2], 2: [2]}
COLS = [(0, "① 当前游戏原样"), (2, "② pixelfx 原样直接贴（旧做法）"), (1, "③ 转平面 + 统一像素 + 吃光 + Noita")]
FONT = "C:/Windows/Fonts/msyh.ttc"


def font(sz):
    return ImageFont.truetype(FONT, sz)


def shoot(px, tier, mode, start, every, n, w=1280, h=720, extra=(), suffix=""):
    tag = "e%d_m%d_px%d%s" % (tier, mode, px, suffix)
    fdir = os.path.join(BUILD, "demo", tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=" + OP, "--shot_stage=%d" % tier, "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=%d" % every, "--shot_n=%d" % n, "--shot_w=%d" % w, "--shot_h=%d" % h,
            "--bal=fx/px_plane=%d" % px, "--bal=fx/recipe_log=1"] + list(extra)
    out, err, to = GR.run_godot(args, 900)
    os.makedirs(LOGS, exist_ok=True)
    open(os.path.join(LOGS, "demo_" + tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    errs = GR.script_errors(out, err)
    ev = [l.split() for l in (out or "").splitlines() if l.startswith("FXRLOG")]
    return tag, sorted(glob.glob(os.path.join(fdir, "f_*.png"))), errs, ev


def energy(frames, ref):
    """每帧与「当前游戏」同帧的差（特效差异能量）：找特效最显眼的帧"""
    e = []
    for f, r in zip(frames, ref):
        a = np.asarray(Image.open(f).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(r).convert("RGB"), dtype=np.int16)
        e.append(int((np.abs(a - b).sum(axis=2) > 60).sum()))
    return e


def label(im, text, sz=26):
    d = ImageDraw.Draw(im)
    f = font(sz)
    tw = d.textlength(text, font=f)
    d.rectangle((8, 8, 24 + tw, 16 + sz + 10), fill=(0, 0, 0))
    d.text((16, 10), text, fill=(255, 255, 255), font=f)
    return im


def sheet3(fr, k, base, title, out):
    font_b = font(30)
    # 三栏：同一帧号（同一时刻、同一画面）
    ims = [Image.open(fr[px][k]).convert("RGB") for px, _ in COLS]
    W, H = ims[0].size
    sheet = Image.new("RGB", (W * 3 + 8, H + 56), (12, 12, 16))
    dd = ImageDraw.Draw(sheet)
    dd.text((12, 8), title, fill=(230, 230, 230), font=font_b)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        sheet.paste(label(im.copy(), lab), (i * (W + 4), 56))
    sheet.save(os.path.join(out, base + ".png"))
    # 2 倍局部：以「转平面」帧里差异最大处为中心，取 320×180 放大到 640×360
    a1 = np.asarray(ims[2], dtype=np.int16)
    a0 = np.asarray(ims[0], dtype=np.int16)
    m = (np.abs(a1 - a0).sum(axis=2) > 60)
    ys, xs = np.nonzero(m)
    cx, cy = (int(np.median(xs)), int(np.median(ys))) if len(xs) else (W // 2, H // 2)
    cw, ch = 320, 180
    x0 = min(max(0, cx - cw // 2), W - cw)
    y0 = min(max(0, cy - ch // 2), H - ch)
    crop = Image.new("RGB", (cw * 2 * 3 + 8, ch * 2 + 56), (12, 12, 16))
    dd = ImageDraw.Draw(crop)
    dd.text((12, 8), "2 倍局部（最近邻放大） · " + title.split(" · 同一帧")[0], fill=(230, 230, 230), font=font_b)
    for i, (im, (px, lab)) in enumerate(zip(ims, COLS)):
        c = im.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST)
        crop.paste(label(c, lab, 20), (i * (cw * 2 + 4), 56))
    crop.save(os.path.join(out, base + "_x2.png"))
    return ims, x0, y0, cw, ch, W, H


def demo(a):
    out = a.out
    os.makedirs(out, exist_ok=True)
    res = {}
    for mode in [int(x) for x in a.modes.split(",")]:
        for tier in MODE_TIERS[mode]:
            for px, _ in COLS:
                tag, frames, errs, ev = shoot(px, tier, mode, a.start, a.every, max(a.n, 190) if (OP == "lumen" and mode == 2) else a.n)
                print(tag, len(frames), "帧", errs[:2], flush=True)
                res[(tier, mode, px)] = frames
                if px == 1:
                    res[(tier, mode, "ev")] = ev
    font_b = font(30)
    for mode in [int(x) for x in a.modes.split(",")]:
        tiers_up = []
        for tier in MODE_TIERS[mode]:
            fr = {px: res[(tier, mode, px)] for px, _ in COLS}
            n = min(len(v) for v in fr.values())
            if n == 0:
                continue
            e = energy(fr[1][:n], fr[0][:n])
            k = int(np.argmax(e))
            # 技能招：按技能事件帧对齐（能量峰常落在普攻上）。S1 出手即判定；S2 起跳约 15 帧后落地；S3 取起手后约 0.3 秒（大水柱 + 第一记暗蓝旋斩）
            OFF = {0: 3, 1: 12, 2: 10} if OP == "skadi" else {0: 4, 1: 3, 2: 4}
            if mode in OFF:
                evs = [int(x[3]) for x in res.get((tier, mode, "ev"), []) if len(x) > 3 and x[2] == "skill%d" % mode and x[3].isdigit()]
                f0 = int(a.start * 30)
                cand = [(fe + OFF[mode] - f0) // a.every for fe in evs if (fe + OFF[mode] - f0) // a.every >= 0]
                if cand and cand[0] < n:
                    k = cand[0]
            base = "cmp_%s_e%d" % (MODE_KEY[mode], tier)
            ims, x0, y0, cw, ch, W, H = sheet3(fr, k, base, "%s %s · 精英 %d · 同一帧（演示第 %d 张）" % (OPS[OP][0], MODE_NAME[mode], tier, k), out)
            if OP == "lumen" and mode == 2:   # 灯火不灭结束光爆：起手后约 10 秒，按光爆事件帧另出一张
                evb = [int(x[3]) for x in res.get((tier, mode, "ev"), []) if len(x) > 3 and x[2] == "lm_burst" and x[3].isdigit()]
                kb = [(fe + 2 - int(a.start * 30)) // a.every for fe in evb]
                kb = [x for x in kb if 0 <= x < n]
                if kb:
                    sheet3(fr, kb[0], "cmp_s3burst_e2", "%s S3 灯火不灭 · 结束光爆 · 精英 2 · 同一帧（演示第 %d 张）" % (OPS[OP][0], kb[0]), out)
            # 三档并排：转平面版，命中峰前后 5 帧
            idx = [max(0, min(n - 1, k + d)) for d in (-2, -1, 0, 2, 5)]
            row = [Image.open(fr[1][j]).convert("RGB").crop((x0 - 160 if x0 >= 160 else 0, max(0, y0 - 90), min(W, x0 + cw + 160), min(H, y0 + ch + 90))) for j in idx]
            tiers_up.append((tier, row))
            print("三栏", base, "帧", k, flush=True)
        if tiers_up:
            rw, rh = tiers_up[0][1][0].size
            sheet = Image.new("RGB", (100 + rw * 5 + 16, 56 + (rh + 8) * len(tiers_up)), (12, 12, 16))
            dd = ImageDraw.Draw(sheet)
            dd.text((12, 8), "转平面版三档 · %s %s（每行一档，命中前后 5 帧）" % (OPS[OP][0], MODE_NAME[mode]), fill=(230, 230, 230), font=font_b)
            for r, (tier, row) in enumerate(tiers_up):
                y = 56 + r * (rh + 8)
                dd.text((16, y + rh // 2 - 18), "E%d" % tier, fill=(255, 255, 255), font=font(34))
                for j, im in enumerate(row):
                    sheet.paste(im.resize((rw, rh)), (100 + j * (rw + 4), y))
            sheet.save(os.path.join(out, "tiers_%s.png" % MODE_KEY[mode]))


def fps_cmp(a):
    """帧率统一前后：同一招（普攻 E2 / S1 E2）同一演示，fx/px_plane_fps = 12.8（各件小数帧率 + 平滑位移）vs 15（统一节拍），
    逐帧连拍（30 帧原速），左右并排 mp4 + 局部 2 倍"""
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    os.makedirs(a.out, exist_ok=True)
    for mode in (3, 0):
        dirs = []
        for fps in ("12.8", "15"):
            tag, frames, errs, ev = shoot(1, 2, mode, 2.0, 1, 150, extra=["--bal=fx/px_plane_fps=" + fps], suffix="_fps" + fps.replace(".", ""))
            print(tag, len(frames), errs[:2], flush=True)
            dirs.append(os.path.join(BUILD, "demo", tag))
        # 局部：以斯卡蒂附近（演示镜头中心）为准，取 480×270 放大 2 倍
        lab = os.path.join(BUILD, "_fps_labels.png")
        im = Image.new("RGBA", (1924, 540), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(26)
        for i, t in enumerate(["统一前：各件小数帧率（12.8 fps）+ 60 Hz 平滑位移", "统一后：全局 15 fps 节拍 + 位置按拍跳格"]):
            x = i * 964
            d.rectangle((x + 8, 8, x + 24 + int(d.textlength(t, font=f)), 50), fill=(0, 0, 0, 180))
            d.text((x + 16, 12), t, fill=(255, 255, 255, 255), font=f)
        im.save(lab)
        mp4 = os.path.join(a.out, "fps_before_after_%s.mp4" % MODE_KEY[mode])
        crop = "crop=480:270:400:225,scale=960:540:flags=neighbor"
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(dirs[0], "f_%04d.png"), "-framerate", "30", "-i", os.path.join(dirs[1], "f_%04d.png"),
                        "-i", lab, "-filter_complex", "[0:v]%s,pad=964:540:0:0:black[l];[1:v]%s[r];[l][r]hstack=inputs=2[h];[h][2:v]overlay=0:0[v]" % (crop, crop),
                        "-map", "[v]", "-c:v", "libx264", "-crf", "18", "-pix_fmt", "yuv420p", mp4], check=True)
        print("录像", mp4, flush=True)


def run(tag, extra, fps, fdir=None):
    os.makedirs(LOGS, exist_ok=True)
    args = [GR.find_godot(), "--path", GAME, "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", str(fps), "--",
            "--balance", "--nodeath", "--trace=1"] + extra
    if fdir:
        shutil.rmtree(fdir, ignore_errors=True)
        os.makedirs(fdir)
        args += ["--shotdir=" + fdir.replace(os.sep, "/")]
    out, err, to = GR.run_godot(args, 5400)
    open(os.path.join(LOGS, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return tag, len([l for l in (out or "").splitlines() if l.startswith("TRACE")]), GR.script_errors(out, err)[:3], to


def traces(tag):
    p = os.path.join(LOGS, tag + ".log")
    return [l for l in open(p, encoding="utf-8").read().splitlines() if l.startswith("TRACE")] if os.path.exists(p) else []


def diff(a, b):
    ta, tb = traces(a), traces(b)
    n = sum(1 for x, y in zip(ta, tb) if x != y) + abs(len(ta) - len(tb))
    same = n == 0 and len(ta) > 0
    print("%s vs %s：TRACE %d / %d 行，%s" % (a, b, len(ta), len(tb), "逐行一致" if same else "有差异 %d 行" % n), flush=True)
    for i, (x, y) in enumerate(zip(ta, tb)):
        if x != y:
            print("  第 %d 行：\n   %s\n   %s" % (i + 1, x[:200], y[:200]))
            break
    return same


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["demo", "rec", "trace", "diff", "fps"])
    ap.add_argument("--out", default=os.path.join(BUILD, "out"))
    ap.add_argument("--modes", default="3,0,1,2")
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--squad", default="")
    ap.add_argument("--from", dest="t0", type=int, default=480)
    ap.add_argument("--secs", type=int, default=20)
    ap.add_argument("--maxt", type=int, default=300)
    ap.add_argument("--extra", default="")
    ap.add_argument("--pxs", default="0,1")
    ap.add_argument("--op", default="skadi", choices=sorted(OPS))
    ap.add_argument("--crf", type=int, default=20)
    a = ap.parse_args()
    global OP
    OP = a.op
    MODE_NAME.clear()
    MODE_NAME.update(OPS[OP][1])
    base = ["--seed=%d" % a.seed, "--op=" + OP] + (["--squad=" + a.squad] if a.squad else []) + a.extra.split()
    if a.cmd == "demo":
        demo(a)
        return
    if a.cmd == "fps":
        fps_cmp(a)
        return
    tags = []
    if a.cmd == "rec":
        for px in (0, 1):   # 串行：本机同一时间只开 1 个 Godot
            tag = "rec%d_%s_s%d_%d" % (px, OP, a.seed, a.t0)
            ex = base + ["--bal=fx/px_plane=%d" % px, "--realtime", "--rtfrom=%d" % a.t0, "--recframes=%d,%d" % (a.t0, a.secs * 30), "--maxt=%d" % (a.t0 + a.secs + 1)]
            print(run(tag, ex, 30, os.path.join(BUILD, tag + "_frames")), flush=True)
            tags.append(tag)
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
        d0, d1 = [os.path.join(BUILD, t + "_frames") for t in tags]
        n = min(len(glob.glob(os.path.join(d0, "rec_*.png"))), len(glob.glob(os.path.join(d1, "rec_*.png"))))
        lab = os.path.join(BUILD, "_rec_labels.png")
        im = Image.new("RGBA", (2560 + 4, 720), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        f = font(28)
        for i, t in enumerate(["关（当前游戏）", "开（fx/px_plane = 1 转平面）"]):
            x = i * 1284
            d.rectangle((x + 10, 660, x + 30 + int(d.textlength(t, font=f)), 705), fill=(0, 0, 0, 170))
            d.text((x + 20, 664), t, fill=(255, 255, 255, 255), font=f)
        im.save(lab)
        os.makedirs(a.out, exist_ok=True)
        mp4 = os.path.join(a.out, "late_%dm%02d_onoff.mp4" % (a.t0 // 60, a.t0 % 60))
        subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(d0, "rec_%05d.png"), "-framerate", "30", "-i", os.path.join(d1, "rec_%05d.png"),
                        "-i", lab, "-filter_complex", "[0:v]pad=1284:720:0:0:black[l];[l][1:v]hstack=inputs=2[h];[h][2:v]overlay=0:0[v]", "-map", "[v]", "-frames:v", str(n),
                        "-c:v", "libx264", "-crf", str(a.crf), "-pix_fmt", "yuv420p", mp4], check=True)
        print("录像", mp4, "%d 帧" % n, "%.1f MB" % (os.path.getsize(mp4) / 1048576.0))
    elif a.cmd == "trace":
        for px in [int(x) for x in a.pxs.split(",")]:
            tag = "trace%d_%s_s%d" % (px, OP, a.seed)
            print(run(tag, base + ["--bal=fx/px_plane=%d" % px, "--maxt=%d" % a.maxt], 60), flush=True)
            tags.append(tag)
    else:
        tags = [os.path.basename(f)[:-4] for f in sorted(glob.glob(os.path.join(LOGS, "trace*_%s_s%d.log" % (OP, a.seed))))]
    ok = True
    for t in tags[1:]:
        ok &= diff(tags[0], t)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
