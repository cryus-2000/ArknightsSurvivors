#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""同种子配对对比 + 多指标报告（docs/80_ab_method.md）。

读两组或多组 balance_run 结果，第一组是基准 A，其余每组各与 A 按（开局编队, seed, 机器人, 难度, 档位 tier, 流派）配对：
  - 每组：胜率 + Wilson 95% 区间；用时、每秒伤害、各 Boss 击杀用时、低血秒、承伤、治疗量的中位数 + bootstrap 95% 区间；
          输局死在第几分钟（超时单列）
  - 配对：两边都赢 / 都输 / 只 A 赢 / 只 B 赢，McNemar 精确检验 p 值，胜率差的配对 bootstrap 区间；
          连续指标的逐对差（B − A）中位数与 bootstrap 95% 区间
  - 结论一句：显著 / 不显著，以及「要把胜率差的 95% 区间收到 ±5 点大约要多少对」
  - 配不上对的局（某组缺这个 seed / 编队）报告数量

来源写法（每个位置参数是一组；「名字=来源」可自定组名；同一组多个来源用 + 连接）：
    ru-uncap-t0                     origin/cloud-results/ru-uncap-t0 分支里 build/cloud/**.json（本地没有该远程分支时自动 fetch）
    cloud:ru-uncap-t0               同上，显式写法
    build/balance                   本地目录：递归读其中所有带 records 的 json（balance_run 的 --out 目录）
    build/balance/x_1012_0606.json  单个 json 文件
    基线=ls-base-t0+ls-main-t2      自定组名，并把两个来源合成一组

用法示例（仓库根目录）：
    python tools/cloud_compare.py ru-cap15-t0 ru-uncap-t0
    python tools/cloud_compare.py 旧=ls-base-t0 新=ls-l1-t0 --bot expert
    python tools/cloud_compare.py build/balance/before_1012_0900.json build/balance/after_1012_1000.json
    python tools/cloud_compare.py md-t0 --split squad          # 一组结果按编队拆成多组，同 seed 配对（固定队友只换一人的对照）
    python tools/cloud_compare.py 流明=md-lumen 凯尔希=md-kaltsit --ignore squad   # 每个编队单独一个 tag 时
    python tools/cloud_compare.py a b c --out build/ab.md --json build/ab.json
    python tools/cloud_compare.py --fetch ru-cap15-t2 ru-uncap-t2  # 先强制 fetch 一遍 cloud-results/*

只读结果，不跑游戏。bootstrap 用固定种子（--boot-seed），同样输入同样输出。
"""
import argparse, glob, json, math, os, random, statistics, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
Z = 1.959964
KEY_FIELDS = ["squad", "seed", "bot", "diff", "tier", "lane", "placebo"]
SPLIT_FIELDS = ["squad", "bot", "diff", "tier", "lane"]
PHASE_NAMES = ["Boss1", "Boss2", "终局Boss"]


# ---------------------------------------------------------------- 读取

def git(*a, check=False):
    p = subprocess.run(["git"] + list(a), cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if check and p.returncode != 0:
        raise RuntimeError("git %s 失败：%s" % (" ".join(a), p.stderr.strip()[:300]))
    return p


def fetch_all():
    git("fetch", "-q", "origin", "refs/heads/cloud-results/*:refs/remotes/origin/cloud-results/*")


def _parse_extra(extra):
    out = {}
    for tok in (extra or "").split():
        if tok.startswith("--") and "=" in tok:
            k, v = tok[2:].split("=", 1)
            out[k] = v
    return out


def _ingest(doc, origin, env=""):
    """一个 balance_run json → 记录列表；每条带上 tier / maxt / 来源"""
    args = doc.get("args", {}) or {}
    ex = _parse_extra(args.get("extra", ""))
    tier = ex.get("tier", "")
    maxt = float(ex.get("maxt", 780))
    recs = []
    for r in doc.get("records", []):
        r = dict(r)
        r["_tier"] = tier
        r.setdefault("placebo", int(ex.get("placebo", 0) or 0))   # 安慰剂实现（docs/36 §8.2）；旧记录没有这一项按 0
        r["_maxt"] = maxt
        r["_src"] = origin
        r["_env"] = env
        recs.append(r)
    return recs, args


def load_cloud(tag):
    ref = "origin/cloud-results/" + tag
    if git("rev-parse", "--verify", "-q", ref).returncode != 0:
        git("fetch", "-q", "origin", "refs/heads/cloud-results/%s:refs/remotes/%s" % (tag, ref))
        if git("rev-parse", "--verify", "-q", ref).returncode != 0:
            raise RuntimeError("找不到 %s（origin 上没有 cloud-results/%s）" % (ref, tag))
    files = git("ls-tree", "-r", "--name-only", ref, "--", "build/cloud", check=True).stdout.split()
    env = ""
    envs = [f for f in files if f.endswith("env.txt")]
    if envs:
        env = git("show", "%s:%s" % (ref, envs[0])).stdout.strip().splitlines()[0:1]
        env = env[0] if env else ""
    recs, metas = [], []
    for f in files:
        if not f.endswith(".json"):
            continue
        try:
            doc = json.loads(git("show", "%s:%s" % (ref, f), check=True).stdout or "{}")
        except (json.JSONDecodeError, RuntimeError):
            continue
        if isinstance(doc, dict) and "records" in doc:
            rs, a = _ingest(doc, "%s:%s" % (tag, os.path.basename(f)), env)
            recs += rs
            metas.append(a)
    if not recs:
        raise RuntimeError("%s 里没有带 records 的 json" % ref)
    return recs, metas, env


def load_path(path):
    files = [path] if os.path.isfile(path) else sorted(glob.glob(os.path.join(path, "**", "*.json"), recursive=True))
    recs, metas = [], []
    env = ""
    if os.path.isdir(path):
        ef = os.path.join(path, "env.txt")
        if os.path.exists(ef):
            env = (open(ef, encoding="utf-8", errors="replace").read().strip().splitlines() or [""])[0]
    for f in files:
        try:
            doc = json.load(open(f, encoding="utf-8"))
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            continue
        if isinstance(doc, dict) and "records" in doc:
            rs, a = _ingest(doc, os.path.relpath(f, ROOT) if f.startswith(ROOT) else f, env)
            recs += rs
            metas.append(a)
    if not recs:
        raise RuntimeError("%s 里没有带 records 的 json" % path)
    return recs, metas, env


def load_source(spec):
    name, src = spec.split("=", 1) if "=" in spec else (None, spec)
    recs, metas, envs = [], [], []
    for part in src.split("+"):
        if part.startswith("cloud:"):
            r, m, e = load_cloud(part[6:])
        elif os.path.exists(part) or os.path.exists(os.path.join(ROOT, part)):
            r, m, e = load_path(part if os.path.exists(part) else os.path.join(ROOT, part))
        else:
            r, m, e = load_cloud(part)
        recs += r; metas += m
        if e:
            envs.append(e[:10])
    return (name or src), recs, metas, envs


# ---------------------------------------------------------------- 指标

def rec_key(r, drop=()):
    v = {"squad": ",".join(r.get("squad", [])), "seed": r.get("seed"), "bot": r.get("bot", "normal"), "diff": r.get("diff", 0),
         "tier": r.get("_tier", ""), "lane": r.get("lane", "none"), "placebo": r.get("placebo", 0)}
    return tuple(v[k] for k in KEY_FIELDS if k not in drop)


def _phase(bo):
    t0 = bo.get("t0", 0)
    return 0 if t0 < 300 else (1 if t0 < 540 else 2)


def metrics(r):
    """一局 → 指标字典；没有的指标为 None"""
    d = r["data"]
    t = float(d.get("t", 0) or 0)
    b = d.get("bot", {}) or {}
    out = sum((d.get("out") or {}).values())
    taken = b.get("taken")
    if taken is None:
        taken = sum((d.get("dmg") or {}).values())
    m = {
        "win": 1.0 if d.get("win") else 0.0,
        "t": t,
        "dps": out / t if t > 0 else None,
        "low_hp_s": float(b["low_hp_s"]) if "low_hp_s" in b else None,
        "low_hp_pct": (100.0 * float(b["low_hp_s"]) / t) if ("low_hp_s" in b and t > 0) else None,
        "taken": float(taken),
        "taken_pm": float(taken) / t * 60.0 if t > 0 else None,
        "heal": float(sum((d.get("heal") or {}).values())),
    }
    # Boss 按出场分段；击杀记 t1 − t0，终局 Boss 在胜利的局按「出现 → 通关」计（同 balance_run.lane_summary）
    for k in range(3):
        m["boss%d" % k] = None
        m["boss%d_seen" % k] = 0
    for bo in b.get("bosses", []):
        k = _phase(bo)
        if m["boss%d_seen" % k]:
            continue   # 同一段两个 Boss（如主教 + 蔑死体）只取第一个，配对时口径一致
        m["boss%d_seen" % k] = 1
        if bo.get("t1", -1) >= 0:
            m["boss%d" % k] = float(bo["t1"] - bo["t0"])
        elif k == 2 and d.get("win"):
            m["boss%d" % k] = float(t - bo["t0"])
    timeout = (not d.get("win")) and t >= r.get("_maxt", 780) - 1
    m["timeout"] = timeout
    m["death_min"] = int(t // 60) if (not d.get("win") and not timeout) else None
    return m


CONT = [  # (键, 名称, 格式, 方向：+1 越大越好 / −1 越小越好 / 0 不评)
    ("t", "用时（秒）", "%.0f", 0),
    ("dps", "每秒伤害", "%.0f", 1),
    ("boss0", "Boss1 击杀用时（秒）", "%.0f", -1),
    ("boss1", "Boss2 击杀用时（秒）", "%.0f", -1),
    ("boss2", "终局 Boss 击杀用时（秒）", "%.0f", -1),
    ("low_hp_s", "低血秒（生命 <35%）", "%.0f", -1),
    ("low_hp_pct", "低血占比 %", "%.1f", -1),
    ("taken", "承伤", "%.0f", -1),
    ("taken_pm", "承伤 / 分", "%.0f", -1),
    ("heal", "治疗量", "%.0f", 0),
]


# ---------------------------------------------------------------- 统计

def wilson(k, n, z=Z):
    if n == 0:
        return (0.0, 0.0, 1.0)
    p = k / n
    den = 1 + z * z / n
    c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return (p, max(0.0, c - h), min(1.0, c + h))


def mcnemar_exact(b, c):
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    s = sum(math.comb(n, i) for i in range(k + 1)) / (2 ** n)
    return min(1.0, 2 * s)


def boot_ci(xs, stat, rng, n_boot):
    if not xs:
        return (None, None, None)
    v = stat(xs)
    if len(xs) == 1:
        return (v, v, v)
    bs = sorted(stat([xs[rng.randrange(len(xs))] for _ in xs]) for _ in range(n_boot))
    return (v, bs[int(0.025 * n_boot)], bs[min(n_boot - 1, int(0.975 * n_boot))])


def mean(xs):
    return sum(xs) / len(xs)


def n_for_halfwidth(var, hw=0.05):
    return int(math.ceil(Z * Z * var / (hw * hw))) if var > 0 else 0


# ---------------------------------------------------------------- 报告

def fmt_ci(v, lo, hi, f):
    if v is None:
        return "-"
    return ("%s [%s, %s]" % (f, f, f)) % (v, lo, hi)


def group_section(name, recs, rng, n_boot):
    ms = [metrics(r) for r in recs]
    n = len(ms)
    k = int(sum(m["win"] for m in ms))
    p, lo, hi = wilson(k, n)
    lines = ["| 指标 | 中位 / 胜率 | 95% 区间 | 均值 | 样本 |", "|---|---|---|---|---|",
             "| 胜率 | %.1f%%（%d/%d） | [%.1f%%, %.1f%%]（Wilson，±%.1f 点） | - | %d |" % (100 * p, k, n, 100 * lo, 100 * hi, 50 * (hi - lo), n)]
    summ = {"n": n, "wins": k, "win": p, "win_ci": [lo, hi], "metrics": {}}
    for key, label, f, _ in CONT:
        xs = [m[key] for m in ms if m[key] is not None]
        v, a, b = boot_ci(xs, statistics.median, rng, n_boot)
        extra = ""
        if key.startswith("boss"):
            seen = sum(m[key + "_seen"] for m in ms)
            extra = "（击杀 %d / 出场 %d）" % (len(xs), seen)
        mu = mean(xs) if xs else None
        lines.append("| %s | %s | %s | %s | %d%s |" % (label, (f % v) if v is not None else "-",
                                                       ("[%s, %s]" % (f, f)) % (a, b) if v is not None else "-",
                                                       (f % mu) if mu is not None else "-", len(xs), extra))
        summ["metrics"][key] = {"median": v, "ci": [a, b], "mean": mu, "n": len(xs)}
    dm = [m["death_min"] for m in ms if m["death_min"] is not None]
    to = sum(1 for m in ms if m["timeout"])
    hist = {}
    for x in dm:
        hist[x] = hist.get(x, 0) + 1
    hs = "  ".join("%d 分 ×%d" % (x, hist[x]) for x in sorted(hist)) or "无"
    lines.append("")
    lines.append("单组胜率要到 ±5 点（Wilson 近似）约需 %d 局。" % n_for_halfwidth(max(p * (1 - p), 0.01)))
    lines.append("输局死亡时间（第几分钟，0 起算）：%s%s" % (hs, "；超时未分胜负 %d 局" % to if to else ""))
    summ["death_min"] = hist
    summ["timeout"] = to
    return "\n".join(lines), summ


def pair_section(nameA, nameB, A, B, drop, rng, n_boot, hw):
    ka = {}
    for r in A:
        ka[rec_key(r, drop)] = r
    kb = {}
    for r in B:
        kb[rec_key(r, drop)] = r
    common = sorted(set(ka) & set(kb), key=str)
    onlyA = len(set(ka) - set(kb))
    onlyB = len(set(kb) - set(ka))
    res = {"A": nameA, "B": nameB, "pairs": len(common), "unpaired_A": onlyA, "unpaired_B": onlyB}
    L = ["### %s 对 %s（B − A）" % (nameB, nameA), ""]
    L.append("配对 %d 局；配不上对：只在 A %d 局、只在 B %d 局。" % (len(common), onlyA, onlyB))
    if not common:
        L.append("\n**没有可配对的局**（检查两组的 seed / 开局 / 机器人 / tier 是否一致，或用 --loose）。")
        return "\n".join(L), res
    mA = {k: metrics(ka[k]) for k in common}
    mB = {k: metrics(kb[k]) for k in common}
    ww = sum(1 for k in common if mA[k]["win"] and mB[k]["win"])
    ll = sum(1 for k in common if not mA[k]["win"] and not mB[k]["win"])
    oa = sum(1 for k in common if mA[k]["win"] and not mB[k]["win"])
    ob = sum(1 for k in common if not mA[k]["win"] and mB[k]["win"])
    n = len(common)
    pv = mcnemar_exact(oa, ob)
    diffs = [mB[k]["win"] - mA[k]["win"] for k in common]
    dw, dlo, dhi = boot_ci(diffs, mean, rng, n_boot)
    pa = sum(mA[k]["win"] for k in common) / n
    pb = sum(mB[k]["win"] for k in common) / n
    var_d = (oa + ob) / n - ((ob - oa) / n) ** 2
    if var_d <= 0:
        var_d = 1.0 / n   # 一个不一致对都没有时按最乐观的 1 对估，避免给出 0
    need_pairs = n_for_halfwidth(var_d, hw)
    var_unp = max(pa * (1 - pa), 0.0) + max(pb * (1 - pb), 0.0)
    need_unp = n_for_halfwidth(var_unp, hw)
    L += ["", "| | 局数 |", "|---|---|",
          "| 两边都赢 | %d |" % ww, "| 两边都输 | %d |" % ll, "| 只 A 赢 | %d |" % oa, "| 只 B 赢 | %d |" % ob, "",
          "配对内胜率：A %.1f%% → B %.1f%%，差 %+.1f 点，配对 bootstrap 95%% 区间 [%+.1f, %+.1f]；McNemar 精确检验 p = %.3g。" % (
              100 * pa, 100 * pb, 100 * dw, 100 * dlo, 100 * dhi, pv), ""]
    sig_of = lambda r: (r["data"].get("win"), r["data"].get("t"), r["data"].get("kills"), round(sum((r["data"].get("out") or {}).values())))
    same = sum(1 for k in common if sig_of(ka[k]) == sig_of(kb[k]))
    L.append("其中胜负、用时、击杀、总伤害都相同 %d 对（改动没影响到这些局；差的中位数常因此为 0，看均值差与区间）。" % same)
    L.append("")
    L += ["| 指标（逐对 B − A） | 差的中位 | 95% 区间 | 均值差 | 95% 区间 | 对数 | 判断 |", "|---|---|---|---|---|---|---|"]
    res.update({"identical": same, "both_win": ww, "both_lose": ll, "only_A": oa, "only_B": ob, "mcnemar_p": pv,
                "win_A": pa, "win_B": pb, "win_diff": dw, "win_diff_ci": [dlo, dhi], "need_pairs_pm%d" % int(hw * 100): need_pairs,
                "need_unpaired_per_group_pm%d" % int(hw * 100): need_unp, "metrics": {}})
    sig_metrics = []
    for key, label, f, direction in CONT:
        ds = [mB[k][key] - mA[k][key] for k in common if mA[k][key] is not None and mB[k][key] is not None]
        v, a, b = boot_ci(ds, statistics.median, rng, n_boot)
        mu, ma, mb = boot_ci(ds, mean, rng, n_boot)
        judge = "-"
        if v is not None and len(ds) < 10:
            judge = "对数太少"
        elif v is not None:
            # 中位差或均值差的区间有一个不含 0 就算有差别（中位差常被完全相同的对压成 0）
            hit = None
            if a > 0 or b < 0:
                hit = v
            elif ma > 0 or mb < 0:
                hit = mu
            if hit is not None:
                good = (hit > 0) == (direction > 0) if direction else None
                judge = "B 更好" if good is True else ("B 更差" if good is False else ("B 更大" if hit > 0 else "B 更小"))
                sig_metrics.append("%s %s" % (label, judge))
            else:
                judge = "区间含 0"
        sf = "%+" + f[1:]
        L.append("| %s | %s | %s | %s | %s | %d | %s |" % (label, sf % v if v is not None else "-",
                                                          ("[" + sf + ", " + sf + "]") % (a, b) if v is not None else "-",
                                                          sf % mu if mu is not None else "-",
                                                          ("[" + sf + ", " + sf + "]") % (ma, mb) if mu is not None else "-", len(ds), judge))
        res["metrics"][key] = {"median_diff": v, "ci": [a, b], "mean_diff": mu, "mean_ci": [ma, mb], "n": len(ds)}
    sig = pv < 0.05
    if sig:
        verdict = "胜率差 %+.1f 点，**显著**（McNemar p = %.3g < 0.05）" % (100 * dw, pv)
    else:
        verdict = "胜率差 %+.1f 点，**不显著**（McNemar p = %.3g）" % (100 * dw, pv)
        if abs(dw) < 0.10:
            verdict += "，差距不到 10 点，不下结论"
    half = 50 * (dhi - dlo)
    more = max(0, need_pairs - n)
    if oa + ob == 0:
        verdict += "。两边胜负逐对一致，没有不一致的对，下面的所需对数按「假设有 1 个不一致对」估，只是下限"
    verdict += "。现有 %d 对，胜率差区间半宽约 ±%.1f 点；要到 ±%d 点约需 %d 对（%s）" % (
        n, half, int(hw * 100), need_pairs, ("还差约 %d 对" % more) if more else "已够")
    verdict += "，不配对的话每组约需 %d 局。" % need_unp
    if sig_metrics:
        verdict += " 连续指标配对差区间不含 0：" + "、".join(sig_metrics) + "。"
        if len(sig_metrics) == 1:
            verdict += "（%d 项指标里偶然有 1 项区间不含 0 是常事，单项不作结论，要复跑或加局确认）" % len(CONT)
    else:
        verdict += " 连续指标的配对差区间都含 0。"
    L += ["", "**结论**：" + verdict]
    res["significant"] = sig
    res["verdict"] = verdict
    return "\n".join(L), res


def main():
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0], epilog=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="+", help="组来源：cloud-results 的 tag、cloud:<tag>、本地目录或 json；可写 名字=来源，多个来源用 + 连接")
    ap.add_argument("--split", choices=SPLIT_FIELDS, default=None, help="把（合并后的）结果按该字段拆成多组再配对，配对键里去掉该字段（例：--split squad 做固定队友对照）")
    ap.add_argument("--base", default=None, help="--split 时作为基准 A 的那一组的值（例：wisadel,skalter,lumen）；缺省为第一组")
    ap.add_argument("--bot", default=None, help="只看这一档机器人")
    ap.add_argument("--squad", default=None, help="只看这些开局（逗号分隔开局干员 id，匹配编队第一位）")
    ap.add_argument("--loose", action="store_true", help="配对只按 编队 + seed（忽略难度 / tier / 机器人 / 流派），两组档位不同时用")
    ap.add_argument("--ignore", default="", help="配对键里去掉这些字段（逗号分隔，可选 squad,bot,diff,tier,lane）；例：两组编队不同、要按 seed 配对时 --ignore squad")
    ap.add_argument("--fetch", action="store_true", help="先 git fetch 全部 cloud-results/*")
    ap.add_argument("--boot", type=int, default=2000, help="bootstrap 重抽次数（缺省 2000）")
    ap.add_argument("--boot-seed", type=int, default=12345)
    ap.add_argument("--hw", type=float, default=5.0, help="目标精度：胜率差 95%% 区间半宽（百分点，缺省 5）")
    ap.add_argument("--no-groups", action="store_true", help="不打印每组的多指标表，只打印配对结果")
    ap.add_argument("--out", default=None, help="同时把报告写到这个 .md")
    ap.add_argument("--json", default=None, help="把数字结果写成 json")
    a = ap.parse_args()
    if a.fetch:
        fetch_all()
    rng = random.Random(a.boot_seed)
    hw = a.hw / 100.0

    groups = []   # (名字, 记录, 说明)
    bad_total = 0
    for spec in a.groups:
        name, recs, metas, envs = load_source(spec)
        ok = [r for r in recs if "data" in r and not r.get("script_errors")]
        bad = len(recs) - len(ok)
        bad_total += bad
        if a.bot:
            ok = [r for r in ok if r.get("bot", "normal") == a.bot]
        if a.squad:
            want = set(a.squad.split(","))
            ok = [r for r in ok if r.get("squad", [""])[0] in want]
        extras = sorted({m.get("extra", "") or "" for m in metas})
        note = "提交 %s；extra `%s`%s" % ("/".join(sorted(set(envs))) or "?", " | ".join(extras),
                                          "；剔除无数据 / 脚本错误 %d 局" % bad if bad else "")
        groups.append((name, ok, note))

    drop = set()
    if a.loose:
        drop |= {"diff", "tier", "bot", "lane"}
    for f in [x for x in a.ignore.split(",") if x]:
        if f not in SPLIT_FIELDS:
            ap.error("--ignore 只能是 %s" % ",".join(SPLIT_FIELDS))
        drop.add(f)
    if a.split:
        allr = [r for g in groups for r in g[1]]
        notes = "；".join("%s：%s" % (g[0], g[2]) for g in groups)
        by = {}
        for r in allr:
            v = {"squad": ",".join(r.get("squad", [])), "bot": r.get("bot", "normal"), "diff": str(r.get("diff", 0)),
                 "tier": r.get("_tier", ""), "lane": r.get("lane", "none")}[a.split]
            by.setdefault(v, []).append(r)
        keys = list(by)
        if a.base and a.base in by:
            keys.remove(a.base); keys.insert(0, a.base)
        groups = [(k, by[k], notes) for k in keys]
        drop.add(a.split)

    out = ["# 配对对比（docs/80）", ""]
    out.append("配对键：%s；基准 A = %s；bootstrap %d 次（种子 %d）。" % (" + ".join(k for k in KEY_FIELDS if k not in drop), groups[0][0], a.boot, a.boot_seed))
    if bad_total:
        out.append("> 共剔除 %d 局无数据或带脚本错误的记录。" % bad_total)
    out.append("")
    js = {"groups": {}, "pairs": []}
    if not a.no_groups:
        out.append("## 各组指标（中位数 + bootstrap 95% 区间）")
        for name, recs, note in groups:
            # 同组内重复键：保留最后一条
            seen = {}
            for r in recs:
                seen[rec_key(r, drop)] = r
            dup = len(recs) - len(seen)
            sec, summ = group_section(name, list(seen.values()), rng, a.boot)
            out += ["", "### %s" % name, "", note + ("；同键重复 %d 局只取一局" % dup if dup else ""), "", sec]
            js["groups"][name] = summ
        out.append("")
    out.append("## 配对对比")
    for name, recs, _ in groups[1:]:
        sec, res = pair_section(groups[0][0], name, groups[0][1], recs, drop, rng, a.boot, hw)
        out += ["", sec]
        js["pairs"].append(res)
    if len(groups) < 2:
        out.append("\n（只有一组，没有配对对比。）")
    text = "\n".join(out) + "\n"
    print(text)
    if a.out:
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        open(a.out, "w", encoding="utf-8").write(text)
    if a.json:
        os.makedirs(os.path.dirname(os.path.abspath(a.json)), exist_ok=True)
        json.dump(js, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
