"""Boss 弹判定对照（claude/bullet-hitbox）：各格整体胜率 + 打到最终 Boss 的局里对各最终 Boss 的胜率。
usage: agg_hitbox.py <cell_dir>...   （每个目录是 balance_run.py --out 的输出，含 *.json）"""
import glob, json, os, sys
FINALS = ["paranoia", "knight_boss", "ishar", "izumik"]
print("格 | 局 | 胜率 | 打到最终 Boss | " + " | ".join("%s 胜 / 到" % f for f in FINALS) + " | 脚本错误")
for d in sys.argv[1:]:
    recs = []
    for p in glob.glob(os.path.join(d, "*.json")):
        recs += json.load(open(p, encoding="utf-8")).get("records", [])
    runs = [r for r in recs if "data" in r]
    win = sum(1 for r in runs if r["data"].get("win"))
    reach = {f: [0, 0] for f in FINALS}
    nreach = 0
    for r in runs:
        bs = [str(x).split(":")[0] for x in r["data"].get("bosses", [])]
        fb = [b for b in bs if b in FINALS]
        if fb:
            nreach += 1
            reach[fb[-1]][1] += 1
            if r["data"].get("win"):
                reach[fb[-1]][0] += 1
    errs = sum(1 for r in recs if r.get("script_errors"))
    cells = " | ".join("%d%% (%d/%d)" % (100 * w / max(1, n), w, n) for w, n in reach.values())
    print("%s | %d | %.1f%% | %d | %s | %d" % (os.path.basename(d.rstrip("/")), len(runs), 100.0 * win / max(1, len(runs)), nreach, cells, errs))
