from pathlib import Path
from PIL import Image,ImageDraw
import json
R=Path(__file__).resolve().parent;m=json.loads((R/'manifest.json').read_text(encoding='utf-8'))
a=next(x for x in m['assets'] if x['name']=='fx_ult_skalter_seaborn_front');b=next(x for x in m['assets'] if x['name']=='fx_ult_skalter_seaborn_back')
body=Image.open(R/a['keyframes'][1]['file']).convert('RGBA');water=Image.open(R/b['keyframes'][1]['file']).convert('RGBA');root=a['native_sources'][1]['native_root_on_canvas'];box=body.getbbox();wb=water.getbbox();factor=min(1,(box[2]-box[0])*1.7/(wb[2]-wb[0]));water=water.resize((round(water.width*factor),round(water.height*factor)),Image.Resampling.NEAREST)
stage=Image.new('RGBA',(384,384));ground=(192,310);offset=(ground[0]-root[0],ground[1]-root[1]);stage.alpha_composite(water,(ground[0]-water.width//2,ground[1]-water.height//2));stage.alpha_composite(body,offset)
box=stage.getbbox();crop=(max(0,box[0]-20),max(0,box[1]-20),min(384,box[2]+20),min(384,box[3]+20));detail=stage.crop(crop);detail=detail.resize((detail.width*3,detail.height*3),Image.Resampling.NEAREST)
board=Image.new('RGB',(detail.width,detail.height+30),'#283542');board.paste(detail,(0,30),detail);ImageDraw.Draw(board).text((12,8),'Original Spine Skill + water layer / enlarged review',fill='white');board.save(R/'previews/seaborn_composite_review.png')
(R/'seaborn_review_alignment.json').write_text(json.dumps({'stage_ground':ground,'native_root_on_keyframe':root,'body_translation':offset,'water_review_scale':factor,'water_frame':3,'body_keyframe':6,'source_pose':a['native_sources'][1],'review_crop':crop,'runtime_verified':False},ensure_ascii=False,indent=2),encoding='utf-8')
p=R/'review.html';s=p.read_text(encoding='utf-8');tag='<div id="seaborn-supplement"><h2>海嗣补充：原骨架张口姿态与水纹对位</h2><p>原作Skill出手时刻，关键姿态预览；升起、循环、沉下完整动画尚未制作。</p><img src="previews/seaborn_composite_review.png" style="max-height:680px"></div>'
if 'id="seaborn-supplement"' not in s and '海嗣补充：' not in s:s=s.replace('<h2>当前游戏风格参照</h2>',tag+'<h2>当前游戏风格参照</h2>',1)
p.write_text(s,encoding='utf-8')
