# 新旧 pixelfx 帧条静态对照（docs/239 §3）：先 git archive 各提交的 game/data、game/scripts、game/art/fx 到 build/pixelfx_compare/<提交>/，改下面 BASE / GROUPS 后运行
import os, re, sys, glob, importlib.util
import numpy as np
from PIL import Image, ImageDraw, ImageFont

S = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "build", "pixelfx_compare")
CMP = os.path.join(S, "cmp")
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = "E:/ArknightsSurvivors/Claude outputs/pixelfx_compare_1103"
BASE = "87149a00c"
GROUPS = {"A": "4e7f89b1b", "B": "632ae4db1", "C": "23c817f9d", "D": "85537c90c"}
BASIC = "5362549ea"
BG = (6, 20, 42)
Z = 2            # 整数放大：世界像素 × 2
MAXF = 4         # 每条关键帧数
H_LIMIT = 7800

spec = importlib.util.spec_from_file_location("cov", os.path.join(REPO, "tools", "fx_coverage.py"))
cov = importlib.util.module_from_spec(spec); spec.loader.exec_module(cov)

def refs(commit):
    cov.G = os.path.join(CMP, commit, "game")
    cov._V6 = None
    ov, ops, link, ult, common, enemy, dyn = cov.build()
    r = {}
    for t, kind in ((ops, "干员"), (link, "连携")):
        for (owner, name), row in t.rows.items():
            r.setdefault(owner, {})[name] = "、".join(sorted(row["cats"]))
    return r

def v6(commit):
    src = open(os.path.join(CMP, commit, "game/scripts/art.gd"), encoding="utf-8").read()
    m = re.search(r"const V6_FRAMES := \{(.*?)\n\}", src, re.S)
    return {nm: int(fr) for nm, fr in re.findall(r'"([a-z0-9_/]+)":\s*\[(\d+)', m.group(1))}

_files = {}
def find_png(commit, name):
    if commit not in _files:
        d = {}
        for p in glob.glob(os.path.join(CMP, commit, "game/art/**/*.png"), recursive=True):
            if "_optical" in p:
                continue
            b = os.path.basename(p)[:-4]
            d.setdefault(b, p)
        _files[commit] = d
    d = _files[commit]
    for k in (name + "@2x", name):
        if k in d:
            return d[k], k.endswith("@2x")
    return None, False

def frames_of(commit, name, nfr):
    p, hi = find_png(commit, name)
    if p is None:
        return None
    im = np.asarray(Image.open(p).convert("RGBA"))
    n = max(1, nfr.get(name, 1))
    w = im.shape[1] // n
    fr = [im[:, i * w:(i + 1) * w] for i in range(n)]
    g = None
    gp, _ = find_png(commit, name + "_glow")
    if gp:
        gi = np.asarray(Image.open(gp).convert("RGB"))
        gn = max(1, nfr.get(name + "_glow", n))
        gw = gi.shape[1] // gn
        g = [gi[:, i * gw:(i + 1) * gw] for i in range(gn)]
    return fr, g, hi

def compose(f, gl, hi, px=False):
    h, w = f.shape[:2]
    base = np.zeros((h, w, 3), np.float32); base[:] = BG
    a = f[..., 3:4] / 255.0
    out = base * (1 - a) + f[..., :3] * a
    if gl is not None and gl.shape[:2] == (h, w):
        out = out + gl.astype(np.float32)
    im = Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))
    k = Z * (1 if (hi or px) else 2)   # pixelfx 帧条一律按 1 贴图像素 = 1 世界像素（docs/228）
    return im.resize((w * k, h * k), Image.NEAREST)

def pick(fr):
    act = [i for i, f in enumerate(fr) if (f[..., 3] > 10).sum() > 0]
    if not act:
        return [0]
    en = [float((f[..., :3].mean(-1) * (f[..., 3] / 255)).sum()) for f in fr]
    a, b = act[0], act[-1]
    peak = max(act, key=lambda i: en[i])
    idx = sorted(set([a, peak, (peak + b) // 2, b]))
    return idx[:MAXF]

def strip_row(commit, name, nfr, label, font):
    r = frames_of(commit, name, nfr)
    if r is None:
        return None
    fr, gl, hi = r
    tiles = [compose(fr[i], gl[i] if gl and i < len(gl) else None, hi, "_px_" in name) for i in pick(fr)]
    tw = sum(t.width for t in tiles) + 4 * (len(tiles) - 1)
    th = max(t.height for t in tiles)
    row = Image.new("RGB", (max(tw, 260), th + 22), (20, 22, 30))
    d = ImageDraw.Draw(row)
    d.text((2, 2), label, fill=(210, 214, 228), font=font)
    x = 0
    for t in tiles:
        row.paste(t, (x, 22 + (th - t.height) // 2)); x += t.width + 4
    return row

def stack(rows, width):
    if not rows:
        return Image.new("RGB", (width, 1), (20, 22, 30))
    h = sum(r.height + 6 for r in rows)
    im = Image.new("RGB", (width, h), (20, 22, 30))
    y = 0
    for r in rows:
        im.paste(r, (0, y)); y += r.height + 6
    return im

def main():
    os.makedirs(OUT, exist_ok=True)
    font = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 15)
    big = ImageFont.truetype("C:/Windows/Fonts/msyhbd.ttc", 22)
    base_refs, base_v6 = refs(BASE), v6(BASE)
    basic_refs, basic_v6 = refs(BASIC), v6(BASIC)
    made = []
    for g, commit in GROUPS.items():
        new_refs, new_v6 = refs(commit), v6(commit)
        blocks = []
        for op in cov.GROUPS[g]:
            old = base_refs.get(op, {})
            new = dict(new_refs.get(op, {}))
            if op in ("lappland", "exusiai"):
                for n, c in basic_refs.get(op, {}).items():
                    if "_px_" in n:
                        new.setdefault(n, c)
            new_px = sorted(n for n in new if "_px_" in n)
            replaced = sorted(n for n in old if n not in new and "_px_" not in n)
            kept = sorted(n for n in old if n in new and "_px_" not in n)
            lrows, rrows = [], []
            for n in replaced:
                r = strip_row(BASE, n, base_v6, "旧 %s（%s）" % (n, old[n]), font)
                if r: lrows.append(r)
            for n in new_px:
                src = commit if find_png(commit, n)[0] else BASIC
                r = strip_row(src, n, new_v6 if src == commit else basic_v6, "新 %s（%s）" % (n, new.get(n, "")), font)
                if r: rrows.append(r)
            lw = max([r.width for r in lrows] + [420]); rw = max([r.width for r in rrows] + [420])
            L, R = stack(lrows, lw), stack(rrows, rw)
            note = ("未换 / 不换：" + "、".join(kept)) if kept else "未换 / 不换：无"
            hdr = 34
            nh = 22 * (1 + len(note) // 150)
            blk = Image.new("RGB", (lw + rw + 24, hdr + max(L.height, R.height) + nh + 8), (12, 14, 20))
            d = ImageDraw.Draw(blk)
            d.text((6, 4), "%s　（左：旧，被替换的 %d 条　右：新 pixelfx，叠光晕，%d 条）" % (op, len(lrows), len(rrows)), fill=(240, 240, 250), font=big)
            blk.paste(L, (0, hdr)); blk.paste(R, (lw + 24, hdr))
            yy = hdr + max(L.height, R.height) + 4
            for k in range(0, len(note), 150):
                d.text((6, yy), note[k:k + 150], fill=(255, 190, 120), font=font); yy += 22
            blocks.append(blk)
        # 按高度切页
        page, ph, pi = [], 0, 1
        def flush(page, pi):
            W = max(b.width for b in page)
            H = sum(b.height + 12 for b in page)
            im = Image.new("RGB", (W, H), (8, 10, 14)); y = 0
            for b in page:
                im.paste(b, (0, y)); y += b.height + 12
            p = os.path.join(OUT, "group_%s_%d.png" % (g, pi)); im.save(p, optimize=True); made.append((p, im.size))
        for b in blocks:
            if b.height > H_LIMIT:
                b = b.crop((0, 0, b.width, H_LIMIT))
            if page and ph + b.height > H_LIMIT:
                flush(page, pi); pi += 1; page, ph = [], 0
            page.append(b); ph += b.height + 12
        if page:
            flush(page, pi)
    for p, s in made:
        print(p, s, os.path.getsize(p) // 1024, "KB")

main()
