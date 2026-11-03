# -*- coding: utf-8 -*-
"""pixelfx 特效导出成游戏帧条（docs/228 §7）。

tools/pixelfx_fx/<类>/<名>.js 是本作写的 pixelfx 特效源码；本脚本把它们拷进 pixelfx 库检出（缺省 build/pixelfx，
不进 git），用库自带的 render.mjs --sheet 导精灵表，再：
  - 还原预乘色（库往透明画布上贴帧时 rgb 乘了 alpha、alpha 原样保留，Godot 直通 alpha 下半透明处 a² 发灰；组长 724b05688，漏项 #23），
  - 逐帧按非空包围盒紧裁、横向打包（漏项 #1；一行满 4096 px 换行，手机 WebGL 贴图上限）：每帧 [x, y, 宽, 高, 原点 x, 原点 y] 写进 game/data/px_frames.json，
    游戏按表取帧、按 pixelfx 原点放置（vfx.spr_rot / ob_fx.fx_frame / ult._draw_strip）；"keep" 条目保留原画布、等宽帧（代码里自带锚点的弹体 / 枪口），
  - 去掉末尾全空帧，
  - 量化到 ≤ 32 色（带透明，按条目 colors 改），存调色板 PNG，
  - 写进 game/art/fx/<名>[ @2x].png。
导出前查：自动图案检查（docs/242 §9.3）、必出矩阵（漏项 #31）、每人显存（全档 ≤ 48 MB、低档 ≤ 12 MB，按盘上该人全部 _ul_ 帧条合计，漏项 #1）；
任一项不过整批不写盘。最后打印 art.gd V6_FRAMES 要登记的 [帧数, fps]。改完记得跑 python tools/asset_index.py。

用法：python tools/pixelfx_export.py [--lib build/pixelfx] [--only 名字,...] [--dry]
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelfx_check as PC

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")
FRAMES_JSON = os.path.join(ROOT, "game", "data", "px_frames.json")
VRAM_FULL_MB, VRAM_LO_MB = 48.0, 12.0   # 每人显存上限（解码后 RGBA8，漏项 #1）
MAX_W = 4096   # 打包帧条一行最宽（手机 WebGL 贴图边长上限）

# 导出目标：tools/pixelfx_fx/targets_*.json（每个并行会话一份，互不改别人的文件，docs/229 §9）。
# 每条：游戏贴图名 → {"fx": 特效 id, "opts": 选项, "hires": 是否 @2x, "keep": 是否保留原画布（枪口这类原点不居中）, "colors": 色数（缺省 32）,
#        "lo": 另出网页低档 <名>_lo（15 fps 按时间就近抽帧，同画布 / 原点；只给队长版第一个种子，docs/242 §6）,
#        "layers": 分核心 / 装饰两层，出 <名> 和 <名>_deco（特效源码要认 o.layer = "core" / "deco"，docs/242 §8）,
#        "judge": 判定数据 {"op", "opts": {选项: 表达式（取 base）}, "src"}（docs/242 §9.1）, "check_sy": 地面透视压扁（0.55）,
#        "check_skip" / "check_note": 自动图案检查放行项与理由（docs/242 §9.3）,
#        "ref": 参照轮廓 tools/pixelfx_fx/ref/<人>_<招式>.png（docs/242 §9.2）,
#        "move": "basic" / "skill" / "ult"（普攻不出 deco_lo，漏项 #31；缺省 skill）,
#        "deco_step" / "deco_lo_step": 装饰层（全档 / 网页低档）隔 N 帧取一帧、帧率除以 N（省显存；核心层不受影响）}
# 名字：<base>[_e0|_e1|_e2][变体 2…][_tm]；必出矩阵见 matrix_check
def load_targets():
    t = {}
    for f in sorted(os.listdir(SRC)):
        if f.startswith("targets") and f.endswith(".json"):
            for name, spec in json.load(open(os.path.join(SRC, f), encoding="utf-8")).items():
                if name.startswith("_"):
                    continue
                if name in t:
                    sys.exit("导出目标重名：%s（%s）" % (name, f))
                t[name] = spec
    return t


def install(lib):
    shutil.copy2(os.path.join(SRC, "house.js"), os.path.join(lib, "src", "fx", "house.js"))   # 公共规范模块：特效里 import "../house.js"
    for cat in os.listdir(SRC):
        if not os.path.isdir(os.path.join(SRC, cat)):
            continue
        for f in os.listdir(os.path.join(SRC, cat)):
            if f.endswith(".js"):
                shutil.copy2(os.path.join(SRC, cat, f), os.path.join(lib, "src", "fx", cat, f))


def render(lib, fx_id, opts, out):
    """用库的 render.mjs --sheet 渲一遍，返回 (逐帧 RGBA 列表, pixelfx 元数据)"""
    r = subprocess.run(["node", "tools/render.mjs", fx_id, "--sheet", "--opts", json.dumps(opts), "--out", out],
                       cwd=lib, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    base = fx_id.split("/")[1]
    meta = json.load(open(os.path.join(out, fx_id, base + ".json")))
    sheet = unpremultiply(Image.open(os.path.join(out, fx_id, base + ".png")).convert("RGBA"))
    frames = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + f["frame"]["w"], f["frame"]["y"] + f["frame"]["h"])) for f in meta["frames"]]
    return frames, meta["meta"]["pixelfx"]


def unpremultiply(im):
    """a > 0 时 rgb = min(255, rgb * 255 / a)（组长 724b05688 的 unpremultiply）"""
    a = np.asarray(im, dtype=np.float32).copy()
    al = a[..., 3:4]
    a[..., :3] = np.where(al > 0, np.minimum(255.0, a[..., :3] * 255.0 / np.maximum(al, 1.0) + 0.5), 0.0)
    a[..., 3:4] = np.where(al > 10, al, 0.0)   # alpha ≤ 10 清零：紧裁按 alpha > 10 取包围盒，反预乘后这些像素变亮，留着会在裁边处露出一条硬边（11-03）
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def _alpha(im):
    return im.getchannel("A").point(lambda a: 255 if a > 10 else 0)


def build_strip(frames, box, pivot):
    """box = None：逐帧紧裁、按高度分层打包（行宽 ≤ MAX_W），返回 (图, 帧表 [[x, y, w, h, ax, ay]…])；否则按 box 等宽切（keep），帧表 None"""
    if box is not None:
        w, h = box[2] - box[0], box[3] - box[1]
        strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            strip.paste(f.crop(box), (i * w, 0))
        return strip, None
    bbs = [_alpha(f).getbbox() for f in frames]
    sz = [(b[2] - b[0], b[3] - b[1]) if b else (0, 0) for b in bbs]
    order = sorted(range(len(sz)), key=lambda i: -sz[i][1])   # 分层打包：按高度从高到低，每行高度 = 这行第一帧的高（省掉等高行的空白）

    def shelf(lim):
        pos, x, y, rh, W = {}, 0, 0, 0, 1
        for i in order:
            w, h = sz[i]
            if x + w > lim and x > 0:
                x, y, rh = 0, y + rh, 0
            pos[i] = (x, y)
            x += w
            rh = max(rh, h)
            W = max(W, x)
        return W * max(1, y + rh), W, max(1, y + rh), pos
    mw = max([w for w, _ in sz] or [1])
    best = min((shelf(lim) for lim in range(max(1, mw), MAX_W + 1, 32)), key=lambda r: r[0])   # 行宽在 [最宽一帧, 4096] 里挑面积最小的
    _, W, H, pos = best
    strip = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    tab = []
    for i, (f, b) in enumerate(zip(frames, bbs)):
        x, y = pos[i]
        if not b:
            tab.append([x, y, 0, 0, 0, 0])
            continue
        strip.paste(f.crop(b), (x, y))
        tab.append([x, y, b[2] - b[0], b[3] - b[1], pivot[0] - b[0], pivot[1] - b[1]])
    return strip, tab


def save_strip(strip, path, colors, dry):
    if not dry:
        strip.quantize(colors=colors, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)   # 调色板 PNG（比 RGBA 小约 2.5 倍）
    return os.path.getsize(path) if not dry else 0


def person(name):
    m = re.match(r"^(?:fx|proj)_([a-z0-9]+)_ul_", name)
    return m.group(1) if m else ""


def vram_mb(w, h):
    return w * h * 4 / 2 ** 20


def matrix_check(name, spec, targets):
    """必出矩阵（漏项 #31）：全档 E2（或不带档位）出 core + deco + 变体 2 + _tm；E1 / E0 只出 core + deco 的单种子，不出 _tm、变体、低档；
    网页低档只给 E2 的队长单种子（不出 _tm / 变体的 _lo），普攻不出 deco_lo。返回违规说明，空 = 合格"""
    m = re.search(r"_e([012])(?=\d?(_tm)?$)", name)
    el = int(m.group(1)) if m else 2
    tm = name.endswith("_tm")
    core = name[:-3] if tm else name
    var = bool(re.search(r"[2-9]$", core)) and core[:-1] in targets   # 变体 = 末位数字 ≥ 2 且去掉它的名字也是导出目标（_s2 这类技能号不算）
    bad = []
    if el < 2 and (tm or var):
        bad.append("E%d 只出单种子核心 + 装饰，不出 _tm / 变体（队友用本档队长版）" % el)
    if spec.get("lo") and (el < 2 or tm or var):
        bad.append("网页低档只给 E2 队长单种子")
    if spec.get("move", "skill") not in ("basic", "skill", "ult"):
        bad.append("move 只能是 basic / skill / ult")
    return bad


def judge_opts(spec):
    """判定数据（docs/242 §9.1）：{"judge": {"op": 干员 id, "opts": {选项: 表达式}, "src": 出处说明}}，表达式里的名字取干员 JSON 的 base，
    例 {"span": "2*half"}。gd 里写死的常量没法读的，直接写数字并在 src 里注明文件和行号"""
    j = spec.get("judge")
    if not j:
        return {}
    base = json.load(open(os.path.join(ROOT, "game", "data", "characters", j["op"] + ".json"), encoding="utf-8"))["base"]
    out = {}
    for k, ex in j.get("opts", {}).items():
        if isinstance(ex, (int, float)):
            out[k] = ex
            continue
        expr = re.sub(r"[A-Za-z_][A-Za-z0-9_]*", lambda m: repr(float(base[m.group(0)])) if m.group(0) in base else m.group(0), ex)
        out[k] = float(eval(expr, {"__builtins__": {}}, {"pi": 3.141592653589793}))
    return out


def export(lib, name, spec, tmp, dry):
    fx_id, opts, hires, keep = spec["fx"], dict(spec.get("opts", {}), **judge_opts(spec)), spec.get("hires", False), spec.get("keep", False)
    if spec.get("ref"):   # 参照轮廓（docs/242 §9.2）：1 位黑白 PNG（黑 = 内部）+ 同名 .json {"origin": [x, y]}，读成 o.ref 给源码的 refMask()
        rp = os.path.join(ROOT, spec["ref"])
        im = Image.open(rp).convert("L")
        org = json.load(open(os.path.splitext(rp)[0] + ".json", encoding="utf-8"))["origin"]
        rows = ["".join("#" if im.getpixel((x, y)) < 128 else "." for x in range(im.width)) for y in range(im.height)]
        opts["ref"] = {"w": im.width, "h": im.height, "ox": org[0], "oy": org[1], "rows": rows}
    colors = int(spec.get("colors", 32))
    # 分层（docs/242 §8）：同一特效按 layer = core / deco 各渲一遍（同种子、同模拟，只是画的图元不同），两层共用裁边框和帧数，逐帧对齐
    layers = [("", dict(opts, layer="core")), ("_deco", dict(opts, layer="deco"))] if spec.get("layers") else [("", opts)]
    sets = []
    for suf, o in layers:
        fr, px = render(lib, fx_id, o, os.path.join(tmp, name + suf))
        sets.append((suf, fr))
    alpha = lambda im: im.getchannel("A").point(lambda a: 255 if a > 10 else 0)
    n = max(len(fr) for _, fr in sets)
    while n > 1 and all(alpha(fr[n - 1]).getbbox() is None for _, fr in sets):   # 末尾全空帧（两层都空才去）
        n -= 1
    sets = [(suf, fr[:n]) for suf, fr in sets]
    fw, fh = px["frameSize"]
    piv = tuple(px["pivot"])
    box = (0, 0, fw, fh) if keep else None
    hx = "@2x" if hires else ""
    # 自动图案检查（docs/242 §9.3）：放射 / 同心圈 / 等距并排 / 持续白，任一层超标就不产出；误报用 check_skip + check_note 放行。按原画布、原点查
    bad = []
    for suf, fr in sets:
        for key, b, note in PC.check_frames(fr, piv, float(spec.get("check_sy", 1.0)), tuple(spec.get("check_skip", ()))):
            if b:
                bad.append("%s%s %s：%s" % (name, suf, key, note))
    if bad:
        print("!! 图案检查超标，不产出：" + "；".join(bad))
        return None
    if spec.get("check_skip"):
        print("   （放行 %s：%s）" % (",".join(spec["check_skip"]), spec.get("check_note", "未写理由")))
    outs = []   # (贴图名, 图, 帧表, 帧数, fps)
    for suf, fr in sets:
        ds = int(spec.get("deco_step", 1)) if suf == "_deco" else 1   # deco_step：装饰层隔帧（帧率减半，柔光 / 颗粒看不出），省显存；核心层不抽
        frs = fr[::ds]
        st, tab = build_strip(frs, box, piv)
        outs.append((name + suf, st, tab, len(frs), float(px["fps"]) / ds))
        if spec.get("lo") and not (suf == "_deco" and spec.get("move", "skill") == "basic"):   # 网页低档（docs/242 §6）：15 fps 按时间就近抽帧，余韵时长不变；普攻不出 deco_lo（#31）
            fps0 = float(px["fps"])
            lfps = 15.0 / (int(spec.get("deco_lo_step", 1)) if suf == "_deco" else 1)   # deco_lo_step：网页低档装饰层再降帧率
            m = max(1, round(n * lfps / fps0))
            lo = [fr[min(n - 1, round(i * fps0 / lfps))] for i in range(m)]
            st, tab = build_strip(lo, box, piv)
            outs.append((name + suf + "_lo", st, tab, m, lfps))
    return [(nm, st, tab, k, fps, hx, colors) for nm, st, tab, k, fps in outs]


def disk_vram():
    """盘上每个 _ul_ 帧条的显存（MB），按贴图名（不带 @2x）"""
    out = {}
    for p in glob.glob(os.path.join(OUT, "*_ul_*.png")):
        nm = os.path.basename(p)[:-4].replace("@2x", "")
        with Image.open(p) as im:
            out[nm] = vram_mb(*im.size)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", default=os.path.join(ROOT, "build", "pixelfx"))
    ap.add_argument("--only", default="")
    ap.add_argument("--dry", action="store_true")
    a = ap.parse_args()
    if not os.path.exists(os.path.join(a.lib, "tools", "render.mjs")):
        sys.exit("找不到 pixelfx 库：先 git clone https://github.com/patch-gg/pixelfx " + a.lib)
    install(a.lib)
    only = set(filter(None, a.only.split(",")))
    targets = load_targets()
    bad = []
    for name, spec in targets.items():
        if not only or name in only:
            bad += ["%s：%s" % (name, x) for x in matrix_check(name, spec, targets)]
    if bad:
        sys.exit("!! 超出必出矩阵，整批不写盘：\n  " + "\n  ".join(bad))
    pend = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, spec in targets.items():
            if not only or name in only:
                r = export(a.lib, name, spec, tmp, a.dry)
                if r is None:
                    sys.exit("!! 图案检查没过，整批不写盘")
                pend += r
    # 每人显存（漏项 #1）：盘上其余帧条 + 这批新帧条，全档 / 低档分开合计
    tot = {}
    new = {nm: vram_mb(*st.size) for nm, st, *_ in pend}
    done = {nm for nm in targets if not only or nm in only}
    disk = disk_vram()
    stale = [nm for nm in disk if nm not in new and any(nm == t + sf for t in done for sf in ("", "_deco", "_lo", "_deco_lo"))]   # 这批目标不再出的旧图（例：普攻的 deco_lo）：删掉
    for nm, mb in [kv for kv in disk.items() if kv[0] not in new and kv[0] not in stale] + list(new.items()):   # 这批要覆盖的旧图不算
        k = (person(nm), nm.endswith("_lo"))
        tot[k] = tot.get(k, 0.0) + mb
    over = []
    for (who, lo), mb in sorted(tot.items()):
        cap = VRAM_LO_MB if lo else VRAM_FULL_MB
        print("显存 %-10s %s %6.1f MB / %.0f" % (who, "低档" if lo else "全档", mb, cap))
        if who and mb > cap:
            over.append("%s %s %.1f MB > %.0f" % (who, "低档" if lo else "全档", mb, cap))
    if over:
        for nm, mb in sorted(new.items(), key=lambda kv: -kv[1]):   # 这批各条帧条的显存，方便挑着削
            print("   %-40s %6.2f MB" % (nm, mb))
        sys.exit("!! 显存超标，整批不写盘：" + "；".join(over))
    ft = json.load(open(FRAMES_JSON, encoding="utf-8")) if os.path.exists(FRAMES_JSON) else {}
    for nm in stale:
        print("删掉不再出的旧图 %s（记得从 art.gd V6_FRAMES 删掉这一行）" % nm)
        ft.pop(nm, None)
        if not a.dry:
            for p in glob.glob(os.path.join(OUT, nm + ".png*")) + glob.glob(os.path.join(OUT, nm + "@2x.png*")):
                os.remove(p)
    for nm, st, tab, k, fps, hx, colors in pend:
        size = save_strip(st, os.path.join(OUT, nm + hx + ".png"), colors, a.dry)
        if tab is None:
            ft.pop(nm, None)
        else:
            ft[nm] = tab
        print('"%s": [%d, %.1f],   # %dx%d，%.1f KB，显存 %.2f MB%s' % (nm, k, fps, st.size[0], st.size[1], size / 1024, vram_mb(*st.size), "" if tab is None else "（打包）"))
    art = open(os.path.join(ROOT, "game", "scripts", "art.gd"), encoding="utf-8").read()
    miss = []
    for nm, st, tab, k, *_ in pend:   # 没登记 V6_FRAMES 的帧条游戏不加载（px_ul_tex 当缺图），装饰层会整层不画（11-03 斯卡蒂 v2 踩过）
        m = re.search(r'"%s": \[(\d+),' % re.escape(nm), art)
        if not m or int(m.group(1)) != k:
            miss.append("%s（应为 %d 帧%s）" % (nm, k, "，现登记 " + m.group(1) if m else "，没登记"))
    if miss:
        print("!! art.gd V6_FRAMES 要改：" + "；".join(miss))
    if not a.dry:
        with open(FRAMES_JSON, "w", encoding="utf-8", newline="\n") as f:
            f.write("{\n" + ",\n".join('\t"%s": %s' % (k, json.dumps(ft[k], separators=(",", ":"))) for k in sorted(ft)) + "\n}\n")


if __name__ == "__main__":
    main()
