# -*- coding: utf-8 -*-
"""干员「人物太亮 / 发白」通用诊断与调色样稿（docs/64 §7.4 德克萨斯 → §7.5 星熊起通用）。只做样稿，不改交付帧条。

和 tools/texas_bright_mockup.py 同一口径（idle@2x 全部帧，去掉透明与全部 #080E18 描边色）：
  HSL 明度均值 = (max+min)/510；亮度 Y = 0.2126R + 0.7152G + 0.0722B；近黑 Y<40，亮部 Y≥160。
德克萨斯的头发要靠邻域识别（同一色既在头发又在衣服上），这里的变体只做「整色替换」：
先用 `sheet` 看清每个颜色落在哪个部位，确认该色只属于一个部位再写进 VARIANTS。

用法（在工作树根目录）：
  python tools/op_bright_mockup.py sheet <干员> [帧]          # 每色一张掩膜（洋红 = 该色），写 build/<干员>_bright/sheet_<干员>.png
  python tools/op_bright_mockup.py metrics [干员 …]           # 明暗结构 + 各部位主色（缺省 = 第三批五人 + 已验收参照）
  python tools/op_bright_mockup.py recolor <干员> <变体> <目录>  # 写出 8 张帧条（1x + @2x）
  python tools/op_bright_mockup.py capture <干员> [变体 … | ref] # 同 seed 实机：当主控 / 当队友 / 选人页 / 图鉴；变体临时写进本工作树 art/incoming，跑完立即 git 还原
  python tools/op_bright_mockup.py compose <干员>             # 拼 build/<干员>_bright/compare.png
  python tools/op_bright_mockup.py lineup <输出.png> <干员 …>   # 几名干员现状同框（先各自 capture <干员> cur）
Godot 只经 tools/godot_runner.py 启动（全机并发上限、副屏 / 屏幕外窗口、静音）；不按进程名结束任何进程。
"""
import os, sys, shutil, subprocess, colorsys, tempfile
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
INC = os.path.join(ROOT, "art", "incoming")
ACTIONS = ["idle", "run", "attack", "skill"]
OUTLINE = (8, 14, 24)
NEW = ["texas", "hoshiguma", "exusiai", "angelina", "skalter"]
REFS = ["skadi", "wisadel", "ulpianus", "saria", "logos"]
OUTNAME = {"hoshiguma": "hsg_bright"}


def outdir(op):
    return os.path.join(ROOT, "build", OUTNAME.get(op, op + "_bright"))


def hx(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def hexs(c):
    return "#%02X%02X%02X" % tuple(c)


def lum(c):
    r, g, b = c
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def hsl_l(c):
    return (max(c) + min(c)) / 510.0


# 部位 → 颜色（按 `sheet` 掩膜目视归类；只列主要颜色，其余归「其他」）
PARTS = {
    "hoshiguma": {
        "头发（薄荷青）": ["68FDE3", "26C9BD", "196070", "209799", "3AF2DC", "93F9E5", "259897"],
        "铠甲 / 盾 中间调灰": ["404050", "7C7580", "908D96", "5A5B6B", "534D5B", "606675", "6B6C7B", "A6AAB0"],
        "铠甲 / 盾 暗部": ["262E40", "15192C", "050615"],
        "盾沿 / 金属高光": ["E7E6E7", "DDE4ED", "FEFAF3"],
        "肤 / 角": ["FFE4D1", "D6BFB9"],
    },
    # 以下四人只做粗分（快表用）；德克萨斯 #7E7A93 头发、外套共用，详见 texas_bright_mockup.py 的邻域识别
    "texas": {
        "头发（含共用 #7E7A93 前）": ["4C4C68", "35375B"],
        "外套 / 短裤 / 长袜（与发梢共用）": ["7E7A93"],
        "衬衫 / 手套 / 徽记": ["FFFDFF", "FBEBDA"],
        "肤 / 橙剑": ["EEBC8B", "FFBE3C", "B69992"],
    },
    "exusiai": {
        "头发（红）": ["9A3C5C", "7D3851", "73233F", "AA3E5E", "CA6982", "BC5371"],
        "外套 / 裤（深灰紫）": ["413E4B", "2D2C37", "3F313B", "6B5D5F", "4E4752", "51525C"],
        "肤 / 光环 / 翅": ["ECB0AA", "B99C90", "E8DAB4", "B9AA8A", "FBE7D2", "F6DCC9"],
    },
    "angelina": {
        "头发 / 耳尾（浅棕）": ["BA8A7B", "AD7568", "8D675D", "845F57", "75514A"],
        "外套（白 / 奶）": ["F7E7DE", "EBD4CB", "DEB0A1", "FAF3EE"],
        "深色（内衬 / 杖 / 暗部）": ["624D4A", "4B403F", "413130", "622E2C", "352323", "2A1112"],
    },
    "skalter": {
        "头发（银白）": ["B3A7BD", "D0CBDA", "DADAE9", "A0818F"],
        "红裙": ["CF1C25", "7C262D", "503A3E"],
        "帽 / 深色": ["272529", "3C373C", "213037", "444C55", "21191D", "212226"],
    },
}

# 变体：整色替换 {原色: 新色}（只换本人四组动作 1x + @2x 帧条）
_HSG_STEEL = {   # 铠甲 / 盾中间调 → 暗钢（亮度约 ×0.6，色相拉到冷蓝灰，去掉 #7C7580 这类偏紫的灰）
    "A6AAB0": "7A808C", "908D96": "5E6370", "7C7580": "4C505C", "6B6C7B": "454957",
    "606675": "3E4351", "5A5B6B": "393C4A", "534D5B": "33343F", "404050": "2A2C38",
}
_HSG_BLACK = {   # 铠甲 / 盾 → 近黑（原作黑外套 + 深灰盾），中间调只留盾面最亮一档
    "A6AAB0": "5C626E", "908D96": "3E424E", "7C7580": "2E303A", "6B6C7B": "2A2D37",
    "606675": "262934", "5A5B6B": "22252F", "534D5B": "1F212A", "404050": "1A1C24",
    "262E40": "14161E",
}
_HSG_HAIR = {    # 头发薄荷青压深一档（色相不变，饱和略降）：只给发梢 / 反光留亮
    "93F9E5": "7DE0CE", "68FDE3": "4FD6C0", "3AF2DC": "2FC7B6", "26C9BD": "1FA39C",
    "209799": "197A80", "259897": "1C7C80", "196070": "134854",
}
_HSG_HAIR2 = {   # 头发再深一档：只有发顶反光 #93F9E5 一档留在亮部（Y≥160），主体落在 Y 115–135
    "93F9E5": "6FD3C2", "68FDE3": "3DB8A8", "3AF2DC": "2E9F95", "26C9BD": "1E8A86",
    "209799": "18686E", "259897": "1A6B70", "196070": "12404C",
}
_HSG_SPLIT = {   # 甲 / 盾拉开明暗：上三档留 V1 的暗钢（甲片受光面、盾面），下六档压暗、其中四档进近黑（衣服、甲缝、阴影）
    "A6AAB0": "7A808C", "908D96": "5E6370", "7C7580": "4C505C", "6B6C7B": "3A3E4A",
    "606675": "2E323E", "5A5B6B": "22252F", "534D5B": "1F212A", "404050": "1A1C24", "262E40": "14161E",
}
VARIANTS = {
    "hoshiguma": {
        "cur": {"label": "现状", "map": {}},
        "v1": {"label": "V1 暗钢甲盾", "map": dict(_HSG_STEEL)},
        "v2": {"label": "V2 暗钢 + 深青发", "map": dict(_HSG_STEEL, **_HSG_HAIR)},
        "v3": {"label": "V3 黑甲 + 深青发", "map": dict(_HSG_BLACK, **_HSG_HAIR)},
        "v4": {"label": "V4 黑甲 + 更深青发", "map": dict(_HSG_BLACK, **_HSG_HAIR2)},
        "v5": {"label": "V5 钢甲拉开明暗 + 深青发", "map": dict(_HSG_SPLIT, **_HSG_HAIR)},
    },
}


def strip_files(op):
    return ["op_%s_%s%s.png" % (op, a, s) for a in ACTIONS for s in ("", "@2x")]


def recolor_img(img, mp):
    if not mp:
        return img
    m = {hx(k): hx(v) for k, v in mp.items()}
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            p = px[x, y]
            if p[3] > 0 and p[:3] in m:
                px[x, y] = m[p[:3]] + (p[3],)
    return img


def write_variant(op, name, dst_dir):
    mp = VARIANTS[op][name]["map"]
    os.makedirs(dst_dir, exist_ok=True)
    for f in strip_files(op):
        recolor_img(Image.open(os.path.join(INC, f)).convert("RGBA"), mp).save(os.path.join(dst_dir, f))


# ---------------------------------------------------------------- 量色

def pixels(op, var=None, action="idle"):
    img = Image.open(os.path.join(INC, "op_%s_%s@2x.png" % (op, action))).convert("RGBA")
    if var:
        recolor_img(img, VARIANTS[op][var]["map"])
    return [q[:3] for q in img.getdata() if q[3] > 0]


LAMP = (1.6, 1.5, 1.3)


def _lit(c):
    return tuple(min(255.0, v * k) for v, k in zip(c, LAMP))


def stats(px):
    body = [c for c in px if c != OUTLINE]
    n = float(len(body))
    ys = [lum(c) for c in body]
    return {
        "hsl": sum(hsl_l(c) for c in body) / n,
        "black": sum(1 for y in ys if y < 40) / n,
        "mid1": sum(1 for y in ys if 40 <= y < 100) / n,
        "mid2": sum(1 for y in ys if 100 <= y < 160) / n,
        "bright": sum(1 for y in ys if y >= 160) / n,
        "line": px.count(OUTLINE) / float(len(px)),   # #080E18（外描边 + 内部勾线）占全部不透明像素
        # 主控受灯火估算（docs/64 §7.4：本体约 R×1.6 G×1.5 B×1.3）：原本是中间调（40≤Y<160）、受光后变成亮部（Y≥160）的占比
        # ——「整个人发白」主要来自这部分；本来就白的衬衫 / 肤色截顶是每个人都有的，单列「有通道截顶」
        "lit_white": sum(1 for c in body if 40 <= lum(c) < 160 and lum(_lit(c)) >= 160) / n,
        "lit_clip": sum(1 for c in body if max(c[0] * LAMP[0], c[1] * LAMP[1], c[2] * LAMP[2]) >= 255) / n,
        "top": Counter(body).most_common(),
        "n": n,
    }


def metrics(ops):
    print("idle@2x（4 帧，去掉透明与 #080E18）：HSL 明度均值 | 近黑 Y<40 | 40–100 | 100–160 | 亮部 Y≥160 | #080E18 占不透明 | 中间调受光变亮部 | 有通道截顶")
    rows = []
    for op in ops:
        names = [None] + [v for v in VARIANTS.get(op, {}) if v != "cur"]
        for v in names:
            if not os.path.exists(os.path.join(INC, "op_%s_idle@2x.png" % op)):
                continue
            s = stats(pixels(op, v))
            tag = op + (":" + v if v else "")
            rows.append((tag, s))
            print("  %-14s %.3f | %4.0f%% | %4.0f%% | %4.0f%% | %4.0f%% | %4.0f%% | %4.0f%% | %4.0f%%" % (
                tag, s["hsl"], 100 * s["black"], 100 * s["mid1"], 100 * s["mid2"], 100 * s["bright"], 100 * s["line"],
                100 * s["lit_white"], 100 * s["lit_clip"]))
    for op in ops:
        if not os.path.exists(os.path.join(INC, "op_%s_idle@2x.png" % op)):
            continue
        s = stats(pixels(op))
        cnt = dict(s["top"])
        print("\n%s 主色（占非描边像素）：" % op)
        used = set()
        for part, cols in PARTS.get(op, {}).items():
            cs = sorted(((hx(c), cnt.get(hx(c), 0)) for c in cols), key=lambda t: -t[1])
            tot = sum(k for _, k in cs)
            used |= {c for c, _ in cs}
            ymean = sum(lum(c) * k for c, k in cs) / max(1, tot)
            print("  %-18s %4.0f%%  加权 Y=%3.0f  " % (part, 100 * tot / s["n"], ymean) +
                  " ".join("%s(Y%.0f,%.0f%%)" % (hexs(c), lum(c), 100 * k / s["n"]) for c, k in cs[:4] if k))
        rest = [(c, k) for c, k in s["top"] if c not in used]
        print("  %-18s " % ("其他前 8" if PARTS.get(op) else "按面积前 10") +
              " ".join("%s(Y%.0f,%.0f%%)" % (hexs(c), lum(c), 100 * k / s["n"]) for c, k in rest[:8 if PARTS.get(op) else 10]))
    return rows


def sheet(op, frame=0):
    img = Image.open(os.path.join(INC, "op_%s_idle@2x.png" % op)).convert("RGBA").crop((frame * 96, 0, frame * 96 + 96, 96))
    cols = [k for k, _ in Counter(p[:3] for p in img.getdata() if p[3] > 0).most_common()]
    W = 288
    per = 7
    canvas = Image.new("RGB", (W * per, (W + 20) * ((len(cols) + per) // per)), (40, 40, 40))
    d = ImageDraw.Draw(canvas)
    big = Image.new("RGB", (96, 96), (33, 58, 63))
    big.paste(img, (0, 0), img)
    canvas.paste(big.resize((W, W), Image.NEAREST), (0, 20))
    ip = img.load()
    for i, col in enumerate(cols):
        j = i + 1
        m = Image.new("RGB", (96, 96), (30, 30, 30))
        px = m.load()
        for y in range(96):
            for x in range(96):
                if ip[x, y][3] > 0:
                    px[x, y] = (255, 0, 255) if ip[x, y][:3] == col else (90, 90, 90)
        X, Y = (j % per) * W, (j // per) * (W + 20)
        canvas.paste(m.resize((W, W), Image.NEAREST), (X, Y + 20))
        d.text((X + 4, Y + 4), "%s Y=%.0f" % (hexs(col), lum(col)), fill=(255, 255, 255))
    os.makedirs(outdir(op), exist_ok=True)
    out = os.path.join(outdir(op), "sheet_%s.png" % op)
    canvas.save(out)
    print(out)


# ---------------------------------------------------------------- 实机截图

def _git_restore(op):
    subprocess.run(["git", "checkout", "--", *[os.path.join("art", "incoming", f) for f in strip_files(op)]], cwd=ROOT, check=True)


def _jobs(op, mates, tag, shotdir, teammate=True):
    """op 当主控（待机 / 跑动）+ 选人页 + 图鉴；teammate=True 时再跑一局斯卡蒂主控、op 当队友"""
    import godot_runner as gr
    base = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--resolution", "1280x720", "--audio-driver", "Dummy",
            "--fixed-fps", "60", "--"]
    sd = shotdir.replace(os.sep, "/")
    run = ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=" + op, "--squad=" + mates]
    j = {
        tag + "_idle": base + run + ["--bot=afk", "--maxt=9", "--shots=180,300,420,480", "--shotdir=" + sd + "/" + tag + "_idle"],
        tag + "_run": base + run + ["--bot=expert", "--maxt=9", "--shots=240,330,420,500", "--shotdir=" + sd + "/" + tag + "_run"],
        tag + "_select": base + ["--unlockall", "--opshot", "--opid=" + op, "--shotdir=" + sd + "/" + tag + "_select"],
        tag + "_codex": base + ["--unlockall", "--galleryshot=0,0,0,1.5", "--galleryid=" + op, "--shotdir=" + sd + "/" + tag + "_codex"],
    }
    if teammate:
        j[tag + "_mate"] = base + ["--balance", "--realtime", "--nodeath", "--seed=3", "--op=skadi", "--squad=" + op + ",wisadel",
                                   "--bot=afk", "--maxt=9", "--shots=180,300,420,480", "--shotdir=" + sd + "/" + tag + "_mate"]
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


def capture(op, names):
    import godot_runner as gr
    gr.ensure_imported(os.path.join(ROOT, "game"))   # 新工作树没有 .godot 导入缓存：字体 / 贴图为空，局内卡到超时
    shot = os.path.join(outdir(op), "shots")
    for name in names:
        jobs = {}
        if name == "ref":
            # 参照：斯卡蒂 / 维什戴尔当主控（队友里带 op，和变体局同一阵容）
            jobs.update(_jobs("skadi", op + ",wisadel", "skadi", shot, teammate=False))
            jobs.update(_jobs("wisadel", op + ",skadi", "wisadel", shot, teammate=False))
        else:
            if name != "cur":
                write_variant(op, name, INC)   # 只写本工作树的 art/incoming，跑完立即 git 还原
            jobs.update(_jobs(op, "skadi,wisadel", name, shot))
        try:
            with ThreadPoolExecutor(5) as ex:
                for n, errs, to in ex.map(lambda kv: _run(*kv), jobs.items()):
                    print(n, "超时" if to else "ok", errs[:2], flush=True)
        finally:
            if name not in ("cur", "ref"):
                _git_restore(op)


# ---------------------------------------------------------------- 拼图

def _font(sz):
    for f in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"]:
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()


# [kind, 文件, 裁剪框, 行名]；实机 160×140 放大 2 倍（主控在画面中心），近景 80×70 放大 4 倍，队友行 320×280 原尺寸
ROWS = [["idle", "shot_420.png", (605, 292, 685, 362), "实机 待机 ×4\n主控近景"],
        ["idle", "shot_420.png", (560, 250, 720, 390), "实机 待机\n主控 · 浅滩"],
        ["run", "shot_330.png", (560, 250, 720, 390), "实机 跑动\n主控 · 浅滩"],
        ["mate", "shot_420.png", (480, 220, 800, 500), "实机 当队友\n斯卡蒂主控"],
        ["mate", "shot_420.png", (528, 272, 608, 342), "当队友 ×4\n（seed 3 左上）"],
        ["select", "shot_oppick.png", (620, 245, 940, 525), "选人页"],
        ["codex", "shot_gallery_ui.png", (520, 140, 840, 420), "图鉴"]]


def compose(op, cols=None):
    shot = os.path.join(outdir(op), "shots")
    vs = VARIANTS.get(op, {"cur": {"label": "现状", "map": {}}})
    cols = cols or [[k, v["label"]] for k, v in vs.items()] + [["skadi", "参考：斯卡蒂主控"], ["wisadel", "参考：维什戴尔主控"]]
    cw, chh = 320, 280
    pad, lab, left = 6, 74, 130
    canvas = Image.new("RGB", (left + len(cols) * (cw + pad), lab + len(ROWS) * (chh + pad)), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    f, fs = _font(17), _font(12)
    for ci, (tag, label) in enumerate(cols):
        x = left + ci * (cw + pad)
        d.text((x + 4, 4), label, fill=(235, 235, 240), font=f)
        if tag in vs:
            s = stats(pixels(op, tag if tag != "cur" else None))
            d.text((x + 4, 28), "HSL %.3f · 近黑 %.0f%% · 亮部 %.0f%%" % (s["hsl"], 100 * s["black"], 100 * s["bright"]),
                   fill=(200, 200, 210), font=fs)
            mp = vs[tag]["map"]
            # 色条：每个部位的主色（变体后）
            sw = []
            for part, cs in PARTS.get(op, {}).items():
                c = hx(cs[0]) if not mp else hx(mp.get(cs[0], cs[0]))
                sw.append(c)
            for i, c in enumerate(sw):
                d.rectangle((x + 4 + i * 62, 48, x + 18 + i * 62, 62), fill=c, outline=(110, 110, 120))
                d.text((x + 21 + i * 62, 49), hexs(c)[1:], fill=(200, 200, 210), font=fs)
    for ri, (kind, src, box, label) in enumerate(ROWS):
        y = lab + ri * (chh + pad)
        for li, t in enumerate(label.split("\n")):
            d.text((8, y + chh // 2 - 20 + li * 22), t, fill=(235, 235, 240), font=f)
        for ci, (tag, _) in enumerate(cols):
            p = os.path.join(shot, tag + "_" + kind, src)
            if os.path.exists(p):
                canvas.paste(Image.open(p).convert("RGB").crop(box).resize((cw, chh), Image.NEAREST), (left + ci * (cw + pad), y))
    out = os.path.join(outdir(op), "compare.png")
    canvas.save(out)
    print(out)


def lineup(out, ops):
    """多名干员的现状同框（各自 build/<干员>_bright/shots/cur_*）：列 = 干员，行 = ROWS"""
    cw, chh = 320, 280
    pad, lab, left = 6, 52, 130
    canvas = Image.new("RGB", (left + len(ops) * (cw + pad), lab + len(ROWS) * (chh + pad)), (18, 20, 26))
    d = ImageDraw.Draw(canvas)
    f, fs = _font(17), _font(12)
    for ci, op in enumerate(ops):
        x = left + ci * (cw + pad)
        s = stats(pixels(op))
        d.text((x + 4, 4), op + " 现状", fill=(235, 235, 240), font=f)
        d.text((x + 4, 28), "HSL %.3f · 近黑 %.0f%% · 亮部 %.0f%% · 受光变亮 %.0f%%" % (
            s["hsl"], 100 * s["black"], 100 * s["bright"], 100 * s["lit_white"]), fill=(200, 200, 210), font=fs)
    for ri, (kind, src, box, label) in enumerate(ROWS):
        y = lab + ri * (chh + pad)
        for li, t in enumerate(label.split("\n")):
            d.text((8, y + chh // 2 - 20 + li * 22), t, fill=(235, 235, 240), font=f)
        for ci, op in enumerate(ops):
            pth = os.path.join(outdir(op), "shots", "cur_" + kind, src)
            if os.path.exists(pth):
                canvas.paste(Image.open(pth).convert("RGB").crop(box).resize((cw, chh), Image.NEAREST), (left + ci * (cw + pad), y))
    canvas.save(out)
    print(out)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "metrics"
    a = sys.argv[2:]
    if cmd == "metrics":
        metrics(a or NEW + REFS)
    elif cmd == "sheet":
        sheet(a[0], int(a[1]) if len(a) > 1 else 0)
    elif cmd == "recolor":
        write_variant(a[0], a[1], a[2])
    elif cmd == "capture":
        capture(a[0], a[1:] or ["cur"])
    elif cmd == "compose":
        compose(a[0])
    elif cmd == "lineup":
        lineup(a[0], a[1:])
