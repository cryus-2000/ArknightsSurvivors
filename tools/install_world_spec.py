"""局内贴图规格补齐（Codex 10-24 交付 art/incoming/world_spec_1024/）装进运行时文件名。

    python tools/install_world_spec.py [交付目录]      # 缺省 art/incoming/world_spec_1024

- C 组（地形 / 珊瑚 / 神经弹 / 柱 / 墙 / 沉船）：尺寸锚点不变，直接覆盖原名文件
- 无人机 drone_laser.png（24×20 × 4）、经验结晶 gem_small / gem_big（8×10 / 11×14）+ 各自 _emit：覆盖 / 新增
- 商人：新增 merchant@1x.png（96×48 两帧，局内读它）；界面立绘 merchant@2x.png 不动
- 溟痕：新增 mire_tile / mire_tile_b / mire_edge 及各自 _emit（都是原生 1x、无 @2x）；
  fx_mire_dissolve 覆盖为新 1x 六帧，并删掉旧 @2x（否则 A.tex 优先读 @2x 的旧图）；fx_mire_dissolve_emit 新增
绘制接入见 world/map.gd（溟痕平铺 + 围边）、render/world.gd（黑潮圈边、退散、结晶、无人机）。"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INC = os.path.join(ROOT, "art", "incoming")
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(INC, "world_spec_1024")

COPY = [
    ("coral/coral.png", "coral.png"),
    ("prop_pillar/prop_pillar.png", "prop_pillar.png"),
    ("prop_wall/prop_wall.png", "prop_wall.png"),
    ("prop_wreck/prop_wreck.png", "prop_wreck.png"),
    ("terrain_ridge/terrain_ridge.png", "terrain_ridge.png"),
    ("terrain_peak/terrain_peak.png", "terrain_peak.png"),
    ("proj_floater_nerve/proj_floater_nerve.png", "proj_floater_nerve.png"),
    ("drone_laser/drone_laser.png", "drone_laser.png"),
    ("gems/gem_small.png", "gem_small.png"),
    ("gems/gem_small_emit.png", "gem_small_emit.png"),
    ("gems/gem_big.png", "gem_big.png"),
    ("gems/gem_big_emit.png", "gem_big_emit.png"),
    ("merchant/merchant@1x.png", "merchant@1x.png"),
    ("mire/fx_mire_dissolve.png", "fx_mire_dissolve.png"),
    ("mire/fx_mire_dissolve_emit.png", "fx_mire_dissolve_emit.png"),
]
REMOVE = ["fx_mire_dissolve@2x.png"]

# 溟痕围边切片（mire/HANDOFF.md，f0；f1 的 x + 288）：N E S W、外角 NW NE SE SW、内角 NW NE SE SW
EDGE_R = [(0, 0, 64, 16), (64, 0, 16, 64), (80, 0, 64, 16), (144, 0, 16, 64),
          (160, 0, 16, 16), (176, 0, 16, 16), (192, 0, 16, 16), (208, 0, 16, 16),
          (224, 0, 16, 16), (240, 0, 16, 16), (256, 0, 16, 16), (272, 0, 16, 16)]
MC = 16   # 栅格边长（美术像素），world/map.gd MIRE_CELL 同值


def build_mire(src: str) -> None:
    """预合成两张图集，运行时 1:1 取格画：
    mire_tile_ab(_emit).png  256×64：A f0、A f1、B f0、B f1（各 64×64）
    mire_edge_atlas(_emit).png  256×768：x = (相位 px/16 × 4 + py/16) × 16，y = ((变体 × 12 + 片) × 2 + 帧) × 16。
      每格 = 该变体底图在全局相位 (px + x, py + y) 的像素 × 边片遮罩（N / S 取 (px + x, y)，E / W 取 (x, py + y)，角片取 (x, y)）；
      边片的不透明像素本来就等于底图同相位像素（HANDOFF「相位」一节），所以任意 16 格位都和内区脉络连续"""
    from PIL import Image
    md = os.path.join(src, "mire")
    tiles = [Image.open(os.path.join(md, n)).convert("RGBA") for n in ("mire_tile.png", "mire_tile_b.png")]
    emits = [Image.open(os.path.join(md, n)).convert("RGBA") for n in ("mire_tile_emit.png", "mire_tile_b_emit.png")]
    edge = Image.open(os.path.join(md, "mire_edge.png")).convert("RGBA")
    for name, ims in (("mire_tile_ab.png", tiles), ("mire_tile_ab_emit.png", emits)):
        ab = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
        ab.paste(ims[0], (0, 0))
        ab.paste(ims[1], (128, 0))
        ab.save(os.path.join(INC, name))
        print("合成 " + name)
    at = Image.new("RGBA", (16 * MC, 48 * MC), (0, 0, 0, 0))
    ae = Image.new("RGBA", (16 * MC, 48 * MC), (0, 0, 0, 0))
    tp = [t.load() for t in tiles]
    ep = [e.load() for e in emits]
    gp = edge.load()
    atp, aep = at.load(), ae.load()
    for v in range(2):
        for t, (rx, ry, rw, rh) in enumerate(EDGE_R):
            for f in range(2):
                oy = ((v * 12 + t) * 2 + f) * MC
                for pxi in range(4):
                    for pyi in range(4):
                        ox = (pxi * 4 + pyi) * MC
                        for y in range(MC):
                            for x in range(MC):
                                if t in (0, 2):
                                    mx, my = pxi * 16 + x, y
                                elif t in (1, 3):
                                    mx, my = x, pyi * 16 + y
                                else:
                                    mx, my = x, y
                                if gp[rx + f * 288 + mx, ry + my][3] < 128:
                                    continue
                                tx, ty = (pxi * 16 + x) % 64 + f * 64, (pyi * 16 + y) % 64
                                atp[ox + x, oy + y] = tp[v][tx, ty]
                                e = ep[v][tx, ty]
                                if e[3] >= 128:
                                    aep[ox + x, oy + y] = e
    at.save(os.path.join(INC, "mire_edge_atlas.png"))
    ae.save(os.path.join(INC, "mire_edge_atlas_emit.png"))
    print("合成 mire_edge_atlas(_emit).png")


def main() -> int:
    if not os.path.isdir(SRC):
        print("找不到交付目录：" + SRC)
        return 1
    for a, b in COPY:
        s = os.path.join(SRC, a)
        if not os.path.exists(s):
            print("缺 " + a)
            return 1
        shutil.copyfile(s, os.path.join(INC, b))
        print("装 %s → %s" % (a, b))
    for b in REMOVE:
        p = os.path.join(INC, b)
        if os.path.exists(p):
            os.remove(p)
            print("删 " + b)
    build_mire(SRC)
    return 0


if __name__ == "__main__":
    sys.exit(main())
