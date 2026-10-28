#!/usr/bin/env python3
"""把 Codex 10-23 怪物重画（art/archive/incoming_1028/enemy_redraw_1023/animations/）装进运行时：
- 本体 / 发光层的 @2x 帧条复制成运行时贴图（asset_paths.out_png，game/art/enemies/…）<runtime_key>@2x / _emit@2x（1x 只给 BOSS_1X 里的 Boss 装，boss_intro 要读）
- 写 game/data/enemy_pixels.json 里每个 runtime_key 的 spec（anchor = origin_2x / frame_size_2x，scale 1.0，frames，frame_size = @2x 单帧）
- 写 game/data/enemy_redraw.json：runtime_key -> {frames, event_frames, release_frame, sample_times, loop, duration}，运行时选帧用
- 改 game/scripts/art.gd 的 V6_FRAMES：已有敌人帧条换新帧数；每个 _death 帧条登记 [帧数, 帧数 / 时长]
可重复运行。契约见 enemy_redraw_1023/animations/HANDOFF.md、integration_map.json。
"""
import json, re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "archive" / "incoming_1028" / "enemy_redraw_1023" / "animations"
sys.path.insert(0, str(ROOT / "tools"))
import asset_paths
PIX = ROOT / "game" / "data" / "enemy_pixels.json"
OUT = ROOT / "game" / "data" / "enemy_redraw.json"
ART_GD = ROOT / "game" / "scripts" / "art.gd"
BEGIN = "\t# >>> enemy_redraw 死亡帧条（tools/install_enemy_redraw.py 生成，别手改）\n"
END = "\t# <<< enemy_redraw\n"
BOSS_1X = {"e_path", "e_izumik", "e_saint", "e_saint_dark", "e_bishop", "e_archon", "e_immortal", "e_paranoia", "e_ishar", "e_knight"}


def patch_art_gd(meta: dict) -> None:
    s = ART_GD.read_text(encoding="utf-8")
    i = s.index("const V6_FRAMES := {")
    j = s.index("\n}\n", i)
    blk = s[i:j]
    if BEGIN in blk:
        a = blk.index(BEGIN)
        b = blk.index(END) + len(END)
        blk = blk[:a].rstrip("\n") + blk[b:]
    gen = {k: v for k, v in meta.items() if k.endswith("_death")}

    def fix(m):
        k = m.group(1)
        if k in meta:
            return '"%s": [%d, %s]' % (k, meta[k]["frames"], m.group(3))
        return m.group(0)

    blk = re.sub(r'"(e_[a-z_0-9]+)": \[(\d+), ([0-9.]+)\]', fix, blk)
    for k in gen:
        blk = re.sub(r'"%s": \[\d+, [0-9.]+\],? ?' % re.escape(k), "", blk)
    lines = [BEGIN]
    ks = sorted(gen)
    for n in range(0, len(ks), 4):
        lines.append("\t" + " ".join('"%s": [%d, %.1f],' % (k, gen[k]["frames"], gen[k]["frames"] / max(0.1, gen[k]["duration"])) for k in ks[n:n + 4]) + "\n")
    lines.append(END)
    blk = blk.rstrip("\n") + "\n" + "".join(lines).rstrip("\n")
    ART_GD.write_text(s[:i] + blk + s[j:], encoding="utf-8")


def main() -> int:
    imap = json.loads((SRC / "integration_map.json").read_text(encoding="utf-8"))
    pix = json.loads(PIX.read_text(encoding="utf-8"))
    meta = {}
    manifests = {}
    for row in imap["files"]:
        key = row["candidate_runtime_key"]
        fid = row["id"]
        if fid not in manifests:
            manifests[fid] = json.loads((SRC / fid / "manifest.json").read_text(encoding="utf-8"))
        act = next((a for a in manifests[fid]["actions"] if a["action"] == row["action"]), {})
        for body, suffix in ((row["body"], ""), (row["emit"], "_emit")):
            src2 = SRC / body
            src1 = Path(str(src2).replace("@2x.png", ".png"))
            # 1x 只给 Boss 本体装：A.tex() 有 @2x 就不读 1x，只有 boss_intro.gd 按 1x 原图量裁切框（docs/131 §1.3）
            pairs = ((src1, ".png"), (src2, "@2x.png")) if key in BOSS_1X and suffix == "" else ((src2, "@2x.png"),)
            for src, tail in pairs:
                if not src.exists():
                    print("缺文件", src)
                    return 1
                shutil.copyfile(src, asset_paths.out_png(f"{key}{suffix}{tail}"[:-4]))
        w, h = row["frame_size_2x"]
        ox, oy = row["origin_2x"]
        pix[key] = {"anchor": [ox / w, oy / h], "scale": 1.0, "preserve_palette": True, "frames": row["frames"], "frame_size": [w, h]}
        meta[key] = {"frames": row["frames"], "event_frames": row["event_frames"], "release_frame": row["release_frame"],
                     "sample_times": act.get("sample_times", []), "loop": act.get("loop", False), "duration": act.get("duration_seconds", 0.0)}
    PIX.write_text(json.dumps(pix, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    OUT.write_text(json.dumps(meta, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    patch_art_gd(meta)
    import asset_index
    idx, _ = asset_index.build()
    open(asset_index.INDEX, "w", encoding="utf-8", newline="\n").write(asset_index.dump(idx))
    print("装入 %d 组动作" % len(meta))
    return 0


if __name__ == "__main__":
    sys.exit(main())
