"""Validate every staged PNG, audio file and JSON through the encrypted game PCK.
The temporary external probe is never included in the public distribution.
"""
import argparse, fnmatch, json, os, re, shutil, struct, tempfile, zipfile
from pathlib import Path
import encrypted_release as enc
import godot_runner
from export_build import SKIP_WORDS

ROOT=Path(__file__).resolve().parents[1]
PROBE=r'''extends SceneTree
const Art = preload("res://scripts/art.gd")
var images = __IMAGES__
var audio_paths = __AUDIO__
var json_paths = __JSON__
var audience = __AUDIENCE__
var failures: Array = []
func _initialize():
    AudioServer.set_bus_mute(0, true)
    call_deferred("_verify")
func _verify():
    Art.normal_maps = false
    for item in images:
        var resource = load("res://art/incoming/" + item[0] + ".png")
        if not resource is Texture2D or resource.get_width() != item[1] or resource.get_height() != item[2]:
            failures.append("packed_png:" + item[0])
        if resource is Texture2D:
            var pixels = resource.get_image()
            if pixels == null or pixels.is_empty():
                failures.append("texture_pixels:" + item[0])
        var base = str(item[0]).trim_suffix("@2x")
        var texture = Art.tex(base)
        if texture == null:
            failures.append("art_tex:" + base)
        if str(item[0]).ends_with("@2x") and Art.hires(base) != 2.0:
            failures.append("hires_density:" + base)
        if Art._incoming_path(base) != "":
            failures.append("external_override:" + base)
    for alias_name in Art.ALIAS:
        if Art.tex(alias_name) == null:
            failures.append("alias:" + alias_name)
    for path in audio_paths:
        var stream = load(path)
        if not stream is AudioStream or stream.get_length() <= 0:
            failures.append("audio:" + path)
    for path in json_paths:
        var parser = JSON.new()
        if parser.parse(FileAccess.get_file_as_string(path)) != OK:
            failures.append("json:" + path)
    var info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
    if not info is Dictionary or info.get("audience", "") != audience or not info.get("encrypted", false):
        failures.append("build_metadata")
    var cfg = root.get_node_or_null("Cfg")
    if cfg == null:
        failures.append("cfg_missing")
    else:
        if cfg.unlock_all or not cfg.dev_args().is_empty() or OS.is_debug_build():
            failures.append("release_debug_gate")
        if not cfg.gallery_seen.is_empty() or not cfg.seen_relics.is_empty() or not cfg.endings_cleared.is_empty() or cfg.diff_unlocked != 0:
            failures.append("fresh_progress")
        if cfg.can_boss_trial() != (audience == "internal"):
            failures.append("boss_trial_audience")
    if audience == "public" and cfg != null:
        var gallery = load("res://scripts/gallery.gd").new()
        root.add_child(gallery)
        gallery.set_process(false)
        for page in 7:
            gallery.tab = page
            gallery._build()
            if gallery.entries.is_empty():
                failures.append("gallery_empty:" + str(page))
            for entry in gallery.entries:
                if bool(entry.get("locked", false)) != (page != 0):
                    failures.append("gallery_initial_lock:" + str(page))
        gallery.queue_free()
    var result = {"packed_png_count": images.size(), "alias_count": Art.ALIAS.size(), "audio_count": audio_paths.size(), "json_count": json_paths.size(), "audience": audience, "failures": failures}
    Art._cache.clear()
    Art._hires.clear()
    Art._hires_rid.clear()
    await process_frame
    await process_frame
    print("PACK_VERIFY_JSON=" + JSON.stringify(result))
    quit(0 if failures.is_empty() else 2)
'''

def in_export(path,project,excludes):
    relative=path.relative_to(project).as_posix()
    if any(fnmatch.fnmatchcase(relative,pattern) for pattern in excludes): return False
    current=path.parent
    while current.is_relative_to(project):
        if (current/'.gdignore').is_file(): return False
        if current==project: break
        current=current.parent
    return True

def save_log(kind,commit,out,err):
    path=ROOT/'build'/('encrypted_'+kind+'_'+commit+'.log')
    path.write_text('STDOUT\n'+out+'\nSTDERR\n'+err,encoding='utf-8')
    return path

def real_errors(text):
    # This exact two-resource engine shutdown diagnostic predates these probes.
    # No script, import, decryption, or other ERROR is permitted by this exception.
    known='ERROR: 2 resources still in use at exit (run with --verbose for details).'
    return [line for line in text.splitlines() if ('ERROR:' in line or 'Parse Error:' in line) and line.strip()!=known]

def isolated_run(arguments,timeout):
    # Windows Godot get_config_path/get_cache_path honor these process env variables.
    saved={name:os.environ.get(name) for name in ('APPDATA','LOCALAPPDATA')}
    with tempfile.TemporaryDirectory(prefix='pack_profile_',dir=ROOT/'build') as directory:
        try:
            for name in saved:
                path=Path(directory)/name
                path.mkdir()
                os.environ[name]=str(path)
            return godot_runner.run_godot(arguments,timeout)
        finally:
            for name,value in saved.items():
                if value is None: os.environ.pop(name,None)
                else: os.environ[name]=value

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',required=True,type=Path)
    ap.add_argument('--staged-project',type=Path,default=ROOT/'build/_export/src/game')
    ap.add_argument('--zip',type=Path)
    args=ap.parse_args()
    package=args.package.resolve(); project=args.staged_project.resolve()
    ordinary=Path(os.environ['APPDATA'])/'Godot/export_templates/4.7.2.stable/windows_release_x86_64.exe'
    verifier=enc.diagnostic_verifier()
    enc.check_distribution(package)
    manifest=json.loads((package/'release_manifest.json').read_text(encoding='utf-8'))
    images=[]
    for path in sorted((project/'art/incoming').glob('*.png')):
        if any(word in path.name.lower() for word in SKIP_WORDS): continue
        raw=path.read_bytes()[:24]
        if raw[:8]!=b'\x89PNG\r\n\x1a\n': raise ValueError('Invalid staged PNG: '+path.name)
        width,height=struct.unpack('>II',raw[16:24])
        images.append([path.stem,width,height])
    if not images or len(images)!=manifest['packed_png_count']: raise ValueError('Staged art inventory does not match release manifest')
    preset=(project/'export_presets.cfg').read_text(encoding='utf-8').split('[preset.1]')[0]
    match=re.search(r'^exclude_filter="(.*)"$',preset,re.M)
    excludes=[value.strip() for value in match.group(1).split(',')] if match else []
    audio=['res://'+p.relative_to(project).as_posix() for p in sorted((project/'audio').rglob('*')) if p.suffix.lower() in ('.ogg','.wav') and in_export(p,project,excludes)]
    json_paths=['res://'+p.relative_to(project).as_posix() for p in sorted((project/'data').rglob('*.json')) if in_export(p,project,excludes)]
    text=PROBE.replace('__IMAGES__',json.dumps(images,ensure_ascii=False)).replace('__AUDIO__',json.dumps(audio)).replace('__JSON__',json.dumps(json_paths)).replace('__AUDIENCE__',json.dumps(manifest['audience']))
    exe=package/'game/ArknightsSurvivors.exe'; pck=exe.with_suffix('.pck')
    enc.check_encrypted_pck(pck)
    with tempfile.TemporaryDirectory(prefix='pack_probe_',dir=ROOT/'build') as directory:
        probe=Path(directory)/'verify.gd'; probe.write_text(text,encoding='utf-8')
        out,err,timeout=isolated_run([str(verifier),'--headless','--audio-driver','Dummy','--main-pack',str(pck),'--script',str(probe),'--','--pack-probe','--unlockall'],300)
        log=save_log('game_probe',manifest['commit'],out,err)
        combined=out+'\n'+err
        line=next((line for line in out.splitlines() if line.startswith('PACK_VERIFY_JSON=')),None)
        if timeout or real_errors(combined) or line is None:
            raise RuntimeError('Pack probe failed (full log: '+str(log)+'): '+combined[-5000:])
        result=json.loads(line.split('=',1)[1])
        result['probe_shutdown_warning']='2 resources still in use at exit' in combined
        result['probe_log']=str(log)
        if result['failures']: raise RuntimeError('Pack resources failed: '+json.dumps(result))
    out,err,timeout=isolated_run([str(exe),'--headless','--audio-driver','Dummy','--quit-after','60','--','--pack-smoke'],120)
    log=save_log('game_boot',manifest['commit'],out,err)
    if timeout or real_errors(out+'\n'+err) or 'Godot Engine' not in out:
        raise RuntimeError('Packaged game boot failed: '+(out+'\n'+err)[-5000:])
    result['packaged_game_boot']=True
    result['boot_shutdown_warning']='2 resources still in use at exit' in out+err
    result['boot_log']=str(log)
    with tempfile.TemporaryDirectory(prefix='ordinary_probe_',dir=ROOT/'build') as directory:
        plain=Path(directory)/'ordinary.exe'
        shutil.copy2(ordinary,plain)
        shutil.copy2(pck,plain.with_suffix('.pck'))
        out,err,timeout=isolated_run([str(plain),'--headless','--audio-driver','Dummy'],30)
    log=save_log('ordinary_rejection',manifest['commit'],out,err)
    if not ('ERR_FILE_CORRUPT' in out+err or ('open_and_parse' in out+err and 'md5' in (out+err).lower())):
        raise RuntimeError('Ordinary template did not clearly reject game PCK')
    result['ordinary_template_rejected']=True
    result['ordinary_template_terminated_after_timeout']=timeout
    if args.zip:
        with zipfile.ZipFile(args.zip) as z:
            names=[Path(n).parts[1:] for n in z.namelist() if not n.endswith('/')]
            expected={p.relative_to(package).as_posix() for p in package.rglob('*') if p.is_file()}
            actual={'/'.join(n) for n in names}
            if actual!=expected: raise ValueError('ZIP files differ from verified distribution')
            for name in z.namelist():
                if name.endswith('/'): continue
                relative='/'.join(Path(name).parts[1:])
                import hashlib
                if hashlib.sha256(z.read(name)).digest()!=hashlib.sha256((package/relative).read_bytes()).digest():
                    raise ValueError('ZIP file differs from verified package: '+relative)
            result['zip_verified']=True
            result['zip_members']=len(names)
    result['commit']=manifest['commit']
    report=ROOT/'build'/('encrypted_game_verification_'+manifest['commit']+'.json')
    report.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(result,indent=2))
    print('Report:',report)

if __name__=='__main__': main()
