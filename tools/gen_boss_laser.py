"""Boss 激光帧条（docs/142b §8.5，10-25 用户定用 Kanpelle · Ultimate Laser Pack）：取素材包白色版，按 Boss 专属色换色，
导出 art/incoming/fx_kp_<boss>_<段>.png。段 = src / mid / hit（持续 4 帧）与 src_on / mid_on / hit_on（开启 4 帧；关闭 = 开启倒放），
每帧 16 × 48（1x 美术像素，光束沿 +x，竖直居中），4 帧横排 = 64 × 48。运行时画法在 render/boss_beam.gd。

素材包本体不入库（art/third_party，许可见 art/third_party/README.md），本脚本只读它；导出的是加工后的游戏资源。

    python tools/gen_boss_laser.py               # 全部（BOSSES 里列的）
    python tools/gen_boss_laser.py iberia        # 只出一只
"""
import os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "incoming")
CANDIDATES = [os.path.join(ROOT, "art", "third_party"), os.path.join(ROOT, "..", "..", "..", "art", "third_party")]   # 工作树里没有时用主仓库那份
SUB = os.path.join("lasers", "kanpelle_ultimate_laser_pack", "Ultimate Laser Pack", "Laser_Beam_Spritesheet_WHITE.png")

# docs/142b §8.4 专属色（近似 RGB 0–1）；样板阶段只出用得到的
BOSSES = {
    "iberia": (1.0, 0.5, 0.2),   # 圣徒伊比利亚 · 炮火橙（手炮）
}
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
    want = sys.argv[1:] or list(BOSSES)
    for boss in want:
        col = BOSSES[boss]
        for seg, row in ROWS.items():
            strip = Image.new("RGBA", (64, 48), (0, 0, 0, 0))
            for f in range(4):
                cell = sheet.crop((f * 48 + 16, row * 48, f * 48 + 32, row * 48 + 48))
                strip.alpha_composite(recolor(cell, col), (f * 16, 0))
            p = os.path.join(OUT, f"fx_kp_{boss}_{seg}.png")
            strip.save(p, optimize=True)
            print(p)


if __name__ == "__main__":
    main()
