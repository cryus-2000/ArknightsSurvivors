#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期可读性第一批（docs/244）开 / 关对照：拼并排图，并按 docs/243 的分层量测重算前后对照。
截图由 late_game_diag_shots.py shoot 产出（同种子，tag 带 OFF / ON 后缀；分层 full / nofriend / nofoe）。

指标（战场区 WORLD_BOX，口径同 docs/243 §1.3）：
  我方特效占屏 / 块数 / 中位块面积：full 与 nofriend 逐像素差 > 0.06 的掩码
  整帧红像素：整帧 HSV 红 / 洋红（H ≥ 330 或 < 20、S > 0.35、V > 0.25）
  小队被盖比例：每名干员脚底向上 64×32 的身体框里，敌方层（full 与 nofoe 的差）像素占比，取平均
  地雷可见度：每枚地雷 / 轰隆隆半径 14 的圆里与 nofriend 不同的像素占比（画了多少）和圆内对圆外 6 像素环带的亮度对比

用法：
    python tools/late_read_compare.py --pairs logos_user,kaltsit_sum,exusiai_solo --targets 180,480,570 --out docs/assets/late_read_b1
"""
import argparse, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import late_game_diag_shots as S

LABEL = {"logos_user": "逻各斯 + 德克萨斯 + 铃兰", "kaltsit_sum": "凯尔希召唤专项（地雷组 + 轰隆隆）", "exusiai_solo": "能天使"}


def _load(op, tag, seed, layer, f):
    from PIL import Image
    import numpy as np
    p = os.path.join(S.SHOT, "%s%s_s%d_%s" % (op, tag, seed, layer), "shot_%d.png" % f)
    if not os.path.exists(p):
        return None, None
    m = os.path.join(S.SHOT, "%s%s_s%d_%s" % (op, tag, seed, layer), "shot_%d.json" % f)
    meta = json.load(open(m)) if os.path.exists(m) else {}
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0, meta


def metrics(op, tag, seed, f):
    import numpy as np
    from scipy import ndimage as ndi
    full, meta = _load(op, tag, seed, "full", f)
    if full is None:
        return None
    x0, y0, x1, y1 = S.WORLD_BOX
    r = {"t": meta.get("t"), "enemies_on": meta.get("enemies_on"), "fx_dim": meta.get("fx_dim"), "deco_dim": meta.get("deco_dim")}
    H, Sa, V = S._hsv(full)
    red = ((H >= 330) | (H < 20)) & (Sa > 0.35) & (V > 0.25)
    r["red_frame_pct"] = float(red.mean() * 100)
    r["red_world_pct"] = float(red[y0:y1, x0:x1].mean() * 100)
    nf, _ = _load(op, tag, seed, "nofriend", f)
    if nf is not None:
        mf = np.abs(full - nf).max(axis=2) > 0.06
        mfb = mf[y0:y1, x0:x1]
        lab, n = ndi.label(mfb)
        sizes = np.bincount(lab.ravel())[1:] if n else np.array([0])
        r["friend_pct"] = float(mfb.mean() * 100)
        r["friend_blobs"] = int(n)
        r["friend_blob_med"] = float(np.median(sizes)) if n else 0.0
        r["friend_blob_p90"] = float(np.percentile(sizes, 90)) if n else 0.0
        L = S._luma(full)
        vis, con = [], []
        for (mx, my) in meta.get("mines_scr", []) + meta.get("bombs_scr", []):
            if not (20 <= mx < 1260 and 20 <= my < 700):
                continue
            yy, xx = np.ogrid[:720, :1280]
            d2 = (xx - mx) ** 2 + ((yy - my) / 0.6) ** 2
            disc = d2 <= 14 ** 2
            ring = (d2 > 16 ** 2) & (d2 <= 22 ** 2)
            vis.append(float(mf[disc].mean()))
            con.append(float(abs(L[disc].mean() - L[ring].mean())))
        if vis:
            r["mine_n"] = len(vis)
            r["mine_drawn"] = float(np.mean(vis))
            r["mine_contrast"] = float(np.mean(con))
    fo, _ = _load(op, tag, seed, "nofoe", f)
    if fo is not None:
        mb = np.abs(full - fo).max(axis=2) > 0.06
        cov = []
        for o in meta.get("ops_scr", []):
            ox, oy = int(o[1]), int(o[2])
            if not (16 <= ox < 1264 and 64 <= oy < 718):
                continue
            cov.append(float(mb[oy - 64:oy, ox - 16:ox + 16].mean()))
        if cov:
            r["squad_cov"] = float(np.mean(cov))
            r["squad_cov_max"] = float(np.max(cov))
    return r


def side_by_side(op, seed, f, t, out, tag_off, tag_on):
    from PIL import Image, ImageDraw, ImageFont
    a = os.path.join(S.SHOT, "%s%s_s%d_full" % (op, tag_off, seed), "shot_%d.png" % f)
    b = os.path.join(S.SHOT, "%s%s_s%d_full" % (op, tag_on, seed), "shot_%d.png" % f)
    if not (os.path.exists(a) and os.path.exists(b)):
        return None
    A, B = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    W, Hh = A.size
    im = Image.new("RGB", (W * 2 + 8, Hh + 36), (12, 14, 20))
    im.paste(A, (0, 36))
    im.paste(B, (W + 8, 36))
    d = ImageDraw.Draw(im)
    font = None
    for fp in ["/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
               os.path.join(ROOT, "game", "fonts", "NotoSansSC-Regular.otf")]:
        if os.path.exists(fp):
            font = ImageFont.truetype(fp, 22)
            break
    lab = "%s  %d:%02d" % (LABEL.get(op_key(op, tag_off), op), t // 60, t % 60)
    d.text((10, 6), "关（基准）  " + lab, fill=(220, 220, 230), font=font)
    d.text((W + 18, 6), "开 render/late_read=1  " + lab, fill=(150, 240, 255), font=font)
    p = os.path.join(out, "ab_%s_%d.png" % (op_key(op, tag_off), t))
    im.save(p, optimize=True)
    im.resize((im.width // 3, im.height // 3), Image.LANCZOS).save(p.replace(".png", "_phone.png"), optimize=True)   # 缩到手机屏宽看 E0 / E1 / E2 分不分得清
    return p


_KEYS = {}
def op_key(op, tag):
    return _KEYS.get((op, tag), op)


def cmd_elite(out, ops=("texas", "exusiai", "logos"), progs=(0, 4, 8)):
    """E0 / E1 / E2 三档对照（--prog=0 / 4 / 8 = 精零 / 精一 / 精二，--sptest 技力常满，前 25 秒每 4 帧一张）：
    每档挑「队长周围亮像素最多」的一帧，拼 关 | 开 两格；量测：队长周围 360×300 框里亮度 > 0.55 的像素数（全部帧平均），看主形面积随档变大多少"""
    import numpy as np
    from PIL import Image, ImageDraw
    rows = []
    cells = {}
    for op in ops:
        for p in progs:
            stat = {}
            for side in ["OFF", "ON"]:
                d = os.path.join(S.SHOT, "elite_%s_p%d_%s" % (op, p, side))
                if not os.path.isdir(d):
                    continue
                vals = []
                for fn in sorted(x for x in os.listdir(d) if x.endswith(".png")):
                    m = json.load(open(os.path.join(d, fn.replace(".png", ".json"))))
                    o = m["ops_scr"][0]
                    x, y = int(o[1]), int(o[2]) - 20
                    im = np.asarray(Image.open(os.path.join(d, fn)).convert("RGB")).astype(np.float32) / 255.0
                    box = im[max(0, y - 150):y + 150, max(0, x - 180):x + 180]
                    vals.append((float((S._luma(box) > 0.55).sum()), fn, x, y))
                stat[side] = vals
            if "ON" not in stat or "OFF" not in stat:
                continue
            best = max(stat["ON"])
            fn, x, y = best[1], best[2], best[3]
            pair = []
            for side in ["OFF", "ON"]:
                d = os.path.join(S.SHOT, "elite_%s_p%d_%s" % (op, p, side))
                pair.append(Image.open(os.path.join(d, fn)).convert("RGB").crop((x - 180, y - 150, x + 180, y + 150)))
            cells[(op, p)] = pair
            r = {"op": op, "prog": p, "elite": [0, 0, 0, 0, 1, 1, 1, 1, 2][p]}
            # 有去我方层（_nf）时：队长周围 360×300 框里我方特效掩码的面积（像素）、连通块中位 / P90 面积，全部帧合计
            from scipy import ndimage as ndi
            for side in ["OFF", "ON"]:
                d = os.path.join(S.SHOT, "elite_%s_p%d_%s" % (op, p, side))
                dn = d + "_nf"
                if not os.path.isdir(dn):
                    continue
                areas, blobs = [], []
                for fn in sorted(x for x in os.listdir(d) if x.endswith(".png")):
                    if not os.path.exists(os.path.join(dn, fn)):
                        continue
                    m = json.load(open(os.path.join(d, fn.replace(".png", ".json"))))
                    o = m["ops_scr"][0]
                    x, y = int(o[1]), int(o[2]) - 20
                    a = np.asarray(Image.open(os.path.join(d, fn)).convert("RGB")).astype(np.float32) / 255.0
                    b = np.asarray(Image.open(os.path.join(dn, fn)).convert("RGB")).astype(np.float32) / 255.0
                    bx0, by0, bx1, by1 = S.WORLD_BOX   # 整个战场区（投射物会飞出队长周围的框）
                    mk = (np.abs(a - b).max(axis=2) > 0.06)[by0:by1, bx0:bx1]
                    areas.append(float(mk.sum()))
                    lab, n = ndi.label(mk)
                    if n:
                        blobs.extend(np.bincount(lab.ravel())[1:].tolist())
                r["area_" + side] = float(np.mean(areas)) if areas else None
                r["blob_med_" + side] = float(np.median(blobs)) if blobs else None
                r["blob_p90_" + side] = float(np.percentile(blobs, 90)) if blobs else None
                r["big_blobs_" + side] = float(sum(1 for v in blobs if v >= 50) / max(1, len(areas)))   # 每帧 ≥ 50 像素的「实心主形」块数
            rows.append(r)
            print(r, flush=True)
    W, H = 360, 300
    im = Image.new("RGB", (len(progs) * (2 * W + 12) + 8, len(ops) * (H + 30) + 30), (12, 14, 20))
    d = ImageDraw.Draw(im)
    font = None
    for fp in ["/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc", "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc"]:
        if os.path.exists(fp):
            from PIL import ImageFont
            font = ImageFont.truetype(fp, 20)
            break
    for j, p in enumerate(progs):
        d.text((8 + j * (2 * W + 12), 4), "精%s（左 关 / 右 开）" % ["零", "一", "二"][j], fill=(230, 230, 240), font=font)
    for i, op in enumerate(ops):
        for j, p in enumerate(progs):
            if (op, p) not in cells:
                continue
            a, b = cells[(op, p)]
            x0 = 8 + j * (2 * W + 12)
            y0 = 30 + i * (H + 30)
            im.paste(a, (x0, y0))
            im.paste(b, (x0 + W + 2, y0))
            d.text((x0 + 4, y0 + H + 2), op, fill=(180, 200, 220), font=font)
    pth = os.path.join(out, "elite_tiers.png")
    im.save(pth, optimize=True)
    im.resize((im.width * 1080 // im.width, im.height * 1080 // im.width), Image.LANCZOS).save(pth.replace(".png", "_phone.png"), optimize=True)
    json.dump(rows, open(os.path.join(out, "elite_tiers.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "elite":
        out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "assets", "late_read_b1")
        os.makedirs(out, exist_ok=True)
        cmd_elite(out)
        return
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", default="logos:_user:logos_user,kaltsit:_sum:kaltsit_sum,exusiai:_solo:exusiai_solo",
                    help="干员:tag 前缀:显示键，tag 实际为 前缀 + OFF / ON")
    ap.add_argument("--targets", default="180,480,570")
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_read_b1"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    S.TARGETS[:] = [int(x) for x in a.targets.split(",")]
    rows = []
    for spec in a.runs.split(","):
        op, pre, key = spec.split(":")
        for side in ["OFF", "ON"]:
            _KEYS[(op, pre + side)] = key
        for ti, t in enumerate(S.TARGETS):
            f = S.frames()[ti * 2]
            for side in ["OFF", "ON"]:
                m = metrics(op, pre + side, a.seed, f)
                if m:
                    m.update({"run": key, "side": side, "t_target": t})
                    rows.append(m)
                    print({k: (round(v, 3) if isinstance(v, float) else v) for k, v in m.items()}, flush=True)
            side_by_side(op, a.seed, f, t, a.out, pre + "OFF", pre + "ON")
    json.dump(rows, open(os.path.join(a.out, "metrics.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
