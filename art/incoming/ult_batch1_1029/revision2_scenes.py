from pathlib import Path
from PIL import Image,ImageDraw,ImageChops
import json,math,numpy as np
R=Path(__file__).resolve().parent;P=R/'previews';m=json.loads((R/'manifest.json').read_text(encoding='utf-8'));A={a['name']:a for a in m['assets']}
def key(name,j=1):return Image.open(R/A[name]['keyframes'][j]['file']).convert('RGBA')
def pastecenter(canvas,im,center):canvas.alpha_composite(im,(round(center[0]-im.width/2),round(center[1]-im.height/2)))
body=key('fx_ult_skalter_seaborn_front');water=key('fx_ult_skalter_seaborn_back');root=A['fx_ult_skalter_seaborn_front']['native_sources'][1]['native_root_on_canvas'];ar=np.array(body);bb=body.getbbox();mask=(ar[:,:,1]>160)&(ar[:,:,2]>150)&(ar[:,:,0]<100);mask[bb[1]+round((bb[3]-bb[1])*.35):]=False;yy,xx=np.where(mask);top=yy.min();eligible=yy<=top+6;mouth=(float(np.median(xx[eligible])),float(np.median(yy[eligible])))
board=Image.new('RGB',(1120,500),'#283542');labels=ImageDraw.Draw(board);scene_meta=[]
for j in range(2):
 scene=Image.new('RGBA',(560,470));ground=(170,418);offset=(ground[0]-root[0],ground[1]-root[1]);w=water.resize((180,54),Image.Resampling.NEAREST);scene.alpha_composite(w,(ground[0]-90,ground[1]-27));scene.alpha_composite(body,offset);origin=(mouth[0]+offset[0],mouth[1]+offset[1]);tile=key('fx_ult_skalter_beam_front',j);beam=Image.new('RGBA',(tile.width*4,tile.height))
 for i in range(4):beam.alpha_composite(tile,(tile.width*i,0))
 beam_width=int(A['fx_ult_skalter_beam_front'].get('review_draw_width',80))
 beam=beam.resize((304,beam_width),Image.Resampling.NEAREST)
 # Preview-only mouth adapter widens along the first24 pixels. Body pixels stay untouched.
 mat=np.array(beam);mid=beam.height/2
 for x in range(24):
  half=4+(beam.height/2-4)*x/23
  mat[np.abs(np.arange(beam.height)-mid)>half,x]=0
 beam=Image.fromarray(mat);direction=(.42,-math.sqrt(1-.42**2));angle=math.degrees(math.atan2(direction[1],direction[0]));rot=beam.rotate(-angle,Image.Resampling.NEAREST,expand=True);center=(origin[0]+direction[0]*beam.width/2,origin[1]+direction[1]*beam.width/2);pastecenter(scene,rot,center);board.paste(scene,(j*560,30),scene);labels.text((j*560+16,10),f'Native mouth origin + beam loop keyframe {(0,3)[j]}',fill='white');scene_meta.append({'origin':origin,'direction':direction,'body_offset':offset,'beam_display_length':304,'beam_display_width':beam_width,'preview_only_taper_length':24})
board.save(P/'beam_scene_r2.png');(R/'beam_scene_r2.json').write_text(json.dumps({'scenes':scene_meta,'runtime_verified':False,'note':'native mouth detected from original cyan texture; review attachment prototype only'},indent=2))
# Meltdown proof: actual native body guide plus independent FX.
rows=[]
for name in ['before_melt.png','fx_ult_kaltsit_melt_front.png']:
 im=Image.open(P/name).convert('RGB');im.thumbnail((920,440),Image.Resampling.NEAREST);rows.append(im)
out=Image.new('RGB',(960,sum(im.height for im in rows)+60),'#283542');d=ImageDraw.Draw(out);y=0
for j,im in enumerate(rows):d.text((12,y+4),['Previous: independent rock core','Revision: original Skill_2 body + independent rupture FX'][j],fill='white');out.paste(im,(0,y+24));y+=im.height+30
out.save(P/'melt_scene_r2.png')
# Repeat all6 materials with seam markers; rings additionally show the agreed30deg arc placement.
names=['fx_ult_texas_scar_back','fx_ult_skalter_beam_front','fx_ult_skalter_domain_back','fx_ult_kaltsit_crack_back','fx_ult_ulpianus_chain_front','fx_ult_ulpianus_crack_back'];out=Image.new('RGB',(1000,660),'#283542');d=ImageDraw.Draw(out)
for row,name in enumerate(names):
 im=key(name);repeat=Image.new('RGBA',(im.width*4,im.height))
 for i in range(4):repeat.alpha_composite(im,(im.width*i,0))
 display=min(1,780/repeat.width);repeat=repeat.resize((round(repeat.width*display),round(repeat.height*display)),Image.Resampling.NEAREST);out.paste(repeat,(210,row*105+28),repeat);d.text((6,row*105+8),name.replace('fx_ult_',''),fill='white')
 for i in range(1,4):x=210+round(im.width*i*display);d.line((x,row*105+20,x,row*105+26),fill=(162,187,198));d.line((x,row*105+30+repeat.height,x,row*105+35+repeat.height),fill=(162,187,198))
out.save(P/'segment_repeat_r2.png');rings=Image.new('RGB',(1200,420),'#283542');d=ImageDraw.Draw(rings)
for j,name in enumerate(['fx_ult_skalter_domain_back','fx_ult_kaltsit_crack_back','fx_ult_ulpianus_crack_back']):
 tile=key(name);ref=A[name]['arc_reference_radius']*2;radius=150;sc=radius/ref;tile=tile.resize((round(tile.width*sc)+2,round(tile.height*sc)),Image.Resampling.NEAREST);canvas=Image.new('RGBA',(400,400))
 for i in range(12):
  theta=2*math.pi*i/12;center=(200+radius*math.cos(theta),200+radius*math.sin(theta));angle=math.degrees(theta)+90;rot=tile.rotate(-angle,Image.Resampling.NEAREST,expand=True);pastecenter(canvas,rot,center)
 rings.paste(canvas,(j*400,20),canvas);d.text((j*400+8,5),name.replace('fx_ult_','')+' / 12 segments',fill='white')
rings.save(P/'ring_repeat_r2.png')
p=R/'review.html';s=p.read_text(encoding='utf-8');s=s if 'src="previews/ring_repeat_r2.png"' in s else s.replace('<img src="previews/segment_repeat_r2.png">','<img src="previews/segment_repeat_r2.png"><img src="previews/ring_repeat_r2.png">');p.write_text(s,encoding='utf-8');print('Built native-mouth beam, native-body melt, six repeat materials and three rings')
