"""Silent Eyjafjalla gallery captures and focused checks via godot_runner."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "build/eyja_volcanic_weight"
(OUT / "tmp").mkdir(parents=True, exist_ok=True)
tempfile.tempdir = str(OUT / "tmp")
sys.path.insert(0, str(ROOT / "tools"))
import godot_runner as gr


def capture(item):
    name, mode = item
    dest = OUT / sys.argv[2] / name
    dest.mkdir(parents=True, exist_ok=True)
    args = [gr.find_godot(), "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
            "--fixed-fps", "30", "--resolution", "960x540", "res://tests/elite_demo_shot.tscn", "--",
            "--regression", "--seed=1", "--shot_op=eyjafjalla", "--shot_stage=2", f"--shot_mode={mode}",
            "--shot_start=0.8", "--shot_every=2", "--shot_n=72", "--shot_w=960", "--shot_h=540",
            "--shot_dir=" + str(dest)]
    out, err, timeout = gr.run_godot(args, 180)
    (dest / "capture.log").write_text(out + err, encoding="utf-8")
    assert not timeout and not gr.script_errors(out, err), name
    assert len(list(dest.glob("f_*.png"))) == 72, name
    print(name, "72 actual viewport frames", flush=True)


if sys.argv[1] == "capture":
    gr.ensure_imported(str(ROOT / "game"))
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(capture, [("low_lob", 3), ("ignite", 1), ("volcano", 2)]))
elif sys.argv[1] == "test":
    args = [gr.find_godot(), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT / "game"),
            "res://tests/eyja_volcanic_weight_test.tscn", "--", "--regression", "--balance", "--seed=1", "--op=eyjafjalla"]
    out, err, timeout = gr.run_godot(args, 120)
    (OUT / "focused_test.log").write_text(out + err, encoding="utf-8")
    print(out[-2000:], err[-1000:])
    assert not timeout and not gr.script_errors(out, err) and "failures=0" in out
elif sys.argv[1] == "trace":
    import json
    import trace_base
    name = sys.argv[2]
    lines, error = trace_base.run_trace(str(ROOT / "game"), 1, "eyjafjalla", 120,
                                        ["--maxprog", "--sptest", "--norecruit"])
    assert error is None, error
    (OUT / f"{name}.txt").write_text("\n".join(lines), encoding="utf-8")
    data = json.loads((ROOT / "game/data/characters/eyjafjalla.json").read_text(encoding="utf-8"))
    (OUT / f"{name}_data.json").write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(name, len(lines), "deterministic trace lines", flush=True)
