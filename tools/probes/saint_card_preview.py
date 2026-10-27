"""Record Saint Iberia / Saint Carmen attack groups (docs/171): four 14-second live-AI segments per boss.

python tools/probes/saint_card_preview.py --boss iberia --tag v1
Writes build/boss_saints/<tag>/<boss>_cards.mp4 only (H.264, original colour/speed; frames deleted after encoding). Delete clips once confirmed or superseded. Window is moved off-screen and muted by godot_runner.
"""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as runner

FPS = 15
SEGS = 4
SEG_SECONDS = 14.0


def encode(folder, out_base):
    paths = sorted(folder.glob("frame_*.png"))
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(folder / "frame_%05d.png"),
                    "-c:v", "libx264", "-crf", "20", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out_base) + "_cards.mp4"], check=True)
    return len(paths)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--boss", choices=["iberia", "carmen"], required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--quality", choices=["high", "low"], default="high")
    a = ap.parse_args()
    base = ROOT / "build/boss_saints" / a.tag
    folder = base / a.boss
    if folder.exists() and list(folder.glob("frame_*.png")):
        raise SystemExit("Choose a new --tag: " + str(folder))
    folder.mkdir(parents=True, exist_ok=True)
    cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
           "res://tests/saint_card_preview.tscn", "--", "--boss=" + a.boss, "--quality=" + a.quality, "--shotdir=" + folder.as_posix()]
    out, err, timed_out = runner.run_godot(cmd, 600)
    (folder / "run.log").write_text(out + "\n" + err, encoding="utf-8")
    if timed_out or runner.script_errors(out, err) or "FX_PREVIEW_DONE" not in out:
        raise SystemExit("Preview failed: " + str(folder / "run.log") + "\n" + (out + err)[-3000:])
    n = encode(folder, base / a.boss)
    for f in folder.glob("frame_*.png"):
        f.unlink()   # 中间帧用完就删
    metrics = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in out.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
    (base / (a.boss + "_capture.json")).write_text(json.dumps({"frames": n, "fps": FPS, "segments": metrics}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"boss": a.boss, "frames": n, "segments": metrics}, ensure_ascii=False))


if __name__ == "__main__":
    main()
