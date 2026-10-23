"""1 倍帧条对照图：每条一行，左 @2x 原条（缩半显示到同尺寸）、右 @1x，各取若干帧，脚底线标红。
用法：python -X utf8 tools/op_1x/sheet_1x.py mizuki,skadi [out.png]"""
import json, os, sys
from PIL import Image, ImageDraw
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
INC = os.path.join(ROOT, "art", "incoming")
ops = sys.argv[1].split(",")
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "..", "op_1x_sheet.png")
rows = []
for op in ops:
    sp = json.load(open(os.path.join(ROOT, "game", "data", "characters", op + ".json"), encoding="utf-8"))["sprites"]
    slots = {}
    for k, v in sp.items():
        v = {"tex": v} if isinstance(v, str) else v
        if isinstance(v, dict) and isinstance(v.get("tex"), str):
            slots[v["tex"]] = (k, v)
    for t in sorted(f[:-7] for f in os.listdir(INC) if f.endswith("@1x.png") and (f.startswith("op_" + op) or f.startswith(op))):
        k, v = slots.get(t, (t, {}))
        one = Image.open(os.path.join(INC, t + "@1x.png")).convert("RGBA")
        n = int(v.get("frames", 0)) or max(1, one.width // one.height)
        fw = one.width // n
        two_p = os.path.join(INC, t + "@2x.png")
        two = Image.open(two_p).convert("RGBA") if os.path.exists(two_p) else None
        foot = v.get("foot")
        idx = list(range(0, n, max(1, n // 6)))[:6]
        S = 3
        row = Image.new("RGBA", (fw * S * len(idx) * 2 + 20, one.height * S + 14), (22, 40, 52, 255))
        d = ImageDraw.Draw(row)
        d.text((2, 1), f"{op} {k} ({t}) {n}f", fill=(230, 230, 230, 255))
        for j, i in enumerate(idx):
            if two:
                fw2 = two.width // n
                c = two.crop((i * fw2, 0, i * fw2 + fw2, two.height)).resize((fw * S, one.height * S), Image.NEAREST)
                row.alpha_composite(c, (j * fw * S, 14))
            c = one.crop((i * fw, 0, i * fw + fw, one.height)).resize((fw * S, one.height * S), Image.NEAREST)
            row.alpha_composite(c, (fw * S * len(idx) + 20 + j * fw * S, 14))
        if foot:
            y = 14 + int(foot[1] * S)
            d.line([(0, y), (row.width, y)], fill=(255, 60, 60, 120))
        rows.append(row)
W = max(r.width for r in rows); H = sum(r.height for r in rows)
o = Image.new("RGBA", (W, H), (22, 40, 52, 255)); y = 0
for r in rows:
    o.alpha_composite(r, (0, y)); y += r.height
o.save(out); print(out, o.size)
