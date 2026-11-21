# -*- coding: utf-8 -*-
"""B 方案帧条规格草稿（docs/365 §7）：按 build/spine_px/<id>/summary.json 与 cfg/<id>_px.json 写 cfg/<owner>_sprites.json。

接入时并进 game/data/characters/<id>.json 的 sprites；游戏现在不读这个文件。
动作的 fire（出手帧，按原作 OnAttack 事件）写在 cfg/<id>_px.json 的动作里；召唤物（tex_prefix / owner）槽名 = 召唤物键_动作。

    python tools/spine_px_sprites.py phantom
    python tools/spine_px_sprites.py dusk dusk_drgn      # 主人 + 召唤物写进同一份
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
CFG = os.path.join(ROOT, "tools", "spine_run_trial", "cfg")


def main(ids):
    owner = ids[0]
    out = {"_doc": "%s 帧条规格草稿（B 方案，docs/365 照做）：接入时并进 game/data/characters/%s.json 的 sprites；现在游戏不读这个文件。"
                   "192 画布 @2x / 96 画布 @1x，foot = 1x 原点 [48,76]（个别动作 256 画布，foot [64,92]）；frame_durations 为原作时长（按 docs/335 出手对时缩放），fire 按原作 OnAttack 事件" % (owner, owner)}
    for oid in ids:
        spec = json.load(open(os.path.join(CFG, "%s_px.json" % oid), encoding="utf-8"))
        summ = json.load(open(os.path.join(_GR.common_root(), "build", "spine_px", oid, "summary.json"), encoding="utf-8"))
        prefix = spec.get("tex_prefix", "op_%s" % oid)
        slot_pre = spec.get("slot_prefix", "" if oid == owner else oid + "_")
        for name, act in spec["actions"].items():
            s = summ.get(name) or summ.get(name + "@1x")
            if not s:
                continue
            c2 = s["canvas"] * (1 if name in summ else 2)   # @2x 画布（192 → foot [48,76]，256 → [64,92]）
            e = {"tex": "%s_%s" % (prefix, name), "frames": s["frames"], "fps": s["fps"], "foot": [c2 // 4, c2 // 4 + 28], "frame_durations": s["durations"]}
            if "fire" in act:
                e["fire"] = act["fire"]
            if name + "@1x" in summ and name not in summ:
                e["only_1x"] = True
            out[slot_pre + name] = e
    p = os.path.join(CFG, "%s_sprites.json" % owner)
    json.dump(out, open(p, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
    print(p, len(out) - 1)


if __name__ == "__main__":
    main(sys.argv[1:])
