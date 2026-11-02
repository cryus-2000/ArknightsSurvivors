# -*- coding: utf-8 -*-
"""pixelfx 特效导出成游戏帧条（docs/228 §7）。

tools/pixelfx_fx/<类>/<名>.js 是本作写的 pixelfx 特效源码；本脚本把它们拷进 pixelfx 库检出（缺省 build/pixelfx，
不进 git），用本作的 tools/pixelfx_fx/ak_layers.mjs 分层导出 color / light 两张帧条（docs/229 §2.7），再：
  - 以原点为中心对称裁边（游戏按帧中心放置；枪口这类非居中的用 keep_canvas 保留原画布），
  - light 层单独存成 <名>_glow 帧条（黑底，游戏里在加色层 fx_add 按同一变换叠画，vfx.glow）；光晕弱到看不出就不出，
    （以前用 render.mjs --sheet 的合成图：光晕烤进颜色再量化会被吃掉，且库存的是预乘色，见 docs/238）
  - 去掉末尾全空帧，
  - 量化到 ≤ 32 色（带透明，按条目 colors 改），存调色板 PNG，
  - 拼成单行横向帧条写进 game/art/fx/<名>[ @2x].png。
最后打印 art.gd V6_FRAMES 要登记的 [帧数, fps]（有光晕的多一行 <名>_glow，两行都要登记）。改完记得跑 python tools/asset_index.py。

用法：python tools/pixelfx_export.py [--lib build/pixelfx] [--only 名字,...] [--dry]
"""
import argparse, json, os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageChops

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SRC = os.path.join(ROOT, "tools", "pixelfx_fx")
OUT = os.path.join(ROOT, "game", "art", "fx")

# 导出目标：tools/pixelfx_fx/targets_*.json（每个并行会话一份，互不改别人的文件，docs/229 §9）。
# 每条：游戏贴图名 → {"fx": 特效 id, "opts": 选项, "hires": 是否 @2x, "keep": 是否保留原画布（枪口这类原点不居中）, "colors": 色数（缺省 32）,
#   "variants": 种子变体数（缺省 3，普攻 2）, "seed": 首个种子（缺省 1）, "spark": [颗数, 色阶下标 0–6, 速度]（开播时实时喷火星，可省）}
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
    shutil.copy2(os.path.join(SRC, "ak_layers.mjs"), os.path.join(lib, "tools", "ak_layers.mjs"))   # 分层导出（color / light 两张）
    for cat in os.listdir(SRC):
        if not os.path.isdir(os.path.join(SRC, cat)):
            continue
        for f in os.listdir(os.path.join(SRC, cat)):
            if f.endswith(".js"):
                shutil.copy2(os.path.join(SRC, cat, f), os.path.join(lib, "src", "fx", cat, f))


GLOW_K = 0.5        # 光晕强度缺省（docs/229 §2.7，house.js GLOW.k）；目标的 opts 里写了 light 就按目标
GLOW_MIN = 8        # light 层最亮通道低于这个就不出 _glow 条


VARIANTS = 3       # 每条缺省出几个种子变体（docs/229 §2.11）；普攻目标写 "variants": 2


def export(lib, name, spec, tmp, dry):
    """一个目标出 variants 个种子变体：<名>、<名>_v1、<名>_v2（种子 = seed + 序号）；spark: [颗数, 色阶下标, 速度] 写进 <名> 的登记第 3 项"""
    seed0 = int(spec.get("seed", spec.get("opts", {}).get("seed", 1)))   # opts 里的 seed 会盖掉 --seed，挪出来当首个种子
    for v in range(max(1, int(spec.get("variants", VARIANTS)))):
        export_one(lib, name if v == 0 else "%s_v%d" % (name, v), spec, tmp, dry, seed0 + v, spec.get("spark") if v == 0 else None)


def export_one(lib, name, spec, tmp, dry, seed, spark):
    fx_id, hires, keep = spec["fx"], spec.get("hires", False), spec.get("keep", False)
    opts = dict(spec.get("opts", {}))
    opts.pop("seed", None)
    opts.setdefault("light", GLOW_K)
    out = os.path.join(tmp, name)
    cmd = ["node", "tools/ak_layers.mjs", fx_id, "--opts", json.dumps(opts), "--out", out, "--seed", str(seed)]
    if spec.get("fps"):
        cmd += ["--fps", str(spec["fps"])]
    r = subprocess.run(cmd, cwd=lib, capture_output=True, text=True)
    if r.returncode:
        sys.exit(r.stderr)
    px = json.load(open(os.path.join(out, "meta.json")))
    n = px["frames"]
    fw, fh = px["frameSize"]
    col = Image.open(os.path.join(out, "color.png")).convert("RGBA")
    lit = Image.open(os.path.join(out, "light.png")).convert("RGB")
    cf = [col.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)]
    lf = [lit.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(n)]
    glow = px.get("lightPeak", 0) >= GLOW_MIN
    # 可见 = color 的 alpha > 10，或 light 任一通道 > GLOW_MIN（光晕比本体大一圈，裁边要把它算进去）
    vis = lambda i: ImageChops.lighter(cf[i].getchannel("A").point(lambda a: 255 if a > 10 else 0),
                                       lf[i].convert("L").point(lambda v: 255 if v > GLOW_MIN else 0) if glow else Image.new("L", (fw, fh)))
    while n and vis(n - 1).getbbox() is None:
        n -= 1
    if keep:
        box = (0, 0, fw, fh)
    else:
        ox, oy = px["pivot"]
        x0, y0, x1, y1 = fw, fh, 0, 0
        for i in range(n):
            b = vis(i).getbbox()
            if b:
                x0, y0, x1, y1 = min(x0, b[0]), min(y0, b[1]), max(x1, b[2]), max(y1, b[3])
        hw, hh = max(ox - x0, x1 - ox), max(oy - y0, y1 - oy)   # 以原点为中心对称
        box = (ox - hw, oy - hh, ox + hw, oy + hh)
    w, h = box[2] - box[0], box[3] - box[1]
    suffix = "@2x" if hires else ""
    lines = []
    for layer, frames, mode in (("", cf, "RGBA"), ("_glow", lf, "RGB")):
        if layer and not glow:
            continue
        strip = Image.new(mode, (w * n, h), (0, 0, 0, 0) if mode == "RGBA" else (0, 0, 0))
        for i in range(n):
            strip.paste(frames[i].crop(box), (i * w, 0))
        # color：32 色调色板 PNG（带透明）；glow：黑底单色相渐变，同样 32 色调色板、不带透明（加色叠画，黑 = 不加）
        q = strip.quantize(colors=int(spec.get("colors", 32)), method=Image.Quantize.FASTOCTREE)
        path = os.path.join(OUT, name + layer + suffix + ".png")
        if not dry:
            q.save(path, optimize=True)
        size = os.path.getsize(path) if not dry else 0
        extra = (", [%d, %d, %.1f]" % (int(spark[0]), int(spark[1]), float(spark[2]))) if spark and not layer else ""
        lines.append('"%s%s": [%d, %.1f%s],   # %dx%d × %d 帧，%.1f KB，显存 %.0f KB' % (name, layer, n, px["fps"], extra, w, h, n, size / 1024, w * n * h * 4 / 1024))
    for ln in lines:
        print(ln)


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
