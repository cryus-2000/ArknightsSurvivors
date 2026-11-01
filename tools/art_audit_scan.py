# -*- coding: utf-8 -*-
"""美术巡检批量扫描（docs/214）。只读，不开 Godot，不改文件。
    python -X utf8 tools/art_audit_scan.py [--json build/art_audit/scan.json]
查：
    import   game/art 下的 PNG 没有 .import（导出包里不会有它）
    empty    整张全透明 / 尺寸为 0
    magenta  洋红抠图残留（不透明且 R、B ≥ 200、G ≤ 60）
    strip    帧条宽不是帧数的整数倍（干员 sprites / 敌人 / art.gd V6_FRAMES / FXF）
    blank    帧条里有全透明帧（死亡 / 消散末帧除外，只报中间帧）
    dup      帧条里连续两帧逐像素相同（卡帧），按条报数
    ref      数据 / 脚本里写死的贴图名在索引里找不到（含 @1x / @2x / 别名 / art/px）
    foot     干员待机帧不透明最低行与 sprites.foot 的脚底行差 > 2（1x 像素）
"""
import argparse
import glob
import json
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = os.path.join(ROOT, "game")
IDX = json.load(open(os.path.join(G, "art", "index.json"), encoding="utf-8"))


def res(p):
    return os.path.join(G, p[len("res://"):]) if p.startswith("res://") else p


def alias_table():
    src = open(os.path.join(G, "scripts", "art.gd"), encoding="utf-8").read()
    m = re.search(r"const ALIAS := \{(.*?)\n\}", src, re.S)
    return dict(re.findall(r'"([a-z0-9_]+)":\s*"([a-z0-9_]+)"', m.group(1))) if m else {}


ALIAS = alias_table()


def find(name):
    """名字 → 实际文件（优先 @1x、@2x、基础名、别名、art/px），找不到返回 None"""
    for n in (name + "@1x", name + "@2x", name):
        if n in IDX:
            return res(IDX[n])
        base = n.replace("@1x", "").replace("@2x", "")
        if base in ALIAS:
            al = ALIAS[base] + n[len(base):]
            if al in IDX:
                return res(IDX[al])
    px = os.path.join(G, "art", "px", name + ".png")
    return px if os.path.exists(px) else None


def load_rgba(p):
    return np.asarray(Image.open(p).convert("RGBA"))


def frames_of(a, n):
    h, w = a.shape[:2]
    fw = w // n
    return [a[:, i * fw:(i + 1) * fw] for i in range(n)]


def strip_issues(name, a, n, out, last_ok_blank=False):
    h, w = a.shape[:2]
    if n <= 0:
        return
    if w % n:
        out.append(("strip", name, "宽 %d 不是帧数 %d 的整数倍（%dx%d）" % (w, n, w, h)))
        return
    fr = frames_of(a, n)
    blank = [i for i, f in enumerate(fr) if not (f[..., 3] > 0).any()]
    if last_ok_blank:
        blank = [i for i in blank if i < n - 2]
    if blank:
        out.append(("blank", name, "全透明帧 %s / %d" % (blank, n)))
    dups = [i for i in range(1, n) if np.array_equal(fr[i], fr[i - 1])]
    if dups and len(dups) >= max(2, n // 3):
        out.append(("dup", name, "连续相同帧 %d 处 / %d 帧：%s" % (len(dups), n, dups[:8])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    args = ap.parse_args()
    out = []
    # ---- 逐张 PNG
    pngs = sorted(glob.glob(os.path.join(G, "art", "**", "*.png"), recursive=True))
    for p in pngs:
        rel = os.path.relpath(p, ROOT).replace("\\", "/")
        if not os.path.exists(p + ".import"):
            out.append(("import", rel, "没有 .import"))
        try:
            a = load_rgba(p)
        except Exception as e:
            out.append(("empty", rel, "读不出：%s" % e))
            continue
        if a.size == 0 or not (a[..., 3] > 0).any():
            out.append(("empty", rel, "整张全透明 %dx%d" % (a.shape[1], a.shape[0])))
            continue
        op = a[..., 3] > 200
        mg = op & (a[..., 0] >= 200) & (a[..., 2] >= 200) & (a[..., 1] <= 60)
        if mg.sum() >= 4:
            out.append(("magenta", rel, "洋红像素 %d" % int(mg.sum())))
    # ---- 干员帧条
    for cj in sorted(glob.glob(os.path.join(G, "data", "characters", "*.json"))):
        d = json.load(open(cj, encoding="utf-8"))
        oid = d["id"]
        sp = dict(d.get("sprites") or {})
        for k, v in sp.items():
            if not isinstance(v, dict) or "tex" not in v:
                continue
            for suf in ("@1x", "@2x"):
                nm = v["tex"] + suf
                p = res(IDX[nm]) if nm in IDX else None
                if p is None:
                    if suf == "@2x" and (v["tex"] + "@1x") not in IDX and v["tex"] not in IDX:
                        out.append(("ref", "%s.sprites.%s" % (oid, k), "%s 没有图" % v["tex"]))
                    continue
                a = load_rgba(p)
                n = int(v.get("frames", 1))
                strip_issues("%s %s%s" % (oid, k, suf), a, n, out, last_ok_blank=k in ("death", "die") or "vanish" in k or "end" in k)
                if k == "idle" and "foot" in v and suf == "@1x" and a.shape[1] % n == 0:
                    fy = int(v["foot"][1])
                    rows = [np.nonzero((f[..., 3] > 0).any(axis=1))[0] for f in frames_of(a, n)]
                    lows = [int(r.max()) for r in rows if len(r)]
                    if lows and abs(max(lows) - fy) > 2:
                        out.append(("foot", "%s idle@1x" % oid, "最低不透明行 %d，foot 行 %d" % (max(lows), fy)))
    # ---- art.gd 帧条表
    src = open(os.path.join(G, "scripts", "art.gd"), encoding="utf-8").read()
    tbl = {}
    m = re.search(r"const V6_FRAMES := \{(.*?)\n\}", src, re.S)
    if m:
        for nm, fr in re.findall(r'"([a-z0-9_/]+)":\s*\[(\d+)', m.group(1)):
            tbl[nm] = int(fr)
    m = re.search(r"const FXF := \{(.*?)\}", src, re.S)
    if m:
        for nm, fr in re.findall(r'"([a-z0-9_]+)":\s*(\d+)', m.group(1)):
            tbl[nm] = int(fr)
    for nm, n in sorted(tbl.items()):
        for suf in ("@2x", "@1x", ""):
            if (nm + suf) in IDX:
                strip_issues("art.gd %s%s" % (nm, suf), load_rgba(res(IDX[nm + suf])), n, out, last_ok_blank=True)
                break
    # ---- 写死的贴图名
    pat = re.compile(r'"((?:op|e|fx|proj|relic|skill|growth|evo|prop|ally|ui|ult|icon|portrait|terrain|tile)_[a-z0-9_]*[a-z0-9])"')
    refs = {}
    files = glob.glob(os.path.join(G, "data", "**", "*.json"), recursive=True) + glob.glob(os.path.join(G, "scripts", "**", "*.gd"), recursive=True)
    for f in files:
        txt = open(f, encoding="utf-8", errors="replace").read()
        for nm in pat.findall(txt):
            refs.setdefault(nm, set()).add(os.path.relpath(f, G).replace("\\", "/"))
    for nm, fs in sorted(refs.items()):
        if find(nm) is None:
            out.append(("ref?", nm, ", ".join(sorted(fs)[:4])))
    # ---- 汇总
    cnt = {}
    for k, _, _ in out:
        cnt[k] = cnt.get(k, 0) + 1
    for k, a, b in out:
        print("%-8s %s  %s" % (k, a, b))
    print("合计", cnt, "PNG", len(pngs))
    if args.json:
        os.makedirs(os.path.dirname(args.json), exist_ok=True)
        json.dump([{"k": k, "what": a, "note": b} for k, a, b in out], open(args.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
