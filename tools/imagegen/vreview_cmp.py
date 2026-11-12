"""vreview 新旧模型对比（docs/337）：同一批素材、同一检查单，逐模型跑，记录命中 / 误报 / 耗时 / token。
用法：python tools/imagegen/vreview_cmp.py <模型> [表决次数]   结果存 build/vreview/cmp_<模型>.json
素材在 build/vreview/cmp/（由 card_text_1106 前后对照图裁出 + 合成坏片，见文档）。
"""
import sys, json, time
sys.path.insert(0, __file__.rsplit("/", 1)[0].rsplit("\\", 1)[0])
import vreview as V
D = str(V.ROOT / "build/vreview/cmp") + "/"
# (名, 检查单, 文件, note, 期望, 期望项, 来源)
C = []
for n in ("levelup", "recruit", "relic", "shop", "swap"):
    C.append((f"卡面改前·{n}", "card_ui", [D + f"card_{n}_before.png"], "", "fix", ["font_size", "overflow", "align"], "用户退回（11-06 字号不一、说明过大）"))
for n in ("levelup", "relic"):
    C.append((f"合成键名外露·{n}", "card_ui", [D + f"card_{n}_rawkey_synth.png"], "", "fix", ["raw_key"], "合成：改后图贴 control_dur"))
C.append(("合成白闪 0.6 秒", "ult_fx", [D + "white_synth.mp4"], "羁绊技录像，代表色青", "fix", ["whiteout"], "合成：2.0–2.6 秒整屏纯白"))
C.append(("合成红铺满屏 1.5 秒", "ult_fx", [D + "red_synth.mp4"], "羁绊技录像，代表色青", "fix", ["color", "whiteout"], "合成：1.5–3.0 秒整屏红 80%（对应用户退回的红铺满屏）"))
C.append(("合成跳帧", "ult_fx", [D + "jump_synth.mp4"], "羁绊技录像", "fix", ["frame_jump"], "合成：硬剪掉 2.0–3.5 秒"))
for n in ("levelup", "recruit", "relic", "shop"):
    C.append((f"卡面改后·{n}", "card_ui", [D + f"card_{n}_after.png"], "", "pass", [], "用户通过"))
C.append(("羁绊录像原片（灯下审决 v6）", "ult_fx", [D + "good_bond.mp4"], "羁绊技录像，代表色青", "pass", [], "最终版（视为通过）"))
model = sys.argv[1]
votes = int(sys.argv[2]) if len(sys.argv) > 2 else 3
rows = []
for name, lst, files, note, want, items, src in C:
    t0 = time.time()
    o = V.review(lst, files, note, model, 5, "", quiet=True, think="low", votes=votes)
    dt = time.time() - t0
    high = [i for i in o["issues"] if i["severity"] == "high"]
    got = sorted({i["item"] for i in high})
    r = {"name": name, "src": src, "want": want, "want_items": items, "verdict": o["verdict"], "high_items": got,
         "item_hit": [x for x in items if x in got], "n_high": len(high), "sec": round(dt, 1), "tin": o["tokens_in"], "tout": o["tokens_out"],
         "usd": o["usd"], "issues": [(i["severity"], i["item"], i["desc"]) for i in o["issues"]]}
    rows.append(r)
    print(f"{name}: 期望 {want} 得 {o['verdict']}；高严重项 {got}；{dt:.0f}s {o['tokens_in']}+{o['tokens_out']} ${o['usd']:.4f}", flush=True)
json.dump(rows, open(V.ROOT / f"build/vreview/cmp_{model}.json", "w", encoding="utf-8"), ensure_ascii=False, indent=1)
