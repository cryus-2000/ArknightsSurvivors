"""归溟幽灵鲨替身待机 native_doll_idle 改按 6 fps 采样（10-21 用户实测「替身抽搐」）。

原条（dg export_doll.py）从 12 fps 源每 3 帧取 1（4 fps、40 帧）。Idle_B 中段（约 3.2–8.6 秒）是周期约 0.62 秒的摇摆，
4 fps 采样每周期只有 2.5 帧，正反帧交替读成抽搐；进出该段的 6 像素升降也只剩一两帧、读成跳变。
改为每 2 帧取 1（6 fps、60 帧，每周期约 3.75 帧），帧条宽 7680 px 仍在 8192 内。像素做法与 dg 相同（package_skalter_specter.doll_frames）。

用法：python -X utf8 tools/probes/package_specter_doll_idle.py
"""
from pathlib import Path
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/probes'))
from package_skalter_specter import doll_frames  # noqa: E402

STEP = 2
idx = list(range(0, 120, STEP))
frames, m = doll_frames('Idle_B', idx)
frames = [f.crop((32, 32, 160, 160)) for f in frames]   # 192 舞台 → 128 画布（原点 64,120）
old = Image.open(ROOT / 'art/incoming/op_specter_unchained_native_doll@2x.png').convert('RGBA')
assert np.array_equal(np.asarray(old.crop((0, 0, 128, 128))), np.asarray(frames[0])), '首帧与原交付不一致（像素做法漂移）'
strip = Image.new('RGBA', (128 * len(frames), 128))
for i, f in enumerate(frames):
    strip.paste(f, (128 * i, 0))
strip.save(ROOT / 'art/incoming/op_specter_unchained_native_doll@2x.png')
path = ROOT / 'game/data/characters/specter_unchained.json'
data = json.loads(path.read_text(encoding='utf-8'))
sp = data['sprites']
sp['native_doll_idle']['frames'] = len(frames)
sp['native_doll_idle']['fps'] = len(frames) / float(m['duration'])
sp['doll']['visual']['times'] = [m['sample_times'][i] for i in idx]
sp['doll']['visual']['duration'] = m['duration']
path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
print('doll idle', len(frames), 'frames', strip.size)
