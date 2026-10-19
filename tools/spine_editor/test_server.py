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
from server import validate_patch, export_frames, make_handler


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

if __name__=='__main__':unittest.main()
