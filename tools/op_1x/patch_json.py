"""给干员 json 的 sprites 加 move_attack 槽（帧数 / 脚底同普攻），斯卡蒂普攻换新帧条（docs/128；make_op_1x.py 之后跑）。
只在文本里插一行 / 改一段，不重排整个文件。可重复跑（已有 move_attack 槽就跳过）。"""
import json, os, re, sys
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CH = os.path.join(ROOT, "game", "data", "characters")
INC = os.path.join(ROOT, "art", "incoming")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths
for f in sorted(os.listdir(CH)):
    if not f.endswith(".json"):
        continue
    op = f[:-5]
    p = os.path.join(CH, f)
    txt = open(p, encoding="utf-8").read()
    d = json.loads(txt)
    sp = d.get("sprites", {})
    att = sp.get("attack")
    att = {"tex": att} if isinstance(att, str) else att
    mtex = f"op_{op}_move_attack"
    changed = False
    if op == "skadi" and att and att.get("tex") == "op_skadi_attack":
        # 新普攻「侧向劈砍」9 帧、出手第 5 帧；动作窗口（出手时刻 / 总长）不变，帧时长按关键帧节奏在前 / 后两段内分配
        ms = [60, 110, 70, 40, 40, 110, 80, 90, 90]
        F = 5
        def split(pre, post):
            a, b = sum(ms[:F]), sum(ms[F:])
            return [round(pre * m / a, 6) for m in ms[:F]] + [round(post * m / b, 6) for m in ms[F:]]
        ft, tot = att["fire_time"], sum(att["frame_durations"])
        at = att["attack_timing"]
        new = dict(att, tex="op_skadi_attack_v2", frames=9, fire=F, frame_durations=split(ft, tot - ft),
                   _doc="10-23 用户逐版定的「侧向劈砍」（tools/spine_run_trial cfg/skadi_sideslash_power.json）：从跑步拖剑位起手、剑不过肩不挡脸，"
                        "预备后仰 → 两帧快挥重心前冲 → 出手定格 → 冲过头回收；9 帧 96 画布，出手第 5 帧；动作窗口沿用旧条（同 seed 不变）")
        new["attack_timing"] = dict(at, frame_durations=split(at["fire_time"], at["duration"] - at["fire_time"]))
        m = re.search(r'\n(\s*)"attack": \{', txt)
        ind = m.group(1)
        start = m.start() + 1
        # 找到 attack 对象的结束括号
        depth, i = 0, txt.index("{", start)
        while True:
            if txt[i] == "{": depth += 1
            elif txt[i] == "}":
                depth -= 1
                if depth == 0: break
            i += 1
        txt = txt[:start] + ind + '"attack": ' + json.dumps(new, ensure_ascii=False) + txt[i + 1:]
        att = new
        changed = True
    if att and "move_attack" not in sp and os.path.exists(asset_paths.runtime_png(mtex + "@1x")):
        slot = {"tex": mtex, "frames": int(att.get("frames", 8)), "foot": att.get("foot", sp.get("foot")),
                "_doc": "10-23 移动攻击（docs/128 §3）：普攻上半身 + 跑步步态腿，原作 Spine 1 倍像素化（tools/op_1x/make_op_1x.py）；帧序与普攻一一对应，只换贴图"}
        m = re.search(r'\n(\s*)"sprites": \{\n(\s*)', txt)
        ind = m.group(2)
        txt = txt[:m.end()] + '"move_attack": ' + json.dumps(slot, ensure_ascii=False) + ",\n" + ind + txt[m.end():]
        changed = True
    if changed:
        json.loads(txt)
        open(p, "w", encoding="utf-8", newline="\n").write(txt)
        print("patched", op)
