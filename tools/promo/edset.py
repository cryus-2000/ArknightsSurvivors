# -*- coding: utf-8 -*-
"""改镜头表一项：python tools/promo/edset.py <main|vert> <id> key=json值 …（如 f=1290 zoom=2.8 'cap={"text":"…"}' src=\"X.mp4\"；值为 del 时删掉该键）"""
import json, os, sys
p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "edit.json")
e = json.load(open(p, encoding="utf-8"))
sh = next(s for s in e[sys.argv[1]] if s["id"] == sys.argv[2])
for kv in sys.argv[3:]:
    k, v = kv.split("=", 1)
    if v == "del":
        sh.pop(k, None)
    else:
        try:
            sh[k] = json.loads(v)
        except ValueError:
            sh[k] = v
json.dump(e, open(p, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print(sh)
