"""1 倍头像素重画的参照图（docs/128 §3，给 Codex）：每人一张 art/incoming/codex_op1x_heads/<op>_ref.png
  左：PRTS 原作待机全身（设定色 / 瞳色参照，build/prts_ref/<op>/idle_f00.png）
  中：局内 @2x 待机首帧头部 ×4（现版细节）
  右：Spine 自动 1 倍待机首帧头部 ×8，带像素格；红十字 = 头骨原点（交付 PNG 的锚点），青框 = 建议画布 32×32（锚点在 (16, 26)）
先跑 tools/op_1x/make_op_1x.py（要 build/op_1x/<op>/run_run 的 idle_t0.png 与 report.json）。
用法：python -X utf8 tools/op_1x/head_refs.py [--only mizuki]"""
import argparse, json, os, sys
from PIL import Image, ImageDraw, ImageFont
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import godot_runner as _GR
import asset_paths
COMMON = _GR.common_root()
OUT = os.path.join(COMMON, "build", "op_1x")
INC = os.path.join(ROOT, "art", "incoming")
DST = os.path.join(INC, "codex_op1x_heads")
BG = (22, 40, 52, 255)
try:
    FONT = ImageFont.truetype("C:/Windows/Fonts/msyh.ttc", 14)
except OSError:
    FONT = ImageFont.load_default()
CW, CH, AX, AY = 32, 32, 16, 26   # 交付画布与锚点（锚点 = 头骨原点，大致在下巴下方颈部）


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--only", default=""); a = ap.parse_args()
    os.makedirs(DST, exist_ok=True)
    ops = sorted(f[:-5] for f in os.listdir(os.path.join(ROOT, "game", "data", "characters")) if f.endswith(".json"))
    if a.only:
        ops = [o for o in ops if o in a.only.split(",")]
    for op in ops:
        rd = os.path.join(OUT, op, "run_run")
        if not os.path.exists(os.path.join(rd, "report.json")):
            rd = os.path.join(OUT, op, "idle_stand")
        rep = json.load(open(os.path.join(rd, "report.json"), encoding="utf-8"))
        hx, hy = rep.get("idle_head_px") or [None, None]
        if hx is None:
            print(op, "无头骨，跳过"); continue
        one = Image.open(os.path.join(rd, "idle_t0.png")).convert("RGBA")
        box1 = (round(hx) - AX, round(hy) - AY, round(hx) - AX + CW, round(hy) - AY + CH)
        head1 = one.crop(box1)
        # 局内 @2x 待机首帧：同一锚点换算到 @2x 帧（compose 的平移：foot − 渲染锚点）
        sp = json.load(open(os.path.join(ROOT, "game", "data", "characters", op + ".json"), encoding="utf-8"))["sprites"]["idle"]
        sp = {"tex": sp} if isinstance(sp, str) else sp
        two = Image.open(asset_paths.runtime_png(sp["tex"] + "@2x")).convert("RGBA")
        n = int(sp.get("frames", max(1, two.width // two.height)))
        f2 = two.crop((0, 0, two.width // n, two.height))
        size = one.width; anc = (size / 2, 120 + (size - 128) / 2); foot = sp.get("foot", [32, 60])   # 同 make_op_1x.compose 的渲染锚点（脚底中心）
        ox, oy = foot[0] - anc[0], foot[1] - anc[1]
        bx, by = (box1[0] + ox) * 2, (box1[1] + oy) * 2
        head2 = f2.crop((round(bx), round(by), round(bx) + CW * 2, round(by) + CH * 2))
        prts_p = os.path.join(COMMON, "build", "prts_ref", op, "idle_f00.png")
        prts = Image.open(prts_p).convert("RGBA") if os.path.exists(prts_p) else None
        S1, S2 = 8, 4
        W = (300 if prts else 0) + CW * 2 * S2 + CW * S1 + 180
        H = max(CH * S1, 300) + 40
        o = Image.new("RGBA", (W, H), BG); d = ImageDraw.Draw(o); x = 10
        if prts:
            b = prts.getbbox(); p = prts.crop(b); p.thumbnail((290, 300))
            o.alpha_composite(p, (x, 30)); d.text((x, 6), "PRTS 原作待机（设定色参照）", fill=(230, 230, 230, 255), font=FONT); x += 300
        o.alpha_composite(head2.resize((CW * 2 * S2, CH * 2 * S2), Image.NEAREST), (x, 30)); d.text((x, 6), "局内 @2x 现版 ×4", fill=(230, 230, 230, 255), font=FONT); x += CW * 2 * S2 + 20
        big = head1.resize((CW * S1, CH * S1), Image.NEAREST)
        g = Image.new("RGBA", big.size, (0, 0, 0, 0)); gd = ImageDraw.Draw(g)
        for i in range(CW + 1):
            gd.line([(i * S1, 0), (i * S1, CH * S1)], fill=(255, 255, 255, 28))
        for j in range(CH + 1):
            gd.line([(0, j * S1), (CW * S1, j * S1)], fill=(255, 255, 255, 28))
        big.alpha_composite(g)
        cx, cy = AX * S1 + S1 // 2, AY * S1 + S1 // 2
        bd = ImageDraw.Draw(big)
        bd.line([(cx - 10, cy), (cx + 10, cy)], fill=(255, 60, 60, 255), width=2); bd.line([(cx, cy - 10), (cx, cy + 10)], fill=(255, 60, 60, 255), width=2)
        bd.rectangle([0, 0, CW * S1 - 1, CH * S1 - 1], outline=(80, 220, 230, 255))
        o.alpha_composite(big, (x, 30)); d.text((x, 6), f"Spine 自动 1 倍 ×8（{CW}×{CH}，红十字 = 锚点 ({AX},{AY})）", fill=(230, 230, 230, 255), font=FONT)
        o.save(os.path.join(DST, op + "_ref.png"))
        head1.save(os.path.join(DST, op + "_auto1x.png"))
        print(op, "ok")


if __name__ == "__main__":
    main()
