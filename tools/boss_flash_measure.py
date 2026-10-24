# -*- coding: utf-8 -*-
"""Boss 战频闪统计（docs/137）：读 tools/boss_flash_rec.py 录的 fr_*.png + flashrec.csv，按 WCAG 2.x「一般闪光」口径数闪烁。
用法：D:/Anaconda/python.exe tools/boss_flash_measure.py <录像目录> [--fps 30] [--plot 输出.png] [--gif 输出.gif --gif-from 帧 --gif-n 帧数]

口径（WCAG 2.3.1 / 2.3.1 的一般闪光阈值，近似实现）：
- 相对亮度 L 按 sRGB 线性化（0.2126 R + 0.7152 G + 0.0722 B）；
- 逐像素把亮度曲线切成单调段（每帧变化 < 0.004 视为平），一段的总变化 ≥ 0.10 且较暗端 < 0.80 记为一次「跳变」，记在段末那一帧；
  这样淡出分几帧走完的也算一次（不会因为每帧变化小而漏数）；
- 同一帧同方向跳变的像素，在任意「1/3 屏宽 × 1/3 屏高」的窗口（≈ 1024×768 下 341×256，10° 视野）里占 ≥ 25%，记一次大面积跳变；
  另记全屏 ≥ 25% 的（ITU-R BT.1702 / Ofcom 口径）；
- 一次闪烁 = 一对相反方向的跳变；任意 1 秒内闪烁 > 3 次不合格。
输出每秒闪烁次数（滑动 1 秒窗口的最大值 / 中位数）、不合格秒数，以及每次大面积跳变那一帧的 CSV 状态（用来按来源分开）。
"""
import os, sys, csv, json, argparse
import numpy as np
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("dir")
ap.add_argument("--fps", type=float, default=30.0)
ap.add_argument("--plot")
ap.add_argument("--gif")
ap.add_argument("--gif-from", type=int, default=0)
ap.add_argument("--gif-n", type=int, default=90)
ap.add_argument("--crop", help="只统计这块（x0,y0,x1,y1，0–1 比例）")
ap.add_argument("--json")
ap.add_argument("--boxd", type=float, default=0.1, help="框内平均亮度一段变化 ≥ 这么多记一次跳变")
ap.add_argument("--boxk", type=float, default=1.6, help="Boss 框半宽 = 碰撞半径 × boxk（框高 = 上 1.6 倍 + 下 0.5 倍）")
a = ap.parse_args()

files = sorted(f for f in os.listdir(a.dir) if f.startswith("fr_") and f.endswith(".png"))
rows = list(csv.DictReader(open(os.path.join(a.dir, "flashrec.csv"), encoding="utf-8")))
n = min(len(files), len(rows))
files, rows = files[:n], rows[:n]


def lum(path):
    x = np.asarray(Image.open(os.path.join(a.dir, path)).convert("RGB"), dtype=np.float32) / 255.0
    x = np.where(x <= 0.04045, x / 12.92, ((x + 0.055) / 1.055) ** 2.4)
    return x[..., 0] * 0.2126 + x[..., 1] * 0.7152 + x[..., 2] * 0.0722


L0 = lum(files[0])
H, W = L0.shape
H0, W0 = H, W
if a.crop:
    c = [float(v) for v in a.crop.split(",")]
    sl = (slice(int(c[1] * H), int(c[3] * H)), slice(int(c[0] * W), int(c[2] * W)))
else:
    sl = (slice(0, H), slice(0, W))
L0 = L0[sl]
H, W = L0.shape
wh, ww = max(1, H // 3), max(1, W // 3)
EPS = 0.004

prev = L0
run_sign = np.zeros_like(L0, dtype=np.int8)
run_start = L0.copy()   # 本段起点亮度
mean_l = [float(L0.mean())]
box_l = [float("nan")]
ev = []   # (帧, 方向, 窗口最大占比, 全屏占比)
lev = []  # Boss 局部：(帧, 方向, Boss 框内占比)
BOXK = a.boxk


def box_of(fi):
    r = rows[min(max(fi, 0), n - 1)]
    if "bx" not in r or float(r["bx"]) < 0:
        return None
    cx, cy, rr = float(r["bx"]) * W0, float(r["by"]) * H0, max(float(r["br"]) * H0 * BOXK, 4.0)
    y0, y1 = int(max(0, cy - rr * 1.6)), int(min(H0, cy + rr * 0.5))
    x0, x1 = int(max(0, cx - rr)), int(min(W0, cx + rr))
    return (slice(y0, y1), slice(x0, x1)) if y1 - y0 > 2 and x1 - x0 > 2 else None


def win_max(mask):
    s = np.pad(mask.astype(np.int32).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    tot = s[wh:, ww:] - s[:-wh, ww:] - s[wh:, :-ww] + s[:-wh, :-ww]
    return float(tot.max()) / (wh * ww)


def flush(i, end_mask, end_val):
    # end_mask 处的段在第 i-1 帧结束（段末亮度 end_val = prev），起点 run_start
    d = end_val - run_start
    dark = np.minimum(end_val, run_start)
    ok = end_mask & (np.abs(d) >= 0.10) & (dark < 0.80)
    for sgn in (1, -1):
        m = ok & (np.sign(d) == sgn)
        if m.any():
            wm = win_max(m)
            fr = float(m.mean())
            if wm >= 0.25:
                ev.append((i - 1, sgn, wm, fr))
            bx = box_of(i - 1) if not a.crop else None
            if bx is not None:
                bf = float(m[bx].mean())
                if bf >= 0.25:
                    lev.append((i - 1, sgn, bf))


for i in range(1, n):
    L = lum(files[i])[sl]
    d = L - prev
    s = np.where(d > EPS, 1, np.where(d < -EPS, -1, 0)).astype(np.int8)
    # 方向反转或变平：上一段在 i-1 结束
    end = (run_sign != 0) & (s != run_sign)
    if end.any():
        flush(i, end, prev)
    newrun = (s != 0) & (s != run_sign)
    run_start = np.where(newrun | (s == 0), prev, run_start)
    run_sign = np.where(s == 0, 0, s).astype(np.int8)
    prev = L
    mean_l.append(float(L.mean()))
    bx = box_of(i) if not a.crop else None
    box_l.append(float(L[bx].mean()) if bx is not None else float("nan"))
flush(n, run_sign != 0, prev)

# 同一帧两个方向都有时各记一次；连续两帧同方向（像素段末分在相邻帧）合并成一次
ev.sort()
merged = []
for e in ev:
    if merged and merged[-1][1] == e[1] and e[0] - merged[-1][0] <= 1:
        if e[2] > merged[-1][2]:
            merged[-1] = (merged[-1][0], e[1], e[2], max(e[3], merged[-1][3]))
        continue
    merged.append(e)
ev = merged

lev.sort()
lm = []
for e in lev:
    if lm and lm[-1][1] == e[1] and e[0] - lm[-1][0] <= 1:
        continue
    lm.append(e)
lev = lm

fps = a.fps
lps = [sum(1 for e in lev if s0 <= e[0] < s0 + fps) / 2.0 for s0 in range(0, max(1, n - int(fps) + 1))]
lps = np.array(lps) if lps else np.zeros(1)
per_sec = []
for s0 in range(0, max(1, n - int(fps) + 1)):
    cnt = sum(1 for e in ev if s0 <= e[0] < s0 + fps)
    per_sec.append(cnt / 2.0)
per_sec = np.array(per_sec) if per_sec else np.zeros(1)
bad = int((per_sec > 3.0).sum())
full = [e for e in ev if e[3] >= 0.25]

# 按来源：大面积跳变那一帧（含前后 1 帧）CSV 里哪些状态在动
def src_of(fi):
    tags = set()
    for j in (fi - 1, fi, fi + 1):
        if 0 <= j < n:
            r = rows[j]
            pr = rows[j - 1] if j > 0 else r
            if float(r["bflash"]) > 0.0 or float(pr["bflash"]) > 0.0:
                tags.add("boss_flash")
            if float(r["gflash"]) > 0.0:
                tags.add("screen_flash")
            if float(r["shake"]) > 0.05:
                tags.add("shake")
            if float(r["hitstop"]) > float(pr["hitstop"]) + 1e-4:
                tags.add("hitstop")
            if int(r["hstar"]) > 0:
                tags.add("hit_star")
            if int(r["intro"]) > 0:
                tags.add("intro")
            if r["phase"] != pr["phase"] or (float(r["cocoon"]) > 0) != (float(pr["cocoon"]) > 0):
                tags.add("phase_change")
            if int(r["warns"]) != int(pr["warns"]):
                tags.add("warn_change")
    return sorted(tags) or ["other"]


by_src = {}
for e in ev:
    for t in src_of(e[0]):
        by_src[t] = by_src.get(t, 0) + 1
# Boss 框内平均亮度曲线的闪烁（第二口径，排除「精灵在框里移动」造成的逐像素跳变）：曲线切单调段，段变化 ≥ BOXD 记一次跳变
BOXD = a.boxd
bt = []
bl = [v for v in box_l]
st, sv, sg = None, None, 0
for i, v in enumerate(bl):
    if v != v:
        continue
    if sv is None:
        sv, pv = v, v
        continue
    dd = v - pv
    sgn = 1 if dd > EPS else (-1 if dd < -EPS else 0)
    if sgn != sg:
        if sg != 0 and abs(pv - sv) >= BOXD:
            bt.append((i - 1, sg))
        sv = pv
        sg = sgn
    pv = v
bps = np.array([sum(1 for e in bt if s0 <= e[0] < s0 + fps) / 2.0 for s0 in range(0, max(1, n - int(fps) + 1))] or [0.0])
lsrc = {}
for e in lev:
    for t in src_of(e[0]):
        lsrc[t] = lsrc.get(t, 0) + 1
bflash_on = sum(1 for r in rows if float(r["bflash"]) > 0.0)
bflash_starts = sum(1 for i in range(1, n) if float(rows[i]["bflash"]) > float(rows[i - 1]["bflash"]) + 1e-4)
res = {
    "dir": os.path.basename(os.path.normpath(a.dir)), "frames": n, "seconds": round(n / fps, 2),
    "transitions": len(ev), "full_screen_transitions": len(full),
    "flash_per_s_max": float(per_sec.max()), "flash_per_s_median": float(np.median(per_sec)),
    "flash_per_s_mean": round(len(ev) / 2.0 / (n / fps), 2),
    "windows_over_3": bad, "windows_total": int(len(per_sec)),
    "boss_flash_frames_pct": round(100.0 * bflash_on / n, 1), "boss_flash_starts_per_s": round(bflash_starts / (n / fps), 2),
    "by_source": by_src,
    "boss_local_transitions": len(lev), "boss_local_flash_per_s_max": float(lps.max()),
    "boss_local_flash_per_s_mean": round(len(lev) / 2.0 / (n / fps), 2), "boss_local_windows_over_3": int((lps > 3.0).sum()),
    "boss_local_by_source": lsrc,
    "boss_mean_flash_per_s_max": float(bps.max()), "boss_mean_flash_per_s_mean": round(len(bt) / 2.0 / (n / fps), 2),
    "boss_mean_windows_over_3": int((bps > 3.0).sum()),
    "mean_lum_range": [round(min(mean_l), 4), round(max(mean_l), 4)],
}
print(json.dumps(res, ensure_ascii=False))
if a.json:
    json.dump({"summary": res, "events": ev, "local_events": lev, "mean_l": mean_l, "box_l": box_l}, open(a.json, "w"), ensure_ascii=False)

if a.plot:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
    fig, ax = plt.subplots(3, 1, figsize=(11, 6.5), sharex=True)
    t = np.arange(n) / fps
    ax[0].plot(t, mean_l, lw=0.8)
    ax[0].plot(t, box_l, lw=0.8, label="Boss 框内")
    ax[0].legend(["全屏", "Boss 框内"], loc="upper right", fontsize=8)
    ax[0].set_ylabel("平均相对亮度")
    for e in lev:
        ax[0].axvline(e[0] / fps, color="r" if e[1] > 0 else "b", alpha=0.25, lw=0.6)
    ax[1].plot(t, [max(0.0, float(r["bflash"])) for r in rows], lw=0.8, label="Boss 白闪（剩余秒）")
    ax[1].plot(t, [min(0.3, float(r["shake"])) for r in rows], lw=0.8, label="震屏（封顶 0.3 显示）")
    ax[1].plot(t, [float(r["gflash"]) for r in rows], lw=0.8, label="全屏闪光")
    ax[1].legend(loc="upper right", fontsize=8)
    ax[2].plot(np.arange(len(per_sec)) / fps, per_sec, lw=0.9, label="全屏（WCAG 10° 窗口）")
    ax[2].plot(np.arange(len(lps)) / fps, lps, lw=0.9, label="Boss 身上（逐像素）")
    ax[2].plot(np.arange(len(bps)) / fps, bps, lw=0.9, label="Boss 框内平均亮度")
    ax[2].legend(loc="upper right", fontsize=8)
    ax[2].axhline(3, color="r", ls="--", lw=0.8)
    ax[2].set_ylabel("每秒闪烁")
    ax[2].set_xlabel("秒")
    fig.suptitle("%s：每秒闪烁最多 全屏 %.1f / Boss 逐像素 %.1f / Boss 框内平均 %.1f（红线 = 3）" % (res["dir"], per_sec.max(), lps.max(), bps.max()))
    fig.tight_layout()
    fig.savefig(a.plot, dpi=90)

if a.gif:
    fr = [Image.open(os.path.join(a.dir, files[i])).convert("RGB") for i in range(a.gif_from, min(n, a.gif_from + a.gif_n))]
    fr = [f.resize((f.width * 2 // 3, f.height * 2 // 3)) if f.width > 400 else f for f in fr]
    fr[0].save(a.gif, save_all=True, append_images=fr[1:], duration=int(1000 / fps), loop=0, optimize=True)
