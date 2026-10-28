# -*- coding: utf-8 -*-
"""德克萨斯「人物太亮」诊断与压暗发色样稿（用户 10-12；docs/64 §7.4）。只做样稿，不改交付帧条。

用法（在工作树根目录）：
  python tools/texas_bright_mockup.py palette               # 量发色：德克萨斯与其他深发干员的头发主色、明度
  python tools/texas_bright_mockup.py recolor <变体> <输出目录>   # 只换头发三色，写出 8 张帧条（1x + @2x）
  python tools/texas_bright_mockup.py capture [变体 …]       # 实机截图：临时把变体写进本工作树的运行时贴图，跑完立即从 git 还原
  python tools/texas_bright_mockup.py compose               # 拼 build/texas_bright/compare.png
变体：cur（现状）/ v1 / v2 / v3 / v3c（v3 + 外套 / 短裤 / 长袜压暗，推荐）/ v2s（v2 + 衬衫压成浅灰）/
  capture 另有 ref（斯卡蒂、维什戴尔各当主控的参照）/ fx70（现状 + 德克萨斯冲刺 / 剑光特效 70% 不透明）/ v2fx（v2 + fx70）
头发识别：#4C4C68（发色主体，几乎只在头发上）全部算头发；#35375B / #7E7A93 只有周围（1x 半径 1、@2x 半径 2）
有足够多 #4C4C68 时才算头发（腿 / 外套下摆也用 #7E7A93，不能整色替换）。
Godot 只经 tools/godot_runner.py 启动（全机并发上限、副屏 / 屏幕外窗口、静音）；不按进程名结束任何进程。
"""
import os, sys, json, shutil, subprocess, colorsys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths


def _rt(f):
    """运行时贴图文件名（带 .png）→ 游戏读的路径（game/art 索引优先，回退 art/incoming）"""
    return asset_paths.runtime_png(f[:-4])
OUT = os.path.join(ROOT, "build", "texas_bright")
ACTIONS = ["idle", "run", "attack", "skill"]
FX = ["fx_texas_blade", "fx_texas_dash"]


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


HAIR_MAIN, HAIR_SHADOW, HAIR_HI = hx("4C4C68"), hx("35375B"), hx("7E7A93")
# 变体：头发 主体 / 暗部 / 高光 三档（只换这三色里被认作头发的像素）
VARIANTS = {
    "cur": None,
    "v1": {"main": "424058", "shadow": "2D2E48", "hi": "6C6882"},   # 略暗：明度 -15%，色相不变
    "v2": {"main": "3A3640", "shadow": "26232C", "hi": "5C5766"},   # 炭灰：去掉蓝紫，偏暖中性
    "v3": {"main": "25242C", "shadow": "17161D", "hi": "4A5870"},   # 近黑 + 冷色高光（原作观感）
}
VARIANTS["v2s"] = dict(VARIANTS["v2"], shirt="D3D0DB")
VARIANTS["v3c"] = dict(VARIANTS["v3"], coat="47444F")   # V3 + 外套 / 短裤 / 长袜从 #7E7A93 压到炭灰（原作黑外套）
VARIANTS["fx70"] = {"fx": 0.7}
VARIANTS["v2fx"] = dict(VARIANTS["v2"], fx=0.7)
VARIANTS["v3fx"] = dict(VARIANTS["v3"], fx=0.7)
WHITE = hx("FFFDFF")


def hair_mask(img, dens):
    """返回头发像素集合（x, y）"""
    w, h = img.size
    px = img.load()
    r = 1 if dens == 1 else 2
    need = 2 if dens == 1 else 4
    main = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            main[y][x] = p[3] > 0 and p[:3] == HAIR_MAIN
    out = set()
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] == 0:
                continue
            c = p[:3]
            if c == HAIR_MAIN:
                out.add((x, y))
            elif c in (HAIR_SHADOW, HAIR_HI):
                n = 0
                for yy in range(max(0, y - r), min(h, y + r + 1)):
                    for xx in range(max(0, x - r), min(w, x + r + 1)):
                        n += main[yy][xx]
                if n >= need:
                    out.add((x, y))
    return out


def recolor_strip(src, dst, var):
    img = Image.open(src).convert("RGBA")
    dens = 2 if "@2x" in os.path.basename(src) else 1
    if var and "main" in var:
        m = hair_mask(img, dens)
        px = img.load()
        mp = {HAIR_MAIN: hx(var["main"]), HAIR_SHADOW: hx(var["shadow"]), HAIR_HI: hx(var["hi"])}
        for (x, y) in m:
            p = px[x, y]
            px[x, y] = mp[p[:3]] + (255,)
        if "coat" in var:
            # 外套 / 短裤 / 长袜：不属于头发的 #7E7A93（现状整块浅灰紫，Y=125）
            cc = hx(var["coat"])
            w, h = img.size
            for y in range(h):
                for x in range(w):
                    p = px[x, y]
                    if p[3] > 0 and p[:3] == HAIR_HI and (x, y) not in m:
                        px[x, y] = cc + (255,)
        if "shirt" in var:
            sc = hx(var["shirt"])
            w, h = img.size
            for y in range(h):
                for x in range(w):
                    p = px[x, y]
                    if p[3] > 0 and p[:3] == WHITE:
                        px[x, y] = sc + (255,)
    img.save(dst)


def fx_alpha(src, dst, k):
    img = Image.open(src).convert("RGBA")
    r, g, b, a = img.split()
    a = a.point(lambda v: int(round(v * k)))
    Image.merge("RGBA", (r, g, b, a)).save(dst)


def strip_files():
    return ["op_texas_%s%s.png" % (a, s) for a in ACTIONS for s in ("", "@2x")]


def write_variant(name, dst_dir=None):
    """dst_dir=None：就地覆盖运行时贴图（capture 用，跑完 git 还原）"""
    var = VARIANTS[name]
    dst = (lambda f: os.path.join(dst_dir, f)) if dst_dir else _rt
    if dst_dir:
        os.makedirs(dst_dir, exist_ok=True)
    for f in strip_files():
        recolor_strip(_rt(f), dst(f), var)
    if var and "fx" in var:
        for n in FX:
            for s in ("", "@2x"):
                f = n + s + ".png"
                if os.path.exists(_rt(f)):
                    fx_alpha(_rt(f), dst(f), var["fx"])


# ---------------------------------------------------------------- 量色

def lum(c):
    r, g, b = c
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def palette():
    """头发区（德克萨斯用识别出的头发像素；其他人列出深色主色）"""
    rows = []
    from collections import Counter
    img = Image.open(_rt("op_texas_idle@2x.png")).convert("RGBA")
    m = hair_mask(img, 2)
    c = Counter(img.getpixel(p)[:3] for p in m)
    tot = sum(c.values())
    print("德克萨斯 idle@2x 头发像素 %d（占非描边不透明 %.0f%%）" % (tot, 100.0 * tot / sum(
        1 for p in img.getdata() if p[3] > 0 and p[:3] != (8, 14, 24))))
    for col, n in c.most_common():
        h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in col))
        print("  #%02X%02X%02X %5.1f%%  HSL L=%.2f S=%.2f H=%3d  亮度Y=%.0f" % (*col, 100.0 * n / tot, l, s, h * 360, lum(col)))
    for name, var in VARIANTS.items():
        if var and "main" in var:
            print(name, " ".join("%s #%s Y=%.0f" % (k, var[k], lum(hx(var[k]))) for k in ("main", "shadow", "hi")))
    # 明暗结构（idle@2x 全部 4 帧，去掉透明与描边 #080E18）：docs/64 口径的 HSL 明度均值、近黑（Y<40）/ 中间调 / 亮部（Y≥160）占比
    print("\n干员 idle@2x 明暗结构：HSL 明度均值 | Y<40 近黑 | 40–100 | 100–160 | Y≥160 亮部")
    import tempfile
    tmp = tempfile.mkdtemp(prefix="txb_")
    for name in ["texas"] + ["texas:" + v for v in ("v1", "v2", "v3", "v3c")] + \
            ["skadi", "wisadel", "ulpianus", "logos", "lumen", "exusiai", "skalter", "hoshiguma", "angelina"]:
        if name.startswith("texas:"):
            v = name[6:]
            recolor_strip(_rt("op_texas_idle@2x.png"), os.path.join(tmp, "x.png"), VARIANTS[v])
            p = os.path.join(tmp, "x.png")
        else:
            p = _rt("op_%s_idle@2x.png" % name)
        if not os.path.exists(p):
            continue
        px = [q[:3] for q in Image.open(p).convert("RGBA").getdata() if q[3] > 0 and q[:3] != (8, 14, 24)]
        n = float(len(px))
        hsl = sum((max(c) + min(c)) / 510.0 for c in px) / n
        ys = [lum(c) for c in px]
        b = [sum(1 for y in ys if y < 40), sum(1 for y in ys if 40 <= y < 100), sum(1 for y in ys if 100 <= y < 160), sum(1 for y in ys if y >= 160)]
        print("  %-12s %.3f | %4.0f%% | %4.0f%% | %4.0f%% | %4.0f%%" % (name, hsl, *(100 * k / n for k in b)))
    shutil.rmtree(tmp, ignore_errors=True)
    return rows


# ---------------------------------------------------------------- 实机截图

def _git_restore(files):
    subprocess.run(["git", "checkout", "--", *[os.path.relpath(_rt(f), ROOT) for f in files]], cwd=ROOT, check=True)


def _jobs(op_main, squad, tag, shotdir):
    import godot_runner as gr
    base = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1280x720", "--audio-driver", "Dummy",
            "--fixed-fps", "60", "--"]
    sd = shotdir.replace(os.sep, "/")
    run = ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=" + op_main, "--squad=" + squad]
    j = {
        tag + "_idle": base + run + ["--bot=afk", "--maxt=9", "--shots=180,300,420,480", "--shotdir=" + sd + "/" + tag + "_idle"],
        tag + "_run": base + run + ["--bot=expert", "--maxt=9", "--shots=240,330,420,500", "--shotdir=" + sd + "/" + tag + "_run"],
        tag + "_fx": base + run + ["--bot=expert", "--maxprog", "--sptest", "--maxt=14", "--shots=" + ",".join(str(f) for f in range(300, 841, 30)),
                                   "--shotdir=" + sd + "/" + tag + "_fx"],
        tag + "_select": base + ["--unlockall", "--opshot", "--opid=" + op_main, "--shotdir=" + sd + "/" + tag + "_select"],
        tag + "_codex": base + ["--unlockall", "--galleryshot=0,0,0,1.5", "--galleryid=" + op_main, "--shotdir=" + sd + "/" + tag + "_codex"],
    }
    return j


def _run(name, args):
    import godot_runner as gr
    sd = [a for a in args if a.startswith("--shotdir=")][0][10:]
    os.makedirs(sd, exist_ok=True)
    o, e, to = gr.run_godot(args, 300)
    errs = gr.script_errors(o, e)
    with open(os.path.join(sd, "log.txt"), "w", encoding="utf-8") as fh:
        fh.write(" ".join(args) + "\n" + o + "\n----\n" + e)
    return name, errs, to


def capture(names):
    shot = os.path.join(OUT, "shots")
    touched = strip_files() + [n + s + ".png" for n in FX for s in ("", "@2x")]
    for name in names:
        jobs = {}
        if name == "ref":
            jobs.update(_jobs("skadi", "texas,wisadel", "skadi", shot))
            jobs.update(_jobs("wisadel", "texas,skadi", "wisadel", shot))
        else:
            if name != "cur":
                write_variant(name)   # 只就地写本工作树的运行时贴图，跑完立即 git 还原
            jobs.update(_jobs("texas", "skadi,wisadel", name, shot))
        try:
            with ThreadPoolExecutor(4) as ex:
                for n, errs, to in ex.map(lambda kv: _run(*kv), jobs.items()):
                    print(n, "超时" if to else "ok", errs[:2], flush=True)
        finally:
            if name not in ("cur", "ref"):
                _git_restore(touched)


# ---------------------------------------------------------------- 拼图

def _font(sz):
    for f in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


PICKS = {
    "cell": [320, 280],
    "cols": [["cur", "现状 e3c8c230"], ["v1", "V1 略暗"], ["v2", "V2 炭灰"], ["v3", "V3 近黑+冷高光"],
             ["v3c", "V3 + 外套压暗（推荐）"], ["v2s", "V2 + 衬衫浅灰"], ["skadi", "参考：斯卡蒂主控"], ["wisadel", "参考：维什戴尔主控"]],
    # [kind, 文件, 裁剪框, 行名]；实机 160×140 放大 2 倍（主控在画面中心），界面 320×280 原尺寸
    "rows": [["idle", "shot_420.png", (605, 292, 685, 362), "实机 待机 ×4\n主控近景"],
             ["idle", "shot_420.png", (560, 250, 720, 390), "实机 待机\n主控 · 浅滩"],
             ["run", "shot_330.png", (560, 250, 720, 390), "实机 跑动\n主控 · 浅滩"],
             ["fx", "shot_300.png", (560, 250, 720, 390), "实机 技能特效\n--sptest"],
             ["select", "shot_oppick.png", (620, 245, 940, 525), "选人页"],
             ["codex", "shot_gallery_ui.png", (520, 140, 840, 420), "图鉴"]],
}


def compose():
    """拼 compare.png：行 = 实机待机 / 跑动 / 特效 / 选人 / 图鉴，列 = PICKS.cols；列头下画该列的头发三色（主体 / 暗部 / 高光）"""
    shot = os.path.join(OUT, "shots")
    cw, chh = PICKS["cell"]
    cols, rows = PICKS["cols"], PICKS["rows"]
    pad, lab, left = 6, 60, 130
    canvas = Image.new("RGB", (left + len(cols) * (cw + pad), lab + len(rows) * (chh + pad)), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    f, fs = _font(17), _font(12)
    for ci, (tag, label) in enumerate(cols):
        x = left + ci * (cw + pad)
        d.text((x + 4, 4), label, fill=(235, 235, 240), font=f)
        var = VARIANTS.get(tag) or {}
        ramp = [var[k] for k in ("main", "shadow", "hi")] if "main" in var else (["4C4C68", "35375B", "7E7A93"] if tag == "cur" else [])
        for i, h in enumerate(ramp):
            d.rectangle((x + 4 + i * 104, 32, x + 20 + i * 104, 48), fill=hx(h), outline=(110, 110, 120))
            d.text((x + 24 + i * 104, 33), "#" + h, fill=(200, 200, 210), font=fs)
    for ri, (kind, src, box, label) in enumerate(rows):
        y = lab + ri * (chh + pad)
        for li, t in enumerate(label.split("\n")):
            d.text((8, y + chh // 2 - 20 + li * 22), t, fill=(235, 235, 240), font=f)
        for ci, (tag, _) in enumerate(cols):
            p = os.path.join(shot, tag + "_" + kind, src)
            if os.path.exists(p):
                canvas.paste(Image.open(p).convert("RGB").crop(box).resize((cw, chh), Image.NEAREST), (left + ci * (cw + pad), y))
    out = os.path.join(OUT, "compare.png")
    canvas.save(out)
    print(out)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "palette"
    if cmd == "palette":
        palette()
    elif cmd == "recolor":
        write_variant(sys.argv[2], sys.argv[3])
    elif cmd == "capture":
        capture(sys.argv[2:] or ["cur"])
    elif cmd == "compose":
        compose()
