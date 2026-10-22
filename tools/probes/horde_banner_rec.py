"""大群横幅两段录屏（codex_task_gameplay_1022b §7 验收）：分股合围「海嗣注意到了你的存在……」与「大群来袭」（--bal=enemy/horde_streams=0）。
第一次大群在 75 秒（enemy/first_horde），预警从 72 秒起；从 71.5 秒起实时 30 fps 连拍 5 秒，隔帧拼 gif（半尺寸）。窗口在屏幕外、静音。
用法：python -X utf8 tools/probes/horde_banner_rec.py
输出：主仓库 build/hud_prompts/horde_streams.gif、horde_swarm.gif
"""
import os
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import godot_runner as gr  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(gr.common_root(ROOT), 'build', 'hud_prompts')
os.makedirs(OUT, exist_ok=True)
gr.ensure_imported(os.path.join(ROOT, 'game'))
CASES = [("horde_streams", []), ("horde_swarm", ["--bal=enemy/horde_streams=0"])]


def run(case):
    name, extra = case
    d = os.path.join(OUT, name + "_frames")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    args = [gr.find_godot(), "--path", os.path.join(ROOT, "game"), "--audio-driver", "Dummy", "--fixed-fps", "30",
            "--resolution", "1280x720", "--position", "-4000,0", "--",
            "--balance", "--seed=1", "--op=mizuki", "--bot=expert", "--realtime", "--rtfrom=69",
            "--recframes=71.5,150", "--shotdir=" + d] + extra
    out, err, to = gr.run_godot(args, 900)
    errs = gr.script_errors(out, err)
    fr = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    ims = [Image.open(os.path.join(d, f)).convert("RGB") for f in fr[::2]]
    ims = [im.resize((im.width // 2, im.height // 2), Image.LANCZOS) for im in ims]
    if ims:
        ims[0].save(os.path.join(OUT, name + ".gif"), save_all=True, append_images=ims[1:], duration=67, loop=0)
    return name, len(fr), to, errs[:2]


with ThreadPoolExecutor(2) as ex:
    for r in ex.map(run, CASES):
        print(*r, flush=True)
