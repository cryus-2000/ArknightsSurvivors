"""视觉预审验证集（结果见同目录 VREVIEW_EVAL.md）：用户挑过毛病的（应判先改）、合成坏图、修复后 / 合成好图。路径指向本机各工作树的录像，换机器要改。
用法：python tools/imagegen/vreview_eval.py [模型] [思考档] [表决次数]
"""
import sys, json, glob
sys.path.insert(0, r"E:/ArknightsSurvivors/.claude/worktrees/charming-grothendieck-ce73d6/tools/imagegen")
import vreview as V

W = "E:/ArknightsSurvivors/.claude/worktrees/"
FIN = W + "peaceful-mendeleev-589316/build/ult_rec/fin_u/"
CO = "E:/ArknightsSurvivors/Claude outputs/"
VR = W + "charming-grothendieck-ce73d6/build/vreview/"
model = sys.argv[1] if len(sys.argv) > 1 else V.MODEL
think = sys.argv[2] if len(sys.argv) > 2 else V.THINK
votes = int(sys.argv[3]) if len(sys.argv) > 3 else 1
cases = [
    # (名, 检查单, 文件, crop, note, 期望结论, 期望抓到的项, 用户原话)
    ("能天使变光束 fin_u", "ult_fx", [FIN + "u_exusiai.mp4"], "", "能天使：代表色红 #F22933 + 金 #FFCC48；锁定连射", "fix", ["beam_merge"], "到后面变成了光束"),
    ("凯尔希熔毁 fin_u", "ult_fx", [FIN + "u_kaltsit.mp4"], "", "凯尔希：代表色青绿 #59F2D9；Mon3tr 熔毁爆炸", "fix", ["power", "whiteout"], "太快了，突然就炸了，不知道发生了什么"),
    ("浊心斯卡蒂吐息 fin_u", "ult_fx", [FIN + "u_skalter.mp4"], "", "浊心斯卡蒂：代表色深红 + 伊莎玛拉青绿；海嗣吐息光束", "fix", ["tiling", "power"], "吐息力量感不够；爆炸像好几个小素材拼接"),
    ("乌尔比安裂地 v1 fin_u", "ult_fx", [FIN + "u_ulpianus.mp4"], "", "乌尔比安：代表色深青；裂地", "fix", ["tiling", "power"], "力量感不够；小素材拼接"),
    ("乌尔比安放射版", "ult_fx", [CO + "ul_crack_v2_对照.mp4"], "right", "乌尔比安：代表色深青；裂地（放射裂缝版）", "fix", ["tiling", "power"], "像大海星"),
    ("乌尔比安裂地 v3（认可）", "ult_fx", [CO + "ul_crack_v3_对照.mp4"], "right", "乌尔比安：代表色深青；裂地", "pass", [], "做的挺好的"),
    ("德克萨斯 fin_u（无意见）", "ult_fx", [FIN + "u_texas.mp4"], "", "德克萨斯：剑雨（多段轻击）", "pass", [], "这轮没提意见"),
    ("选卡 坏（合成：贴键名 + 一张卡说明放大溢出）", "card_ui", [VR + "card_bad_synth.png"], "", "", "fix", ["raw_key", "font_size"], "（合成）露内部键名；说明字号不一"),
    ("选卡 修复后", "card_ui", [VR + "card_after/shot_choice_%d.png" % i for i in (5, 8, 16, 17)], "", "", "pass", [], "（修复后）"),
    ("同屏干员 坏（合成）", "record_sprite", [VR + "lineup/lineup_bad.png"], "", "", "fix", ["scale", "foot"], "（合成：第 3 人放大 1.35、第 5 人抬高）"),
    ("同屏干员 好", "record_sprite", [VR + "lineup/lineup_ok.png"], "", "", "pass", [], ""),
]
rows, total = [], 0.0
for name, lst, files, crop, note, want, want_items, quote in cases:
    if not files:
        print("跳过（无文件）", name)
        continue
    out = V.review(lst, files, note, model, 5, crop, quiet=True, think=think, votes=votes)
    got = {i["item"] for i in out["issues"] if i["severity"] == "high" or i.get("confidence", 0) >= 0.6}
    hit = [x for x in want_items if x in got]
    total += out["usd"]
    rows.append({"name": name, "want": want, "got": out["verdict"], "ok": want == out["verdict"], "want_items": want_items, "hit": hit,
                 "items": sorted(got), "usd": out["usd"], "summary": out["summary"], "quote": quote,
                 "issues": [(i["severity"], i["item"], i.get("time", ""), i["desc"]) for i in out["issues"]]})
    print(f"{'✓' if want == out['verdict'] else '✗'} {name}：期望 {want} 得 {out['verdict']}；期望项 {want_items} 抓到 {hit}；报 {sorted(got)}；{out['usd']:.4f} 美元", flush=True)
ok = sum(r["ok"] for r in rows)
print(f"结论准确 {ok}/{len(rows)}；合计 {total:.3f} 美元")
json.dump(rows, open(VR + f"eval_{model}_{think or 'auto'}_v{votes}.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
