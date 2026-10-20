"""Local, read-only-source native Spine pose editor (Spine 3.5 / 3.8). Start with --source ART_FOLDER or a pack folder."""
import argparse
import base64
import hashlib
import io
import json
import math
import mimetypes
import secrets
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
RUNTIME_DIR = next((p / 'build/prts_ref/_node' for p in HERE.parents if (p / 'build/prts_ref/_node').is_dir()),
                   HERE.parent.parent / 'build/prts_ref/_node')
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


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--runtime',type=Path,help='显式运行库；省略时按骨架文件头版本从 --runtime-dir 选 3.5 / 3.8')
    p.add_argument('--runtime-dir',type=Path,default=RUNTIME_DIR)
    p.add_argument('--output',type=Path,default=HERE.parent.parent/'build/spine_editor')
    p.add_argument('--port',type=int,default=8876)
    args=p.parse_args()
    source=args.source.resolve();output=args.output.resolve()
    if output.is_relative_to(source):raise ValueError('输出目录不能位于原始美术包中')
    project,assets=load_project(source,args.runtime.resolve() if args.runtime else None,args.runtime_dir)
    server=ThreadingHTTPServer(('127.0.0.1',args.port),make_handler(project,assets,output,secrets.token_urlsafe(24)))
    print(f'Spine editor: http://127.0.0.1:{server.server_port}/',flush=True)
    print(f'Saved edits: {output}',flush=True)
    try:server.serve_forever()
    except KeyboardInterrupt:pass
    finally:server.server_close()


if __name__=='__main__':main()
