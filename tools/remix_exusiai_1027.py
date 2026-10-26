"""Reproducible softer Exusiai mix from the approved pre-change WAVs in Git.

Keeps the existing licensed recordings and timing. No new source material.
Run from the repository root with --apply to write the eight WAVs.
"""
import argparse
import io
import json
import subprocess
import wave
from pathlib import Path

import numpy as np
from scipy.signal import butter, sosfilt

BASE = "151d572a4"
NAMES = ["atk", "atk_b", "atk_c", "hit", "s1", "s2", "s3", "big"]


def db(x):
    return float(20 * np.log10(max(float(x), 1e-9)))


def remix(raw):
    with wave.open(io.BytesIO(raw)) as w:
        assert w.getsampwidth() == 2 and w.getnchannels() == 1
        rate = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
    low = sosfilt(butter(2, 3600, fs=rate, output="sos"), x)
    y = (0.4 * x + 0.6 * low) * 10 ** (-2 / 20)
    # Preserve the attack; fade the last 8 ms to avoid truncated tail clicks.
    n = min(len(y), int(rate * 0.008))
    y[-n:] *= np.linspace(1, 0, n)
    assert np.max(np.abs(y)) < 1 and len(x) == len(y)
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.round(y * 32767).astype("<i2").tobytes())
    return out.getvalue(), {
        "rate": rate, "seconds": len(y) / rate,
        "before_peak_dbfs": db(np.max(np.abs(x))), "after_peak_dbfs": db(np.max(np.abs(y))),
        "before_rms_dbfs": db(np.sqrt(np.mean(x*x))), "after_rms_dbfs": db(np.sqrt(np.mean(y*y))),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    report = {}
    for name in NAMES:
        p = Path(f"game/audio/sfx/op_exusiai_{name}.wav")
        raw = subprocess.check_output(["git", "show", f"{BASE}:{p.as_posix()}"])
        result, report[name] = remix(raw)
        if args.apply:
            p.write_bytes(result)
    folder = Path("build/boss_complete")
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "exusiai_levels.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
