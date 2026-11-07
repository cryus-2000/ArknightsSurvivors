# -*- coding: utf-8 -*-
"""分支成长节点卡面清点（docs/302，11-07）：列出 20 名干员的分支节点，卡面以前显示什么、现在显示什么。
现在的卡面行与 character.gd branch_lines() 同一规则：branch_desc 按「；」分段，段首是「路线名」就对上；
对不上 / 没写 branch_desc 时取该路线 desc 第一句兜底（表里「兜底」列标出）。以前的卡面：标题 = 节点名（就是第一条路线名），
手机 / 干员卡一句话 = branch_desc 第一段（choice_panel.brief 取到第一个「；」）。
用法：python tools/branch_card_audit.py [--md 输出.md]；有对不上的返回 1
"""
import argparse, glob, json, os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


SHORT = 16
CAP = 18


def _walk(t, k=None):
    n = i = 0
    while i < len(t) and (k is None or n < k):
        j = t.find("}", i)
        if t[i:i + 2] == "{$" and j > i:
            i, n = j + 1, n + 2
        else:
            i, n = i + 1, n + 1
    return n, i


def vis_len(t):
    return _walk(t)[0]


def vis_cut(t, k):
    return t[:_walk(t, k)[1]]


def lines_of(n, short=False):
    parts = [p.strip().rstrip("。") for p in str(n.get("branch_desc", "")).split("；") if p.strip()]
    out, fb = [], []
    for k, r in n.get("branch", {}).items():
        if not isinstance(r, dict):
            continue
        nm = str(r.get("name", k))
        tag = "「%s」" % nm
        eff = ""
        for p in parts:
            if p.startswith(tag):
                eff = p[len(tag):].strip()
                break
        if not eff:
            fb.append(nm)
            rd = str(r.get("desc", ""))
            eff = rd.split("。")[0].split("；")[0].strip() if rd else ""
            if eff.startswith(tag):
                eff = eff[len(tag):]
        eff = eff.lstrip("：").strip()
        if eff.startswith("使"):
            eff = eff[1:].strip()
        if short and vis_len(eff) > SHORT and eff.find("，") >= 6:
            eff = eff[:eff.find("，")]
        if short and vis_len(eff) > CAP:
            eff = vis_cut(eff, CAP - 1) + "…"
        out.append(tag + "：" + eff if eff else tag)
    return out, fb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--md", default="")
    a = ap.parse_args()
    rows, bad = [], []
    for f in sorted(glob.glob(os.path.join(ROOT, "game", "data", "characters", "*.json"))):
        d = json.load(open(f, encoding="utf-8"))
        nm = d.get("name", os.path.basename(f)[:-5])
        for i, n in enumerate(d.get("progression", [])):
            if not isinstance(n.get("branch"), dict):
                continue
            old_title = "%s · %s" % (nm, n.get("name", "培养路线"))
            old_face = str(n.get("branch_desc", "")).split("；")[0].strip()
            new, fb = lines_of(n)
            face, _ = lines_of(n, True)
            if not n.get("branch_desc"):
                bad.append("%s 节点 %d 没写 branch_desc" % (nm, i + 1))
            if fb:
                bad.append("%s 节点 %d 兜底：%s" % (nm, i + 1, "、".join(fb)))
            rows.append((nm, i + 1, old_title, old_face, "%s · 选择成长路线" % nm, " / ".join(face), " / ".join(new), "、".join(fb)))
    md = ["| 干员 | 节点 | 以前标题 | 以前卡面一句话 | 现在标题 | 现在卡面两行 | 现在详情两行 | 兜底 |", "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        md.append("| " + " | ".join(str(x).replace("|", "／") for x in r) + " |")
    text = "\n".join(md)
    print(text)
    print("\n共 %d 个分支节点；%s" % (len(rows), "全部按 branch_desc 对上" if not bad else "；".join(bad)))
    if a.md:
        open(a.md, "w", encoding="utf-8").write(text + "\n")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
