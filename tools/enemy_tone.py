# -*- coding: utf-8 -*-
"""普通 / 精英怪色板量测（界面与美术 10-14，docs/94「补单（10-14 晚）：色板发闷」与 docs/97 附录四的验收口径）。

口径同 tools/art_lint.py 的 tone 项：描边（#080E18）外的不透明像素，luma 用 Rec.709；每种怪把它的全部 @2x 帧条
（e_<id>.png、e_<id>_<动作>.png）合起来算。不改 art_lint 的干员检查。

    python tools/enemy_tone.py                    # 18 种怪的基线表（终端 + build/enemy_tone/report.md）
    python tools/enemy_tone.py --ids fractal,tracer
    python tools/enemy_tone.py --art <目录>        # 量别的目录（Codex 工作树的 art/incoming）
    python tools/enemy_tone.py --base <提交>       # 与这个提交里的同名帧条比：剪影（alpha）是否逐像素相同 + 各指标前后
    python tools/enemy_tone.py --json out.json

列：
    均值 / 标准差 / p5 / p95   luma
    最暗阶      占描边外像素 ≥ 0.5% 的颜色里最暗那一色的 luma（「最暗一阶」）
    近黑        luma ≤ 35 的占比
    中灰        60 ≤ luma ≤ 140 的占比
    饱和        HSL 饱和均值
    有色暗阶    luma ≤ 35 且 HSL 饱和 ≥ 0.2 的占比（「只加一个有色暗阶」那四只看这一列）
判定（docs/97 附录四）：
    full   fractal / tracer / founder / nest / stone / runner：最暗阶 ≤ 35、近黑 10–25%、中灰 ≤ 40%、饱和 ≥ 0.35
           （fractal 另加标准差 ≥ 35）；亮边「比主色亮 2–3 阶」看图，不机检
    tint   reaper / mimic / slider / floater：有色暗阶 ≥ 5%、饱和 ≥ 0.2
    pass   其余八种（offspring、brood、tear、spitter、bone、pocket、skimmer、mother）：只出数，不判
"""
import argparse, glob, io, json, os, subprocess, sys
import numpy as np
from PIL import Image

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
from art_lint import _is_outline, _luma   # 与 art_lint tone 同口径

ART = os.path.join(ROOT, "art", "incoming")
FULL = ["fractal", "tracer", "founder", "nest", "stone", "runner"]
TINT = ["reaper", "mimic", "slider", "floater"]
PASS = ["offspring", "brood", "tear", "spitter", "bone", "pocket", "skimmer", "mother"]
IDS = FULL + TINT + PASS
T = {"dark_step": 35.0, "near_black": (0.10, 0.25), "mid": 0.40, "sat_full": 0.35, "std_fractal": 35.0,
     "tint_share": 0.05, "tint_sat": 0.20, "sat_tint": 0.20, "dark_luma": 35.0, "mid_lo": 60.0, "mid_hi": 140.0, "step_min_share": 0.005}


def names():
    try:
        d = json.load(open(os.path.join(ROOT, "game", "data", "enemies.json"), encoding="utf-8"))["enemies"]
        return {k: v.get("name", k) for k, v in d.items()}
    except Exception:
        return {}


def strips(art, eid):
    """该怪的全部 @2x 帧条文件名（相对 art 目录）"""
    fs = glob.glob(os.path.join(art, "e_%s@2x.png" % eid)) + glob.glob(os.path.join(art, "e_%s_*@2x.png" % eid))
    return sorted(os.path.basename(f) for f in fs)


def load(path):
    return np.asarray(Image.open(path).convert("RGBA"))


def load_git(rev, name):
    rel = "art/incoming/" + name
    try:
        data = subprocess.run(["git", "show", "%s:%s" % (rev, rel)], cwd=ROOT, capture_output=True, check=True).stdout
    except subprocess.CalledProcessError:
        return None
    return np.asarray(Image.open(io.BytesIO(data)).convert("RGBA"))


def hsl_sat(rgb):
    c = rgb / 255.0
    mx, mn = c.max(-1), c.min(-1)
    l = (mx + mn) / 2.0
    d = mx - mn
    den = 1.0 - np.abs(2.0 * l - 1.0)
    return np.where(den > 1e-6, d / np.maximum(den, 1e-6), 0.0)


def measure(imgs):
    px = []
    for a in imgs:
        m = (a[..., 3] > 0) & ~_is_outline(a)
        px.append(a[m][:, :3].astype(np.float32))
    p = np.concatenate(px) if px else np.zeros((0, 3), np.float32)
    if len(p) == 0:
        return None
    y = _luma(p)
    s = hsl_sat(p)
    cols, inv, cnt = np.unique(p.astype(np.uint8), axis=0, return_inverse=True, return_counts=True)
    big = cnt >= max(1, T["step_min_share"] * len(p))
    cy = _luma(cols.astype(np.float32))
    dark_step = float(cy[big].min()) if big.any() else float(y.min())
    return {
        "n": int(len(p)), "mean": float(y.mean()), "std": float(y.std()),
        "p5": float(np.percentile(y, 5)), "p95": float(np.percentile(y, 95)),
        "dark_step": dark_step,
        "near_black": float((y <= T["dark_luma"]).mean()),
        "mid": float(((y >= T["mid_lo"]) & (y <= T["mid_hi"])).mean()),
        "sat": float(s.mean()),
        "tint_dark": float(((y <= T["dark_luma"]) & (s >= T["tint_sat"])).mean()),
        "colors": int(len(cols)),
    }


def judge(eid, m):
    fails = []
    if eid in FULL:
        if m["dark_step"] > T["dark_step"]:
            fails.append("最暗阶 %.0f > %.0f" % (m["dark_step"], T["dark_step"]))
        lo, hi = T["near_black"]
        if not (lo <= m["near_black"] <= hi):
            fails.append("近黑 %.0f%% 不在 %.0f–%.0f%%" % (m["near_black"] * 100, lo * 100, hi * 100))
        if m["mid"] > T["mid"]:
            fails.append("中灰 %.0f%% > %.0f%%" % (m["mid"] * 100, T["mid"] * 100))
        if m["sat"] < T["sat_full"]:
            fails.append("饱和 %.2f < %.2f" % (m["sat"], T["sat_full"]))
        if eid == "fractal" and m["std"] < T["std_fractal"]:
            fails.append("标准差 %.0f < %.0f" % (m["std"], T["std_fractal"]))
        return ("full", fails)
    if eid in TINT:
        if m["tint_dark"] < T["tint_share"]:
            fails.append("有色暗阶 %.1f%% < %.0f%%" % (m["tint_dark"] * 100, T["tint_share"] * 100))
        if m["sat"] < T["sat_tint"]:
            fails.append("饱和 %.2f < %.2f" % (m["sat"], T["sat_tint"]))
        return ("tint", fails)
    return ("pass", [])


def silhouette(art, base, files):
    """新旧帧条 alpha 是否逐像素相同（1x 与 @2x 都比）；返回 (相同, 说明)"""
    bad = []
    for f2 in files:
        for f in (f2, f2.replace("@2x", "")):
            p = os.path.join(art, f)
            if not os.path.exists(p):
                continue
            old = load_git(base, f)
            if old is None:
                bad.append(f + " 上一版不存在")
                continue
            new = load(p)
            if old.shape != new.shape:
                bad.append("%s 尺寸 %s → %s" % (f, old.shape[1::-1], new.shape[1::-1]))
            elif not np.array_equal(old[..., 3] > 0, new[..., 3] > 0):
                bad.append("%s 剪影变了 %d 像素" % (f, int(((old[..., 3] > 0) != (new[..., 3] > 0)).sum())))
    return (not bad, bad)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--ids", help="逗号分隔的怪物 id；缺省 18 种")
    ap.add_argument("--art", default=ART)
    ap.add_argument("--base", help="与这个提交里的同名帧条比剪影和指标")
    ap.add_argument("--json")
    a = ap.parse_args()
    ids = a.ids.split(",") if a.ids else IDS
    nm = names()
    rows, out, nfail = [], {}, 0
    for eid in ids:
        files = strips(a.art, eid)
        if not files:
            rows.append("| %s | %s | — 找不到帧条 |" % (eid, nm.get(eid, "")))
            continue
        m = measure([load(os.path.join(a.art, f)) for f in files])
        tier, fails = judge(eid, m)
        rec = {"name": nm.get(eid, eid), "tier": tier, "files": files, "now": m, "fails": fails}
        cell_base = ""
        if a.base:
            olds = [load_git(a.base, f) for f in files]
            olds = [o for o in olds if o is not None]
            mb = measure(olds) if olds else None
            same, why = silhouette(a.art, a.base, files)
            rec.update({"base": mb, "silhouette_same": same, "silhouette": why})
            if not same:
                fails = fails + ["剪影：" + "；".join(why)]
                rec["fails"] = fails
            if mb:
                cell_base = " ← 均值 %.0f 标准差 %.0f 最暗阶 %.0f 近黑 %.0f%% 中灰 %.0f%% 饱和 %.2f" % (
                    mb["mean"], mb["std"], mb["dark_step"], mb["near_black"] * 100, mb["mid"] * 100, mb["sat"])
        out[eid] = rec
        verdict = "—" if tier == "pass" else ("通过" if not fails else "未达标：" + "；".join(fails))
        nfail += 1 if (tier != "pass" and fails) else 0
        rows.append("| %s | %s | %s | %.0f | %.0f | %.0f | %.0f | %.0f | %.0f%% | %.0f%% | %.2f | %.1f%% | %d | %s%s |" % (
            eid, nm.get(eid, ""), tier, m["mean"], m["std"], m["p5"], m["p95"], m["dark_step"], m["near_black"] * 100,
            m["mid"] * 100, m["sat"], m["tint_dark"] * 100, m["colors"], verdict, cell_base))
    head = ["| id | 名称 | 档 | 均值 | 标准差 | p5 | p95 | 最暗阶 | 近黑 | 中灰 | 饱和 | 有色暗阶 | 色数 | 判定 |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    text = "\n".join(head + rows)
    sys.stdout.reconfigure(encoding="utf-8")
    print(text)
    od = os.path.join(ROOT, "build", "enemy_tone")
    os.makedirs(od, exist_ok=True)
    with open(os.path.join(od, "report.md"), "w", encoding="utf-8") as fh:
        fh.write("# 怪物色板量测（tools/enemy_tone.py）\n\n目录：%s%s\n\n%s\n" % (a.art, ("；对比 " + a.base) if a.base else "", text))
    if a.json:
        json.dump(out, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("\n未达标 %d 种（full / tint 档）；报告 build/enemy_tone/report.md" % nfail)


if __name__ == "__main__":
    main()
