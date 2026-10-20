"""Local, read-only-source native Spine pose editor (Spine 3.5 / 3.8). Start with --source ART_FOLDER or a pack folder."""
import argparse
import base64
import hashlib
import io
import json
import math
import mimetypes
import re
import secrets
import struct
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, unquote

from PIL import Image

HERE = Path(__file__).resolve().parent


def validate_patch(p, project):
    def require(ok):
        if not ok:
            raise ValueError('姿势文件与来源不匹配，或包含无效数值 / 层序')
    def finite(v, limit):
        return type(v) in (int, float) and math.isfinite(v) and abs(v) <= limit
    require(isinstance(p, dict) and p.get('version') == 1 and p.get('source') == project['id'])
    require(isinstance(p.get('frames'), list) and len(p['frames']) == len(project['frames']))
    for f in p['frames']:
        require(isinstance(f, dict) and isinstance(f.get('ops'), list) and len(f['ops']) <= 500)
        for op in f['ops']:
            require(isinstance(op, dict) and op.get('bone') in project['bones'])
            kind = op.get('type')
            if kind == 'rotate':
                require(finite(op.get('degrees'), 360))
            elif kind == 'translate':
                require(finite(op.get('dx'), 2000) and finite(op.get('dy'), 2000))
            elif kind == 'ik':
                target = op.get('target')
                require(op['bone'] in project['chains'] and isinstance(target, list) and len(target) == 2 and all(finite(v, 2000) for v in target))
            else:
                require(False)
        order = f.get('order')
        require(order is None or (isinstance(order, list) and all(isinstance(n, str) for n in order) and sorted(order) == sorted(project['slots'])))
    return p


def export_frames(output, project, patch, encoded):
    validate_patch(patch, project)
    if not isinstance(encoded, list) or len(encoded) != len(project['frames']):
        raise ValueError('导出必须包含全部八帧')
    frames = []
    for data in encoded:
        if not isinstance(data, str) or len(data) > 1_000_000:
            raise ValueError('PNG 数据过大')
        try:
            im = Image.open(io.BytesIO(base64.b64decode(data, validate=True)))
            if im.format != 'PNG' or im.size != (256, 256):
                raise ValueError('只接受 256×256 PNG 场景帧')
            im = im.convert('RGBA')
            if any(a not in (0, 255) for a in im.getchannel('A').getdata()):
                raise ValueError('像素导出必须为二值透明')
            frames.append(im)
        except (OSError, TypeError) as e:
            raise ValueError('无效 PNG') from e
    output.mkdir(parents=True, exist_ok=True)
    dest = output / ('export_' + time.strftime('%Y%m%d_%H%M%S') + '_' + secrets.token_hex(3))
    dest.mkdir()
    strip = Image.new('RGBA', (256 * len(frames), 256))
    previews = []
    for i, im in enumerate(frames):
        im.save(dest / f'f{i:02d}.png')
        strip.paste(im, (256 * i, 0))
        bg = Image.new('RGBA', im.size, '#303d4d');bg.alpha_composite(im)
        previews.append(bg.convert('RGB').resize((512, 512), Image.Resampling.NEAREST))
    strip.save(dest / 'run_strip.png')
    # 游戏口径 128 @2x：场景原点 (128,180) 对齐帧原点 (64,120)
    game = Image.new('RGBA', (128 * len(frames), 128))
    for i, im in enumerate(frames):
        game.paste(im.crop((64, 60, 192, 188)), (128 * i, 0))
    game.save(dest / 'strip@2x.png')
    durations = [round((i + 1) * 100 / project['fps']) * 10 - round(i * 100 / project['fps']) * 10 for i in range(len(frames))]
    previews[0].save(dest / 'run.gif', save_all=True, append_images=previews[1:], duration=durations, loop=0, disposal=2)
    (dest / 'pose.json').write_text(json.dumps(patch, ensure_ascii=False, indent=2), encoding='utf-8')
    (dest / 'manifest.json').write_text(json.dumps(dict(source=project['id'], fps=project['fps'], frames=8,
        frame_size=[256, 256], origin=[128, 180], pixel_method='Per-attachment Canvas BOX-like downsample and native palette',
        engine_ready=False, game_strip='strip@2x.png 为 128 @2x、原点 (64,120) 的裁切，超出部分丢弃',
        note='审阅用完整场景；未做游戏接入验收'), ensure_ascii=False, indent=2), encoding='utf-8')
    return dest


# 运行库只在主工作区 build/prts_ref/_node（不进 git）；工作树里向上找到主工作区为止
MAIN_ROOT = next((p for p in HERE.parents if (p / 'build/prts_ref/_node').is_dir()), HERE.parent.parent)
RUNTIME_DIR = MAIN_ROOT / 'build/prts_ref/_node'
ART_INCOMING = MAIN_ROOT / '.worktrees/codex-art/art/incoming'
RUNTIMES = {'3.5': 'spine-canvas-3.5.51.js', '3.8': 'spine-canvas-3.8.js'}


def _read_string(data, pos):
    """Spine 二进制字符串：变长整数（字节数 + 1），0 为空。"""
    value, shift = 0, 0
    while True:
        byte = data[pos];pos += 1
        value |= (byte & 0x7F) << shift;shift += 7
        if not byte & 0x80:
            break
    if value == 0:
        return None, pos
    return data[pos:pos + value - 1].decode('utf-8'), pos + value - 1


def spine_version(path):
    """按文件头读 Spine 版本：.json 取 skeleton.spine，.skel 取第二个字符串（hash 之后）。"""
    path = Path(path)
    if path.suffix == '.json':
        return json.loads(path.read_text(encoding='utf-8'))['skeleton']['spine']
    data = path.read_bytes()[:256]
    _, pos = _read_string(data, 0)
    version, _ = _read_string(data, pos)
    if not version or not version[0].isdigit():
        raise ValueError(f'无法识别 Spine 版本：{path.name}')
    return version


def pick_runtime(version, runtime_dir):
    major = '.'.join(version.split('.')[:2])
    if major not in RUNTIMES:
        raise ValueError(f'不支持 Spine {version}；仅支持 3.5 / 3.8')
    path = Path(runtime_dir) / RUNTIMES[major]
    if not path.is_file():
        raise ValueError(f'缺少运行库 {path}')
    return path


def load_pack(source, runtime_dir, runtime=None):
    """通用数据包（tools/spine_run_trial 生成）：pack.json + frames/<name>/bones.json，3.5 JSON 或 3.8 二进制。"""
    pack = json.loads((source / 'pack.json').read_text(encoding='utf-8'))
    if pack.get('version') != 1 or len(pack.get('frames', [])) != 8:
        raise ValueError('数据包需为 version 1、八帧')
    native = Path(pack['skeleton']);atlas = Path(pack['atlas'])
    version = spine_version(native)
    runtime = Path(runtime) if runtime else pick_runtime(version, runtime_dir)
    textures = [line.strip() for line in atlas.read_text().splitlines() if line.strip().endswith('.png')]
    if len(textures) != 1 or '/' in textures[0] or '\\' in textures[0]:
        raise ValueError('要求单张本地纹理图集')
    texture = atlas.parent / textures[0]
    source_files = [source / 'pack.json', native, atlas, texture, runtime]
    rows = []
    for f in pack['frames']:
        bone_file = source / 'frames' / f['name'] / 'bones.json';source_files.append(bone_file)
        rows.append(dict(name=f['name'], anim=f.get('anim', 'Idle'), t=f.get('t', 0), bones=json.loads(bone_file.read_text()),
                         order=f['order'], hidden=f.get('hidden', [])))
    digest = hashlib.sha256()
    for p in source_files:
        digest.update(p.read_bytes())
    fmt = 'json' if native.suffix == '.json' else 'skel'
    project = dict(id=digest.hexdigest(), title=pack['title'], frames=rows, bones=pack['bones'], slots=pack['slots'],
                   chains=pack['chains'], equipment=pack.get('equipment', {}), fps=pack.get('fps', 40 / 3),
                   scale=pack['scale'], palette=pack['palette'], labels=pack.get('labels', {}),
                   default_bone=pack.get('default_bone'), format=fmt, spine=version, character=pack.get('character'))
    assets = {'/native.' + fmt:native, '/native.atlas':atlas, '/texture.png':texture, '/runtime.js':runtime}
    return project, assets


class _Reader:
    """Spine 3.8 二进制读取（只读到骨骼与槽为止）：大端 float / int32，变长整数，字符串表。"""
    def __init__(self, data):
        self.data, self.pos, self.strings = data, 0, []

    def varint(self):
        value, shift = 0, 0
        while True:
            byte = self.data[self.pos];self.pos += 1
            value |= (byte & 0x7F) << shift;shift += 7
            if not byte & 0x80:
                return value

    def string(self):
        value, self.pos = _read_string(self.data, self.pos)
        return value

    def skip(self, n):
        self.pos += n

    def float(self):
        value = struct.unpack_from('>f', self.data, self.pos)[0];self.pos += 4
        return value


def skeleton_names_38(path):
    """3.8 .skel → 骨骼 [(名, 父名, 长度)] 与槽名（层序同 setup 姿势）。"""
    r = _Reader(Path(path).read_bytes())
    r.string()
    version = r.string()
    if not version or not version.startswith('3.8'):
        raise ValueError(f'不是 Spine 3.8 二进制：{Path(path).name}')
    r.skip(16)
    nonessential = r.data[r.pos] != 0;r.skip(1)
    if nonessential:
        r.skip(4);r.string();r.string()
    r.strings = [r.string() for _ in range(r.varint())]
    bones = []
    for i in range(r.varint()):
        name = r.string()
        parent = bones[r.varint()][0] if i else None
        r.skip(28);length = r.float()
        r.varint();r.skip(1)
        if nonessential:
            r.skip(4)
        bones.append((name, parent, length))
    slots, slot_bones = [], set()
    for _ in range(r.varint()):
        slots.append(r.string())
        slot_bones.add(bones[r.varint()][0]);r.skip(8);r.varint();r.varint()
    return bones, slots, slot_bones


ROLE = {'leg': (r'Leg|Thigh', r'Calf|Shin|Knee', r'Foot|Ankle|Shoe'),
        'arm': (r'Arm(?!our|_?B)', r'Fore_?arm|Elbow|Shoulder|Arm_?B', r'Hand|Wrist|Palm')}
WEAPON = re.compile(r'Weapon|Umbrella|Sword|Staff|Gun|Lance|Hammer|Blade|Spear|Knife|Axe|Shield', re.I)
SKIP = re.compile(r'IK|[Aa]rmou?r')


def detect_rig(bones, slot_bones=()):
    """按 PRTS 骨骼命名找双节链（大臂 / 前臂 / 手，大腿 / 小腿 / 脚）、躯干和握持武器。"""
    parent = {n: p for n, p, _ in bones};length = {n: l for n, _, l in bones}
    depth = {}
    for n, p, _ in bones:
        depth[n] = depth[p] + 1 if p else 0
    match = lambda side, pattern, name: name and not SKIP.search(name) and re.match(rf'^F_{side}_({pattern})', name, re.I)
    chains, labels, equipment, alternates = {}, {}, {}, {}
    for side in 'LR':
        for kind, (upper, middle, end) in ROLE.items():
            found = []
            for n, p, _ in bones:
                gp = parent.get(p)
                if match(side, end, n) and match(side, middle, p) and match(side, upper, gp):
                    held = any(q == n and WEAPON.search(m) for m, q, _ in bones)
                    found.append(((length[gp] > 0) + (length[p] > 0), n in slot_bones, held, length[n] > 0, -depth[n],
                                  length[gp] + length[p], length[n], n))
            # 同名多套（换形态的第二套骨骼）都可解算；标签先给首选，浏览器按底稿可见附件改用可见的那套（alternates）
            ends = [f[-1] for f in sorted(found, reverse=True)[:5]]
            for rank, c in enumerate(ends):
                b = parent[c];a = parent[b];chains[c] = [a, b, c]
                own = alternates.setdefault(ends[0], {}).setdefault(c, {})
                part = '腿' if kind == 'leg' else '手'
                for word, n in zip(('髋', '膝', '脚踝') if kind == 'leg' else ('肩', '肘', '手腕'), (a, b, c)):
                    own[n] = f'{side} 侧{part} · {word}'
                if kind == 'arm':
                    held = [n for n, p, _ in bones if p == c and WEAPON.search(n)]
                    if held:
                        equipment[c] = held[:1];own[held[0]] = '武器'
                if rank == 0:
                    labels.update(own)
    for key, word in (('Hip', '髋部'), ('Waist', '腰部'), ('Chest', '胸部'), ('Head', '头部')):
        cands = [n for n, _, _ in bones if re.match(rf'^F_{key}', n, re.I) and not SKIP.search(n)]
        if cands:
            labels[min(cands, key=lambda n: (depth[n], -length[n]))] = word
    return chains, labels, equipment, alternates


OPERATOR_HINT = '可用 --source 指定数据包，或检查 build/prts_ref/_raw 与 codex-art 工作树'


def find_operator_pack(op_id, root=MAIN_ROOT):
    """tools/spine_run_trial 生成的数据包：主工作区或任一 .claude 工作树的 build/spine_run_trial/<id>/editor_pack，取最新。"""
    cands = [root / 'build/spine_run_trial' / op_id / 'editor_pack' / 'pack.json']
    cands += (root / '.claude/worktrees').glob(f'*/build/spine_run_trial/{op_id}/editor_pack/pack.json')
    cands = [p for p in cands if p.is_file()]
    return max(cands, key=lambda p: p.stat().st_mtime).parent if cands else None


def load_operator(op_id, runtime_dir, anim='Idle', spread=False, root=MAIN_ROOT, art=None):
    """按干员 id 直接读原生骨架：骨架 / 图集 build/prts_ref/_raw/<id>；比例与调色板来自 Codex 部件包 bz_18 / bt_18。
    八帧底稿由浏览器用运行库算（anim 的 t=0，或 spread 时八等分时长），地面平移到 y=0。"""
    if not re.fullmatch(r'[a-z0-9_]+', op_id):
        raise ValueError('干员 id 只能含小写字母、数字、下划线')
    art = Path(art) if art else root / '.worktrees/codex-art/art/incoming'
    raw = root / 'build/prts_ref/_raw' / op_id
    parts = art / 'bz_18_native_spine_parts_1017' / op_id
    catalog = art / 'bt_18_complete_parts_1017' / op_id / 'source/catalog.json'
    skels = sorted(raw.glob('*.skel'));atlases = sorted(raw.glob('*.atlas'))
    if len(skels) != 1 or len(atlases) != 1:
        raise ValueError(f'{raw} 下需要正好一个 .skel 与 .atlas；{OPERATOR_HINT}')
    for p in (parts / 'manifest.json', catalog):
        if not p.is_file():
            raise ValueError(f'缺少 {p}；{OPERATOR_HINT}')
    native, atlas = skels[0], atlases[0]
    version = spine_version(native)
    if not version.startswith('3.8'):
        raise ValueError(f'{op_id} 是 Spine {version}：3.5 骨架需先转 JSON，请用 tools/spine_run_trial 生成数据包再 --source')
    runtime = pick_runtime(version, runtime_dir)
    textures = [line.strip() for line in atlas.read_text().splitlines() if line.strip().endswith('.png')]
    if len(textures) != 1 or '/' in textures[0] or '\\' in textures[0]:
        raise ValueError('要求单张本地纹理图集')
    texture = atlas.parent / textures[0]
    manifest = json.loads((parts / 'manifest.json').read_text(encoding='utf-8'))
    scale = manifest['global_transform']['scale'] * float(json.loads(catalog.read_text(encoding='utf-8'))['scale'])
    # 调色板与 run_trial 一致：部件包 parts/*.png 中出现过的全部不透明颜色
    part_files = sorted((parts / 'parts').glob('*.png'))
    colors = set()
    for p in part_files:
        im = Image.open(p).convert('RGBA')
        colors.update(px[:3] for _, px in im.getcolors(im.width * im.height) if px[3] > 0)
    if not colors:
        raise ValueError(f'{parts}/parts 中没有可用调色板')
    bones, slots, slot_bones = skeleton_names_38(native)
    chains, labels, equipment, alternates = detect_rig(bones, slot_bones)
    digest = hashlib.sha256(json.dumps([op_id, anim, spread]).encode())
    for p in [native, atlas, texture, runtime, parts / 'manifest.json', catalog, *part_files]:
        digest.update(p.read_bytes())
    rows = [dict(name=f'{anim}_{i:02d}', anim=anim, t=None if spread else 0, phase=i / 8, bones=None, order=None, hidden=[])
            for i in range(8)]
    arms = [c for c in chains if re.search(ROLE['arm'][2], c, re.I)]
    title = f'{op_id} · {anim}' + (' 八等分' if spread else ' 首帧 ×8')
    project = dict(id=digest.hexdigest(), title=title, frames=rows, bones=[b[0] for b in bones], slots=slots,
                   chains=chains, equipment=equipment, fps=40 / 3, scale=scale, palette=sorted(colors), labels=labels,
                   default_bone=next(iter(equipment), arms[0] if arms else None), format='skel', spine=version,
                   character=op_id, base='native', anim=anim, spread=spread, alternates=alternates,
                   origin_shift=manifest['global_transform']['mapped_root'][0] - 64)
    assets = {'/native.skel': native, '/native.atlas': atlas, '/texture.png': texture, '/runtime.js': runtime}
    return project, assets


def load_project(source, runtime, runtime_dir=None):
    if (source / 'pack.json').exists():
        return load_pack(source, runtime_dir or RUNTIME_DIR, runtime)
    job = json.loads((source / 'job.json').read_text(encoding='utf-8'))
    if job['character'] != 'siege' or not job.get('json'):
        raise ValueError('首版仅支持推进之王的原生 3.5 Run 数据包')
    native = Path(job['json']);atlas = Path(job['atlas'])
    report = json.loads((source / 'raw/report.json').read_text(encoding='utf-8'))
    frames = [f for f in report['frames'] if f['action'] == 'Run']
    frames.sort(key=lambda f: f['index'])
    if len(frames) != 8:
        raise ValueError('需要八帧跑步源数据')
    skel = json.loads(native.read_text(encoding='utf-8'))
    runtime = Path(runtime) if runtime else pick_runtime(spine_version(native), runtime_dir or RUNTIME_DIR)
    textures = [line.strip() for line in atlas.read_text().splitlines() if line.strip().endswith('.png')]
    if len(textures) != 1 or '/' in textures[0] or '\\' in textures[0]:
        raise ValueError('首版要求单张本地纹理图集')
    texture = atlas.parent / textures[0]
    source_files = [source/'job.json', source/'raw/report.json', source/'palette.json', native, atlas, texture, runtime]
    rows = []
    for f in frames:
        bone_file = source/'raw'/f['name']/'bones.json';source_files.append(bone_file)
        rows.append(dict(name=f['name'], anim=f['anim'], t=f['t'], bones=json.loads(bone_file.read_text()),
                         order=f['diagnostics']['authored']['authored_draw_order'],
                         hidden=f['diagnostics']['authored']['hidden_attachments']))
    digest = hashlib.sha256()
    for p in source_files:
        digest.update(p.read_bytes())
    chains = {f'F_{s}_{end}': [f'F_{s}_{a}', f'F_{s}_{b}', f'F_{s}_{end}']
              for s in ('L', 'R') for a,b,end in [('Arm','Shoulder','Hand'),('Leg','Calf','Foot')]}
    project = dict(id=digest.hexdigest(), title='推进之王 · 扛锤跑步', frames=rows,
                   bones=[b['name'] for b in skel['bones']], slots=[s['name'] for s in skel['slots']],
                   chains=chains, equipment={'F_R_Hand':['F_Weapon']},
                   fps=next(a['fps'] for a in job['actions'] if a['action']=='Run'),
                   scale=job['base_scale'], palette=json.loads((source/'palette.json').read_text())['rgb'],
                   labels={}, default_bone='F_R_Hand', format='json', spine=spine_version(native), character='siege')
    assets = {'/native.json':native, '/native.atlas':atlas, '/texture.png':texture, '/runtime.js':runtime}
    return project, assets


def make_handler(project, assets, output, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            if args and str(args[1]) not in ('200', '304'):
                super().log_message(fmt, *args)

        def respond(self, status, body, kind='application/json; charset=utf-8'):
            if not isinstance(body, bytes):
                body = json.dumps(body, ensure_ascii=False).encode()
            self.send_response(status);self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(body)));self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff');self.end_headers();self.wfile.write(body)

        def allowed_host(self):
            return self.headers.get('Host') in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}')

        def do_GET(self):
            if not self.allowed_host():
                self.respond(403, {'error':'仅限本机访问'});return
            route = unquote(urlsplit(self.path).path)
            if route == '/project.json':
                self.respond(200, {**project,'token':token});return
            if route == '/draft.json':
                draft = output/'draft.json'
                self.respond(200, json.loads(draft.read_text(encoding='utf-8')) if draft.exists() else None);return
            static = {'/':HERE/'index.html', '/editor.js':HERE/'editor.js', '/pose_core.js':HERE/'pose_core.js', '/style.css':HERE/'style.css'}
            p = {**assets, **static}.get(route)
            if route.startswith('/exports/'):
                candidate = (output/route[len('/exports/'):]).resolve()
                if candidate.is_relative_to(output.resolve()) and candidate.is_file():p=candidate
            if p is None or not p.is_file():
                self.respond(404, {'error':'不存在'});return
            kind = mimetypes.guess_type(str(p))[0] or 'application/octet-stream'
            if p.suffix == '.js':kind='application/javascript'
            if p.suffix == '.skel':kind='application/octet-stream'
            self.respond(200, p.read_bytes(), kind)

        def do_POST(self):
            origin = self.headers.get('Origin')
            if not self.allowed_host() or self.headers.get('X-Editor-Token') != token or (origin and origin != 'http://' + self.headers['Host']):
                self.respond(403, {'error':'无效的本地编辑请求'});return
            try:
                length = int(self.headers.get('Content-Length', '0'))
                if not 0 < length <= 10_000_000:raise ValueError('请求大小超出范围')
                data = json.loads(self.rfile.read(length))
                patch = validate_patch(data['patch'], project)
                if self.path == '/save':
                    output.mkdir(parents=True, exist_ok=True)
                    payload=json.dumps(patch,ensure_ascii=False,indent=2)
                    backup=output/('pose_'+time.strftime('%Y%m%d_%H%M%S')+'_'+secrets.token_hex(3)+'.json')
                    backup.write_text(payload,encoding='utf-8')
                    temp=output/('draft_'+secrets.token_hex(3)+'.tmp');temp.write_text(payload,encoding='utf-8');temp.replace(output/'draft.json')
                    self.respond(200, {'path':str(output/'draft.json')})
                elif self.path == '/export':
                    dest = export_frames(output,project,patch,data['frames'])
                    self.respond(200, {'path':str(dest),'url':'/exports/'+dest.name+'/run.gif', 'strip':'/exports/'+dest.name+'/run_strip.png'})
                else:self.respond(404, {'error':'不存在'})
            except (ValueError, KeyError, TypeError, OSError) as exc:
                self.respond(400, {'error':str(exc)})
    return Handler


def resolve_source(args):
    """--source 显式目录，或 --operator <id>：数据包（若有且 --base 允许）否则原生骨架。返回 project, assets, 默认输出子目录。"""
    if args.source:
        source = args.source.resolve()
        return (*load_project(source, args.runtime.resolve() if args.runtime else None, args.runtime_dir), source, None)
    op = args.operator
    if op == 'siege':
        source = ART_INCOMING / 'cy_siege_all_actions_1020'
        return (*load_project(source, args.runtime.resolve() if args.runtime else None, args.runtime_dir), source, op)
    pack = find_operator_pack(op) if args.base in ('auto', 'pack') else None
    if args.base == 'pack' and not pack:
        raise ValueError(f'找不到 {op} 的数据包（build/spine_run_trial/{op}/editor_pack）')
    if pack:
        print(f'Pack: {pack}', flush=True)
        return (*load_pack(pack, args.runtime_dir, args.runtime), pack, op)
    project, assets = load_operator(op, args.runtime_dir, args.anim, args.spread)
    return project, assets, assets['/native.skel'].parent, op


def main():
    p=argparse.ArgumentParser(description=__doc__)
    src=p.add_mutually_exclusive_group(required=True)
    src.add_argument('--source',type=Path,help='推进之王 Codex 动作包或 spine_run_trial 数据包目录')
    src.add_argument('--operator',help='干员 id（如 mizuki）；自动定位骨架、部件包和数据包')
    p.add_argument('--base',choices=('auto','pack','native'),default='auto',
                   help='--operator 底稿：auto 有数据包用数据包，否则原生；native 直接用原生动画')
    p.add_argument('--anim',default='Idle',help='原生底稿使用的动画（默认 Idle）')
    p.add_argument('--spread',action='store_true',help='原生底稿按动画时长八等分取样；默认八帧都取 t=0')
    p.add_argument('--runtime',type=Path,help='显式运行库；省略时按骨架文件头版本从 --runtime-dir 选 3.5 / 3.8')
    p.add_argument('--runtime-dir',type=Path,default=RUNTIME_DIR)
    p.add_argument('--output',type=Path,help='默认 build/spine_editor（--operator 时为 build/spine_editor/<id>）')
    p.add_argument('--port',type=int,default=8876)
    args=p.parse_args()
    project,assets,source,op=resolve_source(args)
    output=(args.output or HERE.parent.parent/'build/spine_editor'/(op or '')).resolve()
    if output.is_relative_to(source):raise ValueError('输出目录不能位于原始美术包中')
    server=ThreadingHTTPServer(('127.0.0.1',args.port),make_handler(project,assets,output,secrets.token_urlsafe(24)))
    print(f'Spine editor: http://127.0.0.1:{server.server_port}/ · {project["title"]} · Spine {project.get("spine")}',flush=True)
    print(f'Saved edits: {output}',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()


if __name__=='__main__':main()
