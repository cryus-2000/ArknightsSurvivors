from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import json,hashlib,numpy as np,html
R=Path(__file__).resolve().parent;K=R/'keyframes';K.mkdir(exist_ok=True);P=R/'previews';P.mkdir(exist_ok=True)
GAME=Path('E:/ArknightsSurvivors/art/incoming');NATIVE=R.parent/'de_summon_style_alignment_1020'
m=json.loads((R/'manifest.json').read_text(encoding='utf-8'))
# Layout in generated source, representative frame. Only effects use generated raster sources.
config=[('ult_slash_v2','v',4),('ult_texas_scar','v',2),('ult_texas_sword','h',3),('ult_exusiai_burst','h',2),('ult_exusiai_lock','h',4),('native_seaborn','h',6),('ult_skalter_water','v',3),('ult_skalter_beam','v',3),('ult_skalter_domain','v',3),('ult_kaltsit_melt_v2','h',4),('ult_kaltsit_crack','v',3),('native_mon3tr','h',9),('ult_ulpianus_anchor_v2','h',2),('ult_ulpianus_chain','h',1),('ult_ulpianus_crack','v',3),('ult_ulpianus_burst','h',3)]
stylefiles={
 'texas':['fx_texas_blade@2x.png','fx_texas_sword_drop@2x.png'],
 'exusiai':['fx_exusiai_muzzle_gold@2x.png','fx_exusiai_hit_gold@2x.png'],
 'skalter':['fx_skalter_wave@2x.png','fx_water_splash.png'],
 'kaltsit':['fx_mon3tr_melt_slash@2x.png','op_mon3tr_native_idle@2x.png'],
 'ulpianus':['fx_water_splash.png','op_mon3tr_native_idle@2x.png']}
palettes={}
for group,files in stylefiles.items():
 colors=[]
 for f in files:
  a=np.array(Image.open(GAME/f).convert('RGBA'));colors.extend(a[:,:,:3][a[:,:,3]>192].tolist())
 # Explicit v2 color exceptions: crimson song / white-red meltdown retain task palette.
 if group=='skalter':colors.extend([[72,12,27],[131,26,47],[175,46,65],[35,162,151]]*40)
 if group=='kaltsit':colors.extend([[247,239,224],[119,20,25],[222,51,47]]*40)
 rgb=Image.fromarray(np.array(colors,dtype='uint8').reshape(1,-1,3));palettes[group]=rgb.quantize(colors=24,method=Image.Quantize.MEDIANCUT)

def native_body(which,frame,action='Start'):
 folder=NATIVE/which/action;meta=json.loads((folder/'manifest.json').read_text());im=Image.new('RGBA',(256,256))
 for part in meta['parts'][frame]:
  if part.get('body_included',True):im.alpha_composite(Image.open(folder/part['path']).convert('RGBA'))
 strip=Image.open(folder/'full_motion_strip.png').convert('RGBA');expected=strip.crop((frame*256,0,(frame+1)*256,256));assert im.tobytes()==expected.tobytes(),(which,frame)
 for source in meta['source_files']:
  sourcepath=Path(source['path']);assert sourcepath.exists();assert hashlib.sha256(sourcepath.read_bytes()).hexdigest()==source['sha256']
 return im,meta

def native_pair(which,size):
 poses=[('Start',0),('Start',18)] if which=='mon3tr' else [('Start',0),('Skill',5)];result=[];records=[]
 sourceframes=[native_body(which,f,a) for a,f in poses]
 bottom=max([184]+[im.getbbox()[3] for im,_ in sourceframes if im.getbbox()])+2
 for action,frame in poses:
  im,meta=native_body(which,frame,action);out=Image.new('RGBA',size);offset=(size[0]//2-128,size[1]-bottom);out.alpha_composite(im,offset)
  assert sum(1 for p in out.getdata() if p[3])==sum(1 for p in im.getdata() if p[3]),'body clipped'
  result.append(out);records.append({'action':action,'source_frame':frame,'source_time':meta['sample_times'][frame],'source_manifest':str(NATIVE/which/action/'manifest.json'),'offset_only':offset,'native_root_on_canvas':[128+offset[0],184+offset[1]],'native_body_pixels_unchanged':True,'source_files':meta['source_files']})
 return result,records

cards=[];overview=Image.new('RGB',(1200,16*160),'#283542');od=ImageDraw.Draw(overview);qa=[]
for idx,(entry,(key,axis,rep)) in enumerate(zip(m['assets'],config)):
 name=entry['name'];w,h=entry['logical_size'];size=(w*2,h*2);group=name.split('_')[2];native_records=None;bodypair=None
 if key.startswith('native_'):
  which='mon3tr' if key=='native_mon3tr' else 'seaborn';bodypair,native_records=native_pair(which,size);pair=bodypair
  if which=='mon3tr':
   # Original-body-derived structure effect, independently composited. No generated anatomy.
   pair=[]
   for j,body in enumerate(bodypair):
    a=np.array(body.getchannel('A'));mask=a>0
    eroded=np.array(body.getchannel('A').filter(ImageFilter.MinFilter(3)))>0
    edge=mask & ~eroded;yy,xx=np.indices(edge.shape)
    selected=edge & (((xx+yy*3)%9)<(2 if j==0 else 4))
    fx=np.zeros((size[1],size[0],4),dtype='uint8');fx[selected]=[136,192,66,255]
    overlay=Image.fromarray(fx);d=ImageDraw.Draw(overlay)
    box=body.getbbox()
    if box:
     x0,y0,x1,y1=box
     for k in range(10 if j==0 else 5):
      x=max(2,min(size[0]-4,x0-12+(k*23)%max(24,x1-x0+24)));y=max(2,min(size[1]-4,y0-12+(k*31)%max(24,y1-y0+24)))
      if not mask[y,x]:d.line((x,y,x+2,y-2),fill=(116,162,54,255),width=1)
    pair.append(overlay)
   entry['body_policy']='FX-only overlay; native Start is separate runtime body, never image-generated'
  else:entry['body_policy']='Original Spine Start + Skill attachments recomposed, no generated anatomy'
  entry['native_sources']=native_records
 else:
  source=Image.open(R/(key+'_draft.png')).convert('RGBA');sw,sh=source.size
  cells=[source.crop((0,0,sw,sh//2)),source.crop((0,sh//2,sw,sh))] if axis=='v' else [source.crop((0,0,sw//2,sh)),source.crop((sw//2,0,sw,sh))]
  boxes=[c.getchannel('A').point(lambda x:255 if x>=160 else 0).getbbox() for c in cells];assert all(boxes)
  scale=min((w-4)/max(b[2]-b[0] for b in boxes),(h-4)/max(b[3]-b[1] for b in boxes));pair=[]
  for cell,b in zip(cells,boxes):
   crop=cell.crop(b);small=crop.resize((max(1,round(crop.width*scale)),max(1,round(crop.height*scale))),Image.Resampling.NEAREST)
   alpha=small.getchannel('A').point(lambda x:255 if x>=160 else 0)
   small=small.convert('RGB').quantize(palette=palettes[group],dither=Image.Dither.NONE).convert('RGBA');small.putalpha(alpha)
   canvas=Image.new('RGBA',(w,h));y=h-small.height-2 if '底部' in entry['origin'] else (h-small.height)//2
   canvas.alpha_composite(small,((w-small.width)//2,y));pair.append(canvas.resize(size,Image.Resampling.NEAREST))
  entry['source_candidate']=key+'_draft.png';entry['palette_reference']=stylefiles[group]
 entry['status']='keyframe_candidate';entry['representative_frame']=rep;entry['keyframes']=[]
 for j,(frame,im) in enumerate(zip((0,rep),pair)):
  fn=f'{name}_f{frame:02}@2x.png';im.save(K/fn);a=np.array(im);assert im.size==size and set(np.unique(a[:,:,3]))<={0,255}
  entry['keyframes'].append({'file':'keyframes/'+fn,'frame':frame,'sha256':hashlib.sha256((K/fn).read_bytes()).hexdigest()})
  qa.append({'file':fn,'size':size,'binary_alpha':True})
 # Native overlays are shown with body, but delivered separately.
 show=[]
 for j,im in enumerate(pair):
  if bodypair is not None and key=='native_mon3tr':im=Image.alpha_composite(bodypair[j],im);bodypair[j].save(P/f'mon3tr_native_body_f{(0,rep)[j]:02}@2x.png')
  show.append(im)
 plate=Image.new('RGB',(max(400,size[0]*2+24),max(150,size[1]+40)),'#283542');pd=ImageDraw.Draw(plate)
 for j,im in enumerate(show):
  x=12+j*(plate.width//2);plate.paste(im,(x,30),im);pd.text((x,8),'f0 / start' if j==0 else f'f{rep} / representative',fill='white')
 plate.save(P/(name+'.png'));thumb=plate.copy();thumb.thumbnail((850,145),Image.Resampling.NEAREST);overview.paste(thumb,(340,idx*160+5));od.text((10,idx*160+12),name.replace('fx_ult_',''),fill='white')
 note='原骨架附件重组；非生成本体。' if native_records else '现有游戏色板对齐；像素网格候选。'
 if any(x in name for x in ('scar','crack','chain','beam','domain')):note+=' 拼接端点待逐像素修整，不是可直接接入版。'
 if key=='native_mon3tr':note+='图中本体仅供对位；交付PNG为结构光层。'
 if key=='native_seaborn':note+='f0取原作Start；代表帧取Skill的OnAttack时刻0.3333秒，保持原骨架张口姿态。完整循环待制作。'
 entry['review_note']=note
 cards.append(f'<section><h2>{html.escape(name)}</h2><p>{size[0]} × {size[1]} @2x · f0 + f{rep} · 完整条预算 {entry["planned_rgba_mib"]:.3f} MiB</p><p>{note}</p><img src="previews/{name}.png"></section>')
overview.save(R/'keyframe_overview.png')
m.update(stage='keyframe_candidates_native_bodies',source_order='v2 + user native skeleton correction',runtime_verified=False,visual_approved=False,generated_body_drafts_withdrawn=True,actual_keyframe_rgba_mib=sum(x['physical_size'][0]*x['physical_size'][1]*4*2/1048576 for x in m['assets']))
(R/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');(R/'qa.json').write_text(json.dumps({'keyframes':qa,'native_attachment_recomposition':True,'source_hashes_verified':True,'seam_validation':'pending','runtime_verified':False},ensure_ascii=False,indent=2),encoding='utf-8')
page='''<!doctype html><meta charset="utf-8"><title>终结技第一批 · 关键帧候选</title><style>body{background:#18232e;color:#e4ebee;font:16px system-ui;margin:28px}section{padding:16px;margin:20px 0;background:#283542}img{max-width:100%;image-rendering:pixelated}h2{font-size:17px}a{color:#9dd8f0}</style><h1>终结技第一批 · v2关键帧候选</h1><p>16项，每项f0＋代表帧。只交@2x；完整条预计17.523MiB。当前为审阅，不是动画或游戏截图。</p><p>Mon3tr、海嗣改用原作Spine附件重组，生成本体草稿已撤出。特效按现有游戏色板和像素网格对齐；拼接与完整帧段尚未验收。</p><h2>当前游戏风格参照</h2><img src="references/current_game_fx_board.png"><h2>原作骨架姿态参照</h2><img src="references/native_start_compare.png">'''+''.join(cards)
(R/'review.html').write_text(page,encoding='utf-8');print('Exported',len(qa),'keyframes; native bodies verified; full-strip planned MiB',m['planned_rgba_mib'])

# Keep the native seaborn composite review in sync with regenerated keyframes.
import subprocess,sys
subprocess.run([sys.executable,"-X","utf8",str(R/"refine_keyframes.py")],check=True)
subprocess.run([sys.executable,"-X","utf8",str(R/"seaborn_review.py")],check=True)
subprocess.run([sys.executable,"-X","utf8",str(R/"revision2_scenes.py")],check=True)
subprocess.run([sys.executable,"-X","utf8",str(R/"revision3_review.py")],check=True)
