# -*- coding: utf-8 -*-
"""后期画面杂乱度量测与降噪预设对照（用户 10-12「现在游戏进行到后期画面是不是太乱了，容易看不清」；
预设代码 game/scripts/render/declutter.gd，旋钮 render/declutter 0–3）。

同 seed 实机截图（--balance --nodeath --fixed-fps 60，机器人 expert，非实时）：两套重特效编队各跑一局到 680 秒，
在后期满屏（约 480 / 540 / 580 秒）、中期 Boss（约 425 秒）、最终 Boss（约 615 / 650 秒）各拍一张，同帧写 shot_<帧>.json
（--clutterlog：特效 / 粒子 / 弹幕 / 预警 / 飘字数量与拥挤度）。降噪只改画面，所以同 seed 下各档的对局状态完全一样，可逐帧对比。

分层份额：同一局再用 --clutterdbg=nofriend / nonum / noenemy / nofoe / noamb 各跑一遍（该层画成全透明、代码照跑），
和完整画面逐像素比，差异像素占世界区域的比例 = 这一层占的屏幕份额。

用法（在工作树根目录）：
  python tools/late_clutter.py capture <标签> [--dc=N] [--dbg=a,b] [--squads=A,B] [--more=--bal=x=y;...]
  python tools/late_clutter.py layers <标签前缀> [--dc=N]          # 跑 full + 5 个分层，标签 <前缀>_full / _nofriend …
  python tools/late_clutter.py metrics <标签 …> [--json=out.json]
  python tools/late_clutter.py share <标签前缀>                     # 分层份额表
  python tools/late_clutter.py compose <输出.png> <标签 …> [--labels=a,b] [--scene=late2]
  python tools/late_clutter.py video <输出.mp4> <标签A> <标签B> [--squad=A]   # 同一段 10 秒，A / B 左右并排
  python tools/late_clutter.py perf <输出.json> [--dc=N]             # --realtime --perf --clutterab 同局轮换 0 档 / N 档量帧时间
Godot 只经 tools/godot_runner.py 启动（全机并发上限、副屏 / 屏幕外窗口、静音）；不按进程名结束任何进程。
"""
import os, sys, json, math
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _gr
OUT = os.path.join(_gr.common_root(ROOT), "build", "late_clutter")   # 主仓库的 build（工作树里也放到主仓库，方便看）
SHOT = os.path.join(OUT, "shots")
# 编队：主控在前（重特效：浊心斯卡蒂 / 德克萨斯 / 能天使 / 维什戴尔 / 艾雅法拉）
SQUADS = {"A": ["skalter", "texas", "exusiai"], "B": ["wisadel", "eyjafjalla", "texas"]}   # 编队上限 3 人
SEED = 13   # 6 个种子里灯火最正常、后期屏上敌人最多的一局（seed 13：480 秒 176 只、最终 Boss 骑士）
# 非实时平衡模式约 0.0689 秒 / 渲染帧（look_contrast：8128 帧 ≈ 560 秒）
_C = {"boss1": 6530, "late1": 7290, "late2": 8200, "late3": 8800, "boss2": 9330, "boss3": 9860}   # 约 430 / 480 / 540 / 580 / 615 / 650 秒（0.0659 秒 / 帧）
SCENES = {k: [v, v + 15, v + 30] for k, v in _C.items()}   # 每处连拍 3 张（间隔约 1 秒），量测取平均
MAXT = 690
VID_T0, VID_N = 540.0, 300   # 视频：实时 30 fps 连拍 10 秒（--recframes）
WORLD_BOX = (180, 190, 1000, 530)   # 1280×720 中央战场区（避开顶栏 / 横幅 / 藏品栏 / 小地图 / 小队栏，主控在中间）
LAYERS = ["nofriend", "nonum", "noenemy", "nofoe", "noamb", "noground", "nogem", "nomire"]
LAYER_NAME = {"nofriend": "友方特效（干员粒子 / 帧条 / 加色层 / 自己的投射物 / 命中与击杀火花）", "nonum": "伤害数字",
              "noenemy": "敌人本体（含描边 / 白闪 / 影子）", "nofoe": "敌方弹幕 / 预警 / 敌方特效", "noamb": "环境（浮游颗粒 / 光尘 / 大群波）",
              "noground": "地面（地砖 / 地形道具）", "nogem": "掉落物（经验结晶等）", "nomire": "溟痕（地面污染）"}


def _base():
    import godot_runner as gr
    return [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1280x720", "--audio-driver", "Dummy",
            "--fixed-fps", "60", "--"]


def run_args(sq, extra, shots=True):
    ops = SQUADS[sq]
    a = ["--balance", "--nodeath", "--seed=%d" % SEED, "--op=" + ops[0], "--squad=" + ",".join(ops[1:]), "--bot=expert",
         "--maxt=%d" % MAXT]
    if shots:
        a += ["--shots=" + ",".join(str(f) for v in SCENES.values() for f in v), "--clutterlog"]
    return a + list(extra)


def _extra(dc, dbg, more):
    e = list(more or [])
    if dc is not None:
        e.append("--bal=render/declutter=%d" % dc)
    if dbg:
        e.append("--clutterdbg=" + dbg)
    return e


def _run(name, args, sd, timeout=1500):
    import godot_runner as gr
    os.makedirs(sd, exist_ok=True)
    o, e, to = gr.run_godot(args, timeout)
    errs = gr.script_errors(o, e)
    with open(os.path.join(sd, "log.txt"), "w", encoding="utf-8") as fh:
        fh.write(" ".join(args) + "\n" + o + "\n----\n" + e)
    return name, errs, to


def capture_jobs(tag, dc=None, dbg="", squads=("A", "B"), more=()):
    base = _base()
    js = []
    for sq in squads:
        sd = os.path.join(SHOT, tag, sq)
        js.append((tag + "/" + sq, base + run_args(sq, _extra(dc, dbg, more)) + ["--shotdir=" + sd.replace(os.sep, "/")], sd))
    return js


def run_jobs(js, par=6):
    import godot_runner as gr
    gr.ensure_imported(os.path.join(ROOT, "game"))
    with ThreadPoolExecutor(par) as ex:
        for n, errs, to in ex.map(lambda j: _run(*j), js):
            print(n, "超时" if to else "ok", errs[:2], flush=True)


# ---------------------------------------------------------------- 量化

def _img(path, box=WORLD_BOX):
    return np.asarray(Image.open(path).convert("RGB").crop(box), dtype=np.float32)


def _lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def _grad(y):
    gx = np.zeros_like(y)
    gy = np.zeros_like(y)
    gx[:, 1:-1] = (y[:, 2:] - y[:, :-2]) * 0.5
    gy[1:-1, :] = (y[2:, :] - y[:-2, :]) * 0.5
    return np.sqrt(gx * gx + gy * gy)


def img_metrics(path):
    a = _img(path)
    y = _lum(a)
    g = _grad(y)
    # 局部对比：16×16 块内亮度标准差的平均
    h, w = y.shape
    hb, wb = h // 16, w // 16
    blk = y[:hb * 16, :wb * 16].reshape(hb, 16, wb, 16).std(axis=(1, 3))
    mx, mn = a.max(axis=2), a.min(axis=2)
    sat = np.where(mx > 31, (mx - mn) / np.maximum(mx, 1), 0)
    return {"edge": float((g > 10).mean()), "edge_hi": float((g > 30).mean()), "grad": float(g.mean()), "local_c": float(blk.mean()),
            "bright": float((mx >= 235).mean()), "mean": float(y.mean()), "sat": float(sat[mx > 31].mean())}


def diff_mask(p_full, p_layer, thr=8.0):
    a, b = _img(p_full), _img(p_layer)
    return np.abs(a - b).max(axis=2) > thr


def leader_box(js, box=WORLD_BOX):
    """主控本体框（世界区域坐标）：屏幕位置在脚底，本体约在脚底上方 0–64 像素"""
    x, y = js["leader_scr"]
    x0, y0 = int(x - 22 - box[0]), int(y - 62 - box[1])
    return max(0, x0), max(0, y0), max(0, x0) + 44, max(0, y0) + 66


def scr(full, mask):
    """信号对杂波：mask 内的平均梯度 / mask 外世界区域的平均梯度（越大越跳）"""
    y = _lum(full)
    g = _grad(y)
    if mask.sum() < 30:
        return None
    return float(g[mask].mean() / max(1e-3, g[~mask].mean()))


def files(tag, sq, multi=False):
    """场景 → (截图, json)；multi = True 时返回该场景连拍的全部 [(截图, json, 帧号)]"""
    d = os.path.join(SHOT, tag, sq)
    out = {}
    for sc, fs in SCENES.items():
        lst = []
        for f in fs:
            p = os.path.join(d, "shot_%d.png" % f)
            if os.path.exists(p):
                jp = os.path.join(d, "shot_%d.json" % f)
                lst.append((p, json.load(open(jp, encoding="utf-8")) if os.path.exists(jp) else {}, f))
        if lst:
            out[sc] = lst if multi else lst[0][:2]
    return out


def counts_row(js):
    fk = js.get("fx_kinds", {})
    pf = sum(o["pfx"] for o in js.get("ops", []))
    pf_mate = sum(o["pfx"] for o in js.get("ops", []) if not o["leader"])
    return {"en_on": js.get("enemies_on", 0), "fx_friend": js.get("fx_friend", 0), "fx_foe": js.get("fx_foe", 0),
            "spark": fk.get("spark", 0), "pfx": pf, "pfx_mate": pf_mate, "bullets": js.get("bullets", 0),
            "ebul_on": js.get("ebullets_on", 0), "tells": js.get("warns_full", 0) + js.get("dash_full", 0),
            "tells_dim": js.get("warns_dim", 0) + js.get("dash_dim", 0), "texts": js.get("texts", 0),
            "dcrowd": js.get("dcrowd", 0), "fx_dim": js.get("fx_dim", 0)}


def _avg(ds):
    out = {}
    for d in ds:
        for k, v in d.items():
            if v is not None:
                out.setdefault(k, []).append(v)
    return {k: float(np.mean(v)) for k, v in out.items()}


SC_GROUP = {"late": ["late1", "late2", "late3"], "boss": ["boss1", "boss2", "boss3"]}


def frame_metrics(p, js):
    m = img_metrics(p)
    c = counts_row(js) if js else {}
    r = dict(m)
    r.update(c)
    if js:
        lb = leader_box(js)
        a = _img(p)
        msk = np.zeros(a.shape[:2], bool)
        msk[lb[1]:lb[3], lb[0]:lb[2]] = True
        r["leader_scr"] = scr(a, msk)
    return r


def metrics(tags, js_out=None, squads=("A", "B"), quiet=False):
    """每个标签：后期满屏（late1–3 × 3 张）与 Boss 战（boss1–3 × 3 张）分组平均"""
    res = {}
    cols = [("en_on", "屏上敌人", "%.0f"), ("fx_friend", "友方 fx", "%.0f"), ("spark", "其中火花", "%.0f"), ("pfx", "干员粒子", "%.0f"),
            ("ebul_on", "屏上敌弹", "%.0f"), ("tells", "全强度预警", "%.1f"), ("texts", "飘字", "%.1f"), ("dcrowd", "拥挤度", "%.2f"),
            ("fx_dim", "友方透明度", "%.2f"), ("edge", "边缘密度", "%.3f"), ("grad", "平均梯度", "%.2f"), ("local_c", "局部对比", "%.2f"),
            ("bright", "近白占比", "%.4f"), ("leader_scr", "主控框梯度比", "%.2f")]
    if not quiet:
        print("| 标签 | 分组 | " + " | ".join(c[1] for c in cols) + " |")
        print("|" + "---|" * (len(cols) + 2))
    for t in tags:
        res[t] = {}
        per = {}
        for sq in squads:
            for sc, lst in files(t, sq, True).items():
                for p, js, f in lst:
                    per.setdefault(sc, []).append(frame_metrics(p, js))
        for grp, scs in SC_GROUP.items():
            ds = [d for sc in scs for d in per.get(sc, [])]
            if not ds:
                continue
            a = _avg(ds)
            a["n"] = len(ds)
            res[t][grp] = a
            if not quiet:
                print("| %s | %s | " % (t, grp) + " | ".join((c[2] % a[c[0]]) if c[0] in a else "—" for c in cols) + " |")
    if js_out:
        json.dump(res, open(js_out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return res


def share(prefix, squads=("A", "B"), quiet=False):
    """分层份额：每层画成全透明后与完整画面的差异像素比例（世界区域）；主控框被友方特效 / 数字盖住的比例；
    敌方层（弹幕 / 预警）的信号杂波比 = 敌方层像素上的平均梯度 / 其余像素的平均梯度。另给 full2（同参数再跑一遍）的噪声基线"""
    full = prefix + "_full"
    per = {}
    for sq in squads:
        for sc, lst in files(full, sq, True).items():
            for p, js, f in lst:
                r = {}
                a = _img(p)
                E = _grad(_lum(a)) > 10   # 纹理级边缘（溟痕 / 结晶这类暗色碎纹也算）
                ne = max(1, int(E.sum()))
                anym = np.zeros(E.shape, bool)
                lb = leader_box(js) if js else None
                for L in LAYERS + ["full2"]:
                    pl = os.path.join(SHOT, prefix + "_" + L, sq, "shot_%d.png" % f)
                    if not os.path.exists(pl):
                        continue
                    m = diff_mask(p, pl)
                    r[L] = float(m.mean())
                    if L != "full2":
                        r[L + "@edge"] = float((E & m).sum()) / ne   # 画面边缘（杂乱感的主体）里有多少落在这一层上
                        anym |= m
                    if lb:
                        r[L + "@leader"] = float(m[lb[1]:lb[3], lb[0]:lb[2]].mean())
                    if L == "nofoe":
                        r["foe_scr"] = scr(a, m)
                        r["foe_px"] = float(m.mean())
                r["ground@edge"] = float((E & ~anym).sum()) / ne   # 不在任何一层上的边缘 = 地面 / 地形道具 / 主控与队友本体 / 掉落物
                r["edge_density"] = float(E.mean())
                per.setdefault(sc, []).append(r)
    out = {}
    names = [LAYER_NAME[L].split("（")[0] for L in LAYERS]
    if not quiet:
        print("| 分组 | " + " | ".join(names) + " | 噪声基线 | 主控框被友方特效盖 | 主控框被数字盖 | 主控框被敌人盖 | 敌方层信号杂波比 |")
        print("|" + "---|" * (len(LAYERS) + 7))
    for grp, scs in SC_GROUP.items():
        ds = [d for sc in scs for d in per.get(sc, [])]
        if not ds:
            continue
        a = _avg(ds)
        out[grp] = a
        if not quiet:
            print("| %s | " % grp + " | ".join("%.1f%%" % (100 * a.get(L, float("nan"))) for L in LAYERS) +
                  " | %.1f%% | %.0f%% | %.0f%% | %.0f%% | %.2f |" % (100 * a.get("full2", float("nan")), 100 * a.get("nofriend@leader", float("nan")),
                                                     100 * a.get("nonum@leader", float("nan")), 100 * a.get("noenemy@leader", float("nan")),
                                                     a.get("foe_scr", float("nan"))))
    if not quiet:
        print()
        print("| 分组 | 边缘密度 | " + " | ".join(names) + " | 其余（角色本体 / 掉落 / 交叠） |")
        print("|" + "---|" * (len(LAYERS) + 3))
        for grp, a in out.items():
            print("| %s | %.3f | " % (grp, a["edge_density"]) + " | ".join("%.0f%%" % (100 * a.get(L + "@edge", float("nan"))) for L in LAYERS) +
                  " | %.0f%% |" % (100 * a["ground@edge"]))
    return out


# ---------------------------------------------------------------- 拼图 / 视频

def _font(sz):
    for f in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def compose(out, tags, labels=None, scenes=("late1", "late2", "late3", "boss2"), sq="A", cw=640, chh=360):
    pad, lab, left = 6, 40, 96
    canvas = Image.new("RGB", (left + len(tags) * (cw + pad), lab + len(scenes) * (chh + pad)), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    f, fs = _font(18), _font(13)
    for ci, t in enumerate(tags):
        d.text((left + ci * (cw + pad) + 4, 8), (labels or tags)[ci], fill=(235, 235, 240), font=f)
    for ri, sc in enumerate(scenes):
        y = lab + ri * (chh + pad)
        d.text((8, y + chh // 2 - 10), sc, fill=(235, 235, 240), font=f)
        for ci, t in enumerate(tags):
            fs_ = files(t, sq)
            if sc not in fs_:
                continue
            p, js = fs_[sc]
            im = Image.open(p).convert("RGB").resize((cw, chh), Image.LANCZOS)
            canvas.paste(im, (left + ci * (cw + pad), y))
            m = img_metrics(p)
            c = counts_row(js) if js else {}
            d.text((left + ci * (cw + pad) + 6, y + chh - 20), "t %.0fs  敌 %d  友方fx %d  飘字 %d  边缘 %.3f  局部对比 %.1f" % (
                js.get("t", 0), c.get("en_on", 0), c.get("fx_friend", 0), c.get("texts", 0), m["edge"], m["local_c"]),
                fill=(255, 255, 160), font=fs, stroke_width=2, stroke_fill=(0, 0, 0))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(out)


def crop_pair(out, a, b, la, lb, sc="late2", sq="A", box=(340, 160, 940, 560)):
    """主控附近局部放大（同帧 A / B 左右并排，最近邻放大 1.5 倍）"""
    fa, fb = files(a, sq).get(sc), files(b, sq).get(sc)
    if not fa or not fb:
        return
    ims = [Image.open(x[0]).convert("RGB").crop(box) for x in (fa, fb)]
    w, h = ims[0].size
    k = 1.5
    W, H = int(w * k), int(h * k)
    canvas = Image.new("RGB", (W * 2 + 8, H + 34), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    for i, (im, l) in enumerate(zip(ims, (la, lb))):
        canvas.paste(im.resize((W, H), Image.NEAREST), (i * (W + 8), 34))
        d.text((i * (W + 8) + 6, 6), l, fill=(235, 235, 240), font=_font(18))
    canvas.save(out)
    print(out)


def video_jobs(tag, dc, sq="A", more=()):
    base = [x if x != "60" else "30" for x in _base()]   # 录片用 --fixed-fps 30：300 帧 = 10 秒（A / B 两边同设置，对局逐帧一致）
    sd = os.path.join(SHOT, tag, sq + "_vid")
    a = run_args(sq, _extra(dc, "", more), shots=False)
    a = [x if not x.startswith("--maxt=") else "--maxt=%d" % (VID_T0 + 14) for x in a]
    return [(tag + "/vid", base + a + ["--realtime", "--recframes=%.1f,%d" % (VID_T0, VID_N), "--shotdir=" + sd.replace(os.sep, "/")], sd)]


def video(out, a, b, la, lb, sq="A"):
    import subprocess, tempfile
    da, db = os.path.join(SHOT, a, sq + "_vid"), os.path.join(SHOT, b, sq + "_vid")
    tmp = tempfile.mkdtemp(prefix="clutter_vid_", dir=OUT)
    f = _font(24)
    k = 0
    for i in range(VID_N):
        pa, pb = os.path.join(da, "rec_%05d.png" % i), os.path.join(db, "rec_%05d.png" % i)
        if not (os.path.exists(pa) and os.path.exists(pb)):
            continue
        A_, B_ = Image.open(pa).convert("RGB"), Image.open(pb).convert("RGB")
        W, H = A_.size
        c = Image.new("RGB", (W * 2 + 8, H), (0, 0, 0))
        c.paste(A_, (0, 0))
        c.paste(B_, (W + 8, 0))
        d = ImageDraw.Draw(c)
        d.text((16, 84), la, fill=(255, 255, 255), font=f, stroke_width=3, stroke_fill=(0, 0, 0))
        d.text((W + 24, 84), lb, fill=(255, 240, 120), font=f, stroke_width=3, stroke_fill=(0, 0, 0))
        c.resize((W, H // 2), Image.LANCZOS).save(os.path.join(tmp, "f_%04d.png" % k))
        k += 1
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ff = "ffmpeg"
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "f_%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out], check=True)
    print(out, k, "帧")


def perf_jobs(tag, dc, sq="A", n=1):
    base = _base()
    js = []
    for i in range(n):
        sd = os.path.join(SHOT, tag, "%s_perf%d" % (sq, i))
        a = run_args(sq, _extra(dc, "", ["--perf", "--prof", "--clutterab=30"]), shots=False)
        js.append((tag + "/perf%d" % i, base + a + ["--shotdir=" + sd.replace(os.sep, "/")], sd))
    return js


def perf_report(tag):
    import glob, re
    for lg in sorted(glob.glob(os.path.join(SHOT, tag, "*_perf*", "log.txt"))):
        txt = open(lg, encoding="utf-8").read()
        m = re.search(r"^PERF (\{.*\})$", txt, re.M)
        if not m:
            print(lg, "无 PERF 行")
            continue
        d = json.loads(m.group(1))
        print(lg)
        for w in sorted(k for k in d if "/" in k):
            v = d[w]
            st = v.get("stage_ms", {})
            print("  %-12s n=%4d  帧中位 %.2f  P99 %.2f  渲染CPU %.2f / P99 %.2f  GPU %.2f  draw_world %.2f  fxadd %.2f  hud %.2f  敌人中位 %d" % (
                w, v["n"], v["ft_med"], v["ft_p99"], v["rcpu_med"], v["rcpu_p99"], v["gpu_med"], st.get("draw_world", 0),
                st.get("draw_fxadd", 0), st.get("draw_hud", 0), v["en_med"]))


if __name__ == "__main__":
    cmd = sys.argv[1]
    a = [x for x in sys.argv[2:] if not x.startswith("--")]
    kw = {x.split("=")[0][2:]: x.split("=", 1)[1] if "=" in x else "1" for x in sys.argv[2:] if x.startswith("--")}
    dc = int(kw["dc"]) if "dc" in kw else None
    sqs = kw.get("squads", "A,B").split(",")
    if "seed" in kw:
        SEED = int(kw["seed"])
    more = [m for m in kw.get("more", "").split(";") if m]
    if cmd == "capture":
        run_jobs(capture_jobs(a[0], dc, kw.get("dbg", ""), sqs, more))
    elif cmd == "layers":
        js = capture_jobs(a[0] + "_full", dc, "", sqs, more)
        for L in (kw["layers"].split(",") if "layers" in kw else LAYERS):
            js += capture_jobs(a[0] + "_" + L, dc, L, sqs, more)
        if "layers" not in kw:
            js += capture_jobs(a[0] + "_full2", dc, "", sqs, more)   # 噪声基线：同参数再跑一遍
        run_jobs(js)
    elif cmd == "metrics":
        metrics(a, kw.get("json"), sqs)
    elif cmd == "share":
        share(a[0], sqs)
    elif cmd == "compose":
        compose(a[0], a[1:], kw["labels"].split(",") if "labels" in kw else None,
                kw.get("scenes", "late1,late2,late3,boss2").split(","), kw.get("squad", "A"))
    elif cmd == "crop":
        crop_pair(a[0], a[1], a[2], kw.get("la", a[1]), kw.get("lb", a[2]), kw.get("scene", "late2"), kw.get("squad", "A"))
    elif cmd == "vidcap":   # 标签以 _dcN 结尾：按第 N 档录
        js = []
        for t in a:
            lv = int(t.split("_dc")[-1]) if "_dc" in t else 0
            js += video_jobs(t, lv, kw.get("squad", "A"))
        run_jobs(js)
    elif cmd == "video":
        video(a[0], a[1], a[2], kw.get("la", a[1]), kw.get("lb", a[2]), kw.get("squad", "A"))
    elif cmd == "perf":
        run_jobs(perf_jobs(a[0], dc, kw.get("squad", "A"), int(kw.get("n", "2"))))
    elif cmd == "perfrep":
        perf_report(a[0])
