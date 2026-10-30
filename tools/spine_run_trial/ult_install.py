"""终结技身体条接入（docs/207）：run_trial 出的逐帧 → 游戏帧条 op_<id>_ult_spine@2x / @1x + 干员 json 的 sprites.ult_spine / extra_sprites + 贴图索引。

用法：python -X utf8 tools/spine_run_trial/ult_install.py <id> [<id> ...]
  读 tools/spine_run_trial/cfg/<id>_ult.json（帧时长 durations、画布 canvas、可选 vis_order）和 build/spine_anim_pilot/<id>_ult/frames/fNN.png。
  json 里已有 ult_spine 就整段替换（重出后再跑一遍即可）。玩法里播不播由 ult/spine_body 开关决定（ult_moves_b / _c 的 _spine_body）。
"""
import importlib.util, json, os, re, subprocess, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
_s = importlib.util.spec_from_file_location("op1x", os.path.join(ROOT, "tools", "op_1x", "make_op_1x.py"))
op1x = importlib.util.module_from_spec(_s); _s.loader.exec_module(op1x)


def install(op):
    cfg = json.load(open(os.path.join(ROOT, "tools", "spine_run_trial", "cfg", op + "_ult.json"), encoding="utf-8"))
    S = cfg.get("canvas", 128)
    fdir = os.path.join(ROOT, "build", "spine_anim_pilot", op + "_ult", "frames")
    frames = [Image.open(os.path.join(fdir, f)).convert("RGBA") for f in sorted(os.listdir(fdir)) if re.fullmatch(r"f\d\d\.png", f)]
    n = len(frames)
    strip = Image.new("RGBA", (S * n, S))
    for i, im in enumerate(frames):
        strip.paste(im, (S * i, 0))
    out = os.path.join(ROOT, "game", "art", "operators", op)
    tex = "op_%s_ult_spine" % op
    strip.save(os.path.join(out, tex + "@2x.png"), optimize=True)
    op1x.downsample(strip, n).save(os.path.join(out, tex + "@1x.png"), optimize=True)
    dur = cfg["durations"]
    assert len(dur) == n, (op, len(dur), n)
    pad = (S - 128) // 2
    foot = [(64 + pad) // 2, (120 + pad) // 2]   # 1x 逻辑坐标：原点 (64,120)@2x 随画布居中平移
    spec = {"tex": tex, "frames": n, "foot": foot, "frame_durations": dur}
    if cfg.get("vis_order"):   # 循环段按帧号表重复播（character._vis_frames），不重复画帧
        spec["vis_order"] = cfg["vis_order"]
    d0 = json.load(open(os.path.join(ROOT, "game", "data", "characters", op + ".json"), encoding="utf-8"))
    top = d0["sprites"].get("foot", [32, 60])
    base = int(d0["sprites"].get("size", 64))
    if [float(top[0]) + (S // 2 - base) / 2, float(top[1]) + (S // 2 - base) / 2] != [float(x) for x in foot]:   # 契约 V2：foot = 顶层 foot + 透明加边
        spec["foot_exempt"] = "终结技身体条：原作 Spine 像素化，原点 (64,120)@2x 随画布居中，与顶层小数 foot / 画布口径差 <1px（docs/207）"
    spec["_doc"] = "终结技身体条（docs/207，本地原作 Spine 自产：tools/spine_run_trial cfg/%s_ult.json）；ult/spine_body=1 时终结技开头播，缺省关" % op
    p = os.path.join(ROOT, "game", "data", "characters", op + ".json")
    s = open(p, encoding="utf-8", newline="").read()
    nl = "\r\n" if "\r\n" in s else "\n"
    # 各干员 json 缩进 / 换行风格不同：照 sprites 第一个键的缩进写
    m0 = re.search(r'\n[ \t]*"sprites": \{\r?\n([ \t]*)"', s)
    ind = m0.group(1)
    body = json.dumps(spec, ensure_ascii=False, indent=1).split("\n")
    blk = nl.join([ind + '"ult_spine": ' + body[0]] + [ind + ln for ln in body[1:]])
    m = re.search(r'\r?\n[ \t]*"ult_spine": \{.*?\n[ \t]*\},?', s, re.S)
    if m:
        s = s[:m.start()] + nl + blk + ("," if m.group(0).endswith(",") else "") + s[m.end():]
    else:
        k = m0.end() - len(ind) - 1
        s = s[:k] + blk + "," + nl + s[k:]
    e0 = s.index('"extra_sprites": [') + len('"extra_sprites": [')
    if '"ult_spine"' not in s[e0:s.index("]", e0)]:
        s = s[:e0] + '"ult_spine", ' + s[e0:]
    json.loads(s)
    open(p, "w", encoding="utf-8", newline="").write(s)
    print(op, "帧", n, "画布", S, "foot", foot, "合计 %.2f 秒" % sum(dur), "播放 %.2f 秒" % sum(dur[i] for i in cfg.get("vis_order", range(n))))


if __name__ == "__main__":
    for op in sys.argv[1:]:
        install(op)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "asset_index.py")], check=True)
