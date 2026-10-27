"""Record Saint Iberia / Saint Carmen attack groups (docs/171): four 14-second live-AI segments per boss.

python tools/probes/saint_card_preview.py --boss iberia --tag v1
Writes build/boss_saints/<tag>/<boss>/frame_*.png, <boss>_cards.mp4 and <boss>_sheet.png. Window is moved off-screen and muted by godot_runner.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as runner

FPS = 15
SEGS = 4
SEG_SECONDS = 14.0
SHEET_SECONDS = [1.5, 3.5, 6.0, 9.0, 12.5]


def encode(folder, out_base):
    paths = sorted(folder.glob("frame_*.png"))
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    subprocess.run([ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(folder / "frame_%05d.png"),
                    "-c:v", "libx264", "-crf", "20", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out_base) + "_cards.mp4"], check=True)
    per = len(paths) // SEGS
    sheet = Image.new("RGB", (640 * len(SHEET_SECONDS), 360 * SEGS))
    for s in range(SEGS):
        for i, sec in enumerate(SHEET_SECONDS):
            with Image.open(paths[s * per + min(per - 1, int(sec * FPS))]) as im:
                sheet.paste(im.convert("RGB").resize((640, 360), Image.Resampling.LANCZOS), (i * 640, s * 360))
    sheet.save(str(out_base) + "_sheet.png")
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
    metrics = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in out.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
    (base / (a.boss + "_capture.json")).write_text(json.dumps({"frames": n, "fps": FPS, "segments": metrics}, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"boss": a.boss, "frames": n, "segments": metrics}, ensure_ascii=False))


if __name__ == "__main__":
    main()
