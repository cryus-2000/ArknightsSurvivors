# -*- coding: utf-8 -*-
"""列出各局录下的片段（时长、屏内敌人 / 敌弹峰值、冲击帧位置），出每段 3 帧的缩略拼图 segs_<局>.png
python segs.py A B C"""
import os, re, sys, glob
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))


def parse(run):
    log = open(os.path.join(HERE, "raw", run, "pv.log"), encoding="utf-8").read().splitlines()
    segs, cur, stat = [], None, []
    for l in log:
        if l.startswith("PVLOG"):
            d = dict(kv.split("=", 1) for kv in l.split()[1:])
            stat.append((float(d["t"]), int(d["ne"]), int(d["eb"]), int(d["lamp"]), d["boss"]))
        elif l.startswith("PVSEG"):
            kind, rest = l.split()[1], dict(kv.split("=", 1) for kv in l.split()[2:])
            cur = {"kind": kind, "dir": rest["dir"], "t0": float(rest["t0"]), "pre": int(rest["pre"]), "hf": []}
            segs.append(cur)
        elif l.startswith("PVHF") and cur is not None:
            d = dict(kv.split("=", 1) for kv in l.split()[1:])
            if int(d["n"]) >= 0 and int(d["seg"]) == len(segs):
                cur["hf"].append(int(d["n"]))
        elif l.startswith("PVEND") and cur is not None:
            d = dict(kv.split("=", 1) for kv in l.split()[1:])
            cur["n"] = int(d["n"])
    for s in segs:
        s.setdefault("n", len(glob.glob(os.path.join(HERE, "raw", run, s["dir"], "f*.jpg"))))
        t1 = s["t0"] + s["n"] / 30
        win = [x for x in stat if s["t0"] <= x[0] <= t1]
        s["ne"] = max([x[1] for x in win], default=0)
        s["eb"] = max([x[2] for x in win], default=0)
        s["lamp"] = min([x[3] for x in win], default=0)
        s["boss"] = win[-1][4] if win else ""
    return segs


def sheet(run, segs):
    f = ImageFont.truetype(os.path.join(HERE, "..", "game", "fonts", "ui.ttf"), 18)
    tw, th = 384, 216
    im = Image.new("RGB", (tw * 3, (th + 26) * len(segs)), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for i, s in enumerate(segs):
        fs = sorted(glob.glob(os.path.join(HERE, "raw", run, s["dir"], "f*.jpg")))
        if not fs:
            continue
        picks = [fs[0], fs[min(len(fs) - 1, s["hf"][0] if s["hf"] else len(fs) // 2)], fs[-1]]
        for j, p in enumerate(picks):
            im.paste(Image.open(p).resize((tw, th)), (j * tw, i * (th + 26) + 26))
        d.text((6, i * (th + 26) + 3), "%s  %s  n=%d  ne=%d eb=%d lamp=%d hf=%s %s" % (s["dir"], s["kind"], s["n"], s["ne"], s["eb"], s["lamp"], s["hf"], s["boss"]), font=f, fill=(230, 230, 230))
    im.save(os.path.join(HERE, "segs_%s.png" % run))


if __name__ == "__main__":
    for run in sys.argv[1:]:
        segs = parse(run)
        for s in segs:
            print(run, s["dir"], s["kind"], "n=%d ne=%d eb=%d lamp=%d hf=%s %s" % (s["n"], s["ne"], s["eb"], s["lamp"], s["hf"], s["boss"]))
        sheet(run, segs)
