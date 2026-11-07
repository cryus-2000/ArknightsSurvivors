#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""实机局对照按提示挑帧（docs/310 §8）：读选后那局日志里的 CUE 行（--cuelog），每个 tag 取至多 --n 次（相隔 ≥ --gap 秒），
取触发后最近的截图帧（再往后 --lag 帧，让提示画开），选前 / 选后整帧 1 倍上下拼一张：<out_dir>/real_<名>_<tag>_<k>.png。

用法：python3 tools/cue_real_tags.py <选后日志> <选前目录> <选后目录> <out_dir> <名> [--spf 0.0659] [--n 2] [--gap 3] [--lag 2]
"""
import argparse, glob, os, re
from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    for k in ("log", "d0", "d1", "out", "name"):
        ap.add_argument(k)
    ap.add_argument("--spf", type=float, default=0.0659)
    ap.add_argument("--n", type=int, default=2)
    ap.add_argument("--gap", type=float, default=3.0)
    ap.add_argument("--lag", type=int, default=2)
    ap.add_argument("--cw", type=int, default=360)
    ap.add_argument("--ch", type=int, default=240)
    a = ap.parse_args()
    fr = lambda p: int(re.findall(r"(\d+)", os.path.basename(p))[-1])
    f0 = {fr(p): p for p in glob.glob(os.path.join(a.d0, "*.png"))}
    f1 = {fr(p): p for p in glob.glob(os.path.join(a.d1, "*.png"))}
    ks = sorted(set(f0) & set(f1))
    ev = {}
    for ln in open(a.log, encoding="utf-8", errors="replace"):
        m = re.match(r"CUE ([\d.]+) (\S+) (\S+)(?: (-?\d+) (-?\d+))?", ln)
        if m:
            ev.setdefault((m.group(2), m.group(3)), []).append((float(m.group(1)), int(m.group(4) or -1), int(m.group(5) or -1)))
    for (op, tag), ts in sorted(ev.items()):
        picked = []
        for q in ts:
            if not picked or q[0] - picked[-1][0] >= a.gap:
                picked.append(q)
        done = 0
        for t, sx, sy in picked:
            want = int(t / a.spf)
            cand = [k for k in ks if k >= want]
            if len(cand) <= a.lag:
                continue
            k = cand[a.lag]
            im0, im1 = Image.open(f0[k]).convert("RGB"), Image.open(f1[k]).convert("RGB")
            if sx >= 0 and a.cw > 0:   # 有屏幕坐标：按触发点裁 1 倍小块，选前 / 选后左右并排
                x0 = max(0, min(im0.width - a.cw, sx - a.cw // 2))
                y0 = max(0, min(im0.height - a.ch, sy - a.ch // 2))
                im0, im1 = im0.crop((x0, y0, x0 + a.cw, y0 + a.ch)), im1.crop((x0, y0, x0 + a.cw, y0 + a.ch))
                sh = Image.new("RGB", (a.cw * 2 + 4, a.ch))
                for col, im in enumerate((im0, im1)):
                    ImageDraw.Draw(im).text((4, 4), "%s %s t=%.1f" % ("before" if col == 0 else "after", tag, t), fill=(255, 255, 0))
                    sh.paste(im, (col * (a.cw + 4), 0))
            else:
                sh = Image.new("RGB", (im0.width, im0.height * 2 + 4))
                for row, im in enumerate((im0, im1)):
                    ImageDraw.Draw(im).text((6, 6), "%s %s %s t=%.1f f%d" % ("before" if row == 0 else "after", op, tag, t, k), fill=(255, 255, 0))
                    sh.paste(im, (0, row * (im0.height + 4)))
            sh.save(os.path.join(a.out, "real_%s_%s_%s_%d.png" % (a.name, op, tag, done)))
            done += 1
            if done >= a.n:
                break
        print("%s %s %s：触发 %d 次，出图 %d" % (a.name, op, tag, len(ts), done))


if __name__ == "__main__":
    main()
