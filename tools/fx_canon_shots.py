#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""配方特效三档并排图（docs/245 §5，原作改编轮）：图鉴演示模式（tests/elite_demo_shot.tscn）逐档逐招连拍，
自动找命中峰值对齐，拼成「每行一档（E0 / E1 / E2）、每列同一招前后 5 帧」的并排图，另出手机屏宽版（整屏缩到 390 宽）。
窗口在屏幕外、静音（godot_runner）。原作参照格不在这里拼（原作素材只在本机 Claude outputs/，不进仓库）。

用法（仓库根目录）：
    python tools/fx_canon_shots.py --ops logos,siege --modes 3,0,1,2 --out build/fx_canon
    python tools/fx_canon_shots.py --ops logos --modes 3 --recipe 0        # 关配方（原画面）对照
输出：<out>/tiers_<op>_m<mode>.png、<out>/phone_<op>.png、<out>/raw/<op>_e<档>_m<招>/f_*.png
"""
import argparse, glob, os, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
MODE_NAME = {3: "普攻", 0: "S1", 1: "S2", 2: "S3"}
# 技能按精英化解锁（character.skill_unlocked：S1 精零、S2 精一、S3 精二），只拍真实存在的档
MODE_TIERS = {3: [0, 1, 2], 0: [0, 1, 2], 1: [1, 2], 2: [2]}


def shoot(godot, op, tier, mode, out, recipe, start, every, n, w, h):
    tag = "%s_e%d_m%d_r%d" % (op, tier, mode, recipe)
    fdir = os.path.join(out, "raw", tag)
    os.makedirs(fdir, exist_ok=True)
    for f in glob.glob(os.path.join(fdir, "*.png")):
        os.remove(f)
    args = [godot, "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/elite_demo_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=2",   # 玩法一律精二（精零 / 精一没有 S2 / S3），画面档位用 fx/recipe_tier 强制
            "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=%d" % every, "--shot_n=%d" % n, "--shot_w=%d" % w, "--shot_h=%d" % h,
            "--bal=fx/recipe=%d" % recipe, "--bal=fx/recipe_tier=%d" % tier, "--bal=fx/recipe_log=1"]
    outp, err, to = GR.run_godot(args, 900)
    errs = GR.script_errors(outp, err)
    frames = sorted(glob.glob(os.path.join(fdir, "f_*.png")))
    ev = [l.split()[1:] for l in (outp or "").splitlines() if l.startswith("FXRLOG")]
    with open(os.path.join(fdir, "events.txt"), "w") as f:
        f.write("start %g every %d\n" % (start, every))
        for e in ev:
            f.write(" ".join(e) + "\n")
    return tag, frames, errs, to


def energy(frames):
    """每帧的「特效能量」：和整段中位帧的差（亮度 + 饱和度），找命中峰值"""
    arr = [np.asarray(Image.open(f).convert("RGB"), dtype=np.float32) for f in frames]
    med = np.median(np.stack(arr[:: max(1, len(arr) // 24)]), axis=0)
    e = [float(np.abs(a - med).sum(axis=2).clip(0, 255).__gt__(60).sum()) for a in arr]
    return arr, e


# 技能招式按事件帧对齐（图鉴演示里普攻和技能混着放，能量峰值常落在普攻上）：(干员, 招) → (事件, 相对事件的 5 个偏移，单位 = 存图间隔)
ALIGN = {
    ("logos", 0): [("skill0", 0), ("skill0", 3), ("skill0", 6), ("skill0", 9), ("skill0", 14)],
    ("logos", 1): [("skill1", 1), ("exec", -1), ("exec", 0), ("exec", 2), ("exec", 5)],
    ("logos", 2): [("skill2", 1), ("skill2", 5), ("skill2", 9), ("skill2", 15), ("skill2", 21)],
    ("siege", 0): [("skill0", -1), ("skill0", 1), ("skill0", 3), ("skill0", 5), ("skill0", 8)],
    ("siege", 1): [("leap", 1), ("slam", -2), ("slam", 0), ("slam", 2), ("slam", 5)],
    ("siege", 2): [("skill2", 2), ("swing_h", -1), ("swing_h", 0), ("swing_h", 2), ("swing_h", 5)],
}


LAG = 2   # 演示场景自己的帧计数比引擎帧晚约 2 个存图间隔（场景加载）


def event_idx(fdir, op, mode):
    p = os.path.join(fdir, "events.txt")
    if (op, mode) not in ALIGN or not os.path.exists(p):
        return None
    lines = open(p).read().splitlines()
    start, every = float(lines[0].split()[1]), int(lines[0].split()[3])
    first = {}
    for l in lines[1:]:
        q = l.split()
        if len(q) >= 3 and q[0] == op:
            i = (int(q[2]) - int(start * 30)) // every
            if i >= 2 and q[1] not in first:
                first[q[1]] = i
    # 同一招的各事件取「技能起手之后」的第一次
    sk = [k for k, _ in ALIGN[(op, mode)] if k.startswith("skill")]
    t0 = first.get(sk[0], 0) if sk else 0
    for l in lines[1:]:
        q = l.split()
        if len(q) >= 3 and q[0] == op:
            i = (int(q[2]) - int(start * 30)) // every
            if i >= t0 and (q[1] not in first or first[q[1]] < t0):
                first[q[1]] = i
    out = []
    for k, o in ALIGN[(op, mode)]:
        if k not in first:
            return None
        out.append(first[k] + o + LAG)
    return out


def pick5(arr, e, skip=6, idx=None):
    k = int(np.argmax(e[skip:])) + skip if len(e) > skip else int(np.argmax(e))
    idx = idx or [k - 4, k - 2, k, k + 2, k + 5]
    return [arr[max(0, min(len(arr) - 1, i))] for i in idx]


def crop_box(frames_all, pad=28, minw=360, minh=210):
    """所有档位峰值前后帧的「动了的像素」外接框（相对中位帧），按 16:9 外扩"""
    st = np.stack(frames_all)
    med = np.median(st, axis=0)
    m = (np.abs(st - med).sum(axis=3) > 90).any(axis=0)
    H, W = m.shape
    ys, xs = np.nonzero(m)
    if len(xs) < 20:
        return 0, 0, W, H
    x0, x1 = np.percentile(xs, 1), np.percentile(xs, 99)
    y0, y1 = np.percentile(ys, 1), np.percentile(ys, 99)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    w = max(minw, x1 - x0 + 2 * pad)
    h = max(minh, y1 - y0 + 2 * pad)
    if w / h > 16 / 9:
        h = w * 9 / 16
    else:
        w = h * 16 / 9
    w, h = min(w, W), min(h, H)
    x0 = int(min(max(0, cx - w / 2), W - w))
    y0 = int(min(max(0, cy - h / 2), H - h))
    return x0, y0, x0 + int(w), y0 + int(h)


def crop_rows(rows, box, up):
    x0, y0, x1, y1 = box
    out = []
    for row in rows:
        r2 = []
        for a in row:
            t = Image.fromarray(a[y0:y1, x0:x1].astype(np.uint8))
            t = t.resize((int((x1 - x0) * up), int((y1 - y0) * up)), Image.NEAREST)
            r2.append(np.asarray(t))
        out.append(r2)
    return out


def font(sz):
    for p in ["C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf"]:
        if os.path.exists(p):
            return ImageFont.truetype(p, sz)
    return ImageFont.load_default()


def sheet(rows, labels, title, path, scale=1.0):
    """rows：每行 5 张 HxWx3 数组"""
    h, w = rows[0][0].shape[:2]
    cw, ch = int(w * scale), int(h * scale)
    lab = 60
    top = 30
    im = Image.new("RGB", (lab + cw * 5, top + ch * len(rows)), (10, 12, 18))
    d = ImageDraw.Draw(im)
    d.text((8, 6), title, fill=(220, 224, 232), font=font(16))
    for r, row in enumerate(rows):
        d.text((10, top + r * ch + ch // 2 - 10), labels[r], fill=(230, 230, 236), font=font(18))
        for c, a in enumerate(row):
            t = Image.fromarray(a.astype(np.uint8))
            if scale != 1.0:
                t = t.resize((cw, ch), Image.LANCZOS)
            im.paste(t, (lab + c * cw, top + r * ch))
    im.save(path)
    return im


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ops", default="logos,siege")
    ap.add_argument("--modes", default="3,0,1,2")
    ap.add_argument("--tiers", default="0,1,2")
    ap.add_argument("--recipe", type=int, default=1)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "fx_canon"))
    ap.add_argument("--start", type=float, default=2.0)
    ap.add_argument("--every", type=int, default=2)
    ap.add_argument("--n", type=int, default=75)
    ap.add_argument("--w", type=int, default=640)
    ap.add_argument("--h", type=int, default=360)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--reuse", action="store_true", help="不重拍，只用 raw/ 里已有的帧重新拼图")
    a = ap.parse_args()
    a.out = os.path.abspath(a.out)
    os.makedirs(a.out, exist_ok=True)
    godot = GR.find_godot()
    ops = a.ops.split(",")
    modes = [int(m) for m in a.modes.split(",")]
    tiers = [int(t) for t in a.tiers.split(",")]
    jobs = [(op, t, m) for op in ops for m in modes for t in tiers if t in MODE_TIERS[m]]
    res = {}
    if a.reuse:
        for op, t, m in jobs:
            tag = "%s_e%d_m%d_r%d" % (op, t, m, a.recipe)
            res[(op, t, m)] = sorted(glob.glob(os.path.join(a.out, "raw", tag, "f_*.png")))
    else:
        with ThreadPoolExecutor(max(1, min(a.jobs, 4))) as ex:
            futs = {j: ex.submit(shoot, godot, j[0], j[1], j[2], a.out, a.recipe, a.start, a.every, a.n, a.w, a.h) for j in jobs}
            for j, f in futs.items():
                tag, frames, errs, to = f.result()
                res[j] = frames
                print(tag, "%d 张" % len(frames), "超时" if to else "", ("脚本错误 %d：%s" % (len(errs), errs[0][:240])) if errs else "")
    suf = "" if a.recipe else "_off"
    for op in ops:
        phone_rows = []
        for m in modes:
            rows = []
            mt = [t for t in tiers if t in MODE_TIERS[m]]
            for t in mt:
                fr = res.get((op, t, m), [])
                if not fr:
                    rows = []
                    break
                arr, e = energy(fr)
                rows.append(pick5(arr, e, idx=event_idx(os.path.dirname(fr[0]), op, m)))
            if not rows:
                continue
            box = (130, 50, 482, 248) if a.w == 640 else crop_box([a for row in rows for a in row])   # 图鉴演示的干员 + 敌群固定在这块
            up = 760.0 / (box[2] - box[0])
            full_rows = rows
            rows = crop_rows(rows, box, up)
            sheet(rows, ["E%d" % t for t in mt], "%s %s  %s（每行一档，命中峰值对齐，%s）" % (op, MODE_NAME.get(m, m), " / ".join("E%d" % t for t in mt), "配方开" if a.recipe else "配方关"),
                  os.path.join(a.out, "tiers_%s_m%d%s.png" % (op, m, suf)))
            phone_rows.append(dict(zip(mt, full_rows)))
        if phone_rows:
            # 手机屏宽：每招取峰值帧，整屏缩到 390 宽，列 = 招式，行 = 档位
            cols = len(phone_rows)
            h0, w0 = next(iter(phone_rows[0].values()))[2].shape[:2]
            pw, ph = 390, int(h0 * 390 / w0)
            im = Image.new("RGB", (40 + pw * cols, 30 + ph * len(tiers)), (10, 12, 18))
            d = ImageDraw.Draw(im)
            for c, rows in enumerate(phone_rows):
                d.text((40 + c * pw + 6, 6), MODE_NAME.get(modes[c], str(modes[c])), fill=(220, 224, 232), font=font(16))
                for r, t in enumerate(tiers):
                    if t in rows:   # 没解锁的档留空
                        im.paste(Image.fromarray(rows[t][2].astype(np.uint8)).resize((pw, ph), Image.LANCZOS), (40 + c * pw, 30 + r * ph))
            for r, t in enumerate(tiers):
                d.text((6, 30 + r * ph + ph // 2 - 10), "E%d" % t, fill=(230, 230, 236), font=font(16))
            im.save(os.path.join(a.out, "phone_%s%s.png" % (op, suf)))


if __name__ == "__main__":
    main()
