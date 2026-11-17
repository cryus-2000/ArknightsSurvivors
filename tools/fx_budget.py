#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""每名干员特效预算（docs/368）：静态资源账 + 快检项 fx_budget。不开 Godot，约 1–2 秒。只量，不改特效。

  python tools/fx_budget.py scan [--md]   20 人 × 普攻 / 技能 / 终结技 / 连携 / 召唤 / 天赋 的帧条数、总帧数、显存、包体、音效；
                                          写 build/fx_budget/static.json，--md 另打印 docs/368 用的表
  python tools/fx_budget.py check         对照 tools/fx_budget.json：新干员超硬上限 = ERROR；现有 20 人只在比登记基线涨 > 10% 时 ERROR
                                          （现有超限只列不改，docs/368 §4，改不改用户定）；新干员缺 fx_elements 声明或某招元素 > 3 种 = ERROR

归属规则（tools/fx_budget_map.json）：
  - 转平面帧条 game/art/fx/pxp/pxp_<代号>_<键>.png（斯卡蒂无代号）→ 代号定人，「键干」查表定招（stems）；
    ult_sd/ 目录、pxp_ult_<代号>_* 归终结技；查不到的键按名字规则（lk/link → 连携，ult → 终结技，s1/s2/s3 → 技能，raw_ → 旧做法原样贴）
  - 旧帧条 game/art/fx/fx_<前缀>_*.png（含 _optical/）按 legacy 表定人和招；共用的（受击、预警、寻访界面…）不算进任何人
  - 音效 audio/sfx/op_<id>_* → 普攻 / 技能，ult_<id>_* → 终结技
显存 = PNG 宽 × 高 × 4（RGBA8、无 mipmap，导入设置 compress/mode=0 无损）；包体 = 导入后的 .ctex（game/.godot/imported，没有导入缓存时退回 PNG 大小）
"""
import glob, json, os, re, struct, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
MAP = os.path.join(ROOT, "tools", "fx_budget_map.json")
BUDGET = os.path.join(ROOT, "tools", "fx_budget.json")
OUT = os.path.join(ROOT, "build", "fx_budget")
CATS = ["atk", "skill", "ult", "link", "summon", "talent", "raw", "other"]
CAT_ZH = {"atk": "普攻", "skill": "技能", "ult": "终结技", "link": "连携", "summon": "召唤物", "talent": "天赋 / 成长", "raw": "原样贴备用", "other": "未归类"}
VAR_RE = re.compile(r"(_(e\d|d-?\d+(_5)?|dm\d+(_5)?|m\d+|a-?m?\d+|up|gd\d?|r\d+|z\d|v\d|s\d|h|q|n|m|l|bk|fr|b|f|1x|2x))+$")


def png_size(p):
    with open(p, "rb") as f:
        h = f.read(24)
    if h[:8] != b"\x89PNG\r\n\x1a\n":
        return 0, 0
    return struct.unpack(">II", h[16:24])


def ctex_size(png):
    imp = png + ".import"
    if os.path.exists(imp):
        m = re.search(r'dest_files=\["res://\.godot/imported/([^"]+)"', open(imp, encoding="utf-8", errors="ignore").read())
        if m:
            for base in (os.path.join(GAME, ".godot", "imported"), os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(ROOT))), "game", ".godot", "imported")):
                q = os.path.join(base, m.group(1))
                if os.path.exists(q):
                    return os.path.getsize(q), True
    return os.path.getsize(png), False


def norm_cat(c):
    return "skill" if c in ("s1", "s2", "s3") else c


def guess(stem):
    if re.search(r"(^|_)(lk|link)(_|$)", stem):
        return "link"
    if re.search(r"(^|_)ult", stem):
        return "ult"
    if stem.startswith("raw"):
        return "raw"
    if re.search(r"mon3tr|summon", stem):
        return "summon"
    if re.search(r"(^|_)s[123]", stem):
        return "skill"
    if re.search(r"(^|_)(atk|basic|hit|slash|bash|claw|arc|mz)(_|$)", stem):
        return "atk"
    return "other"


def frame_index():
    """帧条键 → 帧数（data/pxp_<人>.json 的 n；文件名带代号前缀的按后缀匹配）"""
    idx = {}
    for f in glob.glob(os.path.join(GAME, "data", "pxp_*.json")):
        for k, v in json.load(open(f, encoding="utf-8")).items():
            if not k.startswith("_") and isinstance(v, dict) and "n" in v:
                idx[k] = (int(v["n"]), int(v.get("w", 0)), int(v.get("h", 0)))
    return idx


def scan():
    mp = json.load(open(MAP, encoding="utf-8"))
    codes = mp["codes"]           # 代号 -> 干员
    stems = mp["stems"]           # 代号 -> {键干: 招}
    legacy = mp["legacy"]         # 旧帧条前缀 -> [干员, 招]
    ops = sorted(os.path.basename(p)[:-5] for p in glob.glob(os.path.join(GAME, "data", "characters", "*.json")))
    fidx = frame_index()
    acc = {o: {c: {"strips": 0, "frames": 0, "vram": 0, "pkg": 0, "png": 0, "sfx": 0, "max_strip_px": 0} for c in CATS} for o in ops}
    acc["_shared"] = {c: {"strips": 0, "frames": 0, "vram": 0, "pkg": 0, "png": 0, "sfx": 0, "max_strip_px": 0} for c in CATS}
    imported_all = True
    unk = {}

    def add(op, cat, p, frames):
        nonlocal imported_all
        w, h = png_size(p)
        pk, ok = ctex_size(p)
        imported_all &= ok
        a = acc.setdefault(op, {c: {"strips": 0, "frames": 0, "vram": 0, "pkg": 0, "png": 0, "sfx": 0, "max_strip_px": 0} for c in CATS})[cat]
        a["strips"] += 1
        a["frames"] += frames
        a["vram"] += w * h * 4
        a["pkg"] += pk
        a["png"] += os.path.getsize(p)
        a["max_strip_px"] = max(a["max_strip_px"], w * h)

    sorted_codes = sorted(codes, key=len, reverse=True)
    for p in glob.glob(os.path.join(GAME, "art", "fx", "pxp", "**", "*.png"), recursive=True):
        name = os.path.basename(p)[:-4]
        sub = os.path.basename(os.path.dirname(p))
        key = name[4:] if name.startswith("pxp_") else name
        if sub != "pxp":   # ult_sd/ 等子目录：整目录归某人的终结技
            op, cat = mp["dirs"].get(sub, ["_shared", "other"])
            n = fidx.get(key, (0,))[0]
            w, h = png_size(p)
            add(op, cat, p, n or max(1, round(w / max(1, h))))
            continue
        code, rest = "", key
        for c in sorted_codes:
            if c and key.startswith(c + "_"):
                code, rest = c, key[len(c) + 1:]
                break
        op = codes.get(code, "_shared")
        stem = re.sub(r"_r\d+", "", VAR_RE.sub("", rest))
        cat = stems.get(code, {}).get(stem)
        if cat is None and code == "":
            op = "_unregistered"   # 斯卡蒂的帧条没前缀；不在她键干表里的无前缀帧条 = 没登记代号的新帧条（快检报错）
        if cat is None:
            cat = guess(stem)
            unk.setdefault(op, set()).add(key if op == "_unregistered" else stem)
        n = fidx.get(key, fidx.get(rest, (0,)))[0]
        if not n:
            w, h = png_size(p)
            n = max(1, round(w / max(1, h)))   # 没登记帧数的：按方形帧估
        add(op, norm_cat(cat), p, n)

    for p in glob.glob(os.path.join(GAME, "art", "fx", "*.png")) + glob.glob(os.path.join(GAME, "art", "fx", "_optical", "*.png")) + glob.glob(os.path.join(GAME, "art", "fx", "proj", "*.png")):
        name = os.path.basename(p)
        hit = None
        for pre in sorted(legacy, key=len, reverse=True):
            if name.startswith(pre + "_") or name.startswith(pre + "@") or name[:-4] == pre:
                hit = legacy[pre]
                break
        op, cat = hit if hit else ["_shared", "other"]
        op = "_shared" if op == "shared" else op
        w, h = png_size(p)
        add(op, norm_cat(cat), p, max(1, round(w / max(1, h))))

    for p in glob.glob(os.path.join(GAME, "audio", "sfx", "*.*")):
        if p.endswith(".import"):
            continue
        n = os.path.basename(p)
        for o in ops:
            if n.startswith("op_%s_" % o):
                acc[o]["skill" if re.search(r"_s\d", n) else "atk"]["sfx"] += os.path.getsize(p)
            elif n.startswith("ult_%s_" % o):
                acc[o]["ult"]["sfx"] += os.path.getsize(p)

    res = {"imported": imported_all, "ops": {}, "unknown_stems": {k: sorted(v) for k, v in unk.items()}}
    for o, d in acc.items():
        tot = {k: sum(d[c][k] for c in CATS) for k in ("strips", "frames", "vram", "pkg", "png", "sfx")}
        tot["max_strip_px"] = max(d[c]["max_strip_px"] for c in CATS)
        res["ops"][o] = {"cats": d, "total": tot}
    return res


MB = 1024 * 1024


def summary_rows(res):
    rows = []
    for o, d in sorted(res["ops"].items()):
        if o.startswith("_"):
            continue
        c, t = d["cats"], d["total"]
        rows.append({"op": o,
                     "strips": t["strips"], "frames": t["frames"], "vram_mb": t["vram"] / MB, "pkg_mb": t["pkg"] / MB, "sfx_mb": t["sfx"] / MB,
                     "atk_mb": c["atk"]["pkg"] / MB, "skill_mb": c["skill"]["pkg"] / MB, "ult_mb": c["ult"]["pkg"] / MB,
                     "link_mb": c["link"]["pkg"] / MB, "summon_mb": c["summon"]["pkg"] / MB, "raw_mb": c["raw"]["pkg"] / MB,
                     "other_mb": (c["talent"]["pkg"] + c["other"]["pkg"]) / MB,
                     "atk_vram": c["atk"]["vram"] / MB, "skill_vram": c["skill"]["vram"] / MB, "ult_vram": c["ult"]["vram"] / MB,
                     "atk_strips": c["atk"]["strips"], "skill_strips": c["skill"]["strips"], "ult_strips": c["ult"]["strips"],
                     "max_strip_kpx": t["max_strip_px"] / 1000})
    return rows


def md(res):
    rows = summary_rows(res)
    cols = [("op", "干员"), ("strips", "帧条"), ("frames", "总帧"), ("vram_mb", "显存"), ("pkg_mb", "包体"), ("sfx_mb", "音效"),
            ("atk_mb", "普攻"), ("skill_mb", "技能"), ("ult_mb", "终结技"), ("link_mb", "连携"), ("summon_mb", "召唤"), ("raw_mb", "原样贴"), ("other_mb", "其他"),
            ("max_strip_kpx", "最大单条 k像素")]
    out = ["| " + " | ".join(z for _, z in cols) + " |", "|" + "---|" * len(cols)]
    import statistics as st
    for r in rows:
        out.append("| " + " | ".join(("%.2f" % r[k]) if isinstance(r[k], float) else str(r[k]) for k, _ in cols) + " |")
    for lab, fn in (("最小", min), ("中位", st.median), ("最大", max)):
        out.append("| **%s** | " % lab + " | ".join(("%.2f" % fn([r[k] for r in rows])) for k, _ in cols[1:]) + " |")
    return "\n".join(out)


def pct(xs, q):
    xs = sorted(xs)
    if not xs:
        return 0
    i = (len(xs) - 1) * q
    lo = int(i)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (i - lo)


def op_vals(d):
    """一名干员的预算项（与 tools/fx_budget.json static.hard / baseline 同名）"""
    t = d["total"]
    vals = {"total_pkg_mb": t["pkg"] / MB, "total_vram_mb": t["vram"] / MB, "total_strips": t["strips"], "total_frames": t["frames"],
            "total_sfx_mb": t["sfx"] / MB, "max_strip_kpx": t["max_strip_px"] / 1000}
    for c in ("atk", "skill", "ult", "link", "summon"):
        x = d["cats"][c]
        vals["%s_pkg_mb" % c] = x["pkg"] / MB
        vals["%s_vram_mb" % c] = x["vram"] / MB
        vals["%s_strips" % c] = x["strips"]
        vals["%s_max_strip_kpx" % c] = x["max_strip_px"] / 1000
    return vals


def write_baseline():
    """把现有干员的当前值记成基线（docs/368 §4：现有干员只许持平或变小；用户批准加量后重跑这一步）"""
    b = json.load(open(BUDGET, encoding="utf-8"))
    res = scan()
    b["static"]["baseline"] = {o: {k: round(v, 3) for k, v in op_vals(d).items()} for o, d in sorted(res["ops"].items()) if not o.startswith("_")}
    json.dump(b, open(BUDGET, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
    return len(b["static"]["baseline"])


def check():
    """快检项：返回 (errors, detail)"""
    if not os.path.exists(BUDGET) or not os.path.exists(MAP):
        return ["缺 tools/fx_budget.json 或 fx_budget_map.json"], ""
    b = json.load(open(BUDGET, encoding="utf-8"))
    res = scan()
    errs, warns = [], []
    hard = b["static"]["hard"]
    base = b["static"]["baseline"]
    grow = b["static"].get("baseline_grow", 1.10)
    for o, d in sorted(res["ops"].items()):
        if o.startswith("_"):
            continue
        vals = op_vals(d)
        if o in base:
            for k, v in vals.items():
                ref = base[o].get(k)
                if ref is not None and v > max(ref * grow, ref + (0.05 if k.endswith("_mb") else 3)):
                    errs.append("%s %s %.2f 比登记基线 %.2f 涨了 %d%%（docs/368：现有干员只许持平或变小；确要加，先报用户并更新基线）" % (o, k, v, ref, round(100 * (v / max(1e-9, ref) - 1))))
        else:
            for k, v in vals.items():
                if k in hard and v > hard[k]:
                    errs.append("%s %s %.2f > 硬上限 %s（docs/368 速查表）" % (o, k, v, hard[k]))
            # 新干员：要在角色表里声明每招元素种类（≤3）
            cj = os.path.join(GAME, "data", "characters", o + ".json")
            el = json.load(open(cj, encoding="utf-8")).get("fx_elements") if os.path.exists(cj) else None
            if d["total"]["strips"] == 0 and not el:
                continue   # 还没做特效（只有设计稿 / 积木）：不查声明
            if not isinstance(el, dict) or not el:
                errs.append("%s 缺 fx_elements 声明（data/characters/%s.json，每招列出元素种类，≤3 种，docs/368 §3）" % (o, o))
            else:
                for mv, lst in el.items():
                    if mv.startswith("_"):
                        continue
                    if not isinstance(lst, list) or len(lst) > b["visual"]["elements_per_move_max"]:
                        errs.append("%s fx_elements.%s 有 %s 种元素 > %d（docs/368 §3）" % (o, mv, len(lst) if isinstance(lst, list) else "?", b["visual"]["elements_per_move_max"]))
    un = res["unknown_stems"].get("_unregistered", [])
    if un:
        errs.append("%d 张转平面帧条没登记归属（前缀不在 tools/fx_budget_map.json 的 codes 里），例如 %s（docs/368 §5：新干员先登记代号与键干）" % (len(un), ", ".join(un[:4])))
    n_new = len([o for o in res["ops"] if not o.startswith("_") and o not in base])
    detail = "%d 名干员（新 %d 名按硬上限、现有按基线 +%d%%）；%s" % (len([o for o in res["ops"] if not o.startswith("_")]), n_new, round(100 * (grow - 1)),
                                                     "包体按导入缓存" if res["imported"] else "无完整导入缓存，包体按 PNG 估")
    return errs, detail


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if cmd == "scan":
        res = scan()
        os.makedirs(OUT, exist_ok=True)
        json.dump(res, open(os.path.join(OUT, "static.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        if "--md" in sys.argv:
            print(md(res))
        else:
            for r in summary_rows(res):
                print("%-18s 帧条 %4d  帧 %5d  显存 %6.2f MB  包体 %5.2f MB  终结技 %5.2f  音效 %4.2f" % (r["op"], r["strips"], r["frames"], r["vram_mb"], r["pkg_mb"], r["ult_mb"], r["sfx_mb"]))
            sh = res["ops"]["_shared"]["total"]
            print("共用（不归任何人）：帧条 %d  包体 %.2f MB" % (sh["strips"], sh["pkg"] / MB))
            print("导入缓存齐全" if res["imported"] else "注意：部分包体按 PNG 估（没有导入缓存）")
        return 0
    if cmd == "baseline":
        print("基线已写入 tools/fx_budget.json：%d 名干员" % write_baseline())
        return 0
    if cmd == "over":   # 现有干员超硬上限的项（docs/368 §4 的清单）
        b = json.load(open(BUDGET, encoding="utf-8"))
        hard = b["static"]["hard"]
        for o, d in sorted(scan()["ops"].items()):
            if o.startswith("_"):
                continue
            v = op_vals(d)
            bad = ["%s %.2f > %s" % (k, v[k], hard[k]) for k in hard if k in v and v[k] > hard[k]]
            if bad:
                print("%-18s %s" % (o, "；".join(bad)))
        return 0
    if cmd == "check":
        errs, detail = check()
        print(detail)
        for e in errs:
            print("ERROR", e)
        return 1 if errs else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
