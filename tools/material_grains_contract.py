"""Particle pool contract only. One silent headless process; no asset import."""
from pathlib import Path
import os, sys, msvcrt
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/material_grains_check"
OUT.mkdir(parents=True, exist_ok=True)
FILES = {'project.godot': '[application]\nconfig/name="Particle contract"\n[autoload]\nCfg="*res://cfg.gd"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', 'cfg.gd': 'extends Node\nvar quality := "high"\n', 'balance.gd': 'extends RefCounted\nstatic func v(_key, _default):\n\treturn 1.0\n', 'test.gd': 'extends SceneTree\nclass FakeGame extends Node2D:\n\tvar optical_on := true\n\tvar squad = null\n\tvar vrng := RandomNumberGenerator.new()\nclass FakeSquad extends RefCounted:\n\tvar op = null\n\tfunc get_op(_id):\n\t\treturn op\nclass FakeOp extends RefCounted:\n\tvar pfx: Array = []\nfunc _initialize():\n\tvar pool = load("res://grains.gd").new()\n\tvar game := FakeGame.new()\n\tpool.setup(game)\n\tvar img := Image.create(32, 32, false, Image.FORMAT_RGBA8)\n\timg.fill(Color(0.5, 0.7, 0.9, 0.8))\n\tvar tx := ImageTexture.create_from_image(img)\n\tassert(pool.material_burst("fx_flam_hit", tx, 1, Vector2.ZERO, 0, 1, Vector2(16,16), false, Color.WHITE))\n\tassert(pool.pos.size() == 48)\n\tvar ready := 0\n\tfor wait in pool.delay:\n\t\tif wait == 0.0:\n\t\t\tready += 1\n\tassert(ready == 8)\n\tvar pending_life: float = pool.life[5]\n\tvar pending_pos: Vector2 = pool.pos[5]\n\tpool.step(0.1)\n\tassert(is_equal_approx(pool.life[5], pending_life))\n\tassert(pool.pos[5] == pending_pos)\n\tassert(is_equal_approx(pool.delay[5], 0.15))\n\tpool.life[0] = pool.lmax[0] * 0.1\n\tvar ash: Color = pool.grain_color(0)\n\tassert(is_equal_approx(ash.r, ash.g) and is_equal_approx(ash.g, ash.b))\n\tassert(is_equal_approx(pool.col[0].a, 0.8))\n\tpool._frame_n["fire"] = 96\n\tassert(not pool.material_burst("fx_flam_hit", tx, 1, Vector2.ZERO, 0, 1, Vector2.ZERO, false, Color.WHITE))\n\tassert(pool.pos.size() == 48)\n\tpool.step(1.0)\n\tassert(pool.pos.is_empty())\n\tpool.level = 1\n\tassert(pool.material_burst("fx_water_splash", tx, 1, Vector2.ZERO, 0, 1, Vector2.ZERO, false, Color.WHITE))\n\tassert(pool.pos.size() == 32)\n\tpool.level = 0\n\tassert(not pool.material_burst("fx_corrode_hit", tx, 1, Vector2.ZERO, 0, 1, Vector2.ZERO, false, Color.WHITE))\n\tpool.level = 2\n\tpool.step(2.0)\n\tgame.squad = FakeSquad.new()\n\tgame.squad.op = FakeOp.new()\n\tpool.free()\n\tgame.free()\n\tprint("MATERIAL_CONTRACT_PASS")\n\tquit()\n'}
# Exercise replacement admission: successful handoff, once-only emission, full-budget fallback.
FILES["test.gd"] = FILES["test.gd"].replace("var optical_on := true", "var optical_on := true\n\tvar tex := {}")
FILES["test.gd"] = FILES["test.gd"].replace("\tpool.free()", "\tgame.squad.op.pfx.clear()\n\tpool.step(2.0)\n\tgame.tex[\"fx_lappland_slash\"] = tx\n\tvar slash = {\"name\": \"fx_lappland_slash\", \"max\": 0.4, \"life\": 0.2, \"sc\": 2.0, \"ang\": 0.0, \"pos\": Vector2.ZERO, \"fr\": 4}\n\tgame.squad.op.pfx = [slash]\n\tpool.step(0.01)\n\tassert(pool.pos.size() == 72 and slash.get(\"slash_material\", false))\n\tpool.step(0.01)\n\tassert(pool.pos.size() == 72)\n\tvar fallback = slash.duplicate()\n\tfallback.erase(\"slash_material\")\n\tfallback.erase(\"slash_emitted\")\n\tgame.squad.op.pfx = [fallback]\n\tpool._frame_n[\"blade\"] = 144\n\tpool._lappland_step()\n\tassert(not fallback.get(\"slash_material\", false) and pool.pos.size() == 72)\n\tpool.free()")
for name, content in FILES.items():
    (OUT / name).write_text(content, encoding="utf-8")
source = (ROOT / "game/scripts/render/fx_grains.gd").read_text(encoding="utf-8")
(OUT / "grains.gd").write_text(source.replace("res://scripts/core/balance.gd", "res://balance.gd"), encoding="utf-8")
os.environ["GODOT_MAX_PROCS"] = "1"
os.environ["TEMP"] = os.environ["TMP"] = str(OUT)
import godot_runner as gr
with open(gr._LOCK, "a+b") as lock:
    lock.seek(0)
    try:
        msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        sys.exit("Runner busy; retry later")
    lock.seek(0)
    msvcrt.locking(lock.fileno(), msvcrt.LK_UNLCK, 1)
if gr.count_godot():
    sys.exit("Godot busy; retry later")
exe = os.environ.get("GODOT_EXE", gr.find_godot())
out, err, timeout = gr.run_godot([exe, "--headless", "--audio-driver", "Dummy", "--path", str(OUT), "--script", "test.gd"], 20)
print(out, err)
sys.exit(0 if not timeout and "MATERIAL_CONTRACT_PASS" in out and "ERROR" not in out + err else 1)
