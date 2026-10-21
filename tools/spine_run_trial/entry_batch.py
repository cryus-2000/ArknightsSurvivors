"""入场条批量出图（10-22，docs/plans/2026-10-20-spine-run-trial.md §10）。

原作 Start 轨 = 从上方落下 → 着地 → 收势。64 画布 @2x 放不下空中段，只取「整个人进了画布起到收势均匀 8 帧」，
空中下落由游戏代码补（character.arrive_dy）。起点：24 点密采样，第一个包围盒上沿不贴画布顶的采样点；叠加 / 滤色的登场光效不画。

Spine 干员：  python tools/spine_run_trial/entry_batch.py spine <id> [<id> …]
Codex 条：    python tools/spine_run_trial/entry_batch.py codex lappland gladiia   （拉普兰德 / 歌蕾蒂娅，Codex 交付的 Start 大画布条）
产物：build/spine_run_trial/<id>/entry/<id>_entry_strip@2x.png、cfg/<id>_entry.json（durations），--apply 时复制到 art/incoming 并写干员 json。
"""
import json, os, subprocess, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
TRIAL = os.path.join(ROOT, 'tools', 'spine_run_trial')
os.environ['NODE_PATH'] = 'E:/ArknightsSurvivors/build/prts_ref/_node/node_modules'
N_PROBE = 24
CODEX = 'art/incoming/lappland_gladiia_delivery_1021'
CODEX_REV = '5839d9d2'


def mass_y(im):
    a = im.getchannel('A')
    w, h = a.size
    px = a.load()
    s = n = 0
    for y in range(h):
        for x in range(0, w):
            if px[x, y] > 0:
                s += y
                n += 1
    return s / n if n else None


def area(im):
    return sum(1 for v in im.getchannel('A').getdata() if v > 0)


def pick_times(cys, tops, ts, dur, areas=None):
    """cys：各采样点不透明重心 y（None = 画布里看不见）；tops：包围盒上沿。返回 (帧时刻 8 个, 每帧时长 8 个)
    起点 = 第一个整个人进了画布（上沿不贴边、不透明像素 ≥ 收势的一半）的采样点：之前的空中段由游戏代码的落下补；起点到收势均匀 8 帧"""
    vis = [k for k, c in enumerate(cys) if c is not None and tops[k] >= 2 and (areas is None or areas[k] >= 0.5 * areas[-1])]
    t0 = ts[vis[0]]
    times = [round(t0 + (dur - t0) * k / 8, 4) for k in range(8)]
    durs = [round(times[k + 1] - times[k], 4) for k in range(7)] + [round(dur - times[7], 4)]
    return times, durs


def node(cfg_path):
    r = subprocess.run(['node', os.path.join(TRIAL, 'run_trial.js'), cfg_path, '--clean'], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
        raise SystemExit(r.stdout + r.stderr)


def anim_duration(cid):
    r = subprocess.run(['node', os.path.join(TRIAL, 'anims_probe.js'), cid], capture_output=True, text=True, cwd=TRIAL)
    for tok in r.stdout.split():
        if tok.startswith('Start:'):
            return float(tok.split(':')[1])
    raise SystemExit(f'{cid}: 没有 Start 轨\n{r.stdout}{r.stderr}')


def spine(cid):
    dur = anim_duration(cid)
    base = json.load(open(os.path.join(TRIAL, 'cfg', f'{cid}.json'), encoding='utf8'))
    for k in ('keys', 'poses', 'retarget', 'holdPose', 'carry', 'sample', 'canvas'):
        base.pop(k, None)
    probe = dict(base, action='entryprobe', skipAdditive=True, sample={'anim': 'Start', 'times': [round(dur * k / N_PROBE, 4) for k in range(N_PROBE)]})
    pp = os.path.join(TRIAL, 'cfg', f'_{cid}_probe.json')
    json.dump(probe, open(pp, 'w', encoding='utf8'), ensure_ascii=False)
    try:
        node(pp)
    finally:
        os.remove(pp)
    fd = os.path.join(ROOT, 'build', 'spine_run_trial', cid, 'entryprobe', 'frames')
    ims = [Image.open(os.path.join(fd, f'f{k:02d}.png')).convert('RGBA') for k in range(N_PROBE)]
    cys = [mass_y(im) for im in ims]
    tops = [im.getbbox()[1] if im.getbbox() else -1 for im in ims]
    times, durs = pick_times(cys, tops, probe['sample']['times'], dur, [area(im) for im in ims])
    cfg = dict(base, action='entry', skipAdditive=True, sample={'anim': 'Start', 'times': times}, durations=durs,
               _doc='入场条（10-22）：原作 Start 轨，整个人进画布起到收势均匀 8 帧；之前的空中下落由游戏代码补（durations = 帧间原作时长）')
    cp = os.path.join(TRIAL, 'cfg', f'{cid}_entry.json')
    json.dump(cfg, open(cp, 'w', encoding='utf8'), ensure_ascii=False, indent=1)
    node(cp)
    out = os.path.join(ROOT, 'build', 'spine_run_trial', cid, 'entry')
    subprocess.run([sys.executable, '-X', 'utf8', os.path.join(TRIAL, 'sheet.py'), os.path.join(out, 'frames'), os.path.join(out, f'{cid}_entry')], capture_output=True, cwd=ROOT)
    return os.path.join(out, f'{cid}_entry_strip@2x.png'), durs, dur


def codex(cid):
    man = json.loads(subprocess.check_output(['git', 'show', f'{CODEX_REV}:{CODEX}/manifest.json'], cwd=ROOT))
    act = next(a for a in man['actions'] if a['operator'] == cid and a['action'] == 'Start')
    src = Image.open(os.path.join(ROOT, 'build', 'entry', f'_{cid}_start@2x.png')) if os.path.exists(os.path.join(ROOT, 'build', 'entry', f'_{cid}_start@2x.png')) else None
    if src is None:
        os.makedirs(os.path.join(ROOT, 'build', 'entry'), exist_ok=True)
        blob = subprocess.check_output(['git', 'show', f'{CODEX_REV}:{CODEX}/{act["file"]}'], cwd=ROOT)
        p = os.path.join(ROOT, 'build', 'entry', f'_{cid}_start@2x.png')
        open(p, 'wb').write(blob)
        src = Image.open(p)
    src = src.convert('RGBA')
    fw, fh = act['frame_size']
    ox, oy = act['origin']
    n = act['frames']
    # 原点对齐到 128 画布的 (64, 120)：保持像素密度，不缩放（HANDOFF：Start 大画布保留原位移）
    frames = [src.crop((k * fw + ox - 64, oy - 120, k * fw + ox + 64, oy + 8)) for k in range(n)]
    ts = act['sample_times']
    cys = [mass_y(f) for f in frames]
    tops = [f.getbbox()[1] if f.getbbox() else -1 for f in frames]
    times, _ = pick_times(cys, tops, ts, act['duration'], [area(f) for f in frames])
    idx = [min(range(n), key=lambda k: abs(ts[k] - t)) for t in times]
    picked = [ts[k] for k in idx]
    durs = [round(picked[k + 1] - picked[k], 4) for k in range(7)] + [round(act['duration'] - picked[7], 4)]
    out = os.path.join(ROOT, 'build', 'spine_run_trial', cid, 'entry')
    os.makedirs(out, exist_ok=True)
    strip = Image.new('RGBA', (128 * 8, 128))
    for j, k in enumerate(idx):
        strip.paste(frames[k], (j * 128, 0))
    sp = os.path.join(out, f'{cid}_entry_strip@2x.png')
    strip.save(sp)
    cfg = {'id': cid, 'action': 'entry', 'codex_start': f'{CODEX_REV}:{CODEX}/{act["file"]}', 'source_frames': idx, 'sample_times': picked, 'durations': durs,
           '_doc': '入场条（10-22）：Codex 交付的原作 Start 条（20 fps 密采样、大画布），按原点裁到 128 画布，取整个人进画布起到收势 8 帧（就近源帧）；每帧时长 = 到下一取样帧的源时长'}
    json.dump(cfg, open(os.path.join(TRIAL, 'cfg', f'{cid}_entry.json'), 'w', encoding='utf8'), ensure_ascii=False, indent=1)
    return sp, durs, act['duration']


def apply(cid, strip, durs):
    import shutil
    im = Image.open(strip)
    assert im.size == (1024, 128), (cid, im.size)
    shutil.copy(strip, os.path.join(ROOT, 'art', 'incoming', f'op_{cid}_entry@2x.png'))
    p = os.path.join(ROOT, 'game', 'data', 'characters', f'{cid}.json')
    s = open(p, encoding='utf8', newline='').read()
    nl = '\r\n' if '\r\n' in s else '\n'
    d = json.loads(s)
    slot = {'tex': f'op_{cid}_entry', 'frames': 8, 'fps': round(8 / sum(durs), 4), 'foot': [32, 60], 'frame_durations': durs,
            '_doc': f'10-22 入场：原作 Start 轨着地前一帧 + 着地到收势（tools/spine_run_trial cfg/{cid}_entry.json），64 画布 @2x；落下由代码补'}
    run = d['sprites'].get('run')
    if isinstance(run, dict) and run.get('foot_exempt') and run.get('foot') == [32, 60]:   # 小数顶层 foot 的人（docs/108 §5）：同跑步条豁免
        slot = {'foot_exempt': '入场条同跑步条用整数脚底 (32, 60)，与小数顶层 foot 相差不到 1px（docs/108 §5）', **slot}
    line = '  "entry": ' + json.dumps(slot, ensure_ascii=False) + ','
    if 'entry' in d['sprites']:
        lines = s.split(nl)
        lines = [line if l.lstrip().startswith('"entry": {"tex"') else l for l in lines]
        s = nl.join(lines)
    else:
        k = s.index('"sprites": {')
        k = s.index('\n', k) + 1
        s = s[:k] + line + nl + s[k:]
    d = json.loads(s)
    if 'entry' not in d.get('extra_sprites', []):
        if 'extra_sprites' in d:
            s = s.replace('"extra_sprites": [', '"extra_sprites": ["entry", ', 1)
        else:
            k = s.index(' "sprites": {')
            s = s[:k] + ' "extra_sprites": ["entry"],' + nl + s[k:]
    d = json.loads(s)
    assert 'entry' in d['extra_sprites'] and d['sprites']['entry']['tex'] == f'op_{cid}_entry'
    open(p, 'w', encoding='utf8', newline='').write(s)


if __name__ == '__main__':
    mode, ids = sys.argv[1], [a for a in sys.argv[2:] if not a.startswith('--')]
    for cid in ids:
        strip, durs, dur = (spine if mode == 'spine' else codex)(cid)
        print(cid, 'Start', dur, 'durations', durs, 'sum', round(sum(durs), 3))
        if '--apply' in sys.argv:
            apply(cid, strip, durs)
