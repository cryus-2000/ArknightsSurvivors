#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""光感 + 粒子感体检（docs/270）：给已按 fx/px_plane 做完的干员出同条件精二实机截图并量化「光 / 颗粒」。只看，不改特效。
在 GCP 上跑（docs/256 custom 任务），本机不开 Godot。

  shots --ops a,b  每人每招（普攻 mode 3、S1 mode 0）三局图鉴演示（tests/fx_audit_shot.tscn，精二，1280×720，30 帧逐帧）：
                   A 正常（fx/px_plane=1）/ B 关照地光（fx/recipe_dl=0）/ C 关 emit（fx/px_plane_emit=0）。
                   A−B 的亮度差 = 照地光的实际贡献，A−C = 发光核心的实际贡献；探针日志（FXA）给颗粒数、寿命、边长、灯半径 / 强度 / 寿命。
                   产物：<op>_<招>.png（命中那一刻 1 倍）、<op>_<招>_x2.png（2 倍局部 + 照地光 / 发光差分热图）、<op>_<招>.json
  rec   --ops a,b  8:00 起 10 秒混战（本人当队长，fx/px_plane=1，--realtime 30 帧）→ <op>_late_8m00.mp4
"""
import argparse, glob, json, os, re, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
BUILD = os.path.join(ROOT, "build", "fx_audit")
MODES = {3: "atk", 0: "s1"}
VARS = {"A": [], "B": ["--bal=fx/recipe_dl=0"], "C": ["--bal=fx/px_plane_emit=0"]}
LATE = ["--bal=growth/late_shape=1"]
START, N = 2.0, 150   # 2 秒起逐帧 5 秒


def font(sz):
    for f in ["C:/Windows/Fonts/msyh.ttc", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def shoot(op, mode, var):
    tag = "%s_%s_%s" % (op, MODES[mode], var)
    fdir = os.path.join(BUILD, tag)
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    args = [GR.find_godot(), "--audio-driver", "Dummy", "--fixed-fps", "30", "--path", GAME, "res://tests/fx_audit_shot.tscn", "--",
            "--shot_op=" + op, "--shot_stage=2", "--shot_mode=%d" % mode, "--shot_dir=" + fdir.replace("\\", "/"),
            "--shot_start=%g" % START, "--shot_every=1", "--shot_n=%d" % N, "--shot_w=1280", "--shot_h=720",
            "--bal=fx/px_plane=1", "--bal=fx/recipe_log=1", "--seed=11"] + LATE + VARS[var]
    out, err, to = GR.run_godot(args, 1500)
    open(os.path.join(BUILD, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    return tag, len(glob.glob(os.path.join(fdir, "f_*.png"))), GR.script_errors(out or "", err or "")[:2]


def parse(op, tag):
    txt = open(os.path.join(BUILD, tag + ".log"), encoding="utf-8", errors="ignore").read().splitlines()
    fxa, shot, ev = {}, {}, []
    for l in txt:
        s = l.split()
        if l.startswith("FXA "):
            d = {"t": float(s[2])}
            for kv in s[3:]:
                k, _, v = kv.partition("=")
                d[k] = v
            fxa[int(s[1])] = d
        elif l.startswith("FXSHOT "):
            shot[int(s[1])] = int(s[2])
        elif l.startswith("FXRLOG ") and len(s) > 3 and s[1] == op:
            ev.append((s[2], int(s[3])))
    return fxa, shot, ev


def lum(p):
    a = np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)
    return a, 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def newparts(d):
    n, mats = 0, {}
    if d.get("new", "-") != "-":
        for kv in d["new"].split(","):
            m, _, c = kv.partition(":")
            mats[m] = mats.get(m, 0) + int(c)
            n += int(c)
    g = int(d.get("gnew", 0)) + int(d.get("sp", 0))
    if g:
        mats["grains"] = mats.get("grains", 0) + g
    return n + g, mats


def analyse(op, mode, out):
    key = MODES[mode]
    tags = {v: "%s_%s_%s" % (op, key, v) for v in VARS}
    fxa, shot, ev = parse(op, tags["A"])
    f2e = {i: e for i, e in shot.items()}
    e2f = {e: i for i, e in shot.items()}
    if not shot:
        return {"op": op, "mode": key, "err": "没有帧"}
    e0, e1 = min(f2e.values()), max(f2e.values())
    # 统计窗：整段（5 秒）里的事件、颗粒、灯
    hits = [e for k, e in ev if k.startswith("hit") and e0 <= e <= e1]
    acts = [e for k, e in ev if not k.startswith("hit") and not k.startswith("skill") and e0 <= e <= e1]
    sk = [e for k, e in ev if k == "skill0" and e0 - 30 <= e <= e1]
    tot, mats, lifes, szs, lights, emits, alive = 0, {}, [], [], [], [], []
    for e in range(e0, e1 + 1):
        d = fxa.get(e)
        if not d:
            continue
        n, m = newparts(d)
        tot += n
        for k, c in m.items():
            mats[k] = mats.get(k, 0) + c
        if d.get("new", "-") != "-":
            lifes.append((float(d["life"]), n))
            szs.append((float(d["sz"]), n))
        if d.get("L", "-") != "-":
            for L in d["L"].split(";"):
                r, i, lf, c = L.split("/")
                lights.append((int(r), float(i), float(lf), c))
        emits.append(int(d.get("emit", 0)))
        alive.append(int(d.get("alive", 0)) + int(d.get("gr", 0)))
    # 命中那一刻：普攻 = 第一下命中事件后、照地光差分最大的帧；S1 = 技能事件后 1 秒内同法
    anchor = (sk[0] if (mode == 0 and sk) else (hits[0] if hits else (acts[0] if acts else e0 + 15)))
    cand = [i for i in sorted(f2e) if anchor <= f2e[i] <= anchor + (30 if mode == 0 else 8)] or [0]
    best, bk = -1, cand[0]
    cache = {}
    for i in cand:
        pa = os.path.join(BUILD, tags["A"], "f_%04d.png" % i)
        pb = os.path.join(BUILD, tags["B"], "f_%04d.png" % i)
        pc = os.path.join(BUILD, tags["C"], "f_%04d.png" % i)
        if not all(os.path.exists(p) for p in (pa, pb, pc)):
            continue
        A, la = lum(pa)
        _, lb = lum(pb)
        _, lc = lum(pc)
        dl, de = np.clip(la - lb, 0, None), np.clip(la - lc, 0, None)
        sc = float(dl.sum() + de.sum()) + 1e4 * newparts(fxa.get(f2e[i], {}))[0]
        cache[i] = (A, dl, de)
        if sc > best:
            best, bk = sc, i
    if bk not in cache:
        return {"op": op, "mode": key, "err": "缺帧"}
    A, dl, de = cache[bk]
    # 整段的光差分（每帧）：照地光峰值 / 面积，发光核心峰值 / 面积
    pk_l = pk_e = 0.0
    for i in sorted(f2e):
        if i % 3:
            continue
        pa, pb, pc = [os.path.join(BUILD, tags[v], "f_%04d.png" % i) for v in "ABC"]
        if not all(os.path.exists(p) for p in (pa, pb, pc)):
            continue
        _, la = lum(pa)
        _, lb = lum(pb)
        _, lc = lum(pc)
        pk_l = max(pk_l, float(np.clip(la - lb, 0, None).max()))
        pk_e = max(pk_e, float(np.clip(la - lc, 0, None).max()))
    ml, me = dl > 4, de > 8
    secs = (e1 - e0 + 1) / 30.0
    nh = len(hits) or len(acts) or 1
    res = {
        "op": op, "mode": key, "frame": bk, "engine": f2e[bk], "secs": round(secs, 2),
        "hits": len(hits), "acts": len(acts), "skill": len(sk),
        "parts_total": tot, "parts_per_hit": round(tot / nh, 1), "parts_per_s": round(tot / secs, 1),
        "parts_s1_1s": None, "mats": mats,
        "life": round(sum(a * b for a, b in lifes) / max(1, sum(b for _, b in lifes)), 2),
        "sz": round(sum(a * b for a, b in szs) / max(1, sum(b for _, b in szs)), 1),
        "alive_max": max(alive) if alive else 0,
        "lights": len(lights), "lights_per_hit": round(len(lights) / nh, 2),
        "light_r": round(float(np.median([l[0] for l in lights])), 0) if lights else 0,
        "light_i": round(float(np.median([l[1] for l in lights])), 2) if lights else 0,
        "light_life": round(float(np.median([l[2] for l in lights])), 2) if lights else 0,
        "emit_max": max(emits) if emits else 0, "emit_mean": round(float(np.mean([x for x in emits if x] or [0])), 1),
        "gl_peak": round(pk_l, 1), "gl_area_hit": int(ml.sum()), "gl_mean_hit": round(float(dl[ml].mean()) if ml.any() else 0.0, 1),
        "em_peak": round(pk_e, 1), "em_area_hit": int(me.sum()), "em_mean_hit": round(float(de[me].mean()) if me.any() else 0.0, 1),
    }
    if sk:
        s0 = sk[0]
        tt = 0
        for e in range(s0, s0 + 31):
            if e in fxa:
                tt += newparts(fxa[e])[0]
        res["parts_s1_1s"] = tt
    # 图：命中那一刻 1 倍；2 倍局部 = 以特效差分中心取 320×180 放大，旁边配照地光 / 发光差分热图
    im = Image.fromarray(A.astype(np.uint8))
    im.save(os.path.join(out, "%s_%s.png" % (op, key)))
    m = (dl > 4) | (de > 8)
    ys, xs = np.nonzero(m)
    H, W = dl.shape
    cx, cy = (int(np.median(xs)), int(np.median(ys))) if len(xs) else (W // 2, H // 2)
    cw, ch = 320, 180
    x0 = min(max(0, cx - cw // 2), W - cw)
    y0 = min(max(0, cy - ch // 2), H - ch)
    res["crop"] = [x0, y0, cw, ch]

    def heat(d, s):
        h = np.clip(d / s, 0, 1)
        rgb = np.stack([h * 255, h * 200, h * 60], axis=-1).astype(np.uint8)
        return Image.fromarray(rgb)
    sheet = Image.new("RGB", (cw * 2 * 3 + 16, ch * 2 + 40), (12, 12, 16))
    dd = ImageDraw.Draw(sheet)
    f = font(22)
    for j, (pic, lab) in enumerate([(im, "实机 2 倍"), (heat(dl, 40.0), "照地光 A−B（满格=40）"), (heat(de, 80.0), "发光核心 A−C（满格=80）")]):
        sheet.paste(pic.crop((x0, y0, x0 + cw, y0 + ch)).resize((cw * 2, ch * 2), Image.NEAREST), (j * (cw * 2 + 8), 40))
        dd.text((j * (cw * 2 + 8) + 8, 8), lab, fill=(230, 230, 230), font=f)
    sheet.save(os.path.join(out, "%s_%s_x2.png" % (op, key)))
    json.dump(res, open(os.path.join(out, "%s_%s.json" % (op, key)), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("体检", json.dumps(res, ensure_ascii=False), flush=True)
    return res


def shots(a):
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    ops = a.ops.split(",")
    allr = []
    for op in ops:   # 一人一批：6 局并行 → 分析 → 删帧（虚拟机系统盘 20 GB）
        jobs = [(op, mode, v) for mode in MODES for v in VARS]
        with ThreadPoolExecutor(a.jobs) as ex:
            for r in ex.map(lambda j: shoot(*j), jobs):
                print("局", r, flush=True)
        for mode in MODES:
            try:
                allr.append(analyse(op, mode, a.out))
            except Exception as e:   # 一人一招坏了不影响其他人
                print("分析失败", op, mode, repr(e), flush=True)
                allr.append({"op": op, "mode": MODES[mode], "err": repr(e)})
        if not a.keep:
            for v in VARS:
                for mode in MODES:
                    shutil.rmtree(os.path.join(BUILD, "%s_%s_%s" % (op, MODES[mode], v)), ignore_errors=True)
    json.dump(allr, open(os.path.join(a.out, "audit_%s.json" % ops[0]), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for op in ops:
        for mode in MODES:
            lg = os.path.join(BUILD, "%s_%s_A.log" % (op, MODES[mode]))
            if os.path.exists(lg):
                shutil.copy(lg, os.path.join(a.out, os.path.basename(lg)))


def rec_one(op, a):
    import imageio_ffmpeg
    tag = "rec_%s" % op
    fdir = os.path.join(BUILD, tag + "_frames")
    shutil.rmtree(fdir, ignore_errors=True)
    os.makedirs(fdir)
    t0, secs = 480, 10
    args = [GR.find_godot(), "--path", GAME, "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30", "--",
            "--balance", "--nodeath", "--seed=11", "--op=" + op, "--bal=fx/px_plane=1", "--realtime", "--rtfrom=%d" % t0,
            "--recframes=%d,%d" % (t0, secs * 30), "--maxt=%d" % (t0 + secs + 1), "--shotdir=" + fdir.replace(os.sep, "/")] + LATE
    out, err, to = GR.run_godot(args, 5400)
    open(os.path.join(BUILD, tag + ".log"), "w", encoding="utf-8").write((out or "") + "\n" + (err or ""))
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    mp4 = os.path.join(a.out, "%s_late_8m00.mp4" % op)
    if not glob.glob(os.path.join(fdir, "rec_*.png")):
        return op, "没有帧", GR.script_errors(out or "", err or "")[:2]
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-pattern_type", "glob", "-i", os.path.join(fdir, "rec_*.png"),
                    "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", mp4], check=True)
    shutil.rmtree(fdir, ignore_errors=True)
    return op, "%.1f MB" % (os.path.getsize(mp4) / 1048576), GR.script_errors(out or "", err or "")[:2]


def rec(a):
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(BUILD, exist_ok=True)
    with ThreadPoolExecutor(a.jobs) as ex:
        for r in ex.map(lambda op: rec_one(op, a), a.ops.split(",")):
            print("录像", r, flush=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["shots", "rec", "both"])
    ap.add_argument("--ops", required=True)
    ap.add_argument("--out", default=os.path.join(BUILD, "out"))
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--keep", action="store_true")
    a = ap.parse_args()
    if a.cmd in ("shots", "both"):
        shots(a)
    if a.cmd in ("rec", "both"):
        rec(a)


if __name__ == "__main__":
    main()
