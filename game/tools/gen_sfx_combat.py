"""Reproducible original combat synthesis; no sampled game recordings.
Run: python game/tools/gen_sfx_combat.py [sound ...]
Uses the existing event synthesizer's filters, WAV writer and 44.1 kHz format.
Each sound owns its seed; regenerating one cannot alter any other sound.
"""
import sys
import numpy as np
from gen_sfx_events import T, lp, hp, bp, env, glide, save


def cannon(heavy=False, impact=False):
    sec = 1.1 if heavy else (0.7 if impact else 0.48)
    t = T(sec)
    rng = np.random.default_rng(2700 + int(heavy) * 2 + int(impact))
    n = rng.standard_normal(len(t))
    # Sharp pressure crack, descending barrel resonance and a rolling low tail.
    crack = hp(n, 1600) * env(sec, 0.001, 0.018) * 0.55
    body = glide(sec, 125 if impact else 180, 36) * env(sec, 0.002, 0.19 if heavy else 0.11)
    rumble = lp(n, 620 if impact else 360) * env(sec, 0.006, 0.3 if heavy else 0.13) * 2.8
    debris = bp(n, 900, 4200) * env(sec, 0.02, 0.2) * (0.36 if impact else 0.12)
    return crack + body + rumble + debris


def screech():
    sec = 0.8
    t = T(sec)
    rng = np.random.default_rng(2711)
    f = 430 + 600 * np.sin(np.pi * t / sec) + 45 * np.sin(2 * np.pi * 31 * t)
    phase = 2 * np.pi * np.cumsum(f) / 44100
    voice = np.sin(phase) + 0.28 * np.sin(phase * 1.51) + 0.18 * np.sin(phase * 2.07)
    return (voice + 0.28 * bp(rng.standard_normal(len(t)), 700, 3400)) * np.sin(np.pi * t / sec) ** 1.5


def spit():
    sec = 0.34
    t = T(sec)
    n = np.random.default_rng(2712).standard_normal(len(t))
    return bp(n, 400, 3200) * env(sec, 0.004, 0.075) + 0.5 * glide(sec, 530, 110) * env(sec, 0.002, 0.04)


def bite():
    sec = 0.27
    n = np.random.default_rng(2713).standard_normal(len(T(sec)))
    return bp(n, 500, 6000) * env(sec, 0.001, 0.035) + 0.7 * glide(sec, 160, 65) * env(sec, 0.001, 0.06)


SOUNDS = {"op_wisadel_atk": lambda: cannon(), "op_wisadel_hit": lambda: cannon(impact=True),
          "op_wisadel_big": lambda: cannon(heavy=True, impact=True),
          "enemy_screech": screech, "enemy_spit": spit, "enemy_bite": bite}

if __name__ == "__main__":
    for name in (sys.argv[1:] or SOUNDS):
        save(name, SOUNDS[name](), peak=0.84)
