"""Capture real-world final Boss FX at normal scale; never launches a focused or audible window.

python tools/probes/final_boss_fx_preview.py --boss paranoia --quality high --tag candidate01
Only writes beneath build/boss_fx_review. Existing frames are never silently replaced.
"""
import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as runner

BOSSES = ["paranoia", "knight_boss", "ishar", "izumik"]
FPS = 15
MOVE_SECONDS = 12.0
SHEET_SECONDS = [1.2, 2.0, 3.1, 6.5, 11.0]


def encode(folder):
    paths = sorted(folder.glob("frame_*.png"))
    if not paths:
        raise RuntimeError("No preview frames")
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "15", "-i", str(folder / "frame_%05d.png"),
                    "-c:v", "libx264", "-crf", "17", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(folder.parent / (folder.name + ".mp4"))], check=True)
    # One palette keeps the terrain stable between GIF frames; MP4 retains original resolution.
    filters = "fps=12,scale=640:360:flags=neighbor,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle"
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", "15", "-i", str(folder / "frame_%05d.png"),
                    "-filter_complex", filters, "-loop", "0", str(folder.parent / (folder.name + ".gif"))], check=True)
    # Derive offsets from the capture so --encode-only also supports old 8-second clips.
    frames_per_move = len(paths) // 3
    sheet = Image.new("RGB", (768 * len(SHEET_SECONDS), 432 * 3))
    for move in range(3):
        for stage, seconds in enumerate(SHEET_SECONDS):
            index = move * frames_per_move + min(frames_per_move - 1, int(seconds * FPS))
            with Image.open(paths[index]) as image:
                sheet.paste(image.convert("RGB").resize((768, 432), Image.Resampling.NEAREST), (stage * 768, move * 432))
    sheet.save(folder.parent / (folder.name + "_sheet.png"))
    return len(paths)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--boss", choices=BOSSES + ["all"], default="paranoia")
    parser.add_argument("--quality", choices=["high", "low"], default="high")
    parser.add_argument("--tag", required=True)
    parser.add_argument("--encode-only", action="store_true")
    parser.add_argument("--combos", action="store_true", help="Knight only: three 18-second segments with one forced opener and live AI")
    args = parser.parse_args()
    if args.combos and args.boss != "knight_boss":
        parser.error("--combos requires --boss knight_boss")
    move_seconds = 18.0 if args.combos else MOVE_SECONDS
    base = (ROOT / "build/boss_fx_review" / args.tag).resolve()
    if not base.is_relative_to((ROOT / "build/boss_fx_review").resolve()):
        raise ValueError("Output must remain under build/boss_fx_review")
    base.mkdir(parents=True, exist_ok=True)
    for name in ["game/scripts/render/boss_attack_draw.gd", "game/scripts/enemies/final_attacks.gd"]:
        target = base / (Path(name).name + ".baseline")
        if not target.exists():
            target.write_bytes(subprocess.check_output(["git", "show", "8b923c4bc:" + name], cwd=ROOT))
    for boss in BOSSES if args.boss == "all" else [args.boss]:
        folder = base / (boss + "_" + args.quality)
        if not args.encode_only:
            if folder.exists() and list(folder.glob("frame_*.png")):
                raise ValueError("Choose a new --tag to preserve prior frames: " + str(folder))
            folder.mkdir(exist_ok=True)
            # Pin the code that the process loads, even while another worker edits it.
            sources = {}
            for name in ["game/scripts/render/boss_attack_draw.gd", "game/scripts/enemies/final_attacks.gd", "game/scripts/render/final_attack_grains.gd", "game/scripts/render/final_boss_materials.gd", "game/scripts/render/paranoia_bubble.gd", "game/tests/final_boss_fx_preview.gd", "game/tests/knight_combo_preview.gd", "game/scripts/boss_ai.gd", "game/scripts/enemies/bosses/knight_boss.gd", "game/scripts/run/enemies.gd", "game/scripts/enemies/telegraph.gd", "game/scripts/render/world.gd", "game/scripts/run/combat.gd"]:
                path = ROOT / name
                if path.exists():
                    data = path.read_bytes()
                    (folder / (path.name + ".capture_source")).write_bytes(data)
                    sources[name] = hashlib.sha256(data).hexdigest()
            (folder / "source_hashes.json").write_text(json.dumps(sources, indent=2), encoding="utf-8")
            command = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
                       ("res://tests/knight_combo_preview.tscn" if args.combos else "res://tests/final_boss_fx_preview.tscn"), "--", "--fx-preview", "--seed=271027", "--boss=" + boss, "--quality=" + args.quality, "--shotdir=" + folder.as_posix()]
            out, err, timed_out = runner.run_godot(command, 480)
            (folder / "run.log").write_text(out + "\n" + err, encoding="utf-8")
            if timed_out or runner.script_errors(out, err) or "FX_PREVIEW_DONE" not in out:
                raise RuntimeError("Preview failed: " + str(folder / "run.log") + "\n" + (out + err)[-4000:])
        count = encode(folder)
        if not args.encode_only and count != int(3 * move_seconds * FPS):
            raise RuntimeError("Incomplete capture: expected " + str(int(3 * move_seconds * FPS)) + " frames, got " + str(count))
        log = (folder / "run.log").read_text(encoding="utf-8")
        metrics = [json.loads(line.removeprefix("FX_PREVIEW_METRICS ")) for line in log.splitlines() if line.startswith("FX_PREVIEW_METRICS ")]
        if not args.encode_only and len(metrics) != 3:
            raise RuntimeError("Missing per-move metrics: " + str(folder))
        report = {"move_metrics": metrics, "boss": boss, "quality": args.quality, "frames": count, "fps": 15, "source_size": [1280, 720], "gif_size": [640, 360], "gif_fps": 12,
                  "move_seconds": count / (3 * FPS), "duration_seconds": count / FPS,
                  "sheet_sample_seconds": [min(t, (count // 3 - 1) / FPS) for t in SHEET_SECONDS],
                  "simulation": "Production enemies_sys.update + boss AI + shots/telegraphs/status; one forced opener per segment, continuous invulnerable player, no scripted follow-up" if args.combos else "Actual force_move + telegraph + hazard + optical rendering; ordinary AI paused; invulnerable player follows a continuous 100px/s route with turns at 2.6, 4.4, 6.5 and 8.7 seconds; wind/cooldown/pose clocks advance"}
        (folder / "capture.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(json.dumps(report), flush=True)


if __name__ == "__main__":
    main()
