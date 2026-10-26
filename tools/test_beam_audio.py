"""Spectral and loudness guard for the shared Boss beam cues. Run without Godot."""
import re
import unittest
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]


def metrics(path):
    with wave.open(str(path)) as w:
        assert w.getnchannels() == 1 and w.getsampwidth() == 2
        rate = w.getframerate()
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
    power = abs(np.fft.rfft(x)) ** 2
    freq = np.fft.rfftfreq(len(x), 1 / rate)
    width = min(len(x), round(rate * 0.1))
    accum = np.concatenate(([0], np.cumsum(x * x)))
    db = lambda v: float(20 * np.log10(max(float(v), 1e-9)))
    return dict(seconds=len(x) / rate, peak_dbfs=db(max(abs(x))),
                rms_dbfs=db(np.sqrt(np.mean(x * x))),
                rms100_dbfs=db(np.sqrt(max((accum[width:] - accum[:-width]) / width))),
                high2k_percent=float(power[freq >= 2000].sum() / power.sum() * 100),
                high4k_percent=float(power[freq >= 4000].sum() / power.sum() * 100))


class BeamAudioTest(unittest.TestCase):
    def test_cues_leave_room_for_music_without_losing_the_warning(self):
        source = (ROOT / "game/scripts/sfx.gd").read_text(encoding="utf-8")
        volumes = source.split("const CUE_VOL :=", 1)[1].split("}", 1)[0]
        for name, duration in (("cue_beam_start", 0.9), ("cue_beam_hit", 0.8)):
            with self.subTest(cue=name):
                m = metrics(ROOT / "game/audio/sfx" / (name + ".wav"))
                volume = float(re.search('"' + name + r'":\s*(-?[\d.]+)', volumes)[1])
                self.assertAlmostEqual(m["seconds"], duration, places=4)
                self.assertLess(m["high2k_percent"], 5)
                self.assertLess(m["high4k_percent"], 0.5)
                self.assertLessEqual(m["peak_dbfs"], -6)
                self.assertLess(m["rms100_dbfs"] + volume, -22)
                self.assertGreater(m["rms100_dbfs"] + volume, -30)


if __name__ == "__main__":
    unittest.main()
