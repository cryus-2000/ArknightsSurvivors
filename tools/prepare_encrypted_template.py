"""Prepare a private Godot 4.7.2 Windows template with a locally generated AES key.
Downloads pinned official engine source / LLVM-MinGW; never changes system PATH.
"""
import argparse, hashlib, json, os, secrets, subprocess, sys, urllib.request, zipfile
from pathlib import Path

PRIVATE = Path.home()/'.codex'/'private'/'ArknightsSurvivors'
TAG = '4.7.2-stable'
COMMIT = 'ed1daf0bf001b61586d9930840f2f1394092c079'
TOOLCHAIN = 'llvm-mingw-20260922-ucrt-x86_64'
TOOLCHAIN_SHA256 = 'e3ad77d117a4bea19a7a3b333341824d79a5a371004a10e25b8504e7b3047666'
URL = 'https://github.com/mstorsjo/llvm-mingw/releases/download/20260922/'+TOOLCHAIN+'.zip'

def run(args, **kw):
    # Arguments must never include the encryption key.
    return subprocess.run([str(a) for a in args], check=True, **kw)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--jobs', type=int, default=min(8, max(2,(os.cpu_count() or 4)-4)))
    ap.add_argument('--prepare-only', action='store_true')
    ap.add_argument('--verification-template',action='store_true',help='Build a PRIVATE diagnostic template with path overrides; never distribute')
    args=ap.parse_args()
    PRIVATE.mkdir(parents=True, exist_ok=True)
    if os.name=='nt':
        identity=os.environ['USERDOMAIN']+'\\'+os.environ['USERNAME']
        run(['icacls', PRIVATE, '/inheritance:r', '/grant:r', identity+':(OI)(CI)F', 'SYSTEM:(OI)(CI)F'], stdout=subprocess.DEVNULL)
    key_path=PRIVATE/'encryption.key'
    if not key_path.exists():
        with key_path.open('x',encoding='ascii') as f: f.write(secrets.token_hex(32))
    from encrypted_release import load_key
    key=load_key(key_path)
    source=PRIVATE/'godot-source'
    if not source.exists():
        source_zip=PRIVATE/'godot-source.zip'
        print('Downloading official source archive at pinned commit...',flush=True)
        with urllib.request.urlopen('https://codeload.github.com/godotengine/godot/zip/'+COMMIT,timeout=90) as response, source_zip.with_suffix('.part').open('wb') as out:
            import shutil
            shutil.copyfileobj(response,out)
        source_zip.with_suffix('.part').replace(source_zip)
        with zipfile.ZipFile(source_zip) as z:
            for item in z.infolist():
                if not (PRIVATE/item.filename).resolve().is_relative_to(PRIVATE.resolve()):
                    raise SystemExit('Unsafe source archive member')
            z.extractall(PRIVATE)
        (PRIVATE/('godot-'+COMMIT)).rename(source)
        (source/'.source-commit').write_text(COMMIT,encoding='ascii')
    if (source/'.git').exists():
        commit=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
    else:
        commit=(source/'.source-commit').read_text(encoding='ascii').strip()
    if commit!=COMMIT: raise SystemExit('Refusing source checkout: exact official commit does not match')
    compiler=PRIVATE/TOOLCHAIN
    if not compiler.exists():
        archive=PRIVATE/(TOOLCHAIN+'.zip')
        if not archive.exists():
            print('Downloading pinned official LLVM-MinGW portable toolchain...',flush=True)
            request=urllib.request.Request('https://api.github.com/repos/mstorsjo/llvm-mingw/releases/assets/581762383?download=1', headers={'Accept':'application/octet-stream','User-Agent':'ArknightsSurvivors-build'})
            with urllib.request.urlopen(request, timeout=120) as response, archive.with_suffix('.part').open('wb') as out:
                import shutil
                shutil.copyfileobj(response,out)
            archive.with_suffix('.part').replace(archive)
        if hashlib.file_digest(archive.open('rb'),'sha256').hexdigest()!=TOOLCHAIN_SHA256:
            raise SystemExit('Compiler archive SHA256 mismatch; aborting')
        print('Extracting compiler...',flush=True)
        with zipfile.ZipFile(archive) as z:
            for item in z.infolist():
                if not (PRIVATE/item.filename).resolve().is_relative_to(PRIVATE.resolve()):
                    raise SystemExit('Unsafe compiler archive member')
            z.extractall(PRIVATE)
    scons_dir=PRIVATE/'scons'
    if not (scons_dir/'SCons').is_dir():
        run([sys.executable,'-m','pip','install','--target',scons_dir,'scons==4.9.1','--disable-pip-version-check'])
    if args.prepare_only:
        print('Private source and portable toolchain ready; no compilation requested.')
        return
    env=dict(os.environ, SCRIPT_AES256_ENCRYPTION_KEY=key, PYTHONPATH=str(scons_dir), PATH=str(compiler/'bin')+os.pathsep+os.environ['PATH'])
    log=PRIVATE/('compile-diagnostic.log' if args.verification_template else 'compile.log')
    cmd=[sys.executable,'-m','SCons','platform=windows','target=template_release','arch=x86_64','use_mingw=yes','use_llvm=yes','d3d12=no','accesskit=no','production=yes','lto=none','debug_symbols=no','disable_path_overrides='+('no' if args.verification_template else 'yes'),f'-j{args.jobs}']
    print('Compiling exact Godot '+TAG+'; private log: '+str(log),flush=True)
    with log.open('w',encoding='utf-8') as output:
        run(cmd,cwd=source,env=env,stdout=output,stderr=subprocess.STDOUT)
    template=source/'bin'/'godot.windows.template_release.x86_64.llvm.exe'
    if not template.is_file():
        candidates=list((source/'bin').glob('godot.windows.template_release.x86_64*.exe'))
        candidates=[p for p in candidates if 'console' not in p.name]
        if len(candidates)!=1: raise SystemExit('Could not uniquely identify release template')
        template=candidates[0]
    import shutil
    stable_template=PRIVATE/('diagnostic_verifier.exe' if args.verification_template else 'public_template.exe')
    shutil.copy2(template,stable_template)
    template=stable_template
    if args.verification_template:
        manifest=json.loads((PRIVATE/'template.json').read_text(encoding='utf-8'))
        manifest.update(diagnostic_verifier=str(template),diagnostic_verifier_sha256=hashlib.file_digest(template.open('rb'),'sha256').hexdigest(),diagnostic_build_options=cmd[3:])
        (PRIVATE/'template.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
        print('PRIVATE diagnostic verifier ready; public template preserved.',flush=True)
        return
    manifest={'purpose':'public_release','engine_version':'4.7.2.stable','source_commit':COMMIT,'template':str(template),'template_sha256':hashlib.file_digest(template.open('rb'),'sha256').hexdigest(),'toolchain':TOOLCHAIN,'toolchain_sha256':TOOLCHAIN_SHA256,'build_options':cmd[3:]}
    (PRIVATE/'template.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
    print('Encrypted release template ready. Key was not printed or copied into the repository.',flush=True)

if __name__=='__main__': main()
