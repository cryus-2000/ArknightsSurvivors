import base64
import io
import json
import tempfile
import unittest
import threading
import http.client
from http.server import ThreadingHTTPServer
from pathlib import Path
from PIL import Image
from server import validate_patch, export_frames, make_handler, spine_version, pick_runtime, load_project


class EditorTests(unittest.TestCase):
    def setUp(self):
        self.project = dict(id='source', frames=[{}]*8, bones=['root'], slots=['body'], chains={}, fps=8)
        self.patch = dict(version=1, source='source', frames=[dict(ops=[], order=None) for _ in range(8)])

    def test_patch_identity_numbers_and_order(self):
        validate_patch(self.patch, self.project)
        for op in [dict(type='rotate', bone='root', degrees=float('nan')),
                   dict(type='translate', bone='../file', dx=0, dy=0),
                   dict(type='unknown', bone='root')]:
            bad=json.loads(json.dumps(self.patch));bad['frames'][0]['ops']=[op]
            with self.assertRaises(ValueError):validate_patch(bad,self.project)
        bad=json.loads(json.dumps(self.patch));bad['source']='other'
        with self.assertRaises(ValueError):validate_patch(bad,self.project)

    def test_export_roundtrip_and_limits(self):
        im=Image.new('RGBA',(256,256));im.putpixel((10,20),(255,0,0,255))
        buf=io.BytesIO();im.save(buf,format='PNG');png=base64.b64encode(buf.getvalue()).decode()
        scratch=Path(__file__).resolve().parents[2]/'build/spine_editor_tests';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as d:
            output=export_frames(Path(d),self.project,self.patch,[png]*8)
            strip=Image.open(output/'run_strip.png')
            self.assertEqual(strip.size,(2048,256))
            self.assertEqual(strip.getpixel((10+256*7,20)),(255,0,0,255))
            self.assertEqual(json.loads((output/'pose.json').read_text()),self.patch)
            with self.assertRaises(ValueError):export_frames(Path(d),self.project,self.patch,[png]*9)
            with self.assertRaises(ValueError):export_frames(Path(d),self.project,self.patch,['bad']*8)
            self.assertEqual(len(list(Path(d).iterdir())),1)

    def test_http_scope_save_and_reload(self):
        scratch=Path(__file__).resolve().parents[2]/'build/spine_editor_tests';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as d:
            output=Path(d)/'output'
            httpd=ThreadingHTTPServer(('127.0.0.1',0),make_handler(self.project,{},output,'test-token'))
            thread=threading.Thread(target=httpd.serve_forever,daemon=True);thread.start()
            def request(method,path,body=None,headers=None):
                c=http.client.HTTPConnection('127.0.0.1',httpd.server_port,timeout=3)
                c.request(method,path,body=body,headers=headers or {})
                r=c.getresponse();result=(r.status,r.read());c.close();return result
            try:
                body=json.dumps({'patch':self.patch})
                self.assertEqual(request('POST','/save',body)[0],403)
                self.assertEqual(request('POST','/save',body,{'X-Editor-Token':'test-token','Origin':'https://invalid.example'})[0],403)
                self.assertEqual(request('GET','/exports/%2e%2e/server.py')[0],404)
                self.assertEqual(request('GET','/project.json',headers={'Host':'invalid.example'})[0],403)
                self.assertEqual(request('POST','/save',body,{'X-Editor-Token':'test-token'})[0],200)
                status,saved=request('GET','/draft.json');self.assertEqual(status,200);self.assertEqual(json.loads(saved),self.patch)
                self.assertEqual(len(list(output.glob('pose_*.json'))),1)
            finally:
                httpd.shutdown();httpd.server_close();thread.join()

def _spine_string(text):
    raw=text.encode();n=len(raw)+1;out=bytearray()
    while True:
        b=n&0x7F;n>>=7
        out.append(b|(0x80 if n else 0))
        if not n:break
    return bytes(out)+raw


class VersionAndPackTests(unittest.TestCase):
    def scratch(self):
        root=Path(__file__).resolve().parents[2]/'build/spine_editor_tests';root.mkdir(parents=True,exist_ok=True)
        return tempfile.TemporaryDirectory(dir=root)

    def test_version_from_skel_header_and_json(self):
        with self.scratch() as d:
            d=Path(d)
            (d/'a.skel').write_bytes(_spine_string('h'*27)+_spine_string('3.8.99')+b'\x00'*20)
            (d/'b.skel').write_bytes(_spine_string('x')+_spine_string('3.5.51'))
            (d/'c.json').write_text(json.dumps({'skeleton':{'spine':'3.5.51'}}))
            (d/'bad.skel').write_bytes(_spine_string('x')+_spine_string('hello'))
            self.assertEqual(spine_version(d/'a.skel'),'3.8.99')
            self.assertEqual(spine_version(d/'b.skel'),'3.5.51')
            self.assertEqual(spine_version(d/'c.json'),'3.5.51')
            with self.assertRaises(ValueError):spine_version(d/'bad.skel')

    def test_runtime_choice(self):
        with self.scratch() as d:
            d=Path(d)
            for name in ('spine-canvas-3.5.51.js','spine-canvas-3.8.js'):(d/name).write_text('//')
            self.assertEqual(pick_runtime('3.8.99',d).name,'spine-canvas-3.8.js')
            self.assertEqual(pick_runtime('3.5.51',d).name,'spine-canvas-3.5.51.js')
            with self.assertRaises(ValueError):pick_runtime('4.0.64',d)
            (d/'spine-canvas-3.8.js').unlink()
            with self.assertRaises(ValueError):pick_runtime('3.8.99',d)

    def test_generic_38_pack(self):
        with self.scratch() as d:
            d=Path(d);rt=d/'rt';rt.mkdir()
            for name in ('spine-canvas-3.5.51.js','spine-canvas-3.8.js'):(rt/name).write_text('//')
            (d/'op.skel').write_bytes(_spine_string('h')+_spine_string('3.8.99'))
            (d/'op.atlas').write_text('\nop.png\nsize: 4,4\n');(d/'op.png').write_bytes(b'png')
            pack=d/'pack';frames=[]
            for i in range(8):
                (pack/'frames'/f'Run_0{i}').mkdir(parents=True)
                (pack/'frames'/f'Run_0{i}'/'bones.json').write_text(json.dumps([{'name':'root','world':[0,i],'matrix':[1,0,0,1]}]))
                frames.append({'name':f'Run_0{i}','order':['body'],'hidden':[]})
            (pack/'pack.json').write_text(json.dumps({'version':1,'character':'op','title':'op','skeleton':str(d/'op.skel'),'atlas':str(d/'op.atlas'),
                'scale':0.2,'palette':[[0,0,0]],'bones':['root'],'slots':['body'],'chains':{},'frames':frames}),encoding='utf-8')
            project,assets=load_project(pack,None,rt)
            self.assertEqual((project['format'],project['spine']),('skel','3.8.99'))
            self.assertEqual(assets['/runtime.js'].name,'spine-canvas-3.8.js')
            self.assertIn('/native.skel',assets)
            self.assertEqual(project['frames'][3]['bones'][0]['world'],[0,3])
            first=project['id'];(pack/'frames'/'Run_00'/'bones.json').write_text('[]')
            self.assertNotEqual(load_project(pack,None,rt)[0]['id'],first)  # 骨骼变了，旧修正不再匹配
            bad=json.loads((pack/'pack.json').read_text(encoding='utf-8'));bad['frames']=bad['frames'][:7]
            (pack/'pack.json').write_text(json.dumps(bad),encoding='utf-8')
            with self.assertRaises(ValueError):load_project(pack,None,rt)

    def test_export_game_strip(self):
        im=Image.new('RGBA',(256,256));im.putpixel((100,150),(0,255,0,255))
        buf=io.BytesIO();im.save(buf,format='PNG');png=base64.b64encode(buf.getvalue()).decode()
        project=dict(id='s',frames=[{}]*8,bones=['root'],slots=['body'],chains={},fps=8)
        patch=dict(version=1,source='s',frames=[dict(ops=[],order=None) for _ in range(8)])
        with self.scratch() as d:
            out=export_frames(Path(d),project,patch,[png]*8)
            strip=Image.open(out/'strip@2x.png')
            self.assertEqual(strip.size,(1024,128))
            self.assertEqual(strip.getpixel((36+128*5,90)),(0,255,0,255))  # 场景 (128,180) → 帧原点 (64,120)


if __name__=='__main__':unittest.main()
