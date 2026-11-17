#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""每名干员特效预算的运行时量测（docs/368 §1.2–1.4）。只量，不改特效。

  perf  --ops a,b [--from 480 --secs 75 --quality high|low --touch --tag x]
        本机（静音、屏幕外，godot_runner 管并发）：该干员当队长、不招募（--norecruit）、满局外成长（--prog=20）、不死，
        8:00 起实时跑 75 秒；同局每 30 帧轮换「该干员特效画成全透明 / 正常」（--clutterdbg=noop_<id>,abop --clutterab=30，
        代码与随机数照跑，只是不画），--perf 分 /d0（关）/ dN（开）两桶，净差 = 该干员特效的绘制开销（帧时 / 渲染 CPU / GPU / 绘制调用）。
        注意：静音只省绘制，不省特效逻辑（颗粒推进、条目更新）；逻辑开销另由 cover 的条目数 / 颗粒数估。
        输出 build/fx_budget/perf_<tag>.json
  cover --ops a,b [--modes 3,0,1,2,4]
        画面占比：图鉴演示（tests/fx_audit_shot.tscn，精二，1280×720，30 帧逐帧 6 秒）每招两遍——正常 / --clutterdbg=noop_<id>，
        逐像素差（三通道和 > 0.06×255×3，docs/243 §1.3）= 该干员特效像素；量覆盖面积峰值 / 均值、平均亮度增量、持续时间（覆盖 > 0.5% 的帧数）、
        敌人像素被盖比例（noenemy 第三遍取敌人掩码）。缺省在 GCP 上跑（python tools/fx_budget_runtime.py cover-gcp），本机只做 --analyze。
        输出 build/fx_budget/cover.json
  new   --op <id>：新干员交付用，perf（high）+ cover 两项各跑一次并对照 docs/368 速查表，打印超限项。
"""
import argparse, glob, json, os, re, shutil, sys, time
from concurrent.futures import ThreadPoolExecutor

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OUT = os.path.join(ROOT, "build", "fx_budget")
OPS = sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(GAME, "data", "characters", "*.json")))
MODES = {3: "atk", 0: "s1", 1: "s2", 2: "s3", 4: "ult"}
THR = 0.06 * 255 * 3
BUDGET = os.path.join(ROOT, "tools", "fx_budget.json")


# ---------------------------------------------------------------- perf
def perf_one(op, a):
    t0 = a.t0
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--resolution", "1280x720", "--path", GAME, "--",
            "--balance", "--perf", "--realtime", "--rtfrom=%g" % t0, "--maxt=%g" % (t0 + a.secs), "--nodeath", "--seed=%d" % a.seed,
            "--op=" + op, "--norecruit", "--bot=expert", "--prog=20", "--quality=" + a.quality,
            "--clutterdbg=noop_%s,abop" % op, "--clutterab=%d" % a.every] + (["--touch"] if a.touch else [])
    t = time.time()
    out, err, to = GR.run_godot(args, int(t0 * 0.6 + a.secs * 3 + 600))
    errs = GR.script_errors(out or "", err or "")[:3]
    perf = None
    for ln in (out or "").splitlines():
        if ln.startswith("PERF "):
            perf = json.loads(ln[5:])
    row = {"op": op, "wall_s": round(time.time() - t), "timeout": to, "errs": errs}
    if perf:
        def pick(suffix):
            return {k: v for k, v in perf.items() if isinstance(v, dict) and k.endswith(suffix) and "n" in v}
        off, on = pick("/d0"), pick("/dN")
        # 只取 8:00 以后的分段（--rtfrom 前不记）；多段按帧数加权
        def agg(d, key):
            n = sum(v["n"] for v in d.values())
            return round(sum(v[key] * v["n"] for v in d.values()) / max(1, n), 3), n
        for key in ("ft_mean", "ft_p95", "rcpu_med", "gpu_med", "dc_med", "en_med"):
            a_on, n_on = agg(on, key)
            a_off, n_off = agg(off, key)
            row[key] = {"on": a_on, "off": a_off, "d": round(a_on - a_off, 3)}
        row["n"] = [n_on, n_off]
    return row


def cmd_perf(a):
    os.makedirs(OUT, exist_ok=True)
    GR.ensure_imported(GAME)
    ops = a.ops.split(",") if a.ops else OPS
    path = os.path.join(OUT, "perf_%s.json" % a.tag)
    done = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    todo = [o for o in ops if o not in done or a.force]
    with ThreadPoolExecutor(a.jobs) as ex:
        for row in ex.map(lambda o: perf_one(o, a), todo):
            done[row["op"]] = row
            json.dump(done, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
            ft = row.get("ft_mean", {})
            print("%-18s ft on %.2f off %.2f d %+.3f ms  dc d %+.0f  en %s  %s" % (
                row["op"], ft.get("on", 0), ft.get("off", 0), ft.get("d", 0), row.get("dc_med", {}).get("d", 0),
                row.get("en_med", {}).get("on", "?"), row["errs"] or ""), flush=True)
    return done


# ---------------------------------------------------------------- cover
def shoot(op, mode, var, root, start=1.0, n=180):
    d = os.path.join(root, "%s_%s_%s" % (op, MODES[mode], var))
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    dbg = {"full": [], "noop": ["--clutterdbg=noop_" + op], "noen": ["--clutterdbg=noenemy"]}[var]
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/fx_audit_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=2", "--shot_mode=%d" % mode, "--shot_dir=" + d.replace("\\", "/"),
            "--shot_start=%g" % start, "--shot_every=1", "--shot_n=%d" % n, "--shot_w=1280", "--shot_h=720",
            "--seed=11", "--bal=growth/late_shape=1"] + dbg
    out, err, to = GR.run_godot(args, 1800)
    return d, GR.script_errors(out or "", err or "")[:2]


def load(p):
    from PIL import Image
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.int16)


def lumi(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def analyze_move(dfull, dnoop, dnoen):
    fa = sorted(glob.glob(os.path.join(dfull, "f_*.png")))
    rows = []
    for p in fa:
        name = os.path.basename(p)
        q, r = os.path.join(dnoop, name), os.path.join(dnoen, name)
        if not os.path.exists(q):
            continue
        A, B = load(p), load(q)
        m = np.abs(A - B).sum(axis=2) > THR
        cov = float(m.mean())
        dl = float((lumi(A) - lumi(B)).mean())   # 全屏平均亮度增量（0–255）
        en = None
        if os.path.exists(r):
            E = load(r)
            em = np.abs(A - E).sum(axis=2) > THR   # 敌人像素（full 与 noenemy 不同处）
            if em.sum() > 200:
                en = float((m & em).sum() / em.sum())
        rows.append((cov, dl, en))
    if not rows:
        return None
    cov = np.array([r[0] for r in rows])
    dl = np.array([r[1] for r in rows])
    ens = [r[2] for r in rows if r[2] is not None]
    act = cov > 0.005
    return {"frames": len(rows), "cov_peak": round(100 * cov.max(), 2), "cov_mean_active": round(100 * cov[act].mean(), 2) if act.any() else 0.0,
            "cov_mean": round(100 * cov.mean(), 2), "active_s": round(act.sum() / 30.0, 2), "dlum_peak": round(dl.max(), 2),
            "dlum_mean_active": round(dl[act].mean(), 2) if act.any() else 0.0,
            "enemy_covered_peak": round(100 * max(ens), 1) if ens else None,
            "enemy_covered_mean": round(100 * float(np.mean(ens)), 1) if ens else None,
            "cov_curve": [round(100 * float(x), 2) for x in cov[::3]]}


def cmd_cover(a):
    root = a.shots or os.path.join(OUT, "cover_shots")
    ops = a.ops.split(",") if a.ops else OPS
    modes = [int(x) for x in a.modes.split(",")]
    if not a.analyze:
        GR.ensure_imported(GAME)
        jobs = [(o, m, v) for o in ops for m in modes for v in ("full", "noop", "noen")]
        with ThreadPoolExecutor(a.jobs) as ex:
            for d, errs in ex.map(lambda j: shoot(j[0], j[1], j[2], root, n=240 if j[1] == 4 else 180), jobs):
                print(os.path.basename(d), len(glob.glob(os.path.join(d, "f_*.png"))), errs or "", flush=True)
    path = os.path.join(OUT, "cover.json")
    res = json.load(open(path, encoding="utf-8")) if os.path.exists(path) else {}
    for o in ops:
        for m in modes:
            k = "%s_%s" % (o, MODES[m])
            r = analyze_move(*[os.path.join(root, "%s_%s" % (k, v)) for v in ("full", "noop", "noen")])
            if r:
                res.setdefault(o, {})[MODES[m]] = r
                print("%-24s peak %5.1f%%  mean(act) %5.1f%%  act %4.1fs  dlum %5.1f  enemy %s" % (
                    k, r["cov_peak"], r["cov_mean_active"], r["active_s"], r["dlum_peak"], r["enemy_covered_peak"]), flush=True)
    os.makedirs(OUT, exist_ok=True)
    json.dump(res, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    if not a.keep and not a.analyze:
        shutil.rmtree(root, ignore_errors=True)


# ---------------------------------------------------------------- new（新干员交付）
def cmd_new(a):
    b = json.load(open(BUDGET, encoding="utf-8"))
    rt = b.get("runtime", {})
    a.ops = a.op
    perf = cmd_perf(a)[a.op]
    a.modes = "3,0,1,2,4"
    cmd_cover(a)
    cov = json.load(open(os.path.join(OUT, "cover.json"), encoding="utf-8")).get(a.op, {})
    bad = []
    d = perf.get("ft_mean", {}).get("d", 0)
    if d > rt.get("ft_delta_hard_ms", 9e9):
        bad.append("后期绘制帧时增量 %.2f ms > 硬上限 %.2f" % (d, rt["ft_delta_hard_ms"]))
    for mv, r in cov.items():
        lim = rt.get("cover", {}).get("ult" if mv == "ult" else ("atk" if mv == "atk" else "skill"), {})
        for key, lk in (("cov_peak", "cov_peak_hard"), ("cov_mean_active", "cov_mean_hard"), ("dlum_mean_active", "dlum_mean_hard"),
                        ("active_s", "active_s_hard"), ("enemy_covered_mean", "enemy_covered_hard")):
            if lk in lim and r.get(key) is not None and r[key] > lim[lk]:
                bad.append("%s %s = %s > 硬上限 %s" % (mv, key, r[key], lim[lk]))
    print("\n".join(bad) if bad else "运行时各项都在硬上限内（docs/368）")
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["perf", "cover", "new"])
    ap.add_argument("--ops", default="")
    ap.add_argument("--op", default="")
    ap.add_argument("--from", dest="t0", type=float, default=480.0)
    ap.add_argument("--secs", type=float, default=75.0)
    ap.add_argument("--every", type=int, default=30)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--quality", default="high")
    ap.add_argument("--touch", action="store_true")
    ap.add_argument("--tag", default="desk_high")
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--modes", default="3,0,1,2,4")
    ap.add_argument("--shots", default="")
    ap.add_argument("--analyze", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--out", default="", help="结果目录（缺省 build/fx_budget；GCP 上给 $OUT）")
    a = ap.parse_args()
    global OUT
    if a.out:
        OUT = a.out
    sys.exit({"perf": lambda: (cmd_perf(a), 0)[1], "cover": lambda: (cmd_cover(a), 0)[1], "new": lambda: cmd_new(a)}[a.cmd]())


if __name__ == "__main__":
    main()
