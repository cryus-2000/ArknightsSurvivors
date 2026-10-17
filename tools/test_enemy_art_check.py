import json,tempfile,unittest
from pathlib import Path
from PIL import Image
from enemy_art_check import audit

class EnemyArtCheckTest(unittest.TestCase):
    def test_invalid_identity_is_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'enemy_delivery.json';p.write_text('{"actions":[{"action":"Idle"}]}')
            self.assertIn('action identity missing or invalid',audit(p)['errors'])
    def test_empty_delivery_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'enemy_delivery.json';p.write_text('{"actions":[]}')
            self.assertFalse(audit(p)['technical_pass'])
    def test_corrupt_frame_is_rejected_and_pending_is_not_acceptance(self):
        with tempfile.TemporaryDirectory() as tmp:
            r=Path(tmp);im=Image.new('RGBA',(4,4));im.putpixel((1,1),(90,120,150,255));im.save(r/'part.png');im.save(r/'strip.png')
            action={'id':'bone','action':'Idle','strip':'strip.png','frames':1,'frame_size':[4,4],'sample_times':[0],'duration':1,'anchor':[2,4],'parts':[[{'file':'part.png','draw_order':0}]],'sources':[]}
            p=r/'enemy_delivery.json';p.write_text(json.dumps({'actions':[action]}))
            good=audit(p);self.assertTrue(good['technical_pass']);self.assertFalse(good['ready_to_integrate'])
            im.putpixel((2,2),(255,255,255,255));im.save(r/'strip.png')
            self.assertTrue(any('recomposition' in x for x in audit(p)['errors']))
            action['frames']=2;p.write_text(json.dumps({'actions':[action]}))
            self.assertTrue(any('frame count' in x for x in audit(p)['errors']))
    def test_missing_reference_never_passes_delivery_gate(self):
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'enemy_delivery.json';p.write_text(json.dumps({'actions':[{'id':'tear','action':'Idle','status':'missing_reference'}]}))
            self.assertFalse(audit(p)['ready_to_integrate'])

if __name__=='__main__':unittest.main()
