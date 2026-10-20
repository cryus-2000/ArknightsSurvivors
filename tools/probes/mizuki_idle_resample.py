"""水月待机重采样（10-21 用户实测「待机最后一帧有问题」）。
原作 Idle 13.33 秒 = 8 轮 1.33 秒呼吸 + 末 2.67 秒转伞；cb_18 只按 1.9 秒等距采 8 帧（末帧是首帧的循环重复、
转伞只落一帧），游戏里按 0.6 fps 匀速播，转伞一帧突兀闪现、再停在重复帧上。
改为 tools/spine_run_trial 逐附件像素化重采：两轮呼吸 16 帧（每帧 1/6 秒）+ 转伞 20 帧（每帧 0.133 秒），循环 5.33 秒。
与原条 f0 对拍最佳整数偏移 (0,-1)（IoU 0.95），画布 / foot / draw_scale 不变；纯显示。
用法：
  NODE_PATH=E:/ArknightsSurvivors/build/prts_ref/_node/node_modules node tools/spine_run_trial/run_trial.js tools/spine_run_trial/cfg/mizuki_idle.json --out build/spine_run_trial/mizuki/idle_resample/frames
  python -X utf8 tools/probes/mizuki_idle_resample.py
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'build/spine_run_trial/mizuki/idle_resample/frames'
TEX = ROOT / 'art/incoming/mizuki_runtime_idle@2x.png'
cfg = json.loads((ROOT / 'tools/spine_run_trial/cfg/mizuki_idle.json').read_text(encoding='utf-8'))
times = cfg['sample']['times']
n = len(times)
frames = []
for i in range(n):
    im = Image.open(SRC / f'f{i:02d}.png').convert('RGBA'); assert im.size == (192, 192)
    a = np.asarray(im); assert set(np.unique(a[:, :, 3])) <= {0, 255}
    assert a[0, :, 3].sum() == 0, '上移会裁掉顶部像素'
    out = Image.new('RGBA', (192, 192)); out.paste(im.crop((0, 1, 192, 192)), (0, 0)); frames.append(out)
strip = Image.new('RGBA', (192 * n, 192))
for i, f in enumerate(frames): strip.paste(f, (192 * i, 0))
strip.save(TEX)
durs = [1 / 6] * 16 + [(13.333333015441895 * 0.2) / 20] * 20
assert len(durs) == n
path = ROOT / 'game/data/characters/mizuki.json'
data = json.loads(path.read_text(encoding='utf-8'))
spec = data['sprites']['idle']
spec.update(frames=n, fps=n / sum(durs), frame_durations=durs)
path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('mizuki idle', n, 'frames', round(sum(durs), 3), 's')
