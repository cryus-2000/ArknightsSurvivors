"""Package approved native pixels without resizing; preserve gameplay timing separately."""
from pathlib import Path
import hashlib
import json
import sys
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT.parent / 'codex-art' / 'art/incoming'
OUT = ROOT / 'art/incoming'
sys.path.insert(0, str(SOURCE / 'ct_siege_skadi_ulpianus_references_1019/ulpianus_pixel_run_01'))
from export_pixels import compose

sources = {
    'siege': {a: ('cy_siege_all_actions_1020', a) for a in ['Idle', 'Run', 'Attack', 'LeapSlam', 'HeavyAttack', 'Die']},
    'ulpianus': {
        'Idle': ('cu_ulpianus_native_actions_1019', 'Idle'),
        'Run': ('ct_siege_skadi_ulpianus_references_1019/ulpianus_pixel_run_01', 'ulpianus'),
        'Attack': ('cu_ulpianus_attack_revision_01_1019', 'Attack'),
        'Die': ('cu_ulpianus_native_actions_1019', 'Die'),
        **{a: ('cw_ulpianus_skill_pixel_cleanup_1020', a) for a in ['ThrowReel', 'ZipLand', 'Whirl', 'S2Attack']},
    },
}
slots = {'Idle': 'idle', 'Run': 'run', 'Attack': 'attack', 'Die': 'death',
         'LeapSlam': 'leap_native', 'HeavyAttack': 'heavy_attack',
         'ThrowReel': 'tether_native', 'ZipLand': 'zip_native',
         'Whirl': 'whirl_native', 'S2Attack': 'attack_s2'}
rates = {'Idle': 4, 'Run': 40/3, 'Attack': 14, 'Die': 8, 'LeapSlam': 550/42,
         'HeavyAttack': 12, 'ThrowReel': 12, 'ZipLand': 12, 'Whirl': 12, 'S2Attack': 12}
provenance = {}
for op, actions in sources.items():
    path = ROOT / f'game/data/characters/{op}.json'
    data = json.loads(path.read_text(encoding='utf-8'))
    sprites = data['sprites']
    sprites.pop('command', None)
    data['extra_sprites'] = [v for v in data.get('extra_sprites', []) if v != 'command']
    for action, (folder, subdir) in actions.items():
        source = SOURCE / folder / subdir
        frames = []
        hands = []
        hand_world = []
        manifest = None
        if action in ('ThrowReel', 'ZipLand'):
            manifest = next(a for a in json.loads((SOURCE / folder / 'manifest.json').read_text())['actions'] if a['action'] == action)
        for i in range(8):
            file = source / f'f{i:02d}_assembled.png'
            if not file.exists(): file = source / f'f{i:02d}@2x.png'
            im = Image.open(file).convert('RGBA')
            if manifest:
                im = Image.new('RGBA', (256, 256))
                for part in manifest['records'][i]['parts']:
                    if part['kind'] == 'body': compose(im, Image.open(SOURCE / folder / part['file']).convert('RGBA'), part['blend'])
                bones = {b['name']: b for b in json.loads((SOURCE / folder / 'raw' / f'{action}_{i:02d}' / 'bones.json').read_text())}
                hand = max([bones['F_L_Hand_A']['world'], bones['F_R_Hand_A']['world']], key=lambda p: p[0])
                scale = json.loads((SOURCE / folder / 'manifest.json').read_text())['scale']
                hand_world.append([128 + hand[0] * scale, 180 - hand[1] * scale])
            if im.size == (128, 128):
                stage = Image.new('RGBA', (256, 256));stage.paste(im, (64, 60));im = stage
            assert im.size == (256, 256)
            assert set(np.unique(np.asarray(im)[:, :, 3])) <= {0, 255}
            frames.append(im)
            provenance[file.relative_to(SOURCE).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
        crop = (64, 60, 192, 188)
        compact = all(np.asarray(f.crop(crop))[:, :, 3].sum() == np.asarray(f)[:, :, 3].sum() for f in frames)
        size = 128 if compact else 256
        if compact: frames = [f.crop(crop) for f in frames]
        if hand_world: hands = [[(p[0] - (64 if compact else 0))/2, (p[1] - (60 if compact else 0))/2] for p in hand_world]
        strip = Image.new('RGBA', (size * 8, size))
        for i, im in enumerate(frames): strip.paste(im, (size * i, 0))
        slot = slots[action];name = f'op_{op}_{slot}'
        strip.save(OUT / (name + '@2x.png'))
        fps = 4/3 if op == 'ulpianus' and action == 'Idle' else (12 if op == 'ulpianus' and action == 'Attack' else rates[action])
        spec = {'tex': name, 'frames': 8, 'fps': fps, 'foot': [32, 60] if compact else [64, 90]}
        if hands: spec['hand'] = hands
        sprites[slot] = spec
        if slot not in ['idle', 'run', 'attack', 'death'] and slot not in data['extra_sprites']: data['extra_sprites'].append(slot)
        print(op, slot, size, 'pixels')
    def logical(spec, duration, fire, frame):
        spec.update(frame_durations=[duration/8]*8, fire_time=fire, fire=frame)
    if op == 'siege':
        logical(sprites['attack'], 4/14, 2.5/14, 2)
        logical(sprites['heavy_attack'], .5, 3.5/12, 3)
        sprites['activation'] = dict(sprites['idle']);logical(sprites['activation'], .5, 2.5/12, 2)
        sprites['skill'] = dict(sprites['idle']);logical(sprites['skill'], .5, 3.5/12, 3)
        if 'activation' not in data['extra_sprites']: data['extra_sprites'].append('activation')
        data['skills'][0]['anim'] = data['skills'][2]['anim'] = 'activation'
        data['blocks']['attack']['heavy']['anim'] = 'heavy_attack'
        data['native_motion'] = {'attack': 8/14, 'heavy_attack': 8/12, 'leap_native': 8/rates['LeapSlam']}
    else:
        logical(sprites['attack'], 5/12, 3.5/12, 3)
        logical(sprites['attack_s2'], 5/12, 3.5/12, 3)
        sprites['skill'] = dict(sprites['idle']);logical(sprites['skill'], 7/12, 3.5/12, 3)
        sprites['throw'] = dict(sprites['tether_native']);logical(sprites['throw'], 8/14, 3.5/14, 3)
        data['native_motion'] = {'attack': 8/12, 'attack_s2': 8/12}
        source = SOURCE / 'cw_ulpianus_skill_pixel_cleanup_1020'
        manifest = json.loads((source / 'manifest.json').read_text())
        record = manifest['actions'][0]['records'][3]
        Image.open(source / 'ThrowReel/f03_weapon@2x.png').save(OUT / 'op_ulpianus_anchor_native@2x.png')
        ring = record['diagnostics']['authored']['weapon_ring'];scale = manifest['scale'];off = record['weapon_offset_from_body_origin']
        origin = [(ring[0]*scale - off[0])/128, (-ring[1]*scale - off[1])/128]
        sprites['anchor_native'] = {'tex': 'op_ulpianus_anchor_native', 'frames': 1, 'anchor': origin}
        if 'anchor_native' not in data['extra_sprites']: data['extra_sprites'].append('anchor_native')
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1)+'\n', encoding='utf-8')
    for action in ['idle', 'run', 'attack']:
        (OUT / f'op_{op}_{action}.png').unlink(missing_ok=True)
(OUT / 'siege_ulpianus_native_sources.json').write_text(json.dumps(provenance, indent=2)+'\n', encoding='utf-8')
