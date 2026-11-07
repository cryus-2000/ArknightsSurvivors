#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""成长节点提示的选前 / 选后同帧对照（docs/310）：图鉴演示跑两遍（--bal=fx/node_cue=0 / 1，其余一样，画面同帧），
逐帧算差，挑差最大的 3 帧，上排选前、下排选后，1 倍原尺寸拼一张 <out>/<名>.png。

用法（仓库根目录）：
    python tools/node_cue_pairs.py --out "Claude outputs/growth_vis/pairs" --jobs 2 texas:1 hoshiguma:5:ember angelina:4:pull3
    每项 = 干员:节点数[:路线]（路线 = 节点 4 的分支 id，同 elite_demo_shots --route）
    --before-game <另一份 game/>：选前改用那份代码（如基线提交的临时工作树）跑、node_cue 都开——直接改了绘制的项（不走 node_cue 开关）用这个对照
"""
import argparse, glob, os, sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")


def shoot(godot, op, nodes, route, cue, d, a, game=GAME):
    os.makedirs(d, exist_ok=True)
    for f in glob.glob(os.path.join(d, "*.png")):
        os.remove(f)
    args = [godot, "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", game, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=2", "--shot_mode=%d" % a.mode, "--shot_dir=" + d.replace("\\", "/"),
            "--shot_start=%g" % a.start, "--shot_every=%d" % a.every, "--shot_n=%d" % a.n, "--shot_nodes=%d" % nodes,
            "--bal=fx/node_cue=%d" % cue, "--seed=7"]
    if route:
        args.append("--route=%s:%s" % (op, route))
    out, err, to = GR.run_godot(args, 900)
    return GR.script_errors(out, err)


def one(godot, item, a):
    parts = item.split(":")
    op, nodes, route = parts[0], int(parts[1]), (parts[2] if len(parts) > 2 else "")
    name = "%s_n%d%s" % (op, nodes, ("_" + route) if route else "")
    base = os.path.join(a.out, "_frames", name)
    errs = []
    for cue in (0, 1):
        if a.before_game:
            errs += shoot(godot, op, nodes, route, 1, os.path.join(base, "cue%d" % cue), a, a.before_game if cue == 0 else GAME)
        else:
            errs += shoot(godot, op, nodes, route, cue, os.path.join(base, "cue%d" % cue), a)
    from PIL import Image, ImageChops, ImageDraw
    f0 = sorted(glob.glob(os.path.join(base, "cue0", "f_*.png")))
    f1 = sorted(glob.glob(os.path.join(base, "cue1", "f_*.png")))
    n = min(len(f0), len(f1))
    if n == 0:
        return name, "没有截到图", errs
    sc = []
    for i in range(n):
        x = ImageChops.difference(Image.open(f0[i]).convert("RGB"), Image.open(f1[i]).convert("RGB")).convert("L")
        sc.append((sum(1 for v in x.tobytes() if v > 40), i))
    sc.sort(reverse=True)
    pick = sorted(i for s, i in sc[:3] if s > 0)
    if not pick:
        return name, "两遍画面完全相同（%d 帧）" % n, errs
    w, h = Image.open(f0[0]).size
    sheet = Image.new("RGB", (w * len(pick), h * 2 + 6), (0, 0, 0))
    for c, i in enumerate(pick):
        for row, fs in enumerate((f0, f1)):
            im = Image.open(fs[i]).convert("RGB")
            ImageDraw.Draw(im).text((4, 4), ("before " if row == 0 else "after ") + "%s #%d" % (name, i), fill=(255, 255, 0))
            sheet.paste(im, (c * w, row * (h + 6)))
    sheet.save(os.path.join(a.out, name + ".png"))
    return name, "%d 帧，差最大 %s（%d 像素）" % (n, pick, sc[0][0]), errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("items", nargs="+")
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "node_cue_pairs"))
    ap.add_argument("--mode", type=int, default=-1)
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--every", type=int, default=3)
    ap.add_argument("--n", type=int, default=80)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--before-game", default="")
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)
    os.makedirs(a.out, exist_ok=True)
    godot = GR.find_godot()
    with ThreadPoolExecutor(max(1, a.jobs)) as ex:
        for name, msg, errs in ex.map(lambda it: one(godot, it, a), a.items):
            print(name, msg, ("脚本错误 %d：%s" % (len(errs), errs[0][:200])) if errs else "", flush=True)


if __name__ == "__main__":
    main()
