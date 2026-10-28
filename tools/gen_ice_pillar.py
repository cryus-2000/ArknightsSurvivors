"""最后的骑士冰柱（用户 10-25：「骑士的桩可以设置成冰柱，而且多一点，4–5 个」；docs/142b §9）：
取 ansimuz Gothicvania Magic Pack 11 的 Ice_b（64 × 96，23 帧：破土 → 冰柱 → 崩碎），切成三段帧条导出成运行时贴图（game/art/world/props/）：
  prop_ice_pillar_rise.png   破土升起 3 帧（原第 8–10 帧）
  prop_ice_pillar.png        立着 4 帧循环（原第 11 / 13 / 15 / 17 帧）
  prop_ice_pillar_break.png  崩碎 6 帧（原第 18–23 帧）
都是 1x 美术像素、64 × 96 一帧、横排，脚底在第 94 行。素材包本体不入库（art/third_party，已购：可商用可改、不得再分发），本脚本只读它。

    python tools/gen_ice_pillar.py
"""
import glob, os, re, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths
SUB = os.path.join("ansimuz_explosions_magic", "15_gothicvania_magic_pack_11", "sprites", "Ice_b")
CANDIDATES = [os.path.join(ROOT, "art", "third_party"), os.path.join(ROOT, "..", "..", "..", "art", "third_party")]   # 工作树里没有时用主仓库那份
PARTS = {"prop_ice_pillar_rise": [7, 8, 9], "prop_ice_pillar": [10, 12, 14, 16], "prop_ice_pillar_break": [17, 18, 19, 20, 21, 22]}


def main():
    d = next((os.path.join(r, SUB) for r in CANDIDATES if os.path.isdir(os.path.join(r, SUB))), None)
    if d is None:
        sys.exit("找不到素材：art/third_party/" + SUB.replace(os.sep, "/"))
    key = lambda p: [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", os.path.basename(p))]
    frames = [Image.open(p).convert("RGBA") for p in sorted(glob.glob(os.path.join(d, "*.png")), key=key)]
    for name, idx in PARTS.items():
        strip = Image.new("RGBA", (64 * len(idx), 96), (0, 0, 0, 0))
        for k, i in enumerate(idx):
            strip.alpha_composite(frames[i], (64 * k, 0))
        p = asset_paths.out_png(name)
        strip.save(p, optimize=True)
        print(p, strip.size)
    import asset_index
    idx, _ = asset_index.build()
    open(asset_index.INDEX, "w", encoding="utf-8", newline="\n").write(asset_index.dump(idx))


if __name__ == "__main__":
    main()
