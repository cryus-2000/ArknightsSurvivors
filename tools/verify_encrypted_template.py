"""Verify a private encrypted template with a tiny project, without exporting the game."""
import json, os, shutil, struct, tempfile, zlib
from pathlib import Path
import encrypted_release as enc
import godot_runner

ROOT=Path(__file__).resolve().parents[1]

def checked(args,marker=None,negative=False):
    out,err,timed_out=godot_runner.run_godot([str(a) for a in args],20 if negative else 180)
    text=out+'\n'+err
    if negative:
        rejected='ERR_FILE_CORRUPT' in text or ('open_and_parse' in text and 'md5' in text.lower())
        if 'ENC_TEMPLATE_OK' in text or not rejected:
            raise RuntimeError('Ordinary template did not clearly reject encrypted PCK: '+text[-2000:])
        return {'ordinary_template_rejected':True,'ordinary_template_terminated_after_timeout':timed_out}
    elif timed_out or 'ERROR:' in text or 'Parse Error:' in text or (marker and marker not in text):
        raise RuntimeError('Encrypted template verification failed: '+text[-3000:])
    return text

def main():
    template,key=enc.template_and_key()
    (ROOT/'build').mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='encrypted_probe_',dir=ROOT/'build') as folder:
        root=Path(folder)
        project=root/'src'; project.mkdir()
        (project/'project.godot').write_text('config_version=5\n[application]\nrun/main_scene="res://probe.tscn"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
        (project/'probe.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://probe.gd" id="1"]\n[node name="Probe" type="Node"]\nscript=ExtResource("1")\n',encoding='utf-8')
        (project/'probe.gd').write_text('extends Node\nfunc _ready():\n\tif FileAccess.get_file_as_string("res://probe.json") != "PACKED_DATA_OK":\n\t\tpush_error("DATA_MISSING")\n\t\tget_tree().quit(2)\n\t\treturn\n\tvar texture = load("res://probe.png")\n\tif texture == null or texture.get_width() != 1:\n\t\tpush_error("TEXTURE_MISSING")\n\t\tget_tree().quit(3)\n\t\treturn\n\tprint("ENC_TEMPLATE_OK")\n\tget_tree().quit()\n',encoding='utf-8')
        (project/'probe.json').write_text('PACKED_DATA_OK',encoding='utf-8')
        def chunk(kind,data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
        (project/'probe.png').write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',1,1,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(b'\x00\xff\xff\xff\xff'))+chunk(b'IEND',b''))
        preset=(ROOT/'game'/'export_presets.cfg').read_text(encoding='utf-8')
        preset=enc.encrypted_preset(preset,template).replace('data/*.json,data/maps/*.json,data/characters/*.json,art/incoming/*.png','*.json')
        (project/'export_presets.cfg').write_text(preset,encoding='utf-8')
        editor=godot_runner.find_godot()
        checked([editor,'--headless','--path',project,'--import'])
        output=root/'probe.exe'
        previous=os.environ.get('GODOT_SCRIPT_ENCRYPTION_KEY')
        try:
            os.environ['GODOT_SCRIPT_ENCRYPTION_KEY']=key
            checked([editor,'--headless','--path',project,'--export-release','Windows Desktop',output])
        finally:
            if previous is None: os.environ.pop('GODOT_SCRIPT_ENCRYPTION_KEY',None)
            else: os.environ['GODOT_SCRIPT_ENCRYPTION_KEY']=previous
        info=enc.check_encrypted_pck(output.with_suffix('.pck'))
        checked([output,'--headless','--','--encryption-probe'],marker='ENC_TEMPLATE_OK')
        ordinary=Path(os.environ['APPDATA'])/'Godot'/'export_templates'/'4.7.2.stable'/'windows_release_x86_64.exe'
        plain=root/'ordinary.exe'
        shutil.copy2(ordinary,plain)
        shutil.copy2(output.with_suffix('.pck'),plain.with_suffix('.pck'))
        negative_info=checked([plain,'--headless','--audio-driver','Dummy'],negative=True)
        result=dict(info,encrypted_template_boot=True,encrypted_script_scene_json_texture_loaded=True,**negative_info)
        (ROOT/'build'/'encrypted_template_verification.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps(result,indent=2))

if __name__=='__main__': main()
