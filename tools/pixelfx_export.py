# -*- coding: utf-8 -*-
"""pixelfx 特效导出成游戏帧条（docs/228 §7）。

tools/pixelfx_fx/<类>/<名>.js 是本作写的 pixelfx 特效源码；本脚本把它们拷进 pixelfx 库检出（缺省 build/pixelfx，
不进 git），用库自带的 render.mjs --sheet 导精灵表，再：
  - 以原点为中心对称裁边（游戏按帧中心放置；枪口这类非居中的用 keep_canvas 保留原画布），
  - 去掉末尾全空帧，
  - 量化到 ≤ 32 色（带透明，按条目 colors 改），存调色板 PNG，
  - 拼成单行横向帧条写进 game/art/fx/<名>[ @2x].png。
最后打印 art.gd V6_FRAMES 要登记的 [帧数, fps]。改完记得跑 python tools/asset_index.py。

用法：python tools/pixelfx_export.py [--lib build/pixelfx] [--only 名字,...] [--dry]
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile
from PIL import Image
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pixelfx_check as PC

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")

# 导出目标：tools/pixelfx_fx/targets_*.json（每个并行会话一份，互不改别人的文件，docs/229 §9）。
# 每条：游戏贴图名 → {"fx": 特效 id, "opts": 选项, "hires": 是否 @2x, "keep": 是否保留原画布（枪口这类原点不居中）, "colors": 色数（缺省 32）,
#        "lo": 另出网页低档 <名>_lo（15 fps 按时间就近抽帧，同画布 / 原点；只给队长版第一个种子，docs/242 §6）,
#        "layers": 分核心 / 装饰两层，出 <名> 和 <名>_deco（特效源码要认 o.layer = "core" / "deco"，docs/242 §8）,
#        "judge": 判定数据 {"op", "opts": {选项: 表达式（取 base）}, "src"}（docs/242 §9.1）, "check_sy": 地面透视压扁（0.55）,
#        "check_skip" / "check_note": 自动图案检查放行项与理由（docs/242 §9.3）,
#        "ref": 参照轮廓 tools/pixelfx_fx/ref/<人>_<招式>.png（docs/242 §9.2）}
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
    sheet = Image.open(os.path.join(out, fx_id, base + ".png")).convert("RGBA")
    frames = [sheet.crop((f["frame"]["x"], f["frame"]["y"], f["frame"]["x"] + f["frame"]["w"], f["frame"]["y"] + f["frame"]["h"])) for f in meta["frames"]]
    return frames, meta["meta"]["pixelfx"]


def save_strip(frames, box, path, colors, dry):
    w, h = box[2] - box[0], box[3] - box[1]
    strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f.crop(box), (i * w, 0))
    if not dry:
        strip.quantize(colors=colors, method=Image.Quantize.FASTOCTREE).save(path, optimize=True)   # 调色板 PNG（比 RGBA 小约 2.5 倍）
    return os.path.getsize(path) if not dry else 0


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
    if keep:
        box = (0, 0, fw, fh)
    else:
        ox, oy = px["pivot"]
        x0, y0, x1, y1 = fw, fh, 0, 0
        for _, fr in sets:
            for f in fr:
                bb = alpha(f).getbbox()
                if bb:
                    x0, y0, x1, y1 = min(x0, bb[0]), min(y0, bb[1]), max(x1, bb[2]), max(y1, bb[3])
        hw, hh = max(ox - x0, x1 - ox), max(oy - y0, y1 - oy)   # 以原点为中心对称
        box = (ox - hw, oy - hh, ox + hw, oy + hh)
    w, h = box[2] - box[0], box[3] - box[1]
    hx = "@2x" if hires else ""
    # 自动图案检查（docs/242 §9.3）：放射 / 同心圈 / 等距并排 / 持续白，任一层超标就不产出；误报用 check_skip + check_note 放行
    org = (px["pivot"][0] - box[0], px["pivot"][1] - box[1])
    bad = []
    for suf, fr in sets:
        for key, b, note in PC.check_frames([f.crop(box) for f in fr], org, float(spec.get("check_sy", 1.0)), tuple(spec.get("check_skip", ()))):
            if b:
                bad.append("%s%s %s：%s" % (name, suf, key, note))
    if bad:
        print("!! 图案检查超标，不产出：" + "；".join(bad))
        return
    if spec.get("check_skip"):
        print("   （放行 %s：%s）" % (",".join(spec["check_skip"]), spec.get("check_note", "未写理由")))
    for suf, fr in sets:
        size = save_strip(fr, box, os.path.join(OUT, name + suf + hx + ".png"), colors, dry)
        print('"%s%s": [%d, %.1f],   # %dx%d × %d 帧，%.1f KB，显存 %.0f KB' % (name, suf, n, px["fps"], w, h, n, size / 1024, w * n * h * 4 / 1024))
        if spec.get("lo"):   # 网页低档（docs/242 §6）：同画布 / 原点，按 15 fps 按时间就近抽帧，余韵时长不变；deco 同样出 _lo
            fps0 = float(px["fps"])
            m = max(1, round(n * 15.0 / fps0))
            lo = [fr[min(n - 1, round(i * fps0 / 15.0))] for i in range(m)]
            ls = save_strip(lo, box, os.path.join(OUT, name + suf + "_lo" + hx + ".png"), colors, dry)
            print('"%s%s_lo": [%d, 15.0],   # 网页低档 %.1f KB' % (name, suf, m, ls / 1024))


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
    with tempfile.TemporaryDirectory() as tmp:
        for name, spec in load_targets().items():
            if not only or name in only:
                export(a.lib, name, spec, tmp, a.dry)


if __name__ == "__main__":
    main()
