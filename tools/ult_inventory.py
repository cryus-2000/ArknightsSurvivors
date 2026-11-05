#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""终结技 × 新美术差异盘点（docs/278）：只看不改。GCP 上跑（docs/256 custom 任务），本机不开 Godot。

  ult --ops a,b   原版终结技联系表：借 tools/ult_rec.py 的 u_<干员> 段（队长 + 两名队友，0:31.5 充满放出，30 帧原速），
                  每人取 8 帧（起手前、起手、蓄力、最亮帧前后、收尾）拼成 <op>_ult_sheet.png，另存最亮帧 <op>_ult_peak.png
  art --ops a,b   新美术基准：图鉴演示精二、fx/px_plane=1，S3（mode 2）和普攻（mode 3）各一张招牌帧（发光点 + 颗粒最多的那一帧）
                  → <op>_s3.png / <op>_atk.png（1280×720）
"""
import argparse, glob, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "ult_inv")
SKILL_EV = {"mizuki": "mz_burst"}   # 同 fx_audit.py：S3 事件名缺省 skill2


def font(sz):
    for f in ["C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def lum(p):
    a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def ult(a):
    ops = a.ops.split(",")
    os.makedirs(a.out, exist_ok=True)
    tag = "inv"
    cmd = [sys.executable, os.path.join(ROOT, "tools", "ult_rec.py"), "--clips", ",".join("u_" + o for o in ops), "--tag", tag,
           "--jobs", str(a.jobs), "--secs", "10", "--at", "30"]
    print(" ".join(cmd), flush=True)
    subprocess.run(cmd)
    base = os.path.join(ROOT, "build", "ult_rec", tag)
    for op in ops:
        fr = sorted(glob.glob(os.path.join(base, "fr_u_" + op, "rec_*.png")))
        if len(fr) < 60:
            print("缺帧", op, len(fr), flush=True)
            continue
        ref = lum(fr[38])
        # 起手约在第 45 帧（0:31.5）；最亮帧 = 第 42–240 帧里与起手前（第 38 帧）亮度差最大的那一帧
        en = []
        for i in range(42, min(len(fr), 240), 2):
            en.append((float(np.abs(lum(fr[i]) - ref).mean()), i))
        pk = max(en)[1]
        idx = sorted(set([40, 46, 52, max(54, pk - 8), pk, min(len(fr) - 1, pk + 10), min(len(fr) - 1, pk + 25), min(len(fr) - 1, pk + 50)]))
        tw, th = 480, 270
        cols = 4
        rows = (len(idx) + cols - 1) // cols
        sh = Image.new("RGB", (cols * (tw + 4), 44 + rows * (th + 28)), (12, 12, 16))
        d = ImageDraw.Draw(sh)
        d.text((10, 8), "%s 终结技（原版，integ 现行）· 每格标起手后秒数" % op, fill=(235, 235, 235), font=font(24))
        for k, i in enumerate(idx):
            im = Image.open(fr[i]).convert("RGB").resize((tw, th), Image.LANCZOS)
            x, y = (k % cols) * (tw + 4), 44 + (k // cols) * (th + 28)
            sh.paste(im, (x, y + 24))
            d.text((x + 6, y + 2), "%+.2f 秒%s" % ((i - 45) / 30.0, "（最亮）" if i == pk else ""), fill=(255, 210, 120), font=font(18))
        sh.save(os.path.join(a.out, "%s_ult_sheet.png" % op))
        shutil.copy(fr[pk], os.path.join(a.out, "%s_ult_peak.png" % op))
        mp4 = os.path.join(base, "u_%s.mp4" % op)
        if os.path.exists(mp4):
            shutil.copy(mp4, os.path.join(a.out, "%s_ult.mp4" % op))
        print("联系表", op, idx, "最亮", pk, flush=True)


def shoot(op, mode):
    tag = "%s_m%d" % (op, mode)
    fdir = os.path.join(BUILD, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/fx_audit_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=2", "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=1.0", "--shot_every=2", "--shot_n=120", "--shot_w=1280", "--shot_h=720",
            "--bal=fx/px_plane=1", "--bal=fx/recipe_log=1", "--seed=11", "--bal=growth/late_shape=1"]
    out, err, to = GR.run_godot(args, 1500)
    open(os.path.join(BUILD, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return op, mode, len(glob.glob(os.path.join(fdir, "f_*.png"))), GR.script_errors(out or "", err or "")[:2]


def pick(op, mode, out):
    tag = "%s_m%d" % (op, mode)
    txt = open(os.path.join(BUILD, tag + ".log"), encoding="utf-8", errors="ignore").read().splitlines()
    fxa, shot, ev = {}, {}, []
    for l in txt:
        s = l.split()
        if l.startswith("FXA "):
            d = dict(kv.split("=", 1) for kv in s[3:] if "=" in kv)
            fxa[int(s[1])] = int(d.get("glow", 0)) + 3 * int(d.get("alive", 0)) + int(d.get("gr", 0))
        elif l.startswith("FXSHOT "):
            shot[int(s[1])] = int(s[2])
        elif l.startswith("FXRLOG ") and len(s) > 3 and s[1] == op:
            ev.append((s[2], int(s[3])))
    if not shot:
        return None
    lo, hi = min(shot.values()), max(shot.values())
    if mode == 2:
        name = SKILL_EV.get(op, "skill2")
        sk = [e for k, e in ev if k == name and lo <= e <= hi]
        if sk:
            lo, hi = sk[0], min(hi, sk[0] + 60)
    cand = [i for i, e in shot.items() if lo <= e <= hi] or list(shot)
    k = max(cand, key=lambda i: fxa.get(shot[i], 0))
    p = os.path.join(BUILD, tag, "f_%04d.png" % k)
    dst = os.path.join(out, "%s_%s.png" % (op, "s3" if mode == 2 else "atk"))
    shutil.copy(p, dst)
    return dst


def art(a):
    ops = a.ops.split(",")
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    jobs = [(op, m) for op in ops for m in (2, 3)]
    with ThreadPoolExecutor(a.jobs) as ex:
        for r in ex.map(lambda j: shoot(*j), jobs):
            print("局", r, flush=True)
    for op, m in jobs:
        try:
            print("招牌帧", pick(op, m, a.out), flush=True)
        except Exception as e:
            print("挑帧失败", op, m, repr(e), flush=True)
        shutil.rmtree(os.path.join(BUILD, "%s_m%d" % (op, m)), ignore_errors=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["ult", "art", "both"])
    ap.add_argument("--ops", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    if a.cmd in ("art", "both"):
        art(a)
    if a.cmd in ("ult", "both"):
        ult(a)


if __name__ == "__main__":
    main()
