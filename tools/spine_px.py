# -*- coding: utf-8 -*-
"""新干员 B 方案像素帧条（11-18 用户批准：PRTS Spine 渲染 → 像素化 → 修 → 直接进包；docs/365）。

复用 tools/spine_run_trial（逐附件 4 倍渲染 → 4×4 BOX → 二值透明 → 映射调色板 → 按层序合成），本脚本只管：
  1. 调色板：没有 Codex 部件包（bz_18）的新干员，按 bz_18 build_operator.py 同一算法从本人原生附件取：96 色中位切分 + 眼 / 嘴附件各 8 色本地色
     （cfg.palette_protect = false 时不补，改用 cfg.keep_colors 手选设定色）
  2. 按动作清单（cfg/<id>_px.json）逐个动作写临时 cfg、调 run_trial.js 出逐帧
  3. 自动清理：小于等于 2 像素的不透明碎块删掉；单点杂色（八邻无同色、八邻 ≥ 6 个同一色）并入周围色
  4. 人工修补层：cfg.fix.eyes 给手画的眼睛小图（字符矩阵），按逐帧眼骨位置贴回；cfg.fix.patches 给逐帧逐像素补丁
     （art/src/<id>_fix/<动作>.json：{"f03": [[x, y, "#rrggbb" | null], …]}，null = 擦成透明）
  5. 拼帧条（画布 cfg.canvas，缺省 192，原点 (96,152)，= 1x foot [48,76]）到 build/spine_px/<id>/strips/，--apply 再复制到 game/art/operators/<id>/
  6. 审阅图：每个动作 8 倍逐帧 + GIF；--review 出全部动作拼图

    python tools/spine_px.py ling                 # 全部动作
    python tools/spine_px.py ling --only idle attack
    python tools/spine_px.py ling --apply         # 帧条写进 game/art/operators/ling/（不改角色数据、不被游戏引用）

依赖：build/prts_ref/_raw/<id>/（tools/prts_spine.py 拉）、build/prts_ref/_node（spine-ts 与 @napi-rs/canvas）。
"""
import argparse, json, os, shutil, subprocess, sys
from collections import Counter
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
COMMON = _GR.common_root()
TRIAL = os.path.join(ROOT, "tools", "spine_run_trial")
NODE_PATH = os.path.join(COMMON, "build", "prts_ref", "_node", "node_modules")
BG = (48, 61, 77, 255)
N8 = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


# ---------- 1. 调色板 ----------
def atlas_regions(atlas):
    """.atlas（libgdx 文本格式）→ [(名, 页图, (x, y, w, h))]；rotate 的区域宽高互换"""
    out, page, cur = [], None, None
    lines = open(atlas, encoding="utf-8").read().splitlines()
    for ln in lines:
        t = ln.strip()
        if not t:
            page = None
            continue
        if page is None and t.endswith(".png"):
            page = t
            continue
        if ":" not in t:
            cur = {"name": t}
            out.append(cur)
            cur["page"] = page
            continue
        k, v = [x.strip() for x in t.split(":", 1)]
        if cur is not None and k in ("xy", "size", "rotate"):
            cur[k] = v
    res = []
    for r in out:
        if "xy" not in r or "size" not in r:
            continue
        x, y = map(int, r["xy"].split(","))
        w, h = map(int, r["size"].split(","))
        if r.get("rotate") in ("true", "90"):
            w, h = h, w
        res.append((r["name"], r["page"], (x, y, w, h)))
    return res


def make_palette(atlas, n, out, protect=True, alpha=96):
    """同 Codex bz_18 部件包（build_operator.py）口径：全部原生附件颜色（alpha ≥ 96）中位切分 n 色，
    再给名字含 eye / mouth / iris / pupil 的附件（前 20 个）各补 8 色本地色，防止五官被并进大色块"""
    import re
    d = os.path.dirname(atlas)
    pages, rgb, protected = {}, [], []
    for name, page, (x, y, w, h) in atlas_regions(atlas):
        if page not in pages:
            pages[page] = Image.open(os.path.join(d, page)).convert("RGBA")
        reg = pages[page].crop((x, y, x + w, y + h))
        data = list(reg.get_flattened_data() if hasattr(reg, "get_flattened_data") else reg.getdata())
        rgb += [p[:3] for p in data if p[3] >= alpha]
        if protect and re.search(r"eye|mouth|iris|pupil", name, re.I) and len(protected) < 20:
            protected.append([p[:3] for p in data if p[3] > 128])
    src = Image.new("RGB", (len(rgb), 1))
    src.putdata(rgb)
    pal = src.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).getpalette()[:n * 3]
    cols = [tuple(pal[i * 3:i * 3 + 3]) for i in range(n)]
    for col in protected:
        if not col:
            continue
        im = Image.new("RGB", (len(col), 1))
        im.putdata(col)
        lp = im.quantize(colors=8, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).getpalette()[:24]
        cols += [tuple(lp[i * 3:i * 3 + 3]) for i in range(len(lp) // 3)]
    cols = list(dict.fromkeys(cols))
    o = Image.new("RGBA", (len(cols), 1))
    o.putdata([c + (255,) for c in cols])
    o.save(out)
    return out


def extra_colors(pal_png, colors):
    """设定色（瞳色等）补进调色板：量化时容易被并进头发 / 衣服（docs/87 §4.3 瞳色单独保留）"""
    im = Image.open(pal_png).convert("RGBA")
    cur = [im.getpixel((i, 0)) for i in range(im.width)]
    add = [hexrgb(c) + (255,) for c in colors if hexrgb(c) + (255,) not in cur]
    o = Image.new("RGBA", (len(cur) + len(add), 1))
    o.putdata(cur + add)
    o.save(pal_png)


# ---------- 2. 渲染 ----------
def run_trial(cfg_path, out):
    env = dict(os.environ, NODE_PATH=NODE_PATH)
    r = subprocess.run(["node", os.path.join(TRIAL, "run_trial.js"), cfg_path, "--clean", "--out", out], capture_output=True, text=True, encoding="utf-8", env=env, cwd=ROOT)
    if r.returncode != 0:
        raise SystemExit(r.stdout[-2000:] + r.stderr[-2000:])
    return json.load(open(os.path.join(out, "report.json"), encoding="utf-8"))


def times_of(act):
    s = act["sample"]
    if "times" in s:
        return s["times"]
    t0, t1, n = s["range"]
    incl = s.get("inclusive", False)
    return [round(t0 + (t1 - t0) * k / (n - 1 if incl else n), 4) for k in range(n)]


def durations_of(act, times):
    if act.get("durations"):
        return act["durations"]
    s = act.get("sample")
    if not s:
        return [1.0 / act.get("fps", 13.333)] * 8
    end = s.get("end", s["range"][1] if "range" in s else times[-1] + (times[-1] - times[-2]))
    d = [round(times[k + 1] - times[k], 4) for k in range(len(times) - 1)] + [round(max(end - times[-1], 0.04), 4)]
    return d


# ---------- 3. 自动清理 ----------
def clean(im, keep_boxes=()):
    im = im.copy()
    W, H = im.size
    p = im.load()
    stats = {"specks": 0, "lone": 0}
    seen = set()
    for y in range(H):
        for x in range(W):
            if p[x, y][3] == 0 or (x, y) in seen:
                continue
            comp, st = [], [(x, y)]
            seen.add((x, y))
            while st:
                cx, cy = st.pop()
                comp.append((cx, cy))
                for dx, dy in N8:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < W and 0 <= ny < H and (nx, ny) not in seen and p[nx, ny][3]:
                        seen.add((nx, ny))
                        st.append((nx, ny))
            if len(comp) <= 2:
                for q in comp:
                    p[q] = (0, 0, 0, 0)
                stats["specks"] += len(comp)

    def kept(x, y):
        return any(b[0] <= x < b[2] and b[1] <= y < b[3] for b in keep_boxes)

    for _ in range(2):
        changes = []
        for y in range(1, H - 1):
            for x in range(1, W - 1):
                c = p[x, y]
                if c[3] == 0 or kept(x, y):
                    continue
                nb = [p[x + dx, y + dy] for dx, dy in N8]
                if any(n == c for n in nb):
                    continue
                cnt = Counter(n for n in nb if n[3])
                if cnt:
                    col, k = cnt.most_common(1)[0]
                    if k >= 6:
                        changes.append((x, y, col))
        for x, y, col in changes:
            p[x, y] = col
        stats["lone"] += len(changes)
    return im, stats


def outline(im, color, mix, pal):
    """外圈压暗：与透明四邻接的像素向 color 混 mix，再就近映射回调色板（现有 20 人边缘都是本色的暗档，令的原作描边被 4×4 BOX 冲淡）。
    一像素宽的细件（左右或上下两侧都透明，如枝杈、发丝、提灯链）不压，否则整根变黑。"""
    im = im.copy()
    W, H = im.size
    p = im.load()
    tr = lambda x, y: not (0 <= x < W and 0 <= y < H) or p[x, y][3] == 0
    ch = []
    for y in range(H):
        for x in range(W):
            c = p[x, y]
            if c[3] == 0 or not any(tr(x + dx, y + dy) for dx, dy in N8[:4]):
                continue
            if (tr(x - 1, y) and tr(x + 1, y)) or (tr(x, y - 1) and tr(x, y + 1)):
                continue
            t = tuple(round(c[i] * (1 - mix) + color[i] * mix) for i in range(3))
            best = min(pal, key=lambda q: (q[0] - t[0]) ** 2 + (q[1] - t[1]) ** 2 + (q[2] - t[2]) ** 2)
            ch.append((x, y, best + (255,)))
    for x, y, c in ch:
        p[x, y] = c
    return im, len(ch)


# ---------- 4. 人工修补 ----------
def stamp(im, pattern, colors, at, anchor):
    """pattern：字符矩阵；colors：字符 → #hex（'.' 不动，'_' 擦透明）；at：骨骼像素位置；anchor：图案里对准骨骼点的 (列, 行)"""
    p = im.load()
    ox, oy = round(at[0] - anchor[0]), round(at[1] - anchor[1])
    n = 0
    for r, row in enumerate(pattern):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            x, y = ox + c, oy + r
            if 0 <= x < im.width and 0 <= y < im.height and p[x, y][3]:
                p[x, y] = (0, 0, 0, 0) if ch == "_" else hexrgb(colors[ch]) + (255,)
                n += 1
    return n


def apply_patch(im, items):
    p = im.load()
    for x, y, c in items:
        p[x, y] = (0, 0, 0, 0) if c is None else hexrgb(c) + (255,)
    return len(items)


# ---------- 5/6. 帧条与审阅 ----------
def x8_sheet(frames, path, size, crop=None):
    k = 8 if size <= 128 else 6
    box = crop or (0, 0, size, size)
    w, h = box[2] - box[0], box[3] - box[1]
    cols = min(4, len(frames))
    rows = (len(frames) + cols - 1) // cols
    sh = Image.new("RGBA", (cols * (w * k + 8), rows * (h * k + 20)), (24, 28, 36, 255))
    d = ImageDraw.Draw(sh)
    for i, f in enumerate(frames):
        cell = Image.new("RGBA", (w, h), BG)
        cell.alpha_composite(f.crop(box))
        x, y = (i % cols) * (w * k + 8), (i // cols) * (h * k + 20)
        sh.paste(cell.resize((w * k, h * k), Image.NEAREST), (x, y + 16))
        d.text((x + 2, y + 2), "f%d" % i, fill=(220, 220, 220, 255))
    sh.save(path)


def gif(frames, durs, path, scale=3, box=None):
    out = []
    for f in frames:
        c = Image.new("RGBA", f.size, BG)
        c.alpha_composite(f)
        if box:
            c = c.crop(box)
        out.append(c.resize((c.width * scale, c.height * scale), Image.NEAREST).convert("P", palette=Image.ADAPTIVE))
    out[0].save(path, save_all=True, append_images=out[1:], duration=[max(20, int(d * 1000)) for d in durs], loop=0, disposal=2)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("id")
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--no-fix", action="store_true", help="不贴人工修补（看自动结果）")
    a = ap.parse_args()
    spec = json.load(open(os.path.join(TRIAL, "cfg", "%s_px.json" % a.id), encoding="utf-8"))
    rig = json.load(open(os.path.join(TRIAL, "cfg", spec.get("rig", a.id + ".json")), encoding="utf-8"))
    src = json.load(open(os.path.join(TRIAL, "cfg", rig["src"]), encoding="utf-8"))
    out_root = os.path.join(COMMON, "build", "spine_px", a.id)
    os.makedirs(out_root, exist_ok=True)
    size = spec.get("canvas", 192)
    pad = (size - 128) // 2
    origin = (64 + pad, 120 + pad)

    pal = os.path.join(out_root, "palette.png")
    # palette_protect：bz_18 的眼 / 嘴附件补色（缺省开）。令关掉：19 个眼眉睫附件多出 94 色，刘海阴影映射成粉色带（docs/365 §2）
    # palette_alpha：取色的 alpha 下限（bz_18 为 96）；令用 230：半透明的提灯光晕会把灯芯橙色拉淡
    make_palette(src["atlas"], spec.get("colors", 96), pal, spec.get("palette_protect", True), spec.get("palette_alpha", 96))
    if spec.get("keep_colors"):
        extra_colors(pal, spec["keep_colors"])

    pim = Image.open(pal).convert("RGB")
    palette = [pim.getpixel((i, 0)) for i in range(pim.width)]
    fix = spec.get("fix", {}) if not a.no_fix else {}
    eyes = fix.get("eyes")
    e_all = spec.get("fix", {}).get("eyes")
    track = list(e_all["bones"].values()) if e_all else []   # --no-fix 也记眼骨位置（对照用）
    patch_dir = os.path.join(ROOT, "art", "src", "%s_fix" % a.id)
    summary = {}
    for name, act in spec["actions"].items():
        if a.only and name not in a.only:
            continue
        c = dict(rig)
        for k in ("sample", "keys", "poses"):
            c.pop(k, None)
        c.update({k: v for k, v in act.items() if k not in ("durations", "fps", "fix", "note")})
        c["pack"] = dict(rig["pack"], palette_png=pal, scale=spec["scale"])
        c["canvas"] = size
        c["action"] = name
        c["trackBones"] = track
        if "sample" in act:
            c["sample"] = dict(act["sample"], times=times_of(act))
            c["sample"].pop("range", None)
            c["sample"].pop("inclusive", None)
            c["sample"].pop("end", None)
        tmp = os.path.join(TRIAL, "cfg", "_%s_%s_px.json" % (a.id, name))
        json.dump(c, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
        fdir = os.path.join(out_root, name, "frames")
        try:
            rep = run_trial(tmp, fdir)
        finally:
            os.remove(tmp)
        n = len(rep["frames"])
        raw = [Image.open(os.path.join(fdir, "f%02d.png" % i)).convert("RGBA") for i in range(n)]
        frames, st = [], {"specks": 0, "lone": 0, "eye_px": 0, "patch_px": 0}
        patches = {}
        pf = os.path.join(patch_dir, name + ".json")
        if fix and os.path.exists(pf):
            patches = json.load(open(pf, encoding="utf-8"))
        for i, im in enumerate(raw):
            keep = []
            bones = rep["frames"][i].get("bones") or {}
            if eyes and act.get("eyes", True):
                for side, bn in eyes["bones"].items():
                    b = bones.get(bn)
                    if b:
                        keep.append((int(b[0]) - 4, int(b[1]) - 4, int(b[0]) + 5, int(b[1]) + 5))
            im, s = clean(im, keep)
            st["specks"] += s["specks"]
            st["lone"] += s["lone"]
            if spec.get("outline"):
                im, k = outline(im, hexrgb(spec["outline"]["color"]), spec["outline"]["mix"], palette)
                st["outline_px"] = st.get("outline_px", 0) + k
            if eyes and act.get("eyes", True):
                for side, bn in eyes["bones"].items():
                    b = bones.get(bn)
                    if b and (act.get("eye_frames") is None or i in act["eye_frames"]):
                        st["eye_px"] += stamp(im, eyes["pattern"][side], eyes["colors"], b[:2], eyes["anchor"][side])
            if patches.get("f%02d" % i):
                st["patch_px"] += apply_patch(im, patches["f%02d" % i])
            frames.append(im)
        durs = durations_of(act, times_of(act) if "sample" in act else None)
        strip = Image.new("RGBA", (size * n, size))
        for i, f in enumerate(frames):
            strip.paste(f, (size * i, 0))
        os.makedirs(os.path.join(out_root, "strips"), exist_ok=True)
        sp = os.path.join(out_root, "strips", "op_%s_%s@2x.png" % (a.id, name))
        strip.save(sp)
        for i, f in enumerate(frames):
            f.save(os.path.join(fdir, "fixed_f%02d.png" % i))
        colors = len({p for f in frames for p in (f.get_flattened_data() if hasattr(f, "get_flattened_data") else f.getdata()) if p[3]})
        bb = [f.getbbox() for f in frames if f.getbbox()]
        u = (min(b[0] for b in bb), min(b[1] for b in bb), max(b[2] for b in bb), max(b[3] for b in bb))
        x8_sheet(frames, os.path.join(out_root, name, "%s_x8.png" % name), size, (max(0, u[0] - 2), max(0, u[1] - 2), min(size, u[2] + 2), min(size, u[3] + 2)))
        gif(frames, durs, os.path.join(out_root, name, "%s.gif" % name))
        summary[name] = {"frames": n, "durations": durs, "fps": round(n / sum(durs), 4), "colors": colors, "bbox_rel_origin": [u[0] - origin[0], u[1] - origin[1], u[2] - origin[0], u[3] - origin[1]],
                         "clipped": sorted({c for r in rep["frames"] for c in r.get("clipped_near_edge", [])}), **st}
        print(name, json.dumps(summary[name], ensure_ascii=False), flush=True)
        if a.apply:
            dst = os.path.join(ROOT, "game", "art", "operators", a.id)
            os.makedirs(dst, exist_ok=True)
            shutil.copyfile(sp, os.path.join(dst, os.path.basename(sp)))
    old = {}
    sj = os.path.join(out_root, "summary.json")
    if os.path.exists(sj):
        old = json.load(open(sj, encoding="utf-8"))
    old.update(summary)
    json.dump(old, open(sj, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
