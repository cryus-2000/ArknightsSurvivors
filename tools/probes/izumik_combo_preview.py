"""伊祖米克连携实机录像（docs/170）：六组连携各 16 秒，正式 AI，窗口放副屏 / 屏幕外、静音。

python tools/probes/izumik_combo_preview.py --tag v1 [--quality high|low]
输出 build/boss_izumik/<tag>/：每组一个 mp4、整段 mp4、拼图 sheet.png、metrics.json。
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
SEG = 16.0
SAMPLES = [1.5, 4.0, 6.5, 9.0, 12.0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--quality", choices=["high", "low"], default="high")
    ap.add_argument("--encode-only", action="store_true")
    ap.add_argument("--only", default="", help="只录这几组，逗号分隔，从 0 起")
    a = ap.parse_args()
    out = (ROOT / "build/boss_izumik" / a.tag).resolve()
    frames = out / ("frames_" + a.quality)
    if not a.encode_only:
        if frames.exists() and list(frames.glob("frame_*.png")):
            raise SystemExit("choose a new --tag: " + str(frames))
        frames.mkdir(parents=True, exist_ok=True)
        cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
               "res://tests/izumik_combo_preview.tscn", "--", "--shotdir=" + frames.as_posix(), "--quality=" + a.quality] + (["--only=" + a.only] if a.only else [])
        so, se, timed_out = runner.run_godot(cmd, 900)
        (out / ("run_" + a.quality + ".log")).write_text(so + "\n" + se, encoding="utf-8")
        if timed_out or runner.script_errors(so, se) or "FX_PREVIEW_DONE" not in so:
            raise SystemExit("preview failed, see " + str(out / ("run_" + a.quality + ".log")))
    log = (out / ("run_" + a.quality + ".log")).read_text(encoding="utf-8")
    metrics = [json.loads(l.removeprefix("FX_PREVIEW_METRICS ")) for l in log.splitlines() if l.startswith("FX_PREVIEW_METRICS ")]
    (out / ("metrics_" + a.quality + ".json")).write_text(json.dumps(metrics, ensure_ascii=False, indent=1), encoding="utf-8")
    paths = sorted(frames.glob("frame_*.png"))
    per = int(SEG * FPS)
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    enc = ["-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-i", str(frames / "frame_%05d.png")] + enc
                   + [str(out / ("izumik_all_" + a.quality + ".mp4"))], check=True)
    for i, m in enumerate(metrics):
        subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-start_number", str(i * per),
                        "-i", str(frames / "frame_%05d.png"), "-frames:v", str(per)] + enc
                       + [str(out / ("%d_%s_%s.mp4" % (i + 1, m["combo"], a.quality)))], check=True)
    sheet = Image.new("RGB", (640 * len(SAMPLES), 360 * len(metrics)))
    for i in range(len(metrics)):
        for j, s in enumerate(SAMPLES):
            k = min(len(paths) - 1, i * per + int(s * FPS))
            with Image.open(paths[k]) as im:
                sheet.paste(im.convert("RGB").resize((640, 360), Image.Resampling.LANCZOS), (j * 640, i * 360))
    sheet.save(out / ("izumik_sheet_" + a.quality + ".png"))
    print(json.dumps({"frames": len(paths), "segments": len(metrics), "out": str(out)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
