#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""平衡批跑器（docs/27 §6）：并行跑多组 `--balance` 模拟，汇总 BALANCE JSON 成表。

用法（在仓库根目录）：
    python tools/balance_run.py                       # 默认矩阵：8 名干员单人开局 × 3 seed
    python tools/balance_run.py --preset squads       # 预设编队矩阵
    python tools/balance_run.py --op wisadel --seeds 5
    python tools/balance_run.py --squad wisadel,suzuran,saria --seeds 3 --diff 0
    python tools/balance_run.py --preset solo --jobs 8 --tag after_nerf

    python tools/balance_run.py --preset starts --bots afk,bad,normal,expert --seeds 4 --tag bots   # 四档机器人（docs/29）

输出：build/balance/<tag>_<时间>.json（原始）与同名 .md（汇总表）；终端打印汇总表。
速度与复用（docs/36）：同 seed 可复现，「游戏源文件内容 + 参数」相同的局读缓存（--nocache 关掉）；
全机并发上限见 tools/godot_runner.py（GODOT_MAX_PROCS）；--game 指向别的工作树的 game/（A/B 对比用）。
机器人（docs/29）：--bot 选一档，--bots 逗号分隔跑多档矩阵；afk 挂机 / bad 手残 / normal 普通（缺省）/ expert 高手。
多档时额外输出「按机器人汇总」表，并对照 BOT_TARGETS 给出 达标 / 偏难 / 偏易。
指标：胜率、存活时间、等级里程碑（2:00 / 5:00 / 8:00）、最终 Boss 剩余、伤害占比（按干员 / 来源）、
      精英化时间、灯火、死因（承伤最大的来源）。
"""
import argparse, json, os, re, subprocess, sys, time, datetime, statistics, itertools
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
OPS = ["mizuki", "wisadel", "eyjafjalla", "kaltsit", "saria", "siege", "skadi", "suzuran",
       "ulpianus", "irene", "specter_unchained", "logos", "lumen"]
PRESETS = {
    "solo": [[o] for o in OPS],
    "squads": [
        ["wisadel", "suzuran", "saria"],     # 远程输出 + 辅助 + 护盾
        ["mizuki", "kaltsit", "siege"],      # 近战 + 医疗 + 节奏
        ["eyjafjalla", "skadi", "saria"],    # 法术 AoE + 近卫 + 重装
        ["skadi", "siege", "kaltsit"],       # 纯近战
        ["wisadel", "eyjafjalla", "suzuran"],# 纯远程
        ["mizuki", "saria", "suzuran"],      # 水月 + 双辅助
    ],
    "batch2": [
        ["ulpianus", "wisadel", "saria"], ["irene", "wisadel", "saria"], ["specter_unchained", "wisadel", "saria"],
        ["logos", "wisadel", "saria"], ["lumen", "wisadel", "saria"],
        ["ulpianus", "suzuran", "kaltsit"], ["irene", "suzuran", "kaltsit"], ["specter_unchained", "suzuran", "kaltsit"],
        ["logos", "suzuran", "kaltsit"], ["lumen", "suzuran", "kaltsit"],
    ],
    "batch2solo": [["ulpianus"], ["irene"], ["specter_unchained"], ["logos"], ["lumen"], ["skadi"], ["eyjafjalla"], ["kaltsit"]],
    "b2fix": [["ulpianus"], ["specter_unchained"], ["logos"], ["lumen"]],
    "b2fix3": [["logos", "wisadel", "saria"], ["logos", "suzuran", "kaltsit"]],
    "b2fix2": [["logos", "wisadel", "saria"], ["logos", "suzuran", "kaltsit"], ["irene", "wisadel", "saria"], ["irene", "suzuran", "kaltsit"]],
    "pairs": [list(p) for p in itertools.combinations(OPS, 2)],
    # 单人开局、自然招募（真实流程）：每个职业一名代表
    "starts": [["wisadel"], ["eyjafjalla"], ["skadi"], ["mizuki"], ["saria"], ["kaltsit"], ["suzuran"]],
    # 流派矩阵（--lanes）用的缩小开局：远程 / 法术 / 近战 / 重装各一，覆盖 A（近战）、E（远程）、B（追击：维什戴尔、塞雷娅）的对口编队
    "lanes4": [["wisadel"], ["eyjafjalla"], ["skadi"], ["saria"]],
    # 干员横向对比（docs/29 §5）：被测干员 + 两名低输出的固定队友（推进之王 + 流明；测他们自己时换成塞雷娅 / 凯尔希），
    # 开局即满编，被测干员的伤害占比 / 每分钟伤害就是她自己的水平
    "opcmp": [[o] + {"siege": ["saria", "lumen"], "lumen": ["siege", "saria"]}.get(o, ["siege", "lumen"]) for o in OPS],
    # 输出占比（2026-09-26）：被测干员 + 推进之王 + 水月，配 --extra=--nodeath 跑满。队友固定且不在本轮改动里，前后占比才可比
    # （opcmp 的「每分钟伤害」在怪被清空时封顶，而且队友一改动所有人的数字都跟着变，只适合看同一版本内的排名）
    "share": [[o, "siege", "mizuki"] for o in OPS if o not in ("siege", "mizuki")],
    # 近战 / 远程差距快检（2026-09-26）：近战主控 + 一名远程主输出 + 一名辅助，配 --extra="--nodeath --maxt=480"，看近战与远程各拿多少伤害
    "gap": [["skadi", "wisadel", "suzuran"], ["irene", "logos", "saria"], ["ulpianus", "eyjafjalla", "kaltsit"],
            ["specter_unchained", "wisadel", "lumen"], ["mizuki", "logos", "siege"]],
    # 快检主控可玩性：近战 / 远程各三名开局主控，自然招募
    "gapleaders": [["skadi"], ["ulpianus"], ["irene"], ["wisadel"], ["logos"], ["eyjafjalla"]],
}


def src_to_op():
    """伤害来源名 → 干员 id（读 data/characters/*.json 的 hit_sources）"""
    m = {}
    d = os.path.join(GAME, "data", "characters")
    for f in os.listdir(d):
        if f.endswith(".json"):
            try:
                hs = json.load(open(os.path.join(d, f), encoding="utf-8")).get("hit_sources") or {}
            except Exception:
                continue
            for k in hs:
                m[k] = f[:-5]
    return m

BOTS = ["afk", "bad", "normal", "expert"]
## 各档机器人的难度目标（docs/29 §3）：win 胜率区间、t 平均存活秒数区间、s330 3:30 存活率下限
BOT_TARGETS = {
    "afk":    {"win": (0.0, 0.0),   "t": (90, 300),  "s330": None, "desc": "挂机：3:30 前死；活过 5:00 说明太简单"},
    "bad":    {"win": (0.0, 0.10),  "t": (180, 480), "s330": None, "desc": "手残：第一个 Boss 前后死，偶尔撑到中后期"},
    "normal": {"win": (0.30, 0.55), "t": (420, 780), "s330": 0.9, "desc": "普通：几乎都能过 3:30，三到五成通关"},
    "expert": {"win": (0.70, 0.95), "t": (540, 780), "s330": 1.0, "desc": "高手：大多通关，但不是必胜"},
}


find_godot = GR.find_godot


def run_one(godot, squad, seed, diff, extra, timeout, bot=None, game=None, tkey=None):
    game = game or GAME
    args = [godot, "--headless", "--path", game, "--", "--balance", "--seed=%d" % seed, "--diff=%d" % diff, "--op=" + squad[0]]
    if bot:
        args.append("--bot=" + bot)
    if len(squad) > 1:
        args.append("--squad=" + ",".join(squad[1:]))
    args += extra
    # 缓存：同一份源文件 + 同一组参数 = 同一局（docs/36 §3）
    akey = json.dumps([squad, seed, diff, bot or "normal", extra])
    if tkey:
        hit = GR.cache_get(tkey, akey)
        if hit is not None:
            hit["cached"] = True
            return hit
    t0 = time.time()
    out, err, _ = GR.run_godot(args, timeout)
    m = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
    rec = {"squad": squad, "seed": seed, "diff": diff, "bot": bot or "normal", "wall": round(time.time() - t0, 1)}
    # 脚本错误不会让模拟停下，但可能让某段逻辑整段失效（例如 Boss 没刷出来）→ 计数并在报告顶部警告
    # Godot 把脚本错误写到 stderr（2026-09-26 前只查 stdout，漏掉了水月每次出手报错的整批数据）
    errs = GR.script_errors(out, err)
    if errs:
        rec["script_errors"] = len(errs)
        rec["first_error"] = errs[0][:200]
    if m:
        try:
            rec["data"] = json.loads(m.group(1))
        except json.JSONDecodeError:
            rec["error"] = "bad json"
    else:
        rec["error"] = "no BALANCE line"
        rec["tail"] = out[-600:]
    if tkey and "data" in rec and not rec.get("script_errors"):
        GR.cache_put(tkey, akey, rec)
    return rec


def fmt_t(sec):
    return "%d:%02d" % (int(sec) // 60, int(sec) % 60)


def summarize(records):
    """按编队（多档机器人时按 机器人 × 编队）分组汇总"""
    multi_bot = len({r.get("bot", "normal") for r in records}) > 1
    groups = {}
    for r in records:
        key = "+".join(r["squad"])
        if r.get("bot", "normal") != "normal" or multi_bot:
            key = "[%s] %s" % (r.get("bot", "normal"), key)
        if r.get("lane"):
            key = "{%s} %s" % (r["lane"], key)
        groups.setdefault(key, []).append(r)
    s2o = src_to_op()
    rows = []
    for key, rs in groups.items():
        ok = [r["data"] for r in rs if "data" in r]
        if not ok:
            rows.append({"squad": key, "n": len(rs), "error": rs[0].get("error", "?")})
            continue
        wins = sum(1 for d in ok if d.get("win"))
        ts = [d["t"] for d in ok]
        lv = [d["lv"] for d in ok]
        marks = [d.get("marks", {}) for d in ok]
        def mark(k):
            v = [m.get(k) for m in marks if m.get(k) is not None]
            return statistics.mean(v) if v else 0
        boss_hp = [d.get("boss_hp", -1) for d in ok if d.get("boss_hp", -1) >= 0]
        # 伤害占比：按干员（out 的 key 是伤害来源名；hit_sources 里 op 字段无法从 JSON 反推，这里按来源名聚合）
        out_tot = {}
        for d in ok:
            tot = sum(d.get("out", {}).values()) or 1.0
            for k, v in d.get("out", {}).items():
                out_tot[k] = out_tot.get(k, 0.0) + v / tot / len(ok)
        top = sorted(out_tot.items(), key=lambda kv: -kv[1])[:6]
        # 治疗占比（BALANCE 的 heal 段：来源 → 有效治疗量），用来看医疗无人机 / 医疗干员是不是保底
        heal_tot = {}
        heal_abs = 0.0
        for d in ok:
            h = d.get("heal", {})
            tot = sum(h.values()) or 1.0
            heal_abs += sum(h.values()) / len(ok)
            for k, v in h.items():
                heal_tot[k] = heal_tot.get(k, 0.0) + v / tot / len(ok)
        heal_top = sorted(heal_tot.items(), key=lambda kv: -kv[1])[:3]
        drone_lv = statistics.mean([d.get("drone", 0) for d in ok])
        dmg_in = {}
        for d in ok:
            for k, v in d.get("dmg", {}).items():
                dmg_in[k] = dmg_in.get(k, 0.0) + v
        killer = max(dmg_in.items(), key=lambda kv: kv[1])[0] if dmg_in else "-"
        elites = []
        for d in ok:
            for o in d.get("ops", []):
                elites.append((o["id"], o.get("elite", 0)))
        e2 = sum(1 for _, e in elites if e >= 2)
        floor = [d.get("floor_hits", 0) for d in ok]
        rows.append({
            "squad": key, "n": len(ok), "win": wins / len(ok), "floor": statistics.mean(floor),
            "floor_first": statistics.mean([d["floor_times"][0] for d in ok if d.get("floor_times")]) if any(d.get("floor_times") for d in ok) else None,
            "t_mean": statistics.mean(ts), "t_min": min(ts),
            "lv2": mark("120"), "lv5": mark("300"), "lv8": mark("480"), "lv_end": statistics.mean(lv),
            "boss_hp": statistics.mean(boss_hp) if boss_hp else None,
            "lamp": statistics.mean([d.get("lamp", 0) for d in ok]),
            "kills": statistics.mean([d.get("kills", 0) for d in ok]),
            "e2_share": e2 / max(1, len(elites)),
            "top": top, "killer": killer,
            "heal_top": heal_top, "heal_abs": heal_abs, "drone_lv": drone_lv,
            **bot_cols(ok),
            "lead": rs[0]["squad"][0],
            "lead_share": statistics.mean([sum(v for k, v in d.get("out", {}).items() if s2o.get(k) == rs[0]["squad"][0]) / (sum(d.get("out", {}).values()) or 1.0) for d in ok]),
            "lead_dpm": statistics.mean([sum(v for k, v in d.get("out", {}).items() if s2o.get(k) == rs[0]["squad"][0]) / max(1, d["t"]) * 60 for d in ok]),
        })
    return rows


def _mean(v, default=None):
    v = [x for x in v if x is not None]
    return statistics.mean(v) if v else default


def bot_cols(ok):
    """docs/29 的机器人指标：受击频率、承伤、低血时间、死因、精英化 / 招募 / Boss 击杀节奏"""
    bs = [d.get("bot", {}) for d in ok]
    deaths = [b.get("death_src", "") for d, b in zip(ok, bs) if not d.get("win") and b.get("death_src")]
    death_mode = max(set(deaths), key=deaths.count) if deaths else "-"
    def first_elite(b, lvl):
        ts = [t for k, t in b.get("elite_t", {}).items() if k.endswith(":%d" % lvl)]
        return min(ts) if ts else None
    ttk = []
    for b in bs:
        for bo in b.get("bosses", []):
            if bo.get("t1", -1) >= 0:
                ttk.append(bo["t1"] - bo["t0"])
    bosses_killed = [sum(1 for bo in b.get("bosses", []) if bo.get("t1", -1) >= 0) for b in bs]
    rec1 = [b.get("recruit_t", [None])[0] if b.get("recruit_t") else None for b in bs]
    return {
        "s330": sum(1 for d in ok if d.get("win") or d["t"] >= 210) / len(ok),
        "s500": sum(1 for d in ok if d.get("win") or d["t"] >= 300) / len(ok),
        "hits_pm": _mean([b.get("hits_pm") for b in bs], 0), "taken_pm": _mean([b.get("taken_pm") for b in bs], 0),
        "low_hp_s": _mean([b.get("low_hp_s") for b in bs], 0), "dark_s": _mean([b.get("dark_s") for b in bs], 0),
        "death_mode": death_mode, "e1": _mean([first_elite(b, 1) for b in bs]), "e2": _mean([first_elite(b, 2) for b in bs]),
        "rec1": _mean(rec1), "boss_ttk": _mean(ttk), "bosses_killed": _mean(bosses_killed, 0),
        "still": _mean([b.get("still_pct") for b in bs], 0), "moved_pm": _mean([b.get("moved_pm") for b in bs], 0),
    }


def _ft(v):
    return fmt_t(v) if v is not None else "-"


def bot_table(rows):
    """机器人指标表（每个 机器人 × 编队 一行）"""
    lines = ["| 机器人 · 开局 | n | 胜率 | 存活 均/最短 | 3:30 存活 | 5:00 存活 | 首次招募 | 首次精一 / 精二 | 中期 Boss 击杀数 / 平均用时 | 受击/分 | 承伤/分 | 低血(<35%)秒 | 熄灯秒 | 静止% | 开局干员 伤害占比 / 每分钟 | 主要死因 |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            continue
        lines.append("| %s | %d | %d%% | %s / %s | %d%% | %d%% | %s | %s / %s | %.1f / %s | %.1f | %.0f | %.0f | %.0f | %.0f | %d%% / %.0f | %s |" % (
            r["squad"], r["n"], r["win"] * 100, fmt_t(r["t_mean"]), fmt_t(r["t_min"]), r["s330"] * 100, r["s500"] * 100,
            _ft(r["rec1"]), _ft(r["e1"]), _ft(r["e2"]), r["bosses_killed"],
            ("%ds" % r["boss_ttk"]) if r["boss_ttk"] is not None else "-",
            r["hits_pm"], r["taken_pm"], r["low_hp_s"], r["dark_s"], r["still"], r["lead_share"] * 100, r["lead_dpm"], r["death_mode"]))
    return "\n".join(lines)


def bot_summary(records):
    """按机器人汇总（跨所有开局），对照 BOT_TARGETS 判定"""
    by = {}
    for r in records:
        if "data" in r:
            by.setdefault(r.get("bot", "normal"), []).append(r["data"])
    lines = ["| 机器人 | 局数 | 胜率 | 平均存活 | 3:30 存活 | 平均终局等级 | 平均击杀 | 目标（胜率 / 存活） | 判定 |",
             "|---|---|---|---|---|---|---|---|---|"]
    verdicts = {}
    for bot in BOTS + sorted(set(by) - set(BOTS)):
        ds = by.get(bot)
        if not ds:
            continue
        win = sum(1 for d in ds if d.get("win")) / len(ds)
        tm = statistics.mean([d["t"] for d in ds])
        s330 = sum(1 for d in ds if d.get("win") or d["t"] >= 210) / len(ds)
        tg = BOT_TARGETS.get(bot)
        v = "-"
        if tg:
            w0, w1 = tg["win"]
            t0, t1 = tg["t"]
            if win > w1 + 1e-9 or tm > t1 + 1e-9:
                v = "偏易"
            elif win < w0 - 1e-9 or tm < t0 - 1e-9 or (tg["s330"] is not None and s330 < tg["s330"] - 1e-9):
                v = "偏难"
            else:
                v = "达标"
        verdicts[bot] = v
        tgt = ("%d–%d%% / %s–%s" % (tg["win"][0] * 100, tg["win"][1] * 100, fmt_t(tg["t"][0]), fmt_t(tg["t"][1]))) if tg else "-"
        lines.append("| %s | %d | %d%% | %s | %d%% | %.1f | %.0f | %s | **%s** |" % (
            bot, len(ds), win * 100, fmt_t(tm), s330 * 100, statistics.mean([d["lv"] for d in ds]),
            statistics.mean([d.get("kills", 0) for d in ds]), tgt, v))
    return "\n".join(lines), verdicts


def relic_meta():
    """藏品编号 → {name, lanes, rarity, req}（lanes 空 = 通用；req = requires_class 职业门槛）"""
    meta = json.load(open(os.path.join(GAME, "data", "relics.json"), encoding="utf-8"))
    fx = json.load(open(os.path.join(GAME, "data", "relic_effects.json"), encoding="utf-8")).get("relics", {})
    out = {}
    for r in meta["items"]:
        i = str(int(r["id"]))
        e = fx.get(i, {})
        out[i] = {"name": r["name"], "lanes": r.get("lanes") or ["通用"], "rarity": e.get("rarity", r.get("rarity")),
                  "req": e.get("requires_class", r.get("requires_class", []))}
    return out


def relic_table(records):
    """藏品指标（docs/35）：按 机器人 × 开局干员 统计藏品直接伤害占比、各流派出现 / 拿取次数、无效拿取
    （拿到时编队里没有该藏品要求的职业）。流派按当前 relics.json 归类，所以旧 json 换新数据重算也能对照。"""
    M = relic_meta()
    by = {}
    for r in records:
        if "data" in r and "relic_take" in r["data"]:
            by.setdefault((r.get("bot", "normal"), r["squad"][0]), []).append(r["data"])
    if not by:
        return ""
    lines = ["| 机器人 | 开局 | 局数 | 平均藏品数 | 藏品直接伤害 | 各流派 出现 / 拿取 | 无效拿取 |", "|---|---|---|---|---|---|---|"]
    tot_offer, tot_take, per_id = {}, {}, {}

    def lane_str(offer, take):
        ks = sorted(set(offer) | set(take))
        return " ".join("%s %d/%d" % (k, offer.get(k, 0), take.get(k, 0)) for k in ks)

    for (bot, op), ds in sorted(by.items()):
        offer, take = {}, {}
        dead = 0
        ntake = 0
        share = []
        for d in ds:
            tot = sum(d.get("out", {}).values()) or 1.0
            share.append(d.get("relic_out", 0.0) / tot)
            for o in d.get("relic_offer", []):
                for i in o[2]:
                    if i in M:
                        per_id.setdefault(i, [0, 0])[0] += 1
                        for ln in M[i]["lanes"]:
                            offer[ln] = offer.get(ln, 0) + 1
                            tot_offer[ln] = tot_offer.get(ln, 0) + 1
            for tk in d.get("relic_take", []):
                i = tk[1]
                if i not in M:
                    continue
                ntake += 1
                per_id.setdefault(i, [0, 0])[1] += 1
                for ln in M[i]["lanes"]:
                    take[ln] = take.get(ln, 0) + 1
                    tot_take[ln] = tot_take.get(ln, 0) + 1
                req = M[i]["req"]
                if req and not any(c in tk[2] for c in req):
                    dead += 1
        lines.append("| %s | %s | %d | %.1f | %.1f%% | %s | %d |" % (bot, op, len(ds), ntake / len(ds), 100 * statistics.mean(share), lane_str(offer, take), dead))
    lines.append("| 合计 | | | | | %s | |" % lane_str(tot_offer, tot_take))
    top = sorted(per_id.items(), key=lambda kv: -kv[1][1])[:12]
    lines.append("")
    lines.append("拿取最多（出现 / 拿取）：" + "，".join("%s %d/%d" % (M[i]["name"], v[0], v[1]) for i, v in top))
    return "\n".join(lines)


LANE_NAMES = {"none": "不偏好", "A": "前锋·近战", "B": "追击·召唤", "C": "控制·技能循环", "D": "收割·弱点", "E": "远程·火力",
              "F": "深蓝·低灯火", "G": "编队·协同", "H": "守护·续航"}


def _boss_phase(b):
    """Boss 按出场时间分段：第一个（3:30 前后）/ 第二个（7:00 前后）/ 终局（10:00）"""
    t0 = b.get("t0", 0)
    return 0 if t0 < 300 else (1 if t0 < 540 else 2)


def lane_summary(records):
    """流派矩阵（--lanes）：每个 流派 × 机器人 一行，与「不偏好」对照；同 seed 同开局配对，差值只来自选藏品的偏好。
    Boss 用时按出场分段（击杀数 / 出场数，平均与中位秒数；最终 Boss 在胜利的局按「出现 → 通关」计）；8:00 后承伤取机器人曲线里 t > 480 的 30 秒窗口"""
    by = {}
    for r in records:
        if "data" in r:
            by.setdefault((r.get("lane", "none"), r.get("bot", "normal")), []).append(r)
    lines = ["| 流派 | 机器人 | 局数 | 胜率 | 平均存活 | 3:30 / 5:00 存活 | 终局等级 | 击杀 | Boss1 / Boss2 / 终局 用时 均·中（击杀/出场） | 终 Boss 剩余 | 承伤/分 全程 · 8:00 后 | 该流派藏品 5:00 / 末 | 藏品数 | 藏品直接伤害 |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    order = list(LANE_NAMES)
    for (ln, bot), rs in sorted(by.items(), key=lambda kv: (kv[0][1], order.index(kv[0][0]) if kv[0][0] in order else 99)):
        ds = [r["data"] for r in rs]
        bs = [d.get("bot", {}) for d in ds]
        cols = bot_cols(ds)
        boss_hp = [d.get("boss_hp", -1) for d in ds if d.get("boss_hp", -1) >= 0 and not d.get("win")]
        share = [d.get("relic_out", 0.0) / (sum(d.get("out", {}).values()) or 1.0) for d in ds]
        M = relic_meta()
        def lane_n(d, t_max=99999):
            # 该流派拿到的藏品件数（按 id 去重，升级不重复计），由记录里的 relic_take 推算
            return len({tk[1] for tk in d.get("relic_take", []) if tk[0] <= t_max and ln in M.get(tk[1], {}).get("lanes", [])})
        n300 = [lane_n(d, 300) for d in ds if d["t"] >= 300] if ln != "none" else []
        ph = [[], [], []]
        seen = [0, 0, 0]
        for d, b in zip(ds, bs):
            for bo in b.get("bosses", []):
                k = _boss_phase(bo)
                seen[k] += 1
                if bo.get("t1", -1) >= 0:
                    ph[k].append(bo["t1"] - bo["t0"])
                elif k == 2 and d.get("win"):
                    # 最终 Boss 死的同一帧就判胜利、结束对局，机器人来不及记 t1：胜利的局按「出现 → 通关」计（数值 2026-09-26 指出）
                    ph[k].append(d["t"] - bo["t0"])
        boss_s = " / ".join(("%ds·中%ds（%d/%d）" % (statistics.mean(ph[k]), statistics.median(ph[k]), len(ph[k]), seen[k])) if ph[k] else ("-（0/%d）" % seen[k]) for k in range(3))
        late = []
        for b in bs:
            w = [c.get("taken", 0) for c in b.get("curve", []) if c.get("t", 0) > 480]
            if w:
                late.append(sum(w) / (len(w) * 0.5))
        lines.append("| %s %s | %s | %d | %d%% | %s | %d%% / %d%% | %.1f | %.0f | %s | %s | %.0f · %s | %s / %s | %.1f | %.1f%% |" % (
            ln, LANE_NAMES.get(ln, ""), bot, len(ds), 100 * sum(1 for d in ds if d.get("win")) / len(ds), fmt_t(statistics.mean([d["t"] for d in ds])),
            cols["s330"] * 100, cols["s500"] * 100, statistics.mean([d["lv"] for d in ds]), statistics.mean([d.get("kills", 0) for d in ds]),
            boss_s, ("%d%%" % (100 * statistics.mean(boss_hp))) if boss_hp else "-", cols["taken_pm"], ("%.0f" % statistics.mean(late)) if late else "-",
            ("%.1f" % statistics.mean(n300)) if n300 else "-", ("%.1f" % statistics.mean([lane_n(d) for d in ds])) if ln != "none" else "-",
            statistics.mean([len(d.get("relic_take", [])) for d in ds]), 100 * statistics.mean(share)))
    return "\n".join(lines)


FINAL_BOSS_NAMES = {"paranoia": "偏执泡影", "izumik": "伊祖米克", "ishar": "伊莎玛拉", "knight_boss": "最后的骑士"}


def final_boss_summary(records):
    """最终 Boss 按类型分行（机器人 × 类型）：最终 Boss 由结局决定、各有自己的 boss/hp_x_<类型>，混在一起的「终局用时」不能拿来调单个 Boss。
    用时同 lane_summary：击杀记 t1 − t0，胜利的局按「出现 → 通关」计；未击杀的局给剩余血量"""
    by = {}
    for r in records:
        d = r.get("data")
        if not d:
            continue
        for bo in d.get("bot", {}).get("bosses", []):
            if _boss_phase(bo) != 2:
                continue
            e = by.setdefault((r.get("bot", "normal"), bo.get("type", "?")), {"n": 0, "t": [], "hp": [], "end": {}})
            e["n"] += 1
            e["end"][d.get("ending", "?")] = e["end"].get(d.get("ending", "?"), 0) + 1
            if bo.get("t1", -1) >= 0:
                e["t"].append(bo["t1"] - bo["t0"])
            elif d.get("win"):
                e["t"].append(d["t"] - bo["t0"])
            elif d.get("boss_hp", -1) >= 0:
                e["hp"].append(d["boss_hp"])
    if not by:
        return ""
    lines = ["| 机器人 | 最终 Boss | 结局 | 出场 | 击杀 | 用时 均 / 中 / 最短–最长 | 未击杀时剩余血量 |", "|---|---|---|---|---|---|---|"]
    for (bot, ty), e in sorted(by.items(), key=lambda kv: (kv[0][0], -kv[1]["n"])):
        ts = e["t"]
        lines.append("| %s | %s | %s | %d | %d | %s | %s |" % (
            bot, FINAL_BOSS_NAMES.get(ty, ty), " ".join("%s %d" % kv for kv in sorted(e["end"].items())), e["n"], len(ts),
            ("%ds / %ds / %d–%ds" % (statistics.mean(ts), statistics.median(ts), min(ts), max(ts))) if ts else "-",
            ("%d%%" % (100 * statistics.mean(e["hp"]))) if e["hp"] else "-"))
    return "\n".join(lines)


def horde_summary(records):
    """大群（第 k 次）按机器人分行：出现局数、平均出现时间 / 数量、清掉 80% 的用时（t80，清完的局数）、
    开始后 20 秒内的最大掉血（hp0 − minhp）、开始后 30 秒内死亡的局数、编成（comp）出现次数"""
    by = {}
    for r in records:
        d = r.get("data")
        if not d:
            continue
        end_t = d["t"] if not d.get("win") else None
        for k, h in enumerate(d.get("hordes", [])):
            e = by.setdefault((r.get("bot", "normal"), k), {"t": [], "n": [], "t80": [], "drop": [], "dead": 0, "comp": {}})
            e["t"].append(h["t"]); e["n"].append(h["n"])
            if h.get("t80", -1) >= 0:
                e["t80"].append(h["t80"])
            e["drop"].append(h.get("hp0", 0) - h.get("minhp", 0))
            if end_t is not None and h["t"] <= end_t <= h["t"] + 30:
                e["dead"] += 1
            c = "/".join(h.get("comp", []))
            e["comp"][c] = e["comp"].get(c, 0) + 1
    if not by:
        return ""
    lines = ["| 机器人 | 第几次 | 出现 | 时间 | 数量 | 清 80% 用时 均 / 中（清完/出现） | 20 秒内掉血 均 / 最大 | 30 秒内死亡 | 编成 |", "|---|---|---|---|---|---|---|---|---|"]
    for (bot, k), e in sorted(by.items()):
        lines.append("| %s | %d | %d | %s | %.0f | %s（%d/%d） | %.0f / %.0f | %d | %s |" % (
            bot, k + 1, len(e["t"]), fmt_t(statistics.mean(e["t"])), statistics.mean(e["n"]),
            ("%.0fs / %.0fs" % (statistics.mean(e["t80"]), statistics.median(e["t80"]))) if e["t80"] else "-", len(e["t80"]), len(e["t"]),
            statistics.mean(e["drop"]), max(e["drop"]), e["dead"], "；".join("%s ×%d" % kv for kv in sorted(e["comp"].items(), key=lambda kv: -kv[1])[:3])))
    return "\n".join(lines)


ZONE_STATE_NAMES = {0: "未缩圈", 1: "预告", 2: "收缩", 3: "稳定"}


def difficulty_summary(records):
    """难度 / 缩圈 A/B 用的三张表（2026-09-27，记录里有 bot.end / bot.peak 才输出）：
    ① 前 3 分钟：承伤（曲线 t ≤ 180 的窗口合计）与 3:00 前死亡率；② 死因 × 缩圈阶段 × 圈外 × Boss 在场（只计失败的局）；
    ③ 同屏数量峰值（敌人 / 敌方弹幕 / 我方子弹 / 特效 / 飘字）：全程与 8:00–10:00"""
    by = {}
    for r in records:
        d = r.get("data")
        if d and "end" in d.get("bot", {}):
            by.setdefault((r.get("bot", "normal"), r.get("diff", 0)), []).append(d)
    if not by:
        return ""
    out = ["#### 前 3 分钟", "", "| 机器人 | 难度 | 局数 | 3:00 前死亡 | 前 3 分钟承伤 均 / 中 | 3:00 时生命 |", "|---|---|---|---|---|---|"]
    for (bot, df), ds in sorted(by.items()):
        early = [sum(c.get("taken", 0) for c in d["bot"].get("curve", []) if 0 < c.get("t", 0) <= 180) for d in ds]
        hp3 = [c["hp"] for d in ds for c in d["bot"].get("curve", []) if c.get("t") == 180]
        out.append("| %s | %d | %d | %d%% | %.0f / %.0f | %s |" % (bot, df, len(ds), 100 * sum(1 for d in ds if not d.get("win") and d["t"] < 180) / len(ds),
                   statistics.mean(early), statistics.median(early), ("%.0f%%" % statistics.mean(hp3)) if hp3 else "-"))
    out += ["", "#### 死因 × 缩圈阶段 × Boss 在场（失败的局）", "", "| 机器人 | 难度 | 死因 | 缩圈（第几轮 · 阶段） | 圈外 | Boss 在场 | 局数 | 平均死亡时间 |", "|---|---|---|---|---|---|---|---|"]
    for (bot, df), ds in sorted(by.items()):
        cnt = {}
        for d in ds:
            if d.get("win"):
                continue
            e = d["bot"]["end"]
            zs = ZONE_STATE_NAMES.get(e["zone_state"], "?") if e["zone_state"] == 0 else "第 %d 轮 · %s" % (e["zone_phase"] + 1, ZONE_STATE_NAMES.get(e["zone_state"], "?"))
            k = (e.get("src") or "?", zs, "是" if e.get("zone_out") else "否", "是" if e.get("boss") else "否")
            cnt.setdefault(k, []).append(e["t"])
        for k, ts in sorted(cnt.items(), key=lambda kv: -len(kv[1])):
            out.append("| %s | %d | %s | %s | %s | %s | %d | %s |" % ((bot, df) + k + (len(ts), fmt_t(statistics.mean(ts)))))
        if not cnt:
            out.append("| %s | %d | （全部胜利） | | | | 0 | |" % (bot, df))
    names = ["敌人", "敌方弹幕（含抛射）", "我方子弹", "特效", "飘字"]
    out += ["", "#### 同屏数量峰值（每局峰值的 平均 / 最大）", "", "| 机器人 | 难度 | 局数 | 范围 | " + " | ".join(names) + " |", "|---|---|---|---|" + "---|" * len(names)]
    for (bot, df), ds in sorted(by.items()):
        for label, pk in (("全程", lambda d: d["bot"].get("peak")),
                          ("8:00–10:00", lambda d: [max(m[i] for m in d["bot"]["peak_min"][8:10]) for i in range(5)] if len(d["bot"].get("peak_min", [])) > 8 else None)):
            ps = [p for p in map(pk, ds) if p]
            if ps:
                out.append("| %s | %d | %d | %s | %s |" % (bot, df, len(ps), label, " | ".join("%.0f / %d" % (statistics.mean(p[i] for p in ps), max(p[i] for p in ps)) for i in range(5))))
    return "\n".join(out)


def table(rows):
    lines = ["| 编队 | n | 胜率 | 存活(均/最短) | 托底(次/首次) | Lv 2:00/5:00/8:00/末 | 终Boss剩余 | 精二占比 | 灯火 | 击杀 | 主要伤害来源 | 治疗来源(总量/无人机Lv) | 主要死因 |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        if "error" in r:
            lines.append("| %s | %d | 失败: %s | | | | | | | | | | |" % (r["squad"], r["n"], r["error"]))
            continue
        top = " ".join("%s %d%%" % (k, v * 100) for k, v in r["top"][:4])
        heal = " ".join("%s %d%%" % (k, v * 100) for k, v in r["heal_top"]) or "-"
        lines.append("| %s | %d | %d%% | %s / %s | %.1f / %s | %.0f / %.0f / %.0f / %.0f | %s | %d%% | %.0f | %.0f | %s | %s (%.0f / %.1f) | %s |" % (
            r["squad"], r["n"], r["win"] * 100, fmt_t(r["t_mean"]), fmt_t(r["t_min"]),
            r["floor"], fmt_t(r["floor_first"]) if r["floor_first"] is not None else "-",
            r["lv2"], r["lv5"], r["lv8"], r["lv_end"],
            ("%d%%" % (r["boss_hp"] * 100)) if r["boss_hp"] is not None else "-",
            r["e2_share"] * 100, r["lamp"], r["kills"], top, heal, r["heal_abs"], r["drone_lv"], r["killer"]))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preset", choices=list(PRESETS), default=None)
    ap.add_argument("--op", help="单人开局干员")
    ap.add_argument("--squad", help="逗号分隔的编队（第一个是开局干员）")
    ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--diff", type=int, default=0)
    ap.add_argument("--jobs", type=int, default=GR.MAX_PROCS, help="本批并行数；全机总数另受 GODOT_MAX_PROCS 限制")
    ap.add_argument("--timeout", type=int, default=900)
    ap.add_argument("--tag", default="run")
    ap.add_argument("--extra", default="", help="透传给游戏的额外参数，空格分隔，例如 \"--nodeath --botrandom\"")
    ap.add_argument("--bot", choices=BOTS, default=None, help="机器人档位（docs/29），缺省 normal")
    ap.add_argument("--bots", default=None, help="逗号分隔的多档机器人矩阵，例如 afk,bad,normal,expert")
    ap.add_argument("--lanes", default=None, help="逗号分隔的藏品流派矩阵（机器人优先拿该流派，docs/27 §5），none 表示不偏好，例如 none,A,B,C,D,E,F,G,H")
    ap.add_argument("--game", default=None, help="要测的 game/ 目录（缺省为本仓库的 game/；A/B 对比时指向临时工作树）")
    ap.add_argument("--nocache", action="store_true", help="不读也不写结果缓存")
    ap.add_argument("--out", default=None, help="报告输出目录（缺省 build/balance）")
    a = ap.parse_args()
    if a.squad:
        squads = [a.squad.split(",")]
    elif a.op:
        squads = [[a.op]]
    else:
        squads = PRESETS[a.preset or "solo"]
    extra = a.extra.split() if a.extra else []
    godot = find_godot()
    bots = a.bots.split(",") if a.bots else [a.bot]
    game = os.path.abspath(a.game) if a.game else GAME
    GR.ensure_imported(game)   # 新工作树没有导入缓存时先导入（docs/36 §2.1）
    tkey = None if a.nocache else GR.tree_key(game)
    lanes = a.lanes.split(",") if a.lanes else ["none"]
    jobs = [(s, a.seed0 + i, b, ln) for ln in lanes for b in bots for s in squads for i in range(a.seeds)]
    print("跑 %d 局（%d 流派 × %d 机器人 × %d 编队 × %d seed），并行 %d（全机上限 %d）%s" % (len(jobs), len(lanes), len(bots), len(squads), a.seeds, a.jobs, GR.MAX_PROCS,
          "，源文件摘要 " + tkey if tkey else "，不用缓存"), flush=True)
    t0 = time.time()

    def one(j):
        ex2 = extra + (["--lane=" + j[3]] if j[3] != "none" else [])
        rec = run_one(godot, j[0], j[1], a.diff, ex2, a.timeout, j[2], game, tkey)
        if a.lanes:
            rec["lane"] = j[3]
        return rec
    with ThreadPoolExecutor(a.jobs) as ex:
        records = list(ex.map(one, jobs))
    hits = sum(1 for r in records if r.get("cached"))
    if hits:
        print("其中 %d 局读自缓存" % hits)
    rows = summarize(records)
    bad = [r for r in records if r.get("script_errors")]
    warn = ""
    if bad:
        warn = "> ⚠ %d 局出现脚本错误，结果可能无效。首条：`%s`\n\n" % (len(bad), bad[0]["first_error"])
        print(warn)
    md = warn + table(rows) + "\n\n### 机器人指标（docs/29）\n\n" + bot_table(rows)
    rt = relic_table(records)
    if rt:
        md += "\n\n### 藏品（docs/35）\n\n" + rt
    if len(bots) > 1:
        bs, _ = bot_summary(records)
        md = "### 按机器人汇总\n\n" + bs + "\n\n### 明细\n\n" + md
    hs = horde_summary(records)
    if hs:
        md = "### 大群（按第几次）\n\n" + hs + "\n\n" + md
    ds = difficulty_summary(records)
    if ds:
        md = "### 难度 / 缩圈 / 同屏峰值\n\n" + ds + "\n\n" + md
    fb = final_boss_summary(records)
    if fb:
        md = "### 最终 Boss（按类型；上面的「终局」列是四种混算）\n\n" + fb + "\n\n" + md
    if a.lanes:
        md = "### 按流派汇总\n\n" + lane_summary(records) + "\n\n" + md
    print(md)
    print("耗时 %.0fs" % (time.time() - t0))
    outdir = a.out or os.path.join(ROOT, "build", "balance")
    os.makedirs(outdir, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%m%d_%H%M")
    base = os.path.join(outdir, "%s_%s" % (a.tag, stamp))
    json.dump({"args": vars(a), "records": records}, open(base + ".json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    open(base + ".md", "w", encoding="utf-8").write("# balance %s %s\n\nargs: `%s`\n\n%s\n" % (a.tag, stamp, " ".join(sys.argv[1:]), md))
    print("写入", base + ".{json,md}")


if __name__ == "__main__":
    main()
