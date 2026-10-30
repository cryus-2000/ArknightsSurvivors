"""终结技身体条接入（docs/207）：run_trial 出的逐帧 → 游戏帧条 op_<id>_ult_spine@2x / @1x + 干员 json 的 sprites.ult_spine / extra_sprites + 贴图索引。

用法：python -X utf8 tools/spine_run_trial/ult_install.py <id> [<id> ...]
  读 tools/spine_run_trial/cfg/<id>_ult.json（帧时长 durations、画布 canvas）和 build/spine_anim_pilot/<id>_ult/frames/fNN.png。
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
    spec = {"tex": tex, "frames": n, "foot": foot, "frame_durations": dur,
            "_doc": "终结技身体条（docs/207，本地原作 Spine 自产：tools/spine_run_trial cfg/%s_ult.json）；ult/spine_body=1 时终结技开头播，缺省关" % op}
    p = os.path.join(ROOT, "game", "data", "characters", op + ".json")
    s = open(p, encoding="utf-8").read()
    blk = json.dumps({"ult_spine": spec}, ensure_ascii=False, indent=1)[2:-2]   # 去掉外层花括号
    blk = "\n".join(" " + ln for ln in blk.split("\n"))   # sprites 内部缩进 2 格
    m = re.search(r'\n  "ult_spine": \{.*?\n  \},?', s, re.S)
    if m:
        s = s[:m.start()] + "\n" + blk + ("," if m.group(0).endswith(",") else "") + s[m.end():]
    else:
        i = s.index('\n "sprites": {') + len('\n "sprites": {')
        s = s[:i] + "\n" + blk + "," + s[i:]
    if '"ult_spine"' not in s[s.index('"extra_sprites"'):s.index("]", s.index('"extra_sprites"'))]:
        i = s.index('"extra_sprites": [') + len('"extra_sprites": [')
        s = s[:i] + '\n  "ult_spine",' + s[i:]
    json.loads(s)
    open(p, "w", encoding="utf-8").write(s)
    print(op, "帧", n, "画布", S, "foot", foot, "合计 %.2f 秒" % sum(dur))


if __name__ == "__main__":
    for op in sys.argv[1:]:
        install(op)
    subprocess.run([sys.executable, os.path.join(ROOT, "tools", "asset_index.py")], check=True)
