# -*- coding: utf-8 -*-
"""画面「白灰」诊断与观感预设对照（用户 10-12「我觉得整体都有点白灰」；预设代码 game/scripts/render/look.gd，旋钮 render/look）。

同 seed 实机截图（--seed=3 --balance --nodeath，机器人 expert，非实时 8 步 / 帧）：一局里拍浅滩开局（约 8 秒）、
中期（约 300 秒）、后期满屏（约 560 秒）三处，再加选人页、图鉴。观感只改画面，所以同一组参数下各列的对局状态完全一样。

用法（在工作树根目录）：
  python tools/look_contrast.py capture <标签> [--look=N] [--dbg=a,b] [--ops=texas,...] [--scenes=run,select,codex]
  python tools/look_contrast.py metrics <标签 …>            # 屏幕量化表（世界区域，去掉 HUD）
  python tools/look_contrast.py compose <输出.png> <标签 …>  # 行 = 前 / 中 / 后 / 选人 / 图鉴，列 = 标签
  python tools/look_contrast.py video <输出.mp4> <标签A> <标签B>  # 同一局 A / B 每 0.75 秒切换
Godot 只经 tools/godot_runner.py 启动（全机并发上限、副屏 / 屏幕外窗口、静音）；不按进程名结束任何进程。
"""
import os, sys, json, colorsys
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
OUT = os.path.join(ROOT, "build", "look_contrast")
SHOT = os.path.join(OUT, "shots")
OPS = ["texas", "hoshiguma", "skadi", "wisadel", "mizuki"]
# 非实时平衡模式：每步 0.066 秒（8 步 / 渲染帧），shot 帧号按步数算
SCENES = {"early": [120, 136], "mid": [4656, 4704], "late": [8128, 8560]}   # 中 / 后期避开陷进溟痕的帧（紫色边缘光）
MAXT = 568
# 视频：实时 60 fps，连拍 4 秒（浅滩开局 6–10 秒）
VID_FRAMES = list(range(360, 600, 2))
# 世界区域（1280×720，去掉顶栏 / 底部小队栏 / 左右 HUD 卡片）
WORLD_BOX = (150, 70, 1130, 610)


def mates(op):
    return ",".join([m for m in ["skadi", "wisadel", "texas"] if m != op][:2])


def _base():
    import godot_runner as gr
    return [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1280x720", "--audio-driver", "Dummy",
            "--fixed-fps", "60", "--"]


def jobs(tag, look, dbg, ops, scenes, more=()):
    extra = list(more)   # 例如 ["--bal=render/look_actor_cap=1.1"]
    if look is not None:
        extra.append("--bal=render/look=%d" % look)
    if dbg:
        extra.append("--lookdbg=" + dbg)
    base = _base()
    sd = os.path.join(SHOT, tag).replace(os.sep, "/")
    j = {}
    if "run" in scenes:
        shots = ",".join(str(f) for v in SCENES.values() for f in v)
        for op in ops:
            j[op + "_run"] = base + ["--balance", "--nodeath", "--seed=3", "--op=" + op, "--squad=" + mates(op), "--bot=expert",
                                     "--maxt=%d" % MAXT, "--shots=" + shots, "--shotdir=" + sd + "/" + op + "_run"] + extra
    if "video" in scenes:
        for op in ops:
            j[op + "_vid"] = base + ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=" + op, "--squad=" + mates(op),
                                     "--bot=expert", "--maxt=11", "--shots=" + ",".join(map(str, VID_FRAMES)),
                                     "--shotdir=" + sd + "/" + op + "_vid"] + extra
    if "select" in scenes:
        op = ops[0]
        j[op + "_select"] = base + ["--unlockall", "--opshot", "--opid=" + op, "--shotdir=" + sd + "/" + op + "_select"] + extra
    if "codex" in scenes:
        op = ops[0]
        j[op + "_codex"] = base + ["--unlockall", "--galleryshot=0,0,0,1.5", "--galleryid=" + op,
                                   "--shotdir=" + sd + "/" + op + "_codex"] + extra
    return j


def _run(name, args):
    import godot_runner as gr
    sd = [a for a in args if a.startswith("--shotdir=")][0][10:]
    os.makedirs(sd, exist_ok=True)
    o, e, to = gr.run_godot(args, 900)
    errs = gr.script_errors(o, e)
    with open(os.path.join(sd, "log.txt"), "w", encoding="utf-8") as fh:
        fh.write(" ".join(args) + "\n" + o + "\n----\n" + e)
    return name, errs, to


def capture(tag, look=None, dbg="", ops=None, scenes=("run", "select", "codex"), par=6):
    import godot_runner as gr
    gr.ensure_imported(os.path.join(ROOT, "game"))
    js = jobs(tag, look, dbg, ops or OPS, scenes)
    with ThreadPoolExecutor(par) as ex:
        for n, errs, to in ex.map(lambda kv: _run(*kv), js.items()):
            print(tag, n, "超时" if to else "ok", errs[:2], flush=True)


# ---------------------------------------------------------------- 量化

def _lum(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def img_stats(path, box=WORLD_BOX):
    im = Image.open(path).convert("RGB").crop(box)
    px = list(im.get_flattened_data()) if hasattr(im, 'get_flattened_data') else list(im.getdata())
    n = len(px)
    ys = sorted(_lum(*p) for p in px)
    mean = sum(ys) / n
    p1, p5, p50, p95, p99 = (ys[int(n * q)] for q in (0.01, 0.05, 0.5, 0.95, 0.99))
    clip = sum(1 for p in px if max(p) >= 250) / n
    white = sum(1 for p in px if min(p) >= 235) / n
    # 饱和度：HSV S（只算 V ≥ 0.12 的像素，太暗的量化噪声不算）；色度 = max−min；灰白占比 = V ≥ 0.25 且 S < 0.3 的像素
    sv, chroma, grey = [], 0.0, 0
    for r, g, b in px[::5]:
        mx, mn = max(r, g, b), min(r, g, b)
        chroma += mx - mn
        if mx >= 31:
            sv.append((mx - mn) / mx)
            if mx >= 64 and (mx - mn) / mx < 0.3:
                grey += 1
    m5 = len(px[::5])
    # 暗部最低值：最暗 0.5% 像素的平均 RGB（黑位）
    darkest = sorted(px, key=lambda p: _lum(*p))[: max(1, n // 200)]
    dk = tuple(sum(c[i] for c in darkest) / len(darkest) for i in range(3))
    return {"mean": mean, "p1": p1, "p5": p5, "p50": p50, "p95": p95, "p99": p99, "contrast": p95 - p5,
            "clip": clip, "white": white, "sat": sum(sv) / max(1, len(sv)), "chroma": chroma / m5, "grey": grey / m5, "black": dk}


def scene_files(tag, op, scene):
    d = os.path.join(SHOT, tag, op + "_run")
    return [os.path.join(d, "shot_%d.png" % f) for f in SCENES[scene] if os.path.exists(os.path.join(d, "shot_%d.png" % f))]


def avg(dicts):
    out = {}
    for k in dicts[0]:
        if k == "black":
            out[k] = tuple(sum(d[k][i] for d in dicts) / len(dicts) for i in range(3))
        else:
            out[k] = sum(d[k] for d in dicts) / len(dicts)
    return out


def tag_stats(tag, ops=None, scenes=None):
    """标签 → {scene: 平均统计}（跨干员、跨该场景的几张截图）"""
    ops = ops or OPS
    res = {}
    for sc in scenes or SCENES:
        ds = [img_stats(f) for op in ops for f in scene_files(tag, op, sc)]
        if ds:
            res[sc] = avg(ds)
    return res


def leader_box_stats(tag, op, scene="early"):
    """主控本体附近（屏幕中心 64×72）：亮部截白占比"""
    ds = []
    for f in scene_files(tag, op, scene):
        ds.append(img_stats(f, (608, 300, 672, 372)))
    return avg(ds) if ds else None


def metrics(tags, ops=None, js=None):
    rows = []
    hdr = "| 标签 | 场景 | 平均亮度 Y | p5 | p50 | p95 | 对比 p95-p5 | 截白 ≥250 | 近白 min≥235 | 饱和度 S | 色度 | 灰白占比 | 最暗 0.5% RGB |"
    print(hdr)
    print("|" + "---|" * 13)
    out = {}
    for t in tags:
        st = tag_stats(t, ops)
        out[t] = st
        for sc, s in st.items():
            print("| %s | %s | %.1f | %.0f | %.0f | %.0f | %.0f | %.2f%% | %.2f%% | %.3f | %.1f | %.1f%% | %s |" % (
                t, sc, s["mean"], s["p5"], s["p50"], s["p95"], s["contrast"], 100 * s["clip"], 100 * s["white"], s["sat"],
                s["chroma"], 100 * s["grey"],
                "#%02X%02X%02X" % tuple(int(round(c)) for c in s["black"])))
    if js:
        with open(js, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=1)
    return out


def leaders(tags, ops=None):
    print("| 标签 | " + " | ".join(ops or OPS) + " |")
    print("|---|" + "---|" * len(ops or OPS))
    for t in tags:
        cells = []
        for op in ops or OPS:
            s = leader_box_stats(t, op)
            cells.append("—" if s is None else "Y %.0f · 截白 %.1f%% · 饱和 %.2f" % (s["mean"], 100 * s["clip"], s["sat"]))
        print("| %s | %s |" % (t, " | ".join(cells)))


# ---------------------------------------------------------------- 拼图

def _font(sz):
    for f in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


def _row_src(tag, row, op):
    if row in SCENES:
        fs = scene_files(tag, op, row)
        return fs[0] if fs else None
    d = os.path.join(SHOT, tag, op + "_" + row)
    for n in (["shot_oppick.png"] if row == "select" else ["shot_gallery_ui.png"]):
        if os.path.exists(os.path.join(d, n)):
            return os.path.join(d, n)
    return None


ROW_LABEL = {"early": "浅滩开局\n约 8 秒", "mid": "中期\n约 300 秒", "late": "后期满屏\n约 560 秒", "select": "选人页", "codex": "图鉴"}


def compose(out, tags, labels=None, op="texas", rows=("early", "mid", "late", "select", "codex"), cw=480, chh=270, crop=None):
    pad, lab, left = 6, 54, 110
    canvas = Image.new("RGB", (left + len(tags) * (cw + pad), lab + len(rows) * (chh + pad)), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    f, fs = _font(17), _font(12)
    for ci, t in enumerate(tags):
        x = left + ci * (cw + pad)
        d.text((x + 4, 4), (labels or tags)[ci], fill=(235, 235, 240), font=f)
    for ri, row in enumerate(rows):
        y = lab + ri * (chh + pad)
        for li, s in enumerate(ROW_LABEL.get(row, row).split("\n")):
            d.text((8, y + chh // 2 - 20 + li * 22), s, fill=(235, 235, 240), font=f)
        for ci, t in enumerate(tags):
            p = _row_src(t, row, op)
            if p is None:
                continue
            im = Image.open(p).convert("RGB")
            if crop and row in SCENES:
                im = im.crop(crop)
            canvas.paste(im.resize((cw, chh), Image.LANCZOS if crop is None else Image.NEAREST), (left + ci * (cw + pad), y))
            if row in SCENES:
                s = img_stats(p)
                d.text((left + ci * (cw + pad) + 4, y + chh - 18), "Y %.0f  p5–p95 %.0f–%.0f  截白 %.1f%%  饱和 %.2f" % (
                    s["mean"], s["p5"], s["p95"], 100 * s["clip"], s["sat"]), fill=(255, 255, 160), font=fs,
                       stroke_width=2, stroke_fill=(0, 0, 0))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    canvas.save(out)
    print(out)


def video(out, a, b, op="texas", la=None, lb=None):
    """同一局（同 seed、同帧号）A / B 每 0.75 秒切换，左上角标签；ffmpeg 合成 30 fps"""
    import subprocess, tempfile
    da = os.path.join(SHOT, a, op + "_vid")
    db = os.path.join(SHOT, b, op + "_vid")
    tmp = tempfile.mkdtemp(prefix="look_vid_", dir=os.path.join(OUT))
    f = _font(26)
    k = 0
    for i, fr in enumerate(VID_FRAMES):
        use_b = (i // 22) % 2 == 1
        p = os.path.join(db if use_b else da, "shot_%d.png" % fr)
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGB")
        dr = ImageDraw.Draw(im)
        dr.text((16, 90), (lb or b) if use_b else (la or a), fill=(255, 240, 120) if use_b else (255, 255, 255), font=f,
                stroke_width=3, stroke_fill=(0, 0, 0))
        im.save(os.path.join(tmp, "f_%04d.png" % k))
        k += 1
    try:
        import imageio_ffmpeg
        ff = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        ff = "ffmpeg"
    subprocess.run([ff, "-y", "-loglevel", "error", "-framerate", "30", "-i", os.path.join(tmp, "f_%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", out], check=True)
    print(out, k, "帧")


if __name__ == "__main__":
    cmd = sys.argv[1]
    a = [x for x in sys.argv[2:] if not x.startswith("--")]
    kw = {x.split("=")[0][2:]: x.split("=", 1)[1] for x in sys.argv[2:] if x.startswith("--")}
    if cmd == "capture":
        capture(a[0], int(kw["look"]) if "look" in kw else None, kw.get("dbg", ""),
                kw["ops"].split(",") if "ops" in kw else None, kw.get("scenes", "run,select,codex").split(","),
                int(kw.get("par", "6")))
    elif cmd == "metrics":
        metrics(a, kw["ops"].split(",") if "ops" in kw else None, kw.get("json"))
    elif cmd == "leaders":
        leaders(a, kw["ops"].split(",") if "ops" in kw else None)
    elif cmd == "compose":
        compose(a[0], a[1:], kw["labels"].split(",") if "labels" in kw else None, kw.get("op", "texas"))
    elif cmd == "video":
        video(a[0], a[1], a[2], kw.get("op", "texas"), kw.get("la"), kw.get("lb"))
