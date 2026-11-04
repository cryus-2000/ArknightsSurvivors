#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""后期可读性第二批（docs/247）开 / 关对照：拼并排图 + 分层量测。截图由 late_read2_shots.py shoot 产出。

指标（战场区 WORLD_BOX，口径同 docs/243 §1.3：两遍逐像素差 > 0.06 = 该层掩码）：
  friend_pct        我方特效占屏（full 与 nofriend 的差）
  friend_luma_share 我方特效亮度占比：掩码内亮度总和 ÷ 战场区亮度总和
  friend_luma       我方特效平均亮度；ground_luma 地面平均亮度（full 与 noground 的差，扣掉我方掩码）；contrast = 两者之差
  ring_pct          地面光环叠层占屏（full 与 noring 的差：巢穴光环、灯标 / 灯柱、遥乡 / 旗帜地圈）——「地面半透明占屏」
  dl_*              照地光（shot_*.json 的 dl：入选盏数 n、我方 ally、敌方 foe、其中命中光 hit、终结技 ult、重击 heavy）
  frame_luma        整帧平均亮度（「画面整体不更亮」）；red_frame_pct 整帧红 / 洋红像素

    python tools/late_read2_compare.py --out docs/assets/late_read_b2
"""
import argparse, json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import late_game_diag_shots as S
import late_read2_shots as R


def _load(tag, layer, f):
    from PIL import Image
    import numpy as np
    d = os.path.join(S.SHOT, "%s%s_s%d_%s" % (R.OP, tag, R.SEED, layer))
    p = os.path.join(d, "shot_%d.png" % f)
    if not os.path.exists(p):
        return None, {}
    m = os.path.join(d, "shot_%d.json" % f)
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0, (json.load(open(m)) if os.path.exists(m) else {})


def metrics(tag, f):
    import numpy as np
    full, meta = _load(tag, "full", f)
    if full is None:
        return None
    x0, y0, x1, y1 = S.WORLD_BOX
    B = lambda im: im[y0:y1, x0:x1]
    F = B(full)
    L = S._luma(F)
    r = {"t": meta.get("t"), "enemies": meta.get("enemies"), "enemies_on": meta.get("enemies_on"), "env_dim": meta.get("env_dim"),
         "fx_dim": meta.get("fx_dim"), "frame_luma": float(S._luma(full).mean()), "world_luma": float(L.mean())}
    H, Sa, V = S._hsv(full)
    r["red_frame_pct"] = float((((H >= 330) | (H < 20)) & (Sa > 0.35) & (V > 0.25)).mean() * 100)
    dl = meta.get("dl", {})
    for k in ["n", "ally", "foe", "hit", "ult", "heavy", "cand_ally", "cand_foe"]:
        r["dl_" + k] = dl.get(k)
    mf = None
    nf, _ = _load(tag, "nofriend", f)
    if nf is not None:
        mf = np.abs(B(nf) - F).max(axis=2) > 0.06
        r["friend_pct"] = float(mf.mean() * 100)
        r["friend_luma_share"] = float(L[mf].sum() / max(1e-6, L.sum()) * 100)
        r["friend_luma"] = float(L[mf].mean()) if mf.any() else None
    ng, _ = _load(tag, "noground", f)
    if ng is not None:
        mg = np.abs(B(ng) - F).max(axis=2) > 0.06
        if mf is not None:
            mg &= ~mf
        r["ground_pct"] = float(mg.mean() * 100)
        r["ground_luma"] = float(L[mg].mean()) if mg.any() else None
        if r.get("friend_luma") is not None and r["ground_luma"] is not None:
            r["contrast"] = r["friend_luma"] - r["ground_luma"]
    nr, _ = _load(tag, "noring", f)
    if nr is not None:
        mr = np.abs(nr - full).max(axis=2) > 0.06
        r["ring_pct"] = float(B(mr).mean() * 100)
        r["ring_frame_pct"] = float(mr.mean() * 100)
    return r


def _frame(t):
    return int(round(t / S.SPF))


def side(a, b, la, lb, out):
    from PIL import Image, ImageDraw
    w, h = a.size
    im = Image.new("RGB", (w * 2 + 8, h + 28), (16, 16, 20))
    im.paste(a, (0, 28))
    im.paste(b, (w + 8, 28))
    dr = ImageDraw.Draw(im)
    try:
        from PIL import ImageFont
        fnt = ImageFont.truetype(os.path.join(ROOT, "game", "fonts", "ui.ttf"), 18)
    except Exception:
        fnt = None
    dr.text((8, 4), la, fill=(230, 230, 230), font=fnt)
    dr.text((w + 16, 4), lb, fill=(230, 230, 230), font=fnt)
    im.save(out, optimize=True)


def main():
    from PIL import Image
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "assets", "late_read_b2"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rows = {}
    for tag, (_, _, targets) in R.CONFIGS.items():
        for t in targets:
            m = metrics(tag, _frame(t))
            if m is not None:
                rows["%s@%d" % (tag[1:], t)] = m
    json.dump(rows, open(os.path.join(a.out, "metrics.json"), "w"), ensure_ascii=False, indent=1)
    keys = ["enemies_on", "env_dim", "dl_n", "dl_ally", "dl_hit", "dl_foe", "friend_pct", "friend_luma_share", "friend_luma", "ground_luma", "contrast", "ring_pct", "frame_luma", "red_frame_pct"]
    print("配置@秒 | " + " | ".join(keys))
    for k, m in rows.items():
        print(k, "|", " | ".join(("%.3f" % m[x]) if isinstance(m.get(x), float) else str(m.get(x)) for x in keys))
    lab = {"_OFF": "全关", "_ON": "全开", "_V4": "只开 V4 照地光分账", "_V9": "只开 V9 地面光环只画边", "_V10": "只开 V10 拥挤压暗环境"}
    def img(tag, t):
        p = os.path.join(S.SHOT, "%s%s_s%d_full" % (R.OP, tag, R.SEED), "shot_%d.png" % _frame(t))
        return Image.open(p).convert("RGB") if os.path.exists(p) else None
    for t in [180, 480, 570]:
        x, y = img("_OFF", t), img("_ON", t)
        if x and y:
            side(x, y, "%d:%02d 全关" % (t // 60, t % 60), "%d:%02d 全开（V4 + V9 + V10）" % (t // 60, t % 60), os.path.join(a.out, "ab_all_%d.png" % t))
    for tag in ["_V4", "_V9", "_V10"]:
        x, y = img("_OFF", 480), img(tag, 480)
        if x and y:
            side(x, y, "8:00 全关", "8:00 " + lab[tag], os.path.join(a.out, "ab%s_480.png" % tag.lower()))


if __name__ == "__main__":
    main()
