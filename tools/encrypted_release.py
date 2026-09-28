"""Small, fail-closed helpers for Windows encrypted release exports."""
import hashlib, json, os, re, struct
from pathlib import Path
PRIVATE = Path.home()/'.codex'/'private'/'ArknightsSurvivors'

def load_key(path):
    key=Path(path).read_text(encoding='ascii').strip()
    if not re.fullmatch(r'[0-9a-fA-F]{64}',key):
        raise ValueError('Encryption key must be 64 hexadecimal characters')
    return key

def template_and_key():
    key=load_key(PRIVATE/'encryption.key')
    info=json.loads((PRIVATE/'template.json').read_text(encoding='utf-8'))
    if info.get('purpose') != 'public_release': raise ValueError('Only the public release template may be exported')
    if info['engine_version']!='4.7.2.stable' or info['source_commit']!='ed1daf0bf001b61586d9930840f2f1394092c079':
        raise ValueError('Encrypted template must match the pinned Godot 4.7.2 source')
    template=Path(info['template'])
    with template.open('rb') as fh:
        digest=hashlib.file_digest(fh,'sha256').hexdigest()
    if digest!=info['template_sha256']: raise ValueError('Encrypted template checksum mismatch')
    return template,key

def encrypted_preset(text,template):
    # Modify only the Windows preset in a temporary staging tree. Never persist keys.
    blocks=re.split(r'(?=^\[)',text,flags=re.M)
    preset=None
    for block in blocks:
        if re.search(r'^name="Windows Desktop"$',block,re.M):
            preset=block.splitlines()[0][1:-1]
    if preset is None: raise ValueError('Windows Desktop preset not found')
    def set_value(block,name,value):
        pattern=r'^'+re.escape(name)+r'=.*$'
        line=name+'='+value
        return re.sub(pattern,lambda m:line,block,flags=re.M) if re.search(pattern,block,re.M) else block.rstrip()+'\n'+line+'\n\n'
    for i,block in enumerate(blocks):
        if block.startswith('['+preset+']'):
            for name,value in {'encrypt_pck':'true','encrypt_directory':'true','encryption_include_filters':'"*"','encryption_exclude_filters':'""','script_encryption_key':'""','custom_features':'"packed_release"','export_filter':'"all_resources"'}.items():
                block=set_value(block,name,value)
            match=re.search(r'^exclude_filter="(.*)"$',block,re.M)
            exclude=[s.strip() for s in (match.group(1) if match else '').split(',') if s.strip() and s.strip()!='art/incoming/*']
            block=set_value(block,'exclude_filter',json.dumps(','.join(exclude+['tests/*'])))
            block=set_value(block,'include_filter','"data/*.json,data/maps/*.json,data/characters/*.json,art/incoming/*.png"')
            blocks[i]=block
        elif block.startswith('['+preset+'.options]'):
            block=set_value(block,'custom_template/release',json.dumps(str(template).replace('\\','/')))
            block=set_value(block,'binary_format/embed_pck','false')
            blocks[i]=block
    return ''.join(blocks)

def check_encrypted_pck(path):
    with Path(path).open('rb') as f: header=f.read(24)
    if len(header)!=24 or header[:4]!=b'GDPC': raise ValueError('Invalid PCK header')
    version,major,minor,patch,flags=struct.unpack('<IIIII',header[4:])
    if (major,minor,patch)!=(4,7,2): raise ValueError('PCK engine version mismatch')
    if not flags&1: raise ValueError('PCK directory is not encrypted')
    return {'format_version':version,'engine_version':f'{major}.{minor}.{patch}','directory_encrypted':True}

def check_distribution(directory):
    allowed={'game/ArknightsSurvivors.exe','game/ArknightsSurvivors.pck','开始游戏.bat','说明.txt','release_manifest.json'}
    files=list(Path(directory).rglob('*'))
    bad=[str(p.relative_to(directory)) for p in files if p.is_file() and p.relative_to(directory).as_posix() not in allowed]
    if bad: raise ValueError('Unexpected loose files in encrypted distribution: '+', '.join(bad[:10]))
    return len([p for p in files if p.is_file()])


def diagnostic_verifier():
    info=json.loads((PRIVATE/'template.json').read_text(encoding='utf-8'))
    template=Path(info['diagnostic_verifier'])
    with template.open('rb') as fh:
        digest=hashlib.file_digest(fh,'sha256').hexdigest()
    if digest!=info['diagnostic_verifier_sha256']: raise ValueError('Private diagnostic verifier checksum mismatch')
    return template
