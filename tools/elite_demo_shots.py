#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""精英化形态的图鉴演示连拍（docs/91 §24）：跑 game/tests/elite_demo_shot.tscn（图鉴演示模式），每名干员每个阶段拍一串，
拼成拼图（_sheet.png，12 张）与短 GIF（.gif）。窗口开在屏幕外、不抢焦点、静音（tools/godot_runner.py，--audio-driver Dummy）。

用法（仓库根目录）：
    python tools/elite_demo_shots.py --ops logos,eyjafjalla,skadi,ulpianus --stages 1,2 --out build/elite2_shots
    python tools/elite_demo_shots.py --ops skadi --stages 2 --mode 3          # 只看普攻（图鉴的「普攻」模式）
"""
import argparse, glob, os, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def shoot(godot, op, stage, mode, out, start, every, n):
    tag = "%s_e%d%s" % (op, stage, "" if mode < 0 else "_m%d" % mode)
    fdir = os.path.join(out, tag + "_frames")
    os.makedirs(fdir, exist_ok=True)
    for f in glob.glob(os.path.join(fdir, "*.png")):
        os.remove(f)
    args = [godot, "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=%d" % stage, "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=%d" % every, "--shot_n=%d" % n]
    outp, err, to = GR.run_godot(args, 600)
    errs = GR.script_errors(outp, err)
    frames = sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    if not frames:
        return tag, "没有截到图" + ("（超时）" if to else ""), errs
    from PIL import Image
    ims = [Image.open(f).convert("RGB") for f in frames]
    w, h = ims[0].size
    pick = [ims[int(i * (len(ims) - 1) / 11)] for i in range(12)] if len(ims) >= 12 else ims
    cols = 4
    rows = (len(pick) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w // 2, rows * h // 2), (10, 12, 18))
    for i, im in enumerate(pick):
        sheet.paste(im.resize((w // 2, h // 2), Image.LANCZOS), ((i % cols) * w // 2, (i // cols) * h // 2))
    sheet.save(os.path.join(out, tag + "_sheet.png"))
    gif = [im.resize((w * 3 // 4, h * 3 // 4), Image.LANCZOS).quantize(colors=128, method=Image.Quantize.MEDIANCUT) for im in ims]
    gif[0].save(os.path.join(out, tag + ".gif"), save_all=True, append_images=gif[1:], duration=int(1000 * every / 30), loop=0, optimize=True)
    return tag, "%d 张" % len(ims), errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", required=True)
    ap.add_argument("--stages", default="1,2")
    ap.add_argument("--mode", type=int, default=-1, help="-1 轮播技能 / 0–2 只放该技能 / 3 只普攻（同图鉴）")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "elite2_shots"))
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--every", type=int, default=3)
    ap.add_argument("--n", type=int, default=80)
    ap.add_argument("--jobs", type=int, default=2)
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)   # Godot 带 --path 运行时工作目录是 game/，截图目录一律给绝对路径
    os.makedirs(a.out, exist_ok=True)
    godot = GR.find_godot()
    jobs = [(op, int(s)) for op in a.ops.split(",") for s in a.stages.split(",")]
    with ThreadPoolExecutor(max(1, min(a.jobs, 4))) as ex:
        for tag, msg, errs in ex.map(lambda j: shoot(godot, j[0], j[1], a.mode, a.out, a.start, a.every, a.n), jobs):
            print(tag, msg, ("脚本错误 %d：%s" % (len(errs), errs[0][:200])) if errs else "")


if __name__ == "__main__":
    main()
