# -*- coding: utf-8 -*-
"""像素稿可量验收（干员美术「路 1」：@2x 原生细节、1x 人工收敛；尺度 B：1x 64 画布、@2x 128 画布）。纯 Python + PIL，不开 Godot。

输入一对 PNG（1x + @2x）与 1x 脚底原点（@2x 原点 = 2 × 1x 原点，可用 --foot2 另给），逐层检查：
  ① 透明：alpha 只有 0 / 255；不透明像素的四邻域连通体个数（应为 1）；alpha 孤点（四邻都透明的不透明像素）
  ② 颜色孤点（主口径，10-15 用三份逻各斯样本对界面手数校过）：不是描边色、八邻里没有同色、八邻里同一种底色占 ≥ 6
     ——「嵌在一片色块里的单点」，就是看图时会跳出来的那种；「单点高光」= 这样的孤点且明度比底色高 ≥ hl（缺省 16，--hl 可调；暗部里只亮一点点的杂色不算）；
     并上「暗底亮点」：四邻无同色（对角相连不算连块）、不是描边色、8 邻里 ≥ 6 个比它暗 ≥ 240（RGB 和）——暗部多档暗色混排里的碎亮点
     （界面 10-15 核对 C-HD 胸前领口后加；它也计入孤点）。@2x 要求 0：高光至少 2 像素成组。
     口径校准见 docs/36 §9.2（10-15 加暗底亮点后：界面点名的 C-HD @2x 胸前 15 点 + 另 7 点全部计入单点高光）。
     宽口径一并报（只作参考）：与四邻都不同色的像素（isolated_loose）、其中比所有不透明四邻都亮的（highlight_loose）——
     在 27 色量化稿里这会数进大量正常的细节交界，数字偏大
  ③ 1x ↔ @2x 对应：@2x 按 2×2 块取主色（众数；透明也算一色），与 1x 对应像素比较——
     透明性不同、或 RGB 欧氏距离 > 阈值（缺省 48）的块数；比例低说明 1x 是由 @2x 收敛来的
  ④ 色数（不透明）、外描边（与透明四邻接的外圈应为描边色 #080E18；@2x 查 2 像素宽）、最小边距、最低不透明行 vs 脚底行
  ⑤ 量表（可选 --metrics <干员 id>）：调用 tools/body_metrics.py 的 measure()，图像换成这张 @2x；
     脸部项（眼 / 下巴）取 body_metrics 里该干员的人工标注（生产图的），新稿要另标，只能参考几何项

    python tools/px_lint.py <1x.png> <@2x.png> --foot 33 60 [--out build/px_lint/<名>] [--thr 48] [--hl 16] [--metrics logos]
    python tools/px_lint.py --samples          # 跑仓库登记的样本（SAMPLES），供 check.py --only px_lint

输出 <out>/report.json 与 <out>/marked.png（两层各放大 6 倍并排；红圈 = 颜色孤点，黄圈 = 单点高光，品红格 = ③ 对不上的块）。
"""
import argparse, json, math, os, sys
from collections import Counter, deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
OUTLINE = (0x08, 0x0E, 0x18)
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def _common_root():
    try:
        import godot_runner as GR
        return GR.common_root()
    except Exception:
        return ROOT


# 样本：Codex 交付的逻各斯待机 f0 试稿（B / C：r1；C-HD：t2）。art/incoming 里没有时去 codex-art 工作树找
SAMPLES = [
    ("logos_B", "i_pilot_1015_r1/op_logos_idle_f0.png", "i_pilot_1015_r1/op_logos_idle_f0@2x.png", (33, 60)),
    ("logos_C", "i_pilot_1015_r1/op_logos_idle_f0_c.png", "i_pilot_1015_r1/op_logos_idle_f0_c@2x.png", (33, 60)),
    ("logos_C_HD", "i_pilot_1015_t2/op_logos_idle_f0_c_hd.png", "i_pilot_1015_t2/op_logos_idle_f0_c_hd@2x.png", (33, 60)),
]


def _find(rel):
    cr = _common_root()
    for base in (os.path.join(ROOT, "art", "incoming"), os.path.join(cr, "art", "incoming"), os.path.join(cr, ".worktrees", "codex-art", "art", "incoming")):
        p = os.path.join(base, rel)
        if os.path.exists(p):
            return p
    return None


def lum(c):
    return 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]


class Layer:
    def __init__(self, path):
        from PIL import Image
        im = Image.open(path).convert("RGBA")
        self.w, self.h = im.size
        self.px = list(im.get_flattened_data()) if hasattr(im, "get_flattened_data") else list(im.getdata())
        self.path = path

    def at(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y * self.w + x]
        return (0, 0, 0, 0)

    def op(self, x, y):
        return self.at(x, y)[3] > 0


HL = 16.0   # 单点高光 ①：比底色亮多少明度（0.299R + 0.587G + 0.114B）才算
DARK = 240   # 单点高光 ②「暗底亮点」：8 邻里 ≥ DARK_N 个比本像素暗这么多（RGB 和之差）
DARK_N = 6


def analyze(L, foot, outline_w, hl=None):
    hl = HL if hl is None else hl
    W, H = L.w, L.h
    r = {"size": [W, H]}
    alphas = Counter(p[3] for p in L.px)
    r["alpha_binary"] = all(a in (0, 255) for a in alphas)
    r["alpha_partial"] = sum(n for a, n in alphas.items() if a not in (0, 255))
    # 连通体（四邻域，不透明）
    seen, comps = set(), []
    for y in range(H):
        for x in range(W):
            if L.op(x, y) and (x, y) not in seen:
                q, n = deque([(x, y)]), 0
                seen.add((x, y))
                while q:
                    cx, cy = q.popleft()
                    n += 1
                    for dx, dy in N4:
                        p = (cx + dx, cy + dy)
                        if p not in seen and L.op(*p):
                            seen.add(p)
                            q.append(p)
                comps.append(((x, y), n))
    r["components"] = len(comps)
    r["component_sizes"] = sorted((n for _, n in comps), reverse=True)[:8]
    r["alpha_islands"] = [[x, y] for y in range(H) for x in range(W) if L.op(x, y) and not any(L.op(x + dx, y + dy) for dx, dy in N4)]
    # ② 颜色孤点 / 单点高光
    iso, hi, iso_l, hi_l = [], [], [], []
    for y in range(H):
        for x in range(W):
            c = L.at(x, y)
            if c[3] == 0:
                continue
            n4 = [L.at(x + dx, y + dy) for dx, dy in N4]
            if not any(n[3] > 0 and n[:3] == c[:3] for n in n4):
                iso_l.append([x, y])
                on = [lum(n) for n in n4 if n[3] > 0]
                if on and lum(c) > max(on):
                    hi_l.append([x, y])
            if c[:3] == OUTLINE:
                continue
            n8 = [L.at(x + dx, y + dy) for dx, dy in N8]
            # ② 暗底亮点（界面 10-15 核对后加）：四邻无同色（对角相连不算连块）、8 邻里 ≥ 6 个比它暗 ≥ 240（RGB 和）
            #    ——暗部常是几档近黑 / 深蓝混排，「同一底色占 ≥ 6」会漏掉其中的碎亮点（逻各斯 C-HD 胸前领口）
            sc = c[0] + c[1] + c[2]
            dark_base = not any(n[3] > 0 and n[:3] == c[:3] for n in n4) and                 sum(1 for n in n8 if n[3] > 0 and sc - (n[0] + n[1] + n[2]) >= DARK) >= DARK_N
            # ① 色块里的单点：八邻无同色、同一底色占 ≥ 6；比底色亮 ≥ hl 算高光
            flat = False
            if not any(n[3] > 0 and n[:3] == c[:3] for n in n8):
                base = Counter(n[:3] for n in n8 if n[3] > 0).most_common(1)
                if base and base[0][1] >= 6:
                    flat = True
                    bright = lum(c) - lum(base[0][0]) >= hl
            if flat or dark_base:
                iso.append([x, y])
                if dark_base or bright:
                    hi.append([x, y])
    r["isolated"] = iso
    r["single_highlight"] = hi
    r["isolated_loose"] = iso_l
    r["highlight_loose"] = hi_l
    # 外描边：离透明（或画布外）四邻域距离 ≤ outline_w 的不透明像素应为描边色
    dist = {}
    q = deque()
    for y in range(H):
        for x in range(W):
            if L.op(x, y) and any(not L.op(x + dx, y + dy) for dx, dy in N4):
                dist[(x, y)] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        if dist[(x, y)] >= outline_w:
            continue
        for dx, dy in N4:
            p = (x + dx, y + dy)
            if L.op(*p) and p not in dist:
                dist[p] = dist[(x, y)] + 1
                q.append(p)
    bad = [[x, y] for (x, y), d in dist.items() if L.at(x, y)[:3] != OUTLINE]
    r["outline_px"] = len(dist)
    r["outline_bad"] = len(bad)
    r["outline_bad_xy"] = sorted(bad)[:40]
    cols = Counter(p[:3] for p in L.px if p[3] > 0)
    r["colors"] = len(cols)
    xs = [i % W for i, p in enumerate(L.px) if p[3] > 0]
    ys = [i // W for i, p in enumerate(L.px) if p[3] > 0]
    if xs:
        r["bbox"] = [min(xs), min(ys), max(xs), max(ys)]
        r["margin"] = min(min(xs), min(ys), W - 1 - max(xs), H - 1 - max(ys))
        r["lowest_row"] = max(ys)
    r["foot"] = list(foot)
    # @2x 由 1x 放大时 1x 的脚底行占两行（2f、2f+1），所以 @2x 最低行允许 foot 或 foot+1
    r["foot_row_ok"] = bool(xs) and (max(ys) == foot[1] or (outline_w == 2 and max(ys) == foot[1] + 1))
    return r


def compare(L1, L2, foot1, foot2, thr):
    """③ @2x 每个 2×2 块的主色 vs 1x 像素"""
    ox, oy = foot2[0] - 2 * foot1[0], foot2[1] - 2 * foot1[1]
    bad, tot = [], 0
    for y in range(L1.h):
        for x in range(L1.w):
            blk = [L2.at(2 * x + ox + i, 2 * y + oy + j) for j in (0, 1) for i in (0, 1)]
            key = Counter((b[:3] if b[3] > 0 else None) for b in blk)
            dom = key.most_common(1)[0][0]
            p = L1.at(x, y)
            p_c = p[:3] if p[3] > 0 else None
            if dom is None and p_c is None:
                continue
            tot += 1
            if (dom is None) != (p_c is None):
                bad.append([x, y, "alpha"])
            elif math.dist(dom, p_c) > thr:
                bad.append([x, y, round(math.dist(dom, p_c))])
    return {"blocks": tot, "mismatch": len(bad), "ratio": round(len(bad) / tot, 3) if tot else 0.0, "offset": [ox, oy], "thr": thr, "mismatch_xy": bad[:60]}


def marked(L1, L2, r1, r2, cmp, path, k=6):
    from PIL import Image, ImageDraw
    pad = 12
    img = Image.new("RGBA", (L1.w * k * 2 + L2.w * k + pad * 3, max(L1.h * 2, L2.h) * k + pad * 2), (40, 42, 54, 255))
    def blit(L, s, x0):
        im = Image.new("RGBA", (L.w, L.h))
        im.putdata(L.px)
        im = im.resize((L.w * s, L.h * s), Image.NEAREST)
        img.alpha_composite(im, (x0, pad))
    k1 = k * 2   # 1x 层放大 12 倍，与 @2x 放大 6 倍同尺寸
    blit(L1, k1, pad)
    x2 = pad * 2 + L1.w * k1
    blit(L2, k, x2)
    dr = ImageDraw.Draw(img)
    def ring(x0, s, xy, col, rr):
        cx, cy = x0 + xy[0] * s + s / 2, pad + xy[1] * s + s / 2
        dr.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), outline=col, width=2)
    for xy in cmp["mismatch_xy"]:
        dr.rectangle((pad + xy[0] * k1, pad + xy[1] * k1, pad + xy[0] * k1 + k1 - 1, pad + xy[1] * k1 + k1 - 1), outline=(255, 0, 255, 255))
    for xy in r1["isolated"]:
        ring(pad, k1, xy, (255, 60, 60, 255), k1 * 0.8)
    for xy in r1["single_highlight"]:
        ring(pad, k1, xy, (255, 220, 40, 255), k1 * 1.1)
    for xy in r2["isolated"]:
        ring(x2, k, xy, (255, 60, 60, 255), k * 0.9)
    for xy in r2["single_highlight"]:
        ring(x2, k, xy, (255, 220, 40, 255), k * 1.3)
    img.save(path)


def metrics(cid, p2, foot1):
    import body_metrics as BM
    from PIL import Image
    def idle(c):
        BM.NAMES[c] = c
        im = Image.open(p2).convert("RGBA")
        return im.crop((0, 0, im.height, im.height)), list(foot1)
    BM.idle = idle
    try:
        return BM.measure(cid)
    except Exception as e:
        return {"error": str(e)[:200]}


def run(p1, p2, foot1, foot2=None, out=None, thr=48, cid=None, name=None, hl=None):
    foot2 = foot2 or (foot1[0] * 2, foot1[1] * 2)
    L1, L2 = Layer(p1), Layer(p2)
    r1 = analyze(L1, foot1, 1, hl)
    r2 = analyze(L2, foot2, 2, hl)
    cmp = compare(L1, L2, foot1, foot2, thr)
    rep = {"name": name or os.path.splitext(os.path.basename(p1))[0], "1x": dict(r1, path=p1), "2x": dict(r2, path=p2), "match": cmp}
    if cid:
        rep["metrics"] = metrics(cid, p2, foot1)
    out = out or os.path.join(_common_root(), "build", "px_lint", rep["name"])
    os.makedirs(out, exist_ok=True)
    json.dump(rep, open(os.path.join(out, "report.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    marked(L1, L2, r1, r2, cmp, os.path.join(out, "marked.png"))
    rep["out"] = out
    return rep


def summary(rep):
    a, b, m = rep["1x"], rep["2x"], rep["match"]
    def one(r, tag):
        return "%s：%d×%d 色 %d 连通体 %d%s 孤点 %d（其中单点高光 %d；宽口径 %d / 亮 %d） 描边违规 %d / %d 边距 %s 最低行 %s%s" % (
            tag, r["size"][0], r["size"][1], r["colors"], r["components"], "" if r["alpha_binary"] else "（半透明 %d）" % r["alpha_partial"],
            len(r["isolated"]), len(r["single_highlight"]), len(r["isolated_loose"]), len(r["highlight_loose"]), r["outline_bad"], r["outline_px"], r.get("margin"), r.get("lowest_row"),
            "" if r["foot_row_ok"] else "（脚底 %d）" % r["foot"][1])
    return "%s\n  %s\n  %s\n  1x↔@2x 块对不上 %d / %d（%.1f%%，阈值 %d）\n  → %s" % (
        rep["name"], one(a, "1x"), one(b, "@2x"), m["mismatch"], m["blocks"], m["ratio"] * 100, m["thr"], rep["out"])


def problems(rep):
    """硬规则（check.py 用）：二值透明、单连通体、@2x 单点高光 0、描边全对、脚底行对"""
    errs = []
    for k in ("1x", "2x"):
        r = rep[k]
        if not r["alpha_binary"]:
            errs.append("%s %s 有半透明 %d 像素" % (rep["name"], k, r["alpha_partial"]))
        if r["components"] != 1:
            errs.append("%s %s alpha 连通体 %d 个" % (rep["name"], k, r["components"]))
        if r["outline_bad"]:
            errs.append("%s %s 外描边不是 #080E18：%d 像素" % (rep["name"], k, r["outline_bad"]))
        if not r["foot_row_ok"]:
            errs.append("%s %s 最低不透明行 %s ≠ 脚底 %d" % (rep["name"], k, r.get("lowest_row"), r["foot"][1]))
    if rep["2x"]["single_highlight"]:
        errs.append("%s @2x 单点高光 %d 个（要求 0）" % (rep["name"], len(rep["2x"]["single_highlight"])))
    return errs


def run_samples(verbose=True):
    reps, errs, miss = [], [], []
    for name, a, b, foot in SAMPLES:
        p1, p2 = _find(a), _find(b)
        if not p1 or not p2:
            miss.append(name)
            continue
        rep = run(p1, p2, foot, name=name)
        reps.append(rep)
        if verbose:
            print(summary(rep))
        errs += problems(rep)
    return reps, errs, miss


# 样本的校准值（10-15）：工具改口径后这些数变了要先说明再改表
EXPECT = {"logos_B": (26, 0, 0), "logos_C": (35, 0, 0), "logos_C_HD": (44, 75, 195)}   # 1x 孤点、@2x 单点高光、块对不上


def check():
    """check.py --only px_lint：工具在样本上跑通、数字等于校准值（防口径悄悄漂）；样本自己的问题只列在明细里，不算失败"""
    reps, probs, miss = run_samples(False)
    errs = ["找不到样本 %s（art/incoming 或 .worktrees/codex-art）" % m for m in miss]
    for r in reps:
        got = (len(r["1x"]["isolated"]), len(r["2x"]["single_highlight"]), r["match"]["mismatch"])
        if r["name"] in EXPECT and got != EXPECT[r["name"]]:
            errs.append("%s 数字与校准值不同：%s ≠ %s（1x 孤点、@2x 单点高光、块对不上）" % (r["name"], got, EXPECT[r["name"]]))
    detail = "%d 份样本：%s" % (len(reps), "；".join("%s 1x 孤点 %d / @2x 单点高光 %d / 块对不上 %d（%.0f%%）" % (
        r["name"], len(r["1x"]["isolated"]), len(r["2x"]["single_highlight"]), r["match"]["mismatch"], r["match"]["ratio"] * 100) for r in reps))
    if probs:
        detail += "。样本问题（不算失败）：" + "；".join(probs)
    return errs, detail


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("one", nargs="?")
    ap.add_argument("two", nargs="?")
    ap.add_argument("--foot", nargs=2, type=int, help="1x 脚底原点 x y")
    ap.add_argument("--foot2", nargs=2, type=int, help="@2x 脚底原点（缺省 = 2 × --foot）")
    ap.add_argument("--out")
    ap.add_argument("--thr", type=float, default=48, help="③ 块主色与 1x 像素的 RGB 距离阈值")
    ap.add_argument("--hl", type=float, default=HL, help="② 单点高光：比底色亮多少明度才算")
    ap.add_argument("--metrics", help="干员 id：顺带跑 body_metrics 量表")
    ap.add_argument("--samples", action="store_true")
    a = ap.parse_args()
    if a.samples:
        _, errs, miss = run_samples()
        for e in errs:
            print("!! " + e)
        if miss:
            print("找不到样本：" + "、".join(miss))
        return 1 if errs else 0
    if not (a.one and a.two and a.foot):
        ap.error("给 1x、@2x 两张图与 --foot x y，或 --samples")
    rep = run(a.one, a.two, tuple(a.foot), tuple(a.foot2) if a.foot2 else None, a.out, a.thr, a.metrics, hl=a.hl)
    print(summary(rep))
    if "metrics" in rep:
        print("  量表：" + json.dumps(rep["metrics"], ensure_ascii=False))
    errs = problems(rep)
    for e in errs:
        print("!! " + e)
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
