# -*- coding: utf-8 -*-
"""后期画面分层量测（docs/221 §1 的量法，docs/226 用）：同 seed 分层重跑，每秒取 1 帧比较。
  full / nofriend / nofriend,nofoe 三遍（--clutterdbg 只把那一层置透明，画面随机数照抽，局面逐帧一致）：
  - 敌方层像素 = nofriend 与 nofriend,nofoe 有差异的像素；
  - 敌方被友方改色 = 敌方层像素里 full 与 nofriend 也有差异的比例（每帧一个比例，取 均 / p90 / 峰）；
  - 队长周围被友方改色 = 队长屏幕坐标半径 60 视口像素（1280 基准）内 full 与 nofriend 有差异的比例；
  - 友方占屏 = full 与 nofriend 有差异的像素占世界区比例（不算界面：先用 --nohud 那遍取界面掩码；缺省只排除 HUD 外框的固定区）。
用法：python tools/late_render_measure.py --tag before [--bal 段/键=值 ...] [--touch] [--from 596 --secs 16] [--keep]
  输出 build/late_render/<tag>/metrics.json 与逐帧表；--keep 留下 PNG（录对照片用另一个脚本）"""
import argparse, glob, json, os, re, shutil, sys
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
from scipy import ndimage
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ap = argparse.ArgumentParser()
ap.add_argument("--tag", default="now"); ap.add_argument("--bal", action="append", default=[])
ap.add_argument("--touch", action="store_true"); ap.add_argument("--from", dest="t0", type=float, default=596.0)
ap.add_argument("--secs", type=float, default=16.0); ap.add_argument("--keep", action="store_true")
ap.add_argument("--seed", type=int, default=13); ap.add_argument("--thr", type=int, default=24)
ap.add_argument("--extra", default="", help="额外游戏参数（空格分隔）")
ap.add_argument("--reuse", action="store_true", help="不重跑，直接用上次 --keep 留下的帧重算")
ap.add_argument("--minblob", type=int, default=40, help="敌方层掩码去掉小于这么多像素的连通块（画面随机流错位留下的零星颗粒，docs/226 §1）")
a = ap.parse_args()
out = os.path.join(ROOT, "build", "late_render", a.tag); os.makedirs(out, exist_ok=True)
VARS = {"full": "nonum", "nf": "nofriend,nonum", "nfnf": "nofriend,nofoe,nonum", "nohud": "nonum"}   # 伤害数字画在界面层且带抖动，四遍都关掉免得算成敌方层
W, H = (1170, 540) if a.touch else (1920, 1080)


def run(v):
    d = os.path.join(out, "fr_" + v); shutil.rmtree(d, ignore_errors=True); os.makedirs(d)
    dbg = VARS[v]
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--resolution", "%dx%d" % (W, H), "--",
            "--balance", "--nodeath", "--seed=%d" % a.seed, "--bot=expert", "--op=texas", "--squad=exusiai,lappland", "--relics=1",
            "--realtime", "--rtfrom=%g" % (a.t0 - 3), "--recframes=%g,%d" % (a.t0, int(a.secs * 30)), "--recstride=30", "--recchoice", "--recpos",
            "--shotdir=" + d.replace(os.sep, "/"), "--maxt=%d" % (a.t0 + a.secs + 3)] + ["--bal=" + b for b in a.bal] + (["--touch"] if a.touch else []) + a.extra.split()
    if v == "nohud":
        args.append("--nohud")
    args.append("--clutterdbg=" + dbg)
    o, e, to = GR.run_godot(args, 3000)
    pos = {}
    for ln in (o or "").splitlines():
        m = re.match(r"RECPOS (\d+) ([-\d.]+) ([-\d.]+) (\d+)", ln.strip())
        if m:
            pos[int(m.group(1))] = (float(m.group(2)), float(m.group(3)), int(m.group(4)))
    errs = GR.script_errors(o, e)[:3]
    return v, pos, errs, to


if a.reuse:
    res = {v: ({}, [], False) for v in VARS}
    old = json.load(open(os.path.join(out, "metrics.json"), encoding="utf-8"))["rows"]
    res["full"] = ({r["i"]: tuple(r["lp"]) for r in old if r.get("lp")}, [], False)
else:
    with ThreadPoolExecutor(4) as ex:
        res = {v: (p, er, to) for v, p, er, to in ex.map(run, list(VARS))}
for v in res:
    if res[v][1] or res[v][2]:
        print("WARN", v, res[v][1], "timeout" if res[v][2] else "")


def load(v, i):
    p = os.path.join(out, "fr_" + v, "rec_%05d.png" % i)
    return np.asarray(Image.open(p).convert("RGB")).astype(np.int16) if os.path.exists(p) else None


def dif(x, y):
    return np.abs(x - y).max(axis=2) > a.thr


frames = sorted(int(os.path.basename(p)[4:9]) for p in glob.glob(os.path.join(out, "fr_full", "rec_*.png")))
rows = []
for i in frames:
    f, nf, nfnf, nh = (load(v, i) for v in ("full", "nf", "nfnf", "nohud"))
    if any(x is None for x in (f, nf, nfnf, nh)):
        continue
    hud = dif(f, nh)
    world = ~hud
    foe = dif(nf, nfnf) & world
    if a.minblob > 0:
        lab, n = ndimage.label(foe, structure=np.ones((3, 3)))
        if n:
            sz = ndimage.sum(foe, lab, range(1, n + 1))
            foe = np.isin(lab, np.nonzero(sz >= a.minblob)[0] + 1)
    fr = dif(f, nf) & world
    nfoe = int(foe.sum())
    tint = float((foe & fr).sum()) / nfoe if nfoe > 200 else None
    lp = res["full"][0].get(i)
    lead = None
    if lp:
        sc = f.shape[1] / float(lp[2])   # RECPOS 是视口坐标（基准宽 lp[2]）→ 截图像素
        rr = 60.0 * sc   # 队长周围 60 视口像素（1280 基准约一个身位半）
        yy, xx = np.ogrid[:f.shape[0], :f.shape[1]]
        m = ((xx - lp[0] * sc) ** 2 + (yy - (lp[1] - 20) * sc) ** 2 <= rr * rr) & world
        lead = float((fr & m).sum()) / max(1, int(m.sum()))
    rows.append({"lp": lp, "i": i, "foe_px": nfoe, "foe_tint": tint, "lead_tint": lead, "friend_share": float(fr.sum()) / max(1, int(world.sum()))})


def st(k):
    v = [r[k] for r in rows if r[k] is not None]
    if not v:
        return None
    return {"mean": round(float(np.mean(v)) * 100, 1), "p90": round(float(np.percentile(v, 90)) * 100, 1), "max": round(float(np.max(v)) * 100, 1), "n": len(v)}


M = {"tag": a.tag, "bal": a.bal, "minblob": a.minblob, "touch": a.touch, "frames": len(rows), "foe_tint": st("foe_tint"), "lead_tint": st("lead_tint"), "friend_share": st("friend_share")}
json.dump({"metrics": M, "rows": rows}, open(os.path.join(out, "metrics.json"), "w"), indent=1)
print(json.dumps(M, ensure_ascii=False))
if not a.keep:
    for v in VARS:
        shutil.rmtree(os.path.join(out, "fr_" + v), ignore_errors=True)
