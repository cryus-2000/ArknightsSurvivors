# -*- coding: utf-8 -*-
"""画面眩晕 / 粘腻排查（docs/139）：同 seed、同一段局，逐项关掉嫌疑项各录一段，量镜头步长、像素蠕动、发光漂移、顿帧 / 后坐频率。

用法：
    python tools/probes/look_nausea.py rec [--only base,zoom100] [--seg early|late] [--res 1280x720]
    python tools/probes/look_nausea.py ana [--seg ...]           # 出指标表 build/look_nausea/<seg>/metrics.json
    python tools/probes/look_nausea.py gif --only base,zoom100   # 原速 + 1/3 速 gif、关键帧对比

窗口经 godot_runner 放副屏 / 屏幕外、静音；--fixed-fps 60 每帧存图（录像不受机器负载影响，同一段可比）。
"""
import argparse, glob, json, os, re, shutil, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR  # noqa: E402

OUT = os.path.join(GR.common_root(ROOT), "build", "look_nausea")

# 段：起始秒、帧数（60 fps）
SEGS = {"early": (6.0, 240), "late": (300.0, 300)}

KILL_RECOIL = ["--bal=fx/recoil_px=0", "--bal=fx/recoil_px1=0", "--bal=fx/recoil_px2=0", "--bal=fx/recoil_px3=0"]
KILL_SQUASH = ["--bal=fx/squash_basic=0", "--bal=fx/squash_dot=0", "--bal=fx/squash_skill=0"]
VARIANTS = {
    "base": [],
    "zoom100": ["--camzoom=100"],
    "nolowres": ["--bal=render/optical_lowres=0"],
    "nooptical": ["--nooptical"],
    "noglow": ["--bal=render/optical_glow=0"],
    "nosteps": ["--bal=render/optical_steps=0"],
    "nobudget": ["--bal=render/optical_glow_budget=99", "--bal=render/optical_local_budget=99"],
    "nodl": ["--bal=render/optical_dl_max=0"],
    "nosea": ["--bal=render/optical_sea=0", "--bal=render/optical_caustics=0"],
    "nolut": ["--bal=render/optical_lut=0"],
    "nomire": ["--bal=render/optical_mire_emit=0"],
    "noground": ["--bal=render/optical_ground_glow=0"],
    "nokick": ["--bal=fx/leader_kick=0"],
    "norecoil": KILL_RECOIL,
    "nosquash": KILL_SQUASH,
    "nohitstop": ["--nohitstop"],
    "nopop": ["--bal=render/enemy_pop=0"],
    "nokillstyle": ["--bal=render/kill_style=0"],
    # 推荐组合（docs/139 §4）：整数镜头 + 关微震 / 后坐 / 形变 + 发光世界锁定前的临时替代（去阶梯、减辉光）
    "reco": ["--bal=render/nausea_safe=1"],
    "ambdesat": ["--bal=render/ambient_desat=0.5"],
    "ambdesat_nosea": ["--bal=render/ambient_desat=0.5", "--bal=render/optical_sea=0"],
    "camfloat": ["--bal=render/cam_round=0"],
    "camsnap2": ["--bal=render/cam_round=2"],
    "intzoom": ["--bal=render/optical_int_zoom=1"],
    "camfloat_intzoom": ["--bal=render/cam_round=0", "--bal=render/optical_int_zoom=1"],
    "opshi_cf_iz": ["--bal=render/cam_round=0", "--bal=render/optical_int_zoom=1", "--bal=render/optical_ops_hi=1"],
}


def seg_dir(seg, name):
    return os.path.join(OUT, seg, name)


def rec_one(seg, name, res, squad, seed):
    t0, n = SEGS[seg]
    d = seg_dir(seg, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d, exist_ok=True)
    w, h = res.split("x")
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "60",
            "--resolution", "%sx%s" % (w, h), "--",
            "--balance", "--seed=%d" % seed, "--op=" + squad[0], "--squad=" + ",".join(squad[1:]), "--bot=expert",
            "--realtime", "--playclock", "--rtfrom=%g" % max(0.0, t0 - 3.0), "--nohud",
            "--recframes=%g,%d" % (t0, n), "--camlog=%g" % t0, "--shotdir=" + d.replace(os.sep, "/"), "--perf"] + VARIANTS[name]
    out, err, to = GR.run_godot(args, 2400)
    cam = [l for l in out.splitlines() if l.startswith("CAMLOG ")]
    perf = [l for l in out.splitlines() if l.startswith("PERF ") or l.startswith("STOPSTAT")]
    with open(os.path.join(d, "camlog.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(cam))
    with open(os.path.join(d, "stdout.txt"), "w", encoding="utf-8") as fh:
        fh.write(out[-20000:])
    errs = GR.script_errors(out, err)
    nf = len(glob.glob(os.path.join(d, "rec_*.png")))
    print("%s/%s 帧 %d camlog %d %s" % (seg, name, nf, len(cam), ("超时" if to else "") + ("；".join(errs[:2]) if errs else "")))
    return nf


def parse_cam(d):
    rows = []
    for l in open(os.path.join(d, "camlog.txt"), encoding="utf-8"):
        p = l.split()
        if len(p) < 18:
            continue
        rows.append({"f": int(p[1]), "t": float(p[2]), "cx": float(p[3]), "cy": float(p[4]), "ox": float(p[5]), "oy": float(p[6]),
                     "xx": float(p[7]), "xy": float(p[8]), "z": float(p[9]), "lx": float(p[10]), "ly": float(p[11]),
                     "hs": int(p[12]), "nrc": int(p[13]), "nsq": int(p[14]), "ne": int(p[15]), "px": float(p[16]), "py": float(p[17])})
    return rows


def _load(path, crop=None):
    import numpy as np
    from PIL import Image
    im = Image.open(path).convert("RGB")
    if crop:
        im = im.crop(crop)
    return np.asarray(im, dtype=np.int16)


def best_shift(a, b, guess, rad=3):
    """b 相对 a 的整数平移（窗口像素）：在 guess 附近 ±rad 搜平均绝对差最小的；返回 (dx, dy, 残差均值, 残差>24 的像素比例)"""
    import numpy as np
    H, W = a.shape[:2]
    m = 12 + rad + max(abs(guess[0]), abs(guess[1]))
    best = None
    for dy in range(guess[1] - rad, guess[1] + rad + 1):
        for dx in range(guess[0] - rad, guess[0] + rad + 1):
            pa = a[m:H - m, m:W - m]
            pb = b[m + dy:H - m + dy, m + dx:W - m + dx]
            dd = np.abs(pa - pb).max(axis=2)
            s = float(dd.mean())
            if best is None or s < best[2]:
                best = (dx, dy, s, float((dd > 24).mean()))
    return best


def shift_box(a, b, box, rad=7, guess=(0, 0)):
    """box 区域在 b 里的整数平移（窗口像素，±rad 内全搜）：返回 (dx, dy, 残差均值, 残差>24 比例)"""
    import numpy as np
    x0, y0, x1, y1 = box
    best = None
    for dy in range(guess[1] - rad, guess[1] + rad + 1):
        for dx in range(guess[0] - rad, guess[0] + rad + 1):
            if y0 + dy < 0 or x0 + dx < 0 or y1 + dy > b.shape[0] or x1 + dx > b.shape[1]:
                continue
            dd = np.abs(a[y0:y1, x0:x1] - b[y0 + dy:y1 + dy, x0 + dx:x1 + dx]).max(axis=2)
            s = float(dd.mean())
            if best is None or s < best[2]:
                best = (dx, dy, s, float((dd > 24).mean()))
    return best


def _ana1(seg, name):
    return analyze(seg, [name])


def analyze(seg, names):
    import numpy as np
    res = {}
    for name in names:
        d = seg_dir(seg, name)
        cam = parse_cam(d) if os.path.exists(os.path.join(d, "camlog.txt")) else []
        frames = sorted(glob.glob(os.path.join(d, "rec_*.png")))
        if not cam or not frames:
            print("缺", name)
            continue
        cam = cam[:len(frames)]
        # ① 镜头：画布原点逐帧步长（窗口像素）
        st = []
        for i in range(1, len(cam)):
            st.append(((cam[i]["xx"] - cam[i - 1]["xx"]), (cam[i]["xy"] - cam[i - 1]["xy"])))
        mag = np.array([np.hypot(*s) for s in st])
        moving = mag[mag > 0.01]
        hs = [c["hs"] for c in cam]
        kick = sum(1 for c in cam if abs(c["ox"]) + abs(c["oy"]) > 0)
        # 镜头步长不均：相邻两帧步长之差（像素），去掉静止帧
        jerk = np.abs(np.diff(mag))
        # ② 图像实测（窗口像素）：上 / 下两条地面带的整体平移（取残差小的一条）= 世界层每帧位移；中心 80×100（队长）的平移 = 队长在屏幕上的抖动；
        #    地面带对齐后的残差 = 非刚性变化（像素蠕动 + 发光 / 颗粒漂移）
        H, W = _load(frames[0]).shape[:2]
        bands = [(int(W * 0.08), int(H * 0.08), int(W * 0.92), int(H * 0.28)), (int(W * 0.08), int(H * 0.72), int(W * 0.92), int(H * 0.92))]
        ctr = (W // 2 - 40, H // 2 - 70, W // 2 + 40, H // 2 + 30)
        gsteps, pj, resid, frac = [], [], [], []
        prev = _load(frames[0])
        for i in range(1, len(frames)):
            cur = _load(frames[i])
            gg = (int(round(st[i - 1][0])), int(round(st[i - 1][1]))) if i - 1 < len(st) else (0, 0)
            bb = min((shift_box(prev, cur, bx, 2, gg) for bx in bands), key=lambda r: r[2])
            gsteps.append(np.hypot(bb[0], bb[1]))
            resid.append(bb[2])
            frac.append(bb[3])
            pc = shift_box(prev, cur, ctr, 3)
            pj.append(np.hypot(pc[0], pc[1]))
            prev = cur
        gs = np.array(gsteps)
        gm = gs[gs > 0.01]
        res[name] = {
            "frames": len(frames),
            "zoom": cam[0]["z"],
            "cam_step_mean_px": round(float(moving.mean()) if moving.size else 0.0, 3),
            "cam_step_std_px": round(float(moving.std()) if moving.size else 0.0, 3),
            "cam_step_distinct": sorted(set(round(float(x), 2) for x in moving))[:12],
            "cam_jerk_mean_px": round(float(jerk.mean()), 3),
            "cam_still_frames": int((mag <= 0.01).sum()),
            "hitstop_frames": int(sum(hs)),
            "hitstop_events": int(sum(1 for i in range(1, len(hs)) if hs[i] and not hs[i - 1])),
            "kick_frames": kick,
            "recoil_enemies_mean": round(float(np.mean([c["nrc"] for c in cam])), 1),
            "squash_enemies_mean": round(float(np.mean([c["nsq"] for c in cam])), 1),
            "enemies_mean": round(float(np.mean([c["ne"] for c in cam])), 1),
            "ground_step_mean_px": round(float(gm.mean()) if gm.size else 0.0, 3),
            "ground_step_std_px": round(float(gm.std()) if gm.size else 0.0, 3),
            "ground_step_hist": {str(int(k)): int(v) for k, v in zip(*np.unique(np.round(gs).astype(int), return_counts=True))},
            "ground_jerk_px": round(float(np.abs(np.diff(gs)).mean()), 3),
            "player_jitter_px": round(float(np.mean(pj)), 3),
            "player_jitter_frames": int(sum(1 for x in pj if x > 0.5)),
            "resid_mean": round(float(np.mean(resid)), 3),
            "resid_p90": round(float(np.percentile(resid, 90)), 3),
            "resid_frac24": round(float(np.mean(frac)), 4),
        }
        print(name, json.dumps(res[name], ensure_ascii=False))
        json.dump(res[name], open(os.path.join(d, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False)
    # 汇总：各变体目录里的 metrics.json 合成一张
    allm = {}
    for f in sorted(glob.glob(os.path.join(OUT, seg, "*", "metrics.json"))):
        allm[os.path.basename(os.path.dirname(f))] = json.load(open(f, encoding="utf-8"))
    json.dump(allm, open(os.path.join(OUT, seg, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return res


def color_stats(seg, names, every=10):
    """色调：每 every 帧取一张，HSV 统计（有色像素 = 饱和度 > 0.2 且明度 > 0.1）：紫 / 洋红（色相 250–330°）占有色像素比例、
    青蓝（170–230°）比例、平均饱和度、平均明度、整体色偏（R−G、B−G 均值，0–255）；另存一张色相直方图拼图"""
    import numpy as np
    from PIL import Image, ImageDraw
    res = {}
    hists = []
    for name in names:
        fr = sorted(glob.glob(os.path.join(seg_dir(seg, name), "rec_*.png")))[::every]
        if not fr:
            continue
        acc = {"purple": [], "cyan": [], "sat": [], "val": [], "rg": [], "bg": [], "colored": []}
        hh = np.zeros(36)
        for f in fr:
            im = Image.open(f).convert("RGB")
            a = np.asarray(im, dtype=np.float32)
            hsv = np.asarray(im.convert("HSV"), dtype=np.float32)
            h = hsv[..., 0] * 360.0 / 255.0
            sat = hsv[..., 1] / 255.0
            val = hsv[..., 2] / 255.0
            col = (sat > 0.2) & (val > 0.1)
            n = max(1, int(col.sum()))
            acc["purple"].append(float(((h >= 250) & (h <= 330) & col).sum()) / n)
            acc["cyan"].append(float(((h >= 170) & (h <= 230) & col).sum()) / n)
            acc["colored"].append(float(col.mean()))
            acc["sat"].append(float(sat.mean()))
            acc["val"].append(float(val.mean()))
            acc["rg"].append(float((a[..., 0] - a[..., 1]).mean()))
            acc["bg"].append(float((a[..., 2] - a[..., 1]).mean()))
            hh += np.histogram(h[col], bins=36, range=(0, 360), weights=sat[col])[0]
        res[name] = {k: round(float(np.mean(v)), 4) for k, v in acc.items()}
        hists.append((name, hh / max(1e-6, hh.sum())))
        print(name, json.dumps(res[name]))
    # 色相直方图（每行一个变体，柱色 = 该色相）
    if hists:
        import colorsys
        rw, rh = 540, 70
        img = Image.new("RGB", (rw + 110, rh * len(hists)), (24, 24, 28))
        dr = ImageDraw.Draw(img)
        for r, (name, hh) in enumerate(hists):
            mx = max(hh.max(), 1e-6)
            for i, v in enumerate(hh):
                c = tuple(int(x * 255) for x in colorsys.hsv_to_rgb((i * 10 + 5) / 360.0, 0.8, 0.95))
                bh = int((rh - 12) * v / mx)
                dr.rectangle([100 + i * 15, r * rh + rh - 4 - bh, 100 + i * 15 + 12, r * rh + rh - 4], fill=c)
            dr.text((6, r * rh + rh // 2 - 6), name, fill=(230, 230, 230))
        img.save(os.path.join(OUT, seg, "hue_hist.png"))
    p = os.path.join(OUT, seg, "color.json")
    json.dump(res, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return res


PACE = {   # 帧间隔实测：真实时间、开窗口（副屏）、垂直同步开；名字 → 额外参数
    "mid_60": ["--quality=mid", "--maxfps=60"],
    "mid_free": ["--quality=mid", "--maxfps=0"],
    "high_60": ["--quality=high", "--maxfps=60"],
    "high_free": ["--quality=high", "--maxfps=0"],
}


def pace(names, t0=300.0, secs=30.0, squad="mizuki,siege,wisadel,kaltsit", seed=3):
    """真实帧率下的帧间隔分布（不是平均帧率）：中 / 高画质、60 帧上限 / 不限；后期约 100 只同屏"""
    import numpy as np
    GR.ensure_imported(os.path.join(ROOT, "game"))
    sq = squad.split(",")
    res = {}
    d = os.path.join(OUT, "pace")
    os.makedirs(d, exist_ok=True)
    for name in names:
        csv = os.path.join(d, name + ".csv")
        args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--",
                "--balance", "--seed=%d" % seed, "--op=" + sq[0], "--squad=" + ",".join(sq[1:]), "--bot=expert",
                "--realtime", "--playclock", "--rtfrom=%g" % t0, "--maxt=%g" % (t0 + secs), "--perf", "--perfdump=" + csv.replace(os.sep, "/")] + PACE[name]
        out, err, to = GR.run_godot(args, 1800)
        scr = [l for l in out.splitlines() if l.startswith("SCREEN")]
        ft, en = [], []
        for l in open(csv, encoding="utf-8").read().splitlines()[1:]:
            p = l.split(",")
            ft.append(float(p[2]))
            en.append(int(p[7]))
        ft = np.array(ft[30:])
        dd = np.abs(np.diff(ft))
        res[name] = {"screen": scr[0] if scr else "", "n": int(ft.size), "enemies_mean": round(float(np.mean(en)), 1),
                     "ft_mean": round(float(ft.mean()), 2), "ft_med": round(float(np.median(ft)), 2), "ft_std": round(float(ft.std()), 2),
                     "ft_p05": round(float(np.percentile(ft, 5)), 2), "ft_p95": round(float(np.percentile(ft, 95)), 2), "ft_p99": round(float(np.percentile(ft, 99)), 2),
                     "jitter_mean": round(float(dd.mean()), 2), "jitter_gt4ms": round(float((dd > 4).mean()), 3),
                     "hist_ms": {str(k): int(v) for k, v in zip(*np.unique(np.round(ft).astype(int), return_counts=True))}}
        print(name, json.dumps(res[name], ensure_ascii=False))
    p = os.path.join(d, "pace.json")
    old = json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}
    old.update(res)
    json.dump(old, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def make_gif(seg, names, crop_frac=0.5, t_from=0, n=120):
    """每个变体：中央 crop 原尺寸像素，原速（每 2 帧取 1，30 fps）+ 1/3 速（每帧，50 ms = 20 fps）gif；再拼一张并排 gif"""
    from PIL import Image, ImageDraw
    outs = []
    for name in names:
        frames = sorted(glob.glob(os.path.join(seg_dir(seg, name), "rec_*.png")))[t_from:t_from + n]
        if not frames:
            continue
        im0 = Image.open(frames[0])
        W, H = im0.size
        cw, ch = int(W * crop_frac), int(H * crop_frac)
        box = ((W - cw) // 2, (H - ch) // 2, (W + cw) // 2, (H + ch) // 2)
        ims = []
        for f in frames:
            im = Image.open(f).convert("RGB").crop(box)
            ImageDraw.Draw(im).text((6, 4), name, fill=(255, 255, 0))
            ims.append(im)
        outs.append((name, ims))
        d = os.path.join(OUT, seg, "gif")
        os.makedirs(d, exist_ok=True)
        ims[0].save(os.path.join(d, name + "_1x.gif"), save_all=True, append_images=ims[2::2], duration=33, loop=0)
        ims[0].save(os.path.join(d, name + "_third.gif"), save_all=True, append_images=ims[1:], duration=50, loop=0)
    if len(outs) >= 2:
        w, h = outs[0][1][0].size
        side = []
        for i in range(min(len(o[1]) for o in outs)):
            c = Image.new("RGB", (w * len(outs), h))
            for k, o in enumerate(outs):
                c.paste(o[1][i], (k * w, 0))
            side.append(c)
        tag = "_vs_".join(o[0] for o in outs)
        d = os.path.join(OUT, seg, "gif")
        side[0].save(os.path.join(d, tag + "_1x.gif"), save_all=True, append_images=side[2::2], duration=33, loop=0)
        side[0].save(os.path.join(d, tag + "_third.gif"), save_all=True, append_images=side[1:], duration=50, loop=0)
        print("gif", os.path.join(d, tag + "_third.gif"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["rec", "ana", "gif", "color", "pace"])
    ap.add_argument("--seg", default="early")
    ap.add_argument("--only", default="")
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--seed", type=int, default=3)
    ap.add_argument("--squad", default="mizuki,siege,wisadel,kaltsit")
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--from", dest="t_from", type=int, default=0)
    ap.add_argument("--n", type=int, default=120)
    ap.add_argument("--crop", type=float, default=0.5)
    a = ap.parse_args()
    names = [x for x in a.only.split(",") if x] or list(VARIANTS)
    if a.cmd == "rec":
        GR.ensure_imported(os.path.join(ROOT, "game"))
        import concurrent.futures as cf
        with cf.ThreadPoolExecutor(a.jobs) as ex:
            list(ex.map(lambda nm: rec_one(a.seg, nm, a.res, a.squad.split(","), a.seed), names))
    elif a.cmd == "ana":
        if len(names) > 1:
            import concurrent.futures as cf
            with cf.ProcessPoolExecutor(min(6, len(names))) as ex:
                list(ex.map(_ana1, [a.seg] * len(names), names))
            analyze(a.seg, [])
        else:
            analyze(a.seg, names)
    elif a.cmd == "pace":
        pace([x for x in a.only.split(",") if x] or list(PACE))
    elif a.cmd == "color":
        color_stats(a.seg, names)
    else:
        make_gif(a.seg, names, a.crop, a.t_from, a.n)


if __name__ == "__main__":
    main()
