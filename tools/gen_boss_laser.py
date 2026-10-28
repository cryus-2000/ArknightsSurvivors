"""Boss 激光帧条（docs/142b §8.5，10-25 用户定用 Kanpelle · Ultimate Laser Pack）：取素材包白色版，按 Boss 专属色换色，
导出运行时 fx_kp_<boss>_<段>.png（game/art/fx/）。段 = src / mid / hit（持续 4 帧）与 src_on / mid_on / hit_on（开启 4 帧；关闭 = 开启倒放），
每帧 16 × 48（1x 美术像素，光束沿 +x，竖直居中），4 帧横排 = 64 × 48。运行时画法在 render/boss_beam.gd。

素材包本体不入库（art/third_party，许可见 art/third_party/README.md），本脚本只读它；导出的是加工后的游戏资源。

    python tools/gen_boss_laser.py               # 全部（LASER_BOSSES 里列的）
    python tools/gen_boss_laser.py iberia        # 只出一只
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import asset_paths
CANDIDATES = [os.path.join(ROOT, "art", "third_party"), os.path.join(ROOT, "..", "..", "..", "art", "third_party")]   # 工作树里没有时用主仓库那份
SUB = os.path.join("lasers", "kanpelle_ultimate_laser_pack", "Ultimate Laser Pack", "Laser_Beam_Spritesheet_WHITE.png")

# §8.5 表里用激光的 6 只；颜色 = enemies.json 的 bcol（docs/142b §8.4 专属色，游戏里 vfx.boss_color 读同一份）
LASER_BOSSES = ["iberia", "carmen", "paranoia", "ishar", "bishop", "archon"]   # 手炮 / 狙击 → 封锁线 / 凝视 / 三线扫射与共鸣 / 统一与换位 / 蚀潮吐息


def boss_colors():
    import json
    d = json.load(open(os.path.join(ROOT, "game", "data", "enemies.json"), encoding="utf-8"))
    d = d.get("enemies", d)
    return {k: tuple(d[k]["bcol"]) for k in LASER_BOSSES}
ROWS = {"src": 0, "src_on": 1, "mid": 2, "mid_on": 3, "hit": 4, "hit_on": 5}


def recolor(im, col):
    """亮度映射到专属色四阶色板（暗 → 本色 → 亮 → 近白），保留透明度（同 tools/probes/fx_candidates_sheet.recolor）"""
    stops = [(0.0, tuple(c * 0.18 for c in col)), (0.45, tuple(c * 0.75 for c in col)),
             (0.75, col), (1.0, tuple(min(1.0, c * 0.4 + 0.65) for c in col))]
    out = im.copy()
    px, po = im.load(), out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            L = max((0.299 * r + 0.587 * g + 0.114 * b) / 255.0, max(r, g, b) / 255.0 * 0.85)
            c = stops[-1][1]
            for i in range(len(stops) - 1):
                if L <= stops[i + 1][0]:
                    t = (L - stops[i][0]) / max(1e-6, stops[i + 1][0] - stops[i][0])
                    c = tuple(stops[i][1][k] + (stops[i + 1][1][k] - stops[i][1][k]) * t for k in range(3))
                    break
            po[x, y] = (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), a)
    return out


def main():
    src = next((os.path.join(r, SUB) for r in CANDIDATES if os.path.exists(os.path.join(r, SUB))), None)
    if src is None:
        sys.exit("找不到素材包白色版：art/third_party/" + SUB.replace(os.sep, "/"))
    sheet = Image.open(src).convert("RGBA")
    cols = boss_colors()
    want = sys.argv[1:] or LASER_BOSSES
    for boss in want:
        col = cols[boss]
        for seg, row in ROWS.items():
            strip = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
            for f in range(4):
                cell = sheet.crop((f * 48 + 16, row * 48, f * 48 + 32, row * 48 + 48))
                strip.alpha_composite(recolor(cell, col), (f * 16, 0))
            p = asset_paths.out_png(f"fx_kp_{boss}_{seg}")
            strip.save(p, optimize=True)
            print(p)
    import asset_index
    idx, _ = asset_index.build()
    open(asset_index.INDEX, "w", encoding="utf-8", newline="\n").write(asset_index.dump(idx))


if __name__ == "__main__":
    main()
