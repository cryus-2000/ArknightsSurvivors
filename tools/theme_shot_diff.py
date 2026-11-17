# -*- coding: utf-8 -*-
"""主题重构的画面对照（docs/368 §1）：同一组截图在「改前」跑两遍、「改后」跑一遍，逐张比像素。
改前对改前 = 噪声基线（动画 / 计时器带来的自然差异，memory「画面对照用干净局」）；改后对改前的差异不超过噪声基线（外加一点余量）才算一致。

    python tools/theme_shot_diff.py --base <改前提交> --new <改后提交>          # 两个提交各建临时工作树
    python tools/theme_shot_diff.py --base <提交> --new HERE                     # 改后 = 当前工作树
    python tools/theme_shot_diff.py --cases gallery_enemy,bossbar               # 只跑部分（见 CASES）

截图：图鉴（全部解锁）敌人 / 精英 / Boss 每一种的详情页、结局四页；Boss 测试台每个 Boss 第 120 帧（Boss 血条与世界）。
窗口经 tools/godot_runner（屏幕外、不抢焦点、静音），1280×720，--fixed-fps 60。本机每会话最多 2 个 Godot（--jobs 缺省 2）。
输出：build/shot_diff/<标签>/{base1,base2,new}/<局名>.png 与 report.json；差异图 diff_<局名>.png（改后对改前，差异像素标红）。
退出码 0 = 全部在噪声范围内。
"""
import argparse, glob, json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
import godot_runner as GR
import theme_paths as TP

CROOT = GR.common_root()
TOL = 8          # 单通道差 > TOL 才算这个像素不同
MARGIN = 0.0005  # 改后差异比例允许超出噪声基线这么多（0.05%）


def enemy_ids():
    e = json.load(open(TP.data_file("enemies.json"), encoding="utf-8"))["enemies"]
    by = {"enemy": [], "elite": [], "boss": []}
    for k, v in e.items():
        r = v.get("role", "")
        if r == "rare" or v.get("no_gallery"):
            continue
        by["boss" if r == "boss" else ("elite" if r == "elite" else "enemy")].append(k)
    return by


def cases(only):
    by = enemy_ids()
    out = {}
    tabs = {"enemy": 1, "elite": 2, "boss": 3}
    for cat, ids in by.items():
        for k in ids:
            out["gallery_%s_%s" % (cat, k)] = (["--unlockall", "--galleryshot=%d,0,0,1.5" % tabs[cat], "--galleryid=" + k], "shot_gallery_ui.png")
    for i in range(4):
        out["gallery_ending_%d" % i] = (["--unlockall", "--galleryshot=6,%d,0,1.0" % i], "shot_gallery_ui.png")
    for k in by["boss"]:
        out["bossbar_%s" % k] = (["--balance", "--seed=1", "--op=mizuki", "--bosstest=" + k], "shot_boss_%s_120.png" % k)
    if only:
        keep = only.split(",")
        out = {n: v for n, v in out.items() if any(n.startswith(p) for p in keep)}
    return out


def tree_for(ref, tag):
    if ref == "HERE":
        GR.ensure_imported(os.path.join(ROOT, "game"))
        return os.path.join(ROOT, "game"), None
    sha = subprocess.run(["git", "rev-parse", ref], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    wt = os.path.join(CROOT, ".claude", "worktrees", "shot-%s-%s-%d" % (tag, sha[:8], os.getpid()))
    subprocess.run(["git", "worktree", "add", "--detach", wt, sha], cwd=CROOT, check=True, capture_output=True)
    src = os.path.join(ROOT, "game", ".godot")
    if os.path.isdir(src):
        shutil.copytree(src, os.path.join(wt, "game", ".godot"))
    GR.ensure_imported(os.path.join(wt, "game"))
    return os.path.join(wt, "game"), wt


def shoot(game, outdir, cs, jobs):
    os.makedirs(outdir, exist_ok=True)

    def one(item):
        name, (args, png) = item
        sd = os.path.join(outdir, "_" + name)
        shutil.rmtree(sd, ignore_errors=True)
        os.makedirs(sd)
        cmd = [GR.find_godot(), "--path", game, "--resolution", "1280x720", "--audio-driver", "Dummy", "--fixed-fps", "60", "--"] + args + ["--shotdir=" + sd]
        out, err, to = GR.run_godot(cmd, 240)
        src = os.path.join(sd, png)
        if os.path.exists(src):
            shutil.copy2(src, os.path.join(outdir, name + ".png"))
            return name, None
        return name, "没有截图（%s）%s" % ("超时" if to else "", "；".join(GR.script_errors(out, err)[:2]))

    with ThreadPoolExecutor(max(1, jobs)) as ex:
        res = list(ex.map(one, cs.items()))
    for sd in glob.glob(os.path.join(outdir, "_*")):
        shutil.rmtree(sd, ignore_errors=True)
    return {n: w for n, w in res if w}


def diff(a, b, out_png=None):
    from PIL import Image, ImageChops
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return 1.0
    d = ImageChops.difference(ia, ib).point(lambda v: 255 if v > TOL else 0)
    r, g, bb = d.split()
    m = ImageChops.lighter(ImageChops.lighter(r, g), bb)
    n = sum(1 for v in m.getdata() if v)
    if out_png is not None and n:
        red = Image.new("RGB", ia.size, (255, 0, 0))
        Image.composite(red, ia.point(lambda v: v // 3), m).save(out_png)
    return n / float(ia.size[0] * ia.size[1])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--cases", default="")
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--tag", default="")
    a = ap.parse_args()
    cs = cases(a.cases)
    tag = a.tag or ("%s_vs_%s" % (a.base[:9], a.new[:9]))
    out = os.path.join(ROOT, "build", "shot_diff", tag)
    shutil.rmtree(out, ignore_errors=True)
    wts = []
    try:
        gb, wb = tree_for(a.base, "base")
        wts.append(wb)
        gn, wn = tree_for(a.new, "new")
        wts.append(wn)
        print("截图 %d 组 × 3 遍（改前两遍 + 改后一遍）……" % len(cs), flush=True)
        miss = {}
        for sub, game in (("base1", gb), ("base2", gb), ("new", gn)):
            miss.update({"%s/%s" % (sub, k): v for k, v in shoot(game, os.path.join(out, sub), cs, a.jobs).items()})
    finally:
        for w in wts:
            if w:
                subprocess.run(["git", "worktree", "remove", "--force", w], cwd=CROOT, capture_output=True)
    rep, bad = {}, []
    for n in cs:
        f = [os.path.join(out, s, n + ".png") for s in ("base1", "base2", "new")]
        if not all(os.path.exists(x) for x in f):
            rep[n] = {"error": "缺截图"}
            bad.append(n)
            continue
        noise = diff(f[0], f[1])
        chg = diff(f[0], f[2], os.path.join(out, "diff_%s.png" % n))
        chg2 = diff(f[1], f[2])
        ok = min(chg, chg2) <= noise + MARGIN
        rep[n] = {"noise": round(noise, 5), "change": round(min(chg, chg2), 5), "ok": ok}
        if not ok:
            bad.append(n)
    json.dump({"base": a.base, "new": a.new, "tol": TOL, "margin": MARGIN, "cases": rep, "missing": miss}, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for n, r in rep.items():
        print("%s %-34s %s" % ("一致" if r.get("ok") else "不同", n, r))
    print("\n画面对照：%d 组，%d 组一致；报告 %s" % (len(cs), len(cs) - len(bad), os.path.join(out, "report.json")))
    return 0 if not bad else 1


if __name__ == "__main__":
    for _s in (sys.stdout, sys.stderr):
        try:
            _s.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    sys.exit(main())
