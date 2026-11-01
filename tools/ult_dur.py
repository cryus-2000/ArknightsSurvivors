# -*- coding: utf-8 -*-
"""终结技时长表（docs/216 §4）：每名干员当队长跑一局，0:31.5 充满放出（口径同 tools/ult_rec.py 的 u_<干员>），读 ult.gd --ultdur 打印的 ULTDUR；带 --playclock（按玩家局时钟推进，顿帧才真的停）。
用法：python -X utf8 tools/ult_dur.py [--ops texas,skadi] [--jobs 2] [--extra=--bal=ult/finish=0] [--json 输出]
按界面时钟（--fixed-fps 30 下按固定步长，等于玩家看到的真实时长）：cast = 按下到放出、done = 招式结束、end = 最后一个特效消失、
frozen = 世界停住（超必杀暂停 + 顿帧）、slow = 慢放。打印表格 + 中位数。"""
import argparse, json, os, statistics, sys
from concurrent.futures import ThreadPoolExecutor
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_runner as GR
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ALL = "angelina exusiai eyjafjalla gladiia hoshiguma irene kaltsit lappland logos lumen mizuki saria siege skadi skalter specter_unchained suzuran texas ulpianus wisadel".split()
ap = argparse.ArgumentParser()
ap.add_argument("--ops", default=",".join(ALL)); ap.add_argument("--jobs", type=int, default=2); ap.add_argument("--extra", default=""); ap.add_argument("--json", default="")
a = ap.parse_args()
AT = 31.5


def one(op):
    mates = [m for m in ["saria", "exusiai", "lappland"] if m != op][:2]
    args = [GR.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30", "--",
            "--balance", "--realtime", "--rtfrom=%g" % (AT - 2), "--nodeath", "--seed=3", "--op=" + op, "--squad=" + ",".join(mates), "--bot=expert",
            "--maxprog", "--bal=ult/bot_n=1", "--bal=ult/test_swarm_at=%g" % (AT - 1.2), "--bal=ult/test_swarm_every=6", "--bal=ult/test_fill_at=%g" % AT,
            "--maxt=%d" % (AT + 24), "--ultdur", "--playclock"] + a.extra.split()
    o, e, to = GR.run_godot([x for x in args if x], 900)
    rows = [json.loads(ln[7:]) for ln in o.splitlines() if ln.startswith("ULTDUR ")]
    r = rows[0] if rows else {"id": op}
    r["err"] = GR.script_errors(o, e)[:1]
    return r


with ThreadPoolExecutor(a.jobs) as ex:
    rows = list(ex.map(one, a.ops.split(",")))
print("%-18s %6s %6s %6s %6s %6s" % ("干员", "放出", "结束", "特效完", "停住", "慢放"))
for r in rows:
    print("%-18s %6s %6s %6s %6s %6s %s" % (r["id"], r.get("cast", "-"), r.get("done", "-"), r.get("end", "-"), r.get("frozen", "-"), r.get("slow", "-"), r.get("err") or ""))
for k in ("done", "end", "frozen"):
    v = [r[k] for r in rows if k in r]
    if v:
        print("中位数 %s %.2f（%.2f – %.2f）" % (k, statistics.median(v), min(v), max(v)))
if a.json:
    json.dump(rows, open(a.json, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
