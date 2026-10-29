from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
from html import escape
import json,hashlib,shutil
R=Path(__file__).resolve().parent
old=json.loads((R/'animation_keyframe_manifest.json').read_text(encoding='utf8'))
data={}
for group in ['native','impact','segments']:
    entries=json.loads((R/'animation_work'/group/'entries.json').read_text(encoding='utf8'))
    if isinstance(entries,dict):entries=entries['assets']
    for a in entries:
        assert a['name'] not in data
        data[a['name']]=a
assert len(data)==16
rows=[]
for original in old['assets']:
    a=dict(original);a.update(data[a['name']]);name=a['name']
    path=Path(a['file']);path=path if path.is_absolute() else R/path
    out=R/(name+'@2x.png');shutil.copyfile(path,out)
    a['file']=out.name;a['sha256']=hashlib.sha256(out.read_bytes()).hexdigest()
    a['approved_keyframe_reference']=a.pop('keyframes',[])
    a.pop('review_note',None)
    a.setdefault('layer',name.rsplit('_',1)[-1])
    a['status']='full_animation_delivery';a['runtime_verified']=False
    a['rgba_mib']=a['physical_size'][0]*a['physical_size'][1]*4*a['frame_count']/1048576
    rows.append(a)
manifest={'stage':'full_animation_delivery','order_commit':'975cfaf31','keyframe_commit':'9f956fcf0',
          'rgba_mib':sum(a['rgba_mib'] for a in rows),'runtime_verified':False,
          'deviations':[{'asset':'fx_ult_skalter_beam_front','reason':'用户关键帧阶段连续要求加粗，保留review_draw_width=80；纹理192x80与v2一致，不能将显示宽度误算成额外贴图高度。'},
                        {'asset':'fx_ult_texas_sword_front','reason':'完整动画保持原剑雨源0–4顺序，末帧补落地碎屑；代表帧从旧快照f3调整到完整动画f4。'}],
          'assets':rows}
(R/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
P=R/'animation_previews';P.mkdir(exist_ok=True)
font=ImageFont.truetype('C:/Windows/Fonts/consola.ttf',12)
board=Image.new('RGBA',(1280,1280),'#182831');d=ImageDraw.Draw(board)
for i,a in enumerate(rows):
    w,h=a['physical_size'];f=a['representative_frame'];im=Image.open(R/a['file']).convert('RGBA').crop((f*w,0,(f+1)*w,h))
    im.save(P/(a['name']+'.png'))
    x=(i%4)*320;y=(i//4)*320
    d.text((x+10,y+12),a['name'].replace('fx_ult_',''),font=font,fill='white')
    if im.getbbox():
        im=im.crop(im.getbbox());scale=min(290/im.width,260/im.height,2);im=im.resize((max(1,round(im.width*scale)),max(1,round(im.height*scale))),Image.Resampling.NEAREST)
        board.alpha_composite(im,(x+(320-im.width)//2,y+40+(260-im.height)//2))
board.save(R/'animation_overview.png')
html=['<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>终结技第一批 · 完整动画</title>',
      '<style>body{max-width:1200px;margin:24px auto;padding:16px;background:#17232d;color:#e4edf0;font:16px/1.7 system-ui}section{background:#263542;padding:20px;margin:24px 0}h2{font-size:18px;overflow-wrap:anywhere}video,img{max-width:100%;image-rendering:pixelated}a{color:#a0d9ef}.meta{color:#b2c6d0;font-size:14px}</style>',
      '<h1>终结技第一批 · 完整动画</h1><p>5 人、16 项完整 @2x 帧条。每段视频按素材原速、30 fps 输出，依次展示黑底与本作暗色地面。此页是素材播放预览；实机接入由 Claude 在终结技原型中验收。</p>',
      '<img src="animation_overview.png" alt="完整动画总览">']
for a in rows:
    name=a['name'];fps=a.get('fps')
    html.extend([f'<section><h2>{name}</h2>',f'<video controls loop muted playsinline preload="metadata" poster="animation_previews/{name}.png" src="animation_previews/{name}.mp4"></video>',
                 f'<p class="meta">{a["frame_count"]} 帧 · {fps if fps else "程序旋转角度帧"} fps · 单帧 @2x {a["physical_size"]} · {a["rgba_mib"]:.4f} MiB</p>',
                 f'<p>{escape(a.get("motion_note",a.get("notes","")))}</p>',f'<a href="{a["file"]}">帧条</a> · <a href="animation_previews/{name}.mp4">MP4</a></section>'])
html.append('<p><a href="manifest.json">Manifest</a> · <a href="handoff_animation.md">交接说明</a> · <a href="animation_qa.json">技术核验</a></p></html>')
(R/'review.html').write_text('\n'.join(html),encoding='utf8')
print('Assembled',len(rows),'strips;',manifest['rgba_mib'],'MiB')
