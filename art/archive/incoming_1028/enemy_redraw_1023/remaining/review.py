"""Read-only candidate QA and review layout. Never edits sprite assets."""
from pathlib import Path
import hashlib, json, html
from PIL import Image, ImageDraw, ImageFont
import numpy as np

R=Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def save(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf8',newline='\n')
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',n)
job=json.loads((R/'job.json').read_text('utf8')); failures=[]; assets=[]; reports=[]; cards=[]
for j in job['jobs']:
 k=j['id'];prefix='e_'+k+'_idle_f0';base=Image.open(R/'f0'/f'{prefix}.png').convert('RGBA');emit=Image.open(R/'f0'/f'{prefix}_emit.png').convert('RGBA')
 a=np.array(base);em=np.array(emit);mask=a[:,:,3]>0;box=base.getbbox();cw,ch=j['canvas_1x'];h=j['visible_height_1x']
 checks={'canvas':base.size==emit.size==(cw,ch),'height':box[3]-box[1]==h,'origin':box[3]==ch-4,'border':box[0]>0 and box[1]>0 and box[2]<cw,'palette':len(np.unique(a[:,:,:3][mask],axis=0))<=j['color_cap'],'emission_inside_body':not np.any((em[:,:,3]>0)&~mask)}
 actual_em={tuple(c) for c in em[:,:,:3][em[:,:,3]>0]};palette={tuple(bytes.fromhex(c[1:])) for c in j['emission_palette']}
 checks['emission_colour']=actual_em<=palette
 checks['emission_present']=bool(actual_em) if k!='mimic_disguised' else not bool(actual_em)
 ref=R.parents[4]/j['reference']
 checks['reference_hash']=ref.exists() and sha(ref)==j['reference_sha256']
 if 'generated_sha256' in j:
  checks['generated_source_hash']=sha(R/'generated'/f'{k}.png')==j['generated_sha256']
  checks['prompt_hash']=sha(R/'prompts'/f'{k}.txt')==j['prompt_sha256']
 checks['no_alpha_islands']=all(mask[max(0,y-1):y+2,max(0,x-1):x+2].sum()>1 for y,x in zip(*np.where(mask)))
 for suffix,im in [('',base),('_emit',emit)]:
  b=np.array(im);hi=np.array(Image.open(R/'f0'/f'{prefix}{suffix}@2x.png').convert('RGBA'))
  checks[suffix+'binary_alpha']=set(np.unique(b[:,:,3]))<={0,255}
  checks[suffix+'exact_x2']=np.array_equal(hi,b.repeat(2,0).repeat(2,1))
  for density in (1,2):
   f='f0/'+prefix+suffix+('@2x' if density==2 else '')+'.png'
   assets.append({'file':f,'id':k,'frame_size':[cw*density,ch*density],'frames':1,'static':True,'fps':None,'event_frame':None,'origin':[cw//2*density,(ch-4)*density],'anchor_convention':'bottom-exclusive foot/projected center','density':density,'layer':'independent RGB emission' if suffix else 'body','sha256':sha(R/f)})
 if k in ['bone','stone','carmen']:
  checks['body_unchanged']=np.array_equal(a,np.array(Image.open(R.parent/'f0'/f'{prefix}.png').convert('RGBA')))
 if k=='carmen':
  old=np.array(Image.open(R.parent/'f0'/f'{prefix}_emit.png').convert('RGBA'))
  checks['rear_hat_position_unchanged']=np.array_equal(old[:,:,3],em[:,:,3])
 if k=='mimic_disguised':
  chest=Image.open(R/'references/mimic_disguised.png').convert('RGBA');checks['exact_chest']=np.array_equal(np.array(base.crop(box)),np.array(chest.crop(chest.getbbox())))
 report={'id':k,'name':j['name'],'visible_height_1x':h,'screen_height':h*2,'canvas_1x':[cw,ch],'body_colors':len(np.unique(a[:,:,:3][mask],axis=0)),'emit_pixels':int((em[:,:,3]>0).sum()),'checks':checks}
 reports.append(report);failures.extend(k+':'+name for name,ok in checks.items() if not ok)
 comp=Image.alpha_composite(base,emit);panel=Image.new('RGB',(960,340),'#14222e');d=ImageDraw.Draw(panel)
 d.text((18,12),j['name']+' / '+k,fill='#d5e0e6',font=font(20))
 d.text((18,43),f'屏幕高 {h*2}px · 画布 {cw}×{ch} · {report["body_colors"]}色 · 独立发光层',fill='#8faab9',font=font(14))
 for n,(title,pic) in enumerate([('本体',base),('发光层',emit),('合成预览',comp)]):
  scale=min(4,250//cw,210//ch);scale=max(1,scale);pic=pic.resize((cw*scale,ch*scale),Image.Resampling.NEAREST)
  panel.paste(pic,(n*320+(320-pic.width)//2,85+(210-pic.height)//2),pic)
  d.text((n*320+135,310),title,fill='#a6b8c3',font=font(16))
 (R/'previews').mkdir(exist_ok=True);panel.save(R/'previews'/f'{k}.png')
 cards.append(f'<section><h2>{html.escape(j["name"])} <small>{k}</small></h2><p>实际显示大小：{h*2}px 高</p><div class="actual"><img src="f0/{prefix}@2x.png"><img class="emit" src="f0/{prefix}_emit@2x.png"></div><img class="detail" src="previews/{k}.png"></section>')
save(R/'manifest.json',{'brief_commit':'9d0bc4ec','scope':'32 static f0 states; no animation/integration claim','emission_contract':'same canvas/origin, independent RGB overlay; never sample body RGB for glow','assets':assets,'job_sha256':sha(R/'job.json'),'export_sha256':sha(R/'export.ps1'),'review_sha256':sha(Path(__file__))})
save(R/'qa.json',{'technical_status':'pass' if not failures else 'fail','failures':failures,'reports':reports,'visual_status':'candidate for user review','motion_status':'not started','engine_status':'not integrated'})
for page,start in enumerate(range(0,32,8),1):
 sheet=Image.new('RGB',(1280,1200),'#14222e');d=ImageDraw.Draw(sheet)
 for idx,j in enumerate(job['jobs'][start:start+8]):
  k=j['id'];x=(idx%2)*640;y=(idx//2)*300
  d.text((x+16,y+12),j['name']+f' / {j["visible_height_1x"]*2}px',font=font(18),fill='#d5e0e6')
  b=Image.open(R/'f0'/f'e_{k}_idle_f0@2x.png').convert('RGBA');e=Image.open(R/'f0'/f'e_{k}_idle_f0_emit@2x.png').convert('RGBA');im=Image.alpha_composite(b,e)
  sheet.paste(im,(x+320-im.width//2,y+270-im.height),im);d.line((x+12,y+271,x+628,y+271),fill='#36454f')
 sheet.save(R/f'lineup_{page}.png')
(R/'review.html').write_text('<!doctype html><html lang="zh"><meta charset="utf-8"><title>怪物重画 · 全形态静帧</title><style>body{background:#101b25;color:#d5e0e6;font:16px system-ui;margin:28px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(470px,1fr));gap:20px}section{background:#14222e;padding:18px;border:1px solid #354650}h2{font-size:20px}small{color:#8faab9}.actual{position:relative;display:inline-block;min-height:80px}.actual img{image-rendering:pixelated}.emit{position:absolute;left:0;top:0}.detail{display:block;width:100%;max-width:960px}button{padding:10px}body.hide-emission .emit{visibility:hidden}</style><h1>32 个形态 · 静帧对照</h1><p><a style="color:#82CDDC" href="color_comparison.png">原作／上一稿／修正稿配色对照</a> · 掠海漂移体现为屏幕高60px</p><p>颜色规则 9d0bc4ec：海嗣青蓝，精英更亮；红只用于危险提示。发光独立 RGB 层。</p><p>本页为静帧候选，尚未扩展动画或接入游戏。上方按屏幕实际尺寸，下方为分层放大。</p><button onclick="document.body.classList.toggle(\'hide-emission\')">切换发光层</button><main>'+''.join(cards)+'</main></html>',encoding='utf8',newline='\n')
print(json.dumps({'states':len(reports),'assets':len(assets),'status':'pass' if not failures else 'fail','failures':failures},ensure_ascii=False))
raise SystemExit(bool(failures))
