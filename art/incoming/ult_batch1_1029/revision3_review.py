from pathlib import Path
from PIL import Image,ImageDraw
import numpy as np,json,hashlib
R=Path(__file__).resolve().parent;P=R/'previews';m=json.loads((R/'manifest.json').read_text(encoding='utf-8'));A={a['name']:a for a in m['assets']};beam=A['fx_ult_skalter_beam_front'];sword=A['fx_ult_texas_sword_front'];sword_source=Image.open(sword['source_candidate']).convert('RGBA');w=sword_source.width//5;qa=[]
for info,f in zip(sword['keyframes'],[0,4]):
 im=Image.open(R/info['file']).convert('RGBA');src=sword_source.crop((f*w,0,(f+1)*w,80));visible=np.array(src)[:,:,3]>0;crop=im.crop((20,148,20+w,228));assert np.array_equal(np.array(crop)[visible],np.array(src)[visible]);assert np.count_nonzero(np.array(im)[:,:,3])==np.count_nonzero(visible);qa.append({'source_frame':f,'visible_pixels_exact':True,'not_clipped':True})
for a in [beam,sword]:
 for f in a['keyframes']:
  p=R/f['file'];im=Image.open(p).convert('RGBA');assert im.size==tuple(a['physical_size']);assert set(np.unique(np.array(im)[:,:,3]))<={0,255};assert hashlib.sha256(p.read_bytes()).hexdigest()==f['sha256']
for f in beam['keyframes']:
 ar=np.array(Image.open(R/f['file']));assert np.array_equal(ar[:,0],ar[:,-1])
# Same display scale for laser studies. Main candidate keeps the rough edge without a braided core.
out=Image.new('RGB',(760,410),'#283542');d=ImageDraw.Draw(out)
rows=[('Earlier: braided lines',Image.open(P/'before_beam.png').convert('RGBA')),('Existing game laser structure: retained as comparison',None),('Current candidate: steady core + rough material edge',None)]
for row,(label,im) in enumerate(rows):
 y=row*132;d.text((12,y+8),label,fill='white')
 if row==0:
  im.thumbnail((730,95),Image.Resampling.NEAREST);out.paste(im,(12,y+32),im)
 else:
  for j in range(2):
   if row==1:im=Image.open(P/f'beam_existing_material_r3_f{(0,3)[j]:02}@2x.png').convert('RGBA')
   else:im=Image.open(R/beam['keyframes'][j]['file']).convert('RGBA')
   im=im.resize((336,96),Image.Resampling.NEAREST);out.paste(im,(12+j*370,y+30),im)
out.save(P/'beam_design_compare_r3.png')
# Sword proof uses exact same source crop and delivered crop at equal nearest-neighbor enlargement.
out=Image.new('RGB',(640,390),'#283542');d=ImageDraw.Draw(out)
for j,f in enumerate([0,4]):
 for col in range(2):
  src=sword_source.crop((f*w,0,(f+1)*w,80)) if col==0 else Image.open(R/sword['keyframes'][j]['file']).crop((20,148,20+w,228));src=src.resize((w*4,320),Image.Resampling.NEAREST);out.paste(src,(30+j*310+col*140,45),src);d.text((30+j*310+col*140,12),('Game' if col==0 else 'Ultimate')+f' f{f}',fill='white')
out.save(P/'sword_reuse_proof_r3.png')
p=R/'review.html';s=p.read_text(encoding='utf-8');tag='<section id="revision3-focus"><h2>本轮：复用现有剑雨剑体，重做光束轮廓</h2><p>剑雨原样复用当前优先调用的fx_texas_sword_drop；光束去掉编织波纹，保留现有结构版作对照。</p><img src="previews/sword_reuse_proof_r3.png"><img src="previews/beam_design_compare_r3.png"></section>'
if 'id="revision3-focus"' not in s:s=s.replace('<h2>本轮对位与拼接预览</h2>',tag+'<h2>本轮对位与拼接预览</h2>',1)
p.write_text(s,encoding='utf-8');(R/'revision3_qa.json').write_text(json.dumps({'sword_reuse':qa,'beam_endpoints_equal':True,'dimensions_alpha_hashes':True,'runtime_verified':False,'native_laser_variant':'comparison only; main candidate uses revision3_beam.png'},indent=2),encoding='utf-8')
print('PASS: exact current-game sword reuse, two beam endpoint profiles, dimensions/alpha/hashes')
