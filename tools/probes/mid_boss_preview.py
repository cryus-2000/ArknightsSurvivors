"""塑路者 / 接潮组实机录像（docs/170）：每段一幕 18 秒，正式 AI，队长无敌绕圈跑；窗口经 godot_runner 放副屏 / 屏幕外、静音、不抢焦点。

python tools/probes/mid_boss_preview.py --tag v1 [--quality high|low]
输出 build/boss_path_tide/<tag>/：每段一个 mp4（原色 H.264，单个约 20 MB）、capture.json（含源码 SHA256）；中间帧编码完即删
"""
import argparse
import hashlib
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
SEG_SECONDS = 18
NAMES = ["path_act1", "path_act2", "tide_archon_act1", "tide_archon_act2", "tide_immortal_act2"]
SOURCES = ["game/scripts/enemies/mid_cards.gd", "game/scripts/render/mid_card_draw.gd", "game/scripts/enemies/bosses/path.gd", "game/scripts/enemies/bosses/bishop.gd",
           "game/scripts/enemies/bosses/archon.gd", "game/scripts/enemies/bosses/immortal.gd", "game/tests/mid_boss_preview.gd", "game/scripts/render/world.gd",
           "game/scripts/render/telegraph_draw.gd", "game/data/enemies.json"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", required=True)
    ap.add_argument("--quality", choices=["high", "low"], default="high")
    a = ap.parse_args()
    base = ROOT / "build/boss_path_tide" / a.tag
    frames = base / ("frames_" + a.quality)
    if frames.exists() and any(frames.iterdir()):
        raise SystemExit("choose a new --tag: " + str(frames))
    frames.mkdir(parents=True, exist_ok=True)
    hashes = {n: hashlib.sha256((ROOT / n).read_bytes()).hexdigest() for n in SOURCES}
    cmd = [runner.find_godot(), "--path", str(ROOT / "game"), "--audio-driver", "Dummy", "--resolution", "1280x720", "--fixed-fps", "30",
           "res://tests/mid_boss_preview.tscn", "--", "--fx-preview", "--quality=" + a.quality, "--shotdir=" + frames.as_posix()]
    out, err, to = runner.run_godot(cmd, 900)
    (base / "run.log").write_text(out + "\n" + err, encoding="utf-8")
    if to or runner.script_errors(out, err) or "MID_PREVIEW_DONE" not in out:
        raise SystemExit("preview failed, see " + str(base / "run.log") + "\n" + (out + err)[-3000:])
    paths = sorted(frames.glob("frame_*.png"))
    per = SEG_SECONDS * FPS
    if len(paths) != per * len(NAMES):
        raise SystemExit("incomplete capture %d" % len(paths))
    ff = imageio_ffmpeg.get_ffmpeg_exe()
    enc = ["-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    for i, nm in enumerate(NAMES):
        subprocess.run([ff, "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(FPS), "-start_number", str(i * per), "-i", str(frames / "frame_%05d.png"),
                        "-frames:v", str(per)] + enc + [str(base / ("%d_%s_%s.mp4" % (i + 1, nm, a.quality)))], check=True)
    metrics = [json.loads(l.split(" ", 1)[1]) for l in out.splitlines() if l.startswith("MID_PREVIEW_METRICS ")]
    (base / ("capture_%s.json" % a.quality)).write_text(json.dumps({"segments": NAMES, "seconds": SEG_SECONDS, "fps": FPS, "metrics": metrics, "source_sha256": hashes,
        "simulation": "production enemies_sys.update + boss AI + shots/telegraph/status; no forced moves; invulnerable leader circling r190 at 110 px/s"}, ensure_ascii=False, indent=2), encoding="utf-8")
    shutil.rmtree(frames)
    print(json.dumps(metrics, ensure_ascii=False))


if __name__ == "__main__":
    main()
