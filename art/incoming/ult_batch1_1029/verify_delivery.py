from pathlib import Path
from PIL import Image
import ast,hashlib,json,re,numpy as np
R=Path(__file__).resolve().parent
m=json.loads((R/'manifest.json').read_text(encoding='utf-8'));A={a['name']:a for a in m['assets']};assert len(A)==16
report={'stage':'approved keyframe snapshot','keyframes':0,'repeat_checks':0,'runtime_verified':False}
for a in m['assets']:
 assert len(a['keyframes'])==2
 full=np.prod(a['physical_size'])*4*a['frame_count']/1048576;assert abs(full-a['planned_rgba_mib'])<1e-9 and full<=5
 for f in a['keyframes']:
  p=R/f['file'];im=Image.open(p).convert('RGBA');assert im.size==tuple(a['physical_size']);assert set(np.unique(np.asarray(im)[:,:,3]))<={0,255};assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256'];report['keyframes']+=1
 if a.get('seam_endpoint_equal'):
  for f in a['keyframes']:
   ar=np.array(Image.open(R/f['file']));assert np.array_equal(ar[:,0],ar[:,-1]);assert np.any(ar[:,0,3]);report['repeat_checks']+=1
assert report['keyframes']==32 and report['repeat_checks']==12
report['planned_full_animation_mib']=sum(a['planned_rgba_mib'] for a in m['assets']);assert report['planned_full_animation_mib']<=30
anchor=A['fx_ult_ulpianus_anchor_front'];aa=Image.open(R/anchor['keyframes'][0]['file']).convert('RGBA');ab=Image.open(R/anchor['keyframes'][1]['file']).convert('RGBA');assert aa.transpose(Image.Transpose.ROTATE_270).tobytes()==ab.tobytes();report['anchor_rotation_exact']=True
pm=json.loads((R/'references/native_anchor/pixel_manifest.json').read_text(encoding='utf-8'));comp=Image.new('RGBA',(96,96))
for part in pm['parts']:
 p=R/part['pixel_file'];assert hashlib.sha256(p.read_bytes()).hexdigest()==part['sha256'];comp.alpha_composite(Image.open(p).convert('RGBA'))
assert comp.resize((192,192),Image.Resampling.NEAREST).tobytes()==aa.tobytes();report['anchor_attachment_recomposition_exact']=True
sword=A['fx_ult_texas_sword_front'];src=Image.open(sword['source_candidate']).convert('RGBA');assert hashlib.sha256(Path(sword['source_candidate']).read_bytes()).hexdigest()==sword['current_game_source_hash'];fw=src.width//5
for i,f in enumerate(sword['keyframes']):
 source=src.crop((fw*sword['source_frames'][i],0,fw*(sword['source_frames'][i]+1),src.height));out=Image.open(R/f['file']).convert('RGBA');x,y=sword['source_to_delivery_offset'];crop=out.crop((x,y,x+fw,y+src.height));mask=np.asarray(source)[:,:,3]>0;assert np.array_equal(np.asarray(source)[mask],np.asarray(crop)[mask]);assert int(np.count_nonzero(np.asarray(out)[:,:,3]))==int(np.count_nonzero(mask))
report['current_game_sword_exact']=True
beam=A['fx_ult_skalter_beam_front'];scene=json.loads((R/'beam_scene_r2.json').read_text(encoding='utf-8'));assert beam['review_draw_width']==80 and all(s['beam_display_width']==80 and s['beam_display_length']==304 for s in scene['scenes']);report['beam_review_width']=80
files=json.loads((R/'delivery_files.json').read_text(encoding='utf-8'))['files'];selected=set(files)
for rel in files:
 p=R/rel
 if rel=='commit_verification.json':continue
 assert p.is_file(),rel
 if p.suffix=='.png':
  with Image.open(p) as im:im.verify()
 if p.suffix=='.py':ast.parse(p.read_text(encoding='utf-8-sig'),filename=str(p))
 if p.suffix=='.html':
  for v in re.findall(r'(?:src|href)=[\"\x27]([^\"\x27]+)',p.read_text(encoding='utf-8')):
   if v.startswith(('http:','https:','#','data:')):continue
   ref=(p.parent/v.split('#')[0]).resolve();assert ref.is_file(),(rel,v)
   try:target=ref.relative_to(R.resolve()).as_posix()
   except ValueError:continue
   assert target in selected,(rel,target,'missing from commit selection')
report['selected_files']=len(files);report['selected_preview_references_complete']=True;report['status']='PASS'
(R/'commit_verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');print(json.dumps(report,ensure_ascii=False))
