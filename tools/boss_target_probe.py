"""选敌排查（11-17「干员不打 Boss」）：同种子平衡局，按干员统计 Boss 在场期间打 Boss（含部件）的伤害占比。

  python tools/boss_target_probe.py run --tag before --seeds 1,2,3 [--jobs 2] [--out build/bprobe]
  python tools/boss_target_probe.py table build/bprobe/before.jsonl [build/bprobe/after.jsonl]

阵容：20 人循环三人组（第 i 组 = 第 i、i+1、i+2 人，第一位当队长），每人当 1 次队长、2 次队友；
每局打 --bprobe（run/telemetry.gd），输出一行 BPROBE {op: [打 Boss, 全部, Boss 命中数]}。
占比 = 自己打 Boss 的伤害 ÷ 自己在 Boss 在场期间的全部伤害（与阵容输出多少无关，可跨阵容比）。
"""
import argparse, json, os, re, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
REPO = os.path.dirname(HERE)
OPS = sorted(f[:-5] for f in os.listdir(os.path.join(REPO, "game/data/characters")) if f.endswith(".json"))


def squads(only=None):
    out = []
    n = len(OPS)
    for i in range(n):
        sq = [OPS[i], OPS[(i + 7) % n], OPS[(i + 13) % n]]
        if only and not set(sq) & set(only):
            continue
        out.append(sq)
    return out


def run(a):
    import godot_runner as GR
    godot = GR.find_godot()
    game = os.path.join(REPO, "game")
    GR.ensure_imported(game)
    os.makedirs(a.out, exist_ok=True)
    path = os.path.join(a.out, a.tag + ".jsonl")
    done = set()
    if os.path.exists(path):
        for ln in open(path, encoding="utf-8"):
            r = json.loads(ln)
            done.add((tuple(r["squad"]), r["seed"]))
    jobs = [(sq, s) for sq in squads(a.only.split(",") if a.only else None) for s in a.seeds]
    jobs = [j for j in jobs if (tuple(j[0]), j[1]) not in done]
    print("jobs", len(jobs), flush=True)

    def one(job):
        sq, sd = job
        args = [godot, "--headless", "--path", game, "--", "--balance", "--seed=%d" % sd, "--diff=%d" % a.diff,
                "--op=" + sq[0], "--squad=" + ",".join(sq[1:]), "--bprobe"] + a.extra.split() + ["--audio-driver", "Dummy"]
        out, err, to = GR.run_godot(args, 3000)
        m = re.search(r"^BPROBE (\{.*\})\s*$", out, re.M)
        b = re.search(r"^BALANCE (\{.*\})\s*$", out, re.M)
        bal = json.loads(b.group(1)) if b else {}
        rec = {"squad": sq, "seed": sd, "probe": json.loads(m.group(1)) if m else None,
               "won": bal.get("won"), "t": bal.get("time", bal.get("t")), "timeout": bool(to),
               "errs": GR.script_errors(out, err)[:3]}
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(sq, sd, "ok" if rec["probe"] is not None else "NOPROBE", rec["errs"][:1], flush=True)
        return rec

    with ThreadPoolExecutor(a.jobs) as ex:
        list(ex.map(one, jobs))


def agg(path):
    """op -> {lead: [boss, all, hits, runs], mate: [...]}"""
    res = {}
    for ln in open(path, encoding="utf-8"):
        r = json.loads(ln)
        if not r.get("probe"):
            continue
        for k, op in enumerate(r["squad"]):
            v = r["probe"].get(op)
            if v is None:
                continue
            d = res.setdefault(op, {"lead": [0.0, 0.0, 0, 0], "mate": [0.0, 0.0, 0, 0]})
            s = d["lead" if k == 0 else "mate"]
            s[0] += v[0]; s[1] += v[1]; s[2] += v[2]; s[3] += 1
    return res


def pct(s):
    return 100.0 * s[0] / s[1] if s[1] > 0 else float("nan")


def table(a):
    A = [agg(p) for p in a.files]
    hdr = "| 干员 |" + "".join(" 队长%s | 队友%s | 队友命中/局%s |" % ((" " + str(i + 1),) * 3 if len(A) > 1 else ("",) * 3) for i in range(len(A)))
    print(hdr)
    print("|---|" + "---|---|---|" * len(A))
    for op in OPS:
        row = "| %s |" % op
        for R in A:
            d = R.get(op)
            if not d:
                row += " - | - | - |"
                continue
            l, m = d["lead"], d["mate"]
            row += " %.0f%% | %.0f%% | %.0f |" % (pct(l), pct(m), m[2] / max(1, m[3]))
        print(row)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    r = sp.add_parser("run")
    r.add_argument("--tag", required=True)
    r.add_argument("--seeds", default="1,2,3", type=lambda s: [int(x) for x in s.split(",")])
    r.add_argument("--jobs", type=int, default=2)
    r.add_argument("--diff", type=int, default=0)
    r.add_argument("--only", default="")
    r.add_argument("--extra", default="--nodeath --bot=expert", help="不死 + 高手机器人：每局都打满到最终 Boss")
    r.add_argument("--out", default=os.path.join(REPO, "build/bprobe"))
    t = sp.add_parser("table")
    t.add_argument("files", nargs="+")
    a = ap.parse_args()
    run(a) if a.cmd == "run" else table(a)
