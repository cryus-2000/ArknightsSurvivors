# -*- coding: utf-8 -*-
"""队长剪影（render/lead_sil，docs/226 §2）对照截图：同 seed 同帧，剪影开 / 关各录一遍，按队长屏幕坐标裁 240×240 拼成两行。
用法：python tools/leader_sil_shots.py --tag before [--bal 段/键=值 ...] [--from 596 --secs 16 --stride 15] [--touch]
输出 build/leader_sil/<tag>/pairs.png（上行开、下行关，只放两遍有差异的帧）与 stats.json（剪影出现的帧占比）"""
import argparse, glob, json, os, re, shutil, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--tag", default="now"); ap.add_argument("--bal", action="append", default=[])
ap.add_argument("--from", dest="t0", type=float, default=596.0); ap.add_argument("--secs", type=float, default=16.0)
ap.add_argument("--stride", type=int, default=15); ap.add_argument("--seed", type=int, default=13)
ap.add_argument("--touch", action="store_true"); ap.add_argument("--max", type=int, default=8)
a = ap.parse_args()
out = os.path.join(ROOT, "build", "leader_sil", a.tag); os.makedirs(out, exist_ok=True)
W, H = (1170, 540) if a.touch else (1920, 1080)


def run(v):
    d = os.path.join(out, "fr_" + v); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--resolution", "%dx%d" % (W, H), "--",
            "--balance", "--nodeath", "--seed=%d" % a.seed, "--bot=expert", "--op=texas", "--squad=exusiai,lappland", "--relics=1",
            "--realtime", "--rtfrom=%g" % (a.t0 - 3), "--recframes=%g,%d" % (a.t0, int(a.secs * 30)), "--recstride=%d" % a.stride, "--recchoice", "--recpos",
            "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (a.t0 + a.secs + 3)] + ["--bal=" + b for b in a.bal] + (["--bal=render/lead_sil=0"] if v == "off" else []) + (["--touch"] if a.touch else [])
    o, e, to = GR.run_godot(args, 3000)
    pos = {}
    for ln in (o or "").splitlines():
        m = re.match(r"RECPOS (\d+) ([-\d.]+) ([-\d.]+) (\d+)", ln.strip())
        if m:
            pos[int(m.group(1))] = (float(m.group(2)), float(m.group(3)), int(m.group(4)))
    return v, pos, GR.script_errors(o, e)[:3]


with ThreadPoolExecutor(2) as ex:
    res = {v: (p, er) for v, p, er in ex.map(run, ["on", "off"])}
for v in res:
    if res[v][1]:
        print("WARN", v, res[v][1])
frames = sorted(int(os.path.basename(p)[4:9]) for p in glob.glob(os.path.join(out, "fr_on", "rec_*.png")))
shown, n_diff, crops = [], 0, []
for i in frames:
    lp = res["on"][0].get(i)
    po, pf = (os.path.join(out, "fr_%s" % v, "rec_%05d.png" % i) for v in ("on", "off"))
    if not lp or not os.path.exists(pf):
        continue
    A_, B_ = (np.asarray(Image.open(p).convert("RGB")) for p in (po, pf))
    sc = A_.shape[1] / float(lp[2])
    cx, cy = int(lp[0] * sc), int((lp[1] - 20) * sc)
    r = int(120 * sc / 1.5)
    box = (max(0, cx - r), max(0, cy - r), min(A_.shape[1], cx + r), min(A_.shape[0], cy + r))
    ca, cb = (x[box[1]:box[3], box[0]:box[2]] for x in (A_, B_))
    d = int((np.abs(ca.astype(np.int16) - cb.astype(np.int16)).max(axis=2) > 24).sum())
    if d > 30:
        n_diff += 1
        crops.append((i, d, Image.fromarray(ca).resize((240, 240)), Image.fromarray(cb).resize((240, 240))))
crops.sort(key=lambda c: -c[1])
crops = sorted(crops[:a.max], key=lambda c: c[0])
if crops:
    m = Image.new("RGB", (240 * len(crops), 480))
    for k, (i, d, ca, cb) in enumerate(crops):
        m.paste(ca, (240 * k, 0)); m.paste(cb, (240 * k, 240))
    m.save(os.path.join(out, "pairs.png"))
S = {"tag": a.tag, "bal": a.bal, "frames": len(frames), "sil_frames": n_diff, "sil_pct": round(100.0 * n_diff / max(1, len(frames)), 1), "shown": [c[0] for c in crops]}
json.dump(S, open(os.path.join(out, "stats.json"), "w"), indent=1)
print(json.dumps(S, ensure_ascii=False))
