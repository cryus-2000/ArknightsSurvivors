"""伊祖米克子代对照：usage agg_off.py <trial jsonl>...（boss_diag 的 off 字段）"""
import json, sys, statistics as st
for p in sys.argv[1:]:
    recs = [rec for l in open(p, encoding="utf-8") for r in [json.loads(l)] for rec in r["recs"] if rec["boss"] == "izumik" and "off" in rec]
    if not recs:
        print(p, "no data"); continue
    def med(k):
        return st.median([x["off"][k] for x in recs])
    curve = [round(st.mean([x["off"]["curve"][i] for x in recs if len(x["off"]["curve"]) > i]), 1) for i in range(0, 31, 5)]
    wins = sum(1 for x in recs if x["why"] == "win")
    print("%s runs %d | spawned %.0f killed %.0f absorbed %.0f | clear %.2fs | learn layers %.0f absorb_n %.0f stacks %.0f | alive@0,5..30s %s | win %d/%d | fight %.0fs" % (
        p.replace("\\", "/").split("/")[-1], len(recs), med("spawned"), med("killed"), med("absorbed"), med("clear_t"),
        med("izu_layers"), med("absorb_n"), med("izu_stacks"), curve, wins, len(recs), st.median([x["fight_t"] for x in recs])))
