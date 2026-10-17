"""Capture the first five seconds of real enemy-demo AI; no all-moves coverage claim."""
import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from godot_runner import find_godot, run_godot
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ids", help="Comma-separated enemy IDs; defaults to all entries")
    parser.add_argument("--statuses", action="store_true", help="Capture initial state, palette policy, stun, hit and atlas; no AI timeline")
    parser.add_argument("--phase2", action="store_true", help="Use the existing enemy-demo phase-2 setup")
    parser.add_argument("--isolated", action="store_true", help="Give each enemy a fresh Godot process (up to three runner slots)")
    parser.add_argument("--package-existing", action="store_true", help="Package successful per-enemy logs after retrying failures, without rerunning Godot")
    args = parser.parse_args()
    output = ROOT / ("build/enemy_status_captures" if args.statuses else "build/enemy_animation_captures")
    if args.phase2:
        output = output.with_name(output.name + "_phase2")
    output.mkdir(parents=True, exist_ok=True)
    temp = ROOT / "build/test_tmp"
    temp.mkdir(parents=True, exist_ok=True)
    os.environ["TEMP"] = os.environ["TMP"] = str(temp)
    roster = json.loads((ROOT / "game/data/enemies.json").read_text(encoding="utf-8"))["enemies"]
    ids = args.ids.split(",") if args.ids else list(roster)
    if not ids or any(key not in roster for key in ids):
        parser.error("Unknown or empty enemy IDs")
    metadata_path = ROOT / "game/data/enemy_pixels.json"
    metadata_bytes = metadata_path.read_bytes()
    metadata = json.loads(metadata_bytes)
    source_hashes = {name: hashlib.sha256((ROOT / "art/incoming" / (name + "@2x.png")).read_bytes()).hexdigest()
                     for name in metadata}
    command = [find_godot(), "--path", str(ROOT / "game"),
               "res://tests/enemy_animation_gallery.tscn", "--",
               "--enemy-animation-output=" + output.as_posix(),
               "--enemy-animation-ids=" + ",".join(ids)]
    if args.statuses:
        command.append("--enemy-animation-statuses")
    if args.phase2:
        command.append("--enemy-animation-phase2")
    if args.package_existing:
        reference = json.loads((output / "capture_manifest.json").read_text(encoding="utf-8"))
        if reference['metadata_sha256'] != hashlib.sha256(metadata_bytes).hexdigest() or reference['source_sha256'] != source_hashes:
            raise SystemExit("Existing capture sources differ from current assets")
        out = ''.join((output / key / 'run.log').read_text(encoding='utf-8') for key in ids)
        err, timed_out = '', False
    elif args.isolated:
        def capture_one(key):
            cmd = ["--enemy-animation-ids=" + key if arg.startswith("--enemy-animation-ids=") else arg for arg in command]
            result = run_godot(cmd, timeout=180)
            folder = output / key
            folder.mkdir(exist_ok=True)
            (folder / "run.log").write_text(result[0] + result[1], encoding="utf-8")
            print(key + (" failed" if result[2] or "ERROR:" in result[0] + result[1] else " captured"), flush=True)
            return result
        with ThreadPoolExecutor(max_workers=3) as pool:
            results = list(pool.map(capture_one, ids))
        out = ''.join(result[0] for result in results)
        err = ''.join(result[1] for result in results)
        timed_out = any(result[2] for result in results)
    else:
        out, err, timed_out = run_godot(command, timeout=max(180, len(ids) * 60))
    (output / "run.log").write_text(out + err, encoding="utf-8")
    print(out, flush=True)
    if timed_out or any(token in out + err for token in ("ERROR:", "WARNING:", "leaked")):
        print(err, file=sys.stderr)
        raise SystemExit("Capture failed; inspect run.log")
    if metadata_path.read_bytes() != metadata_bytes or any(
            hashlib.sha256((ROOT / "art/incoming" / (name + "@2x.png")).read_bytes()).hexdigest() != digest
            for name, digest in source_hashes.items()):
        raise SystemExit("Assets changed during capture; rerun after the delivery is frozen")
    cards = []
    coverage = {}
    for key in ids:
        marker = "ENEMY STATUS CAPTURE: " + key + " 5 states" if args.statuses else "ENEMY ANIMATION CAPTURE: " + key + " 50 frames / 5 seconds"
        assert marker in out
        folder = output / key
        evidence = json.loads((folder / "evidence.json").read_text(encoding="utf-8"))
        assert len(evidence["frames"]) == (5 if args.statuses else 50)
        coverage[key] = {"captures": len(evidence["frames"]),
                         "phases": sorted({rec["phase"] for rec in evidence["frames"]}),
                         "move_names": sorted({rec["move_name"] for rec in evidence["frames"]} - {""}),
                         "attack_window_captures": sum(rec["attack_active"] for rec in evidence["frames"]),
                         "positions": len({tuple(rec["position"]) for rec in evidence["frames"]})}
        frames = []
        for rec in evidence["frames"]:
            with Image.open(folder / rec["file"]) as im:
                frames.append(im.convert("RGB"))
        frames[0].save(folder / "preview.gif", save_all=True, append_images=frames[1:], duration=800 if args.statuses else 100, loop=0)
        pictures = ''.join(f'<figure><figcaption>{html.escape(rec["state"])}</figcaption><img loading="lazy" src="{key}/{rec["file"]}"></figure>'
                           for rec in evidence['frames']) if args.statuses else f'<img loading="lazy" src="{key}/preview.gif">'
        cards.append(f'<section><h2>{html.escape(roster[key]["name"])} ({key})</h2>'
                     f'{pictures}<a href="{key}/evidence.json">运行记录</a></section>')
    scope = ('初始姿态的原色策略、颜色增强策略、眩晕、受击及图集五状态。保色素材不会强制增强颜色；此动图仅切换状态，不是动作。'
             if args.statuses else '真实 AI 起始 5 秒，60 Hz 模拟、10 fps 录像。')
    (output / "review.html").write_text('<!doctype html><meta charset="utf-8"><title>怪物实机动画检查</title>'
        '<style>body{background:#18212b;color:#eee;font:16px sans-serif;margin:24px}img{display:block;max-width:100%;image-rendering:pixelated}a{color:#8dd}</style>'
        '<h1>怪物实机动画检查</h1><p>' + scope + ' 使用游戏实际资源、锚点、缩放和绘制路径。'
        '本页没有覆盖全部招式、后续阶段或死亡，不代表逐动作视觉验收通过。</p>' + ''.join(cards), encoding='utf-8')
    (output / "capture_manifest.json").write_text(json.dumps({"ids": ids,
        "metadata_sha256": hashlib.sha256(metadata_bytes).hexdigest(), "source_sha256": source_hashes,
        "scope": scope, "visual_approved": False}, indent=2), encoding="utf-8")
    (output / "coverage.json").write_text(json.dumps(coverage, ensure_ascii=False, indent=2), encoding="utf-8")
    print(output / "review.html")


if __name__ == "__main__":
    main()
