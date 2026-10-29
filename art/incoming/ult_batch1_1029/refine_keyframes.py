from pathlib import Path
from PIL import Image,ImageDraw,ImageFilter
import json,hashlib,math,numpy as np
R=Path(__file__).resolve().parent;K=R/'keyframes';P=R/'previews';N=R.parent/'de_summon_style_alignment_1020';GAME=Path('E:/ArknightsSurvivors/art/incoming')
m=json.loads((R/'manifest.json').read_text(encoding='utf-8'));assets={a['name']:a for a in m['assets']};changed=[];checks=[]
def H(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def binary(im):
 a=np.array(im.convert('RGBA'));a[:,:,3]=np.where(a[:,:,3]>=128,255,0);a[a[:,:,3]==0]=0;return Image.fromarray(a)
def cells(file,axis):
 im=Image.open(R/file).convert('RGBA');w,h=im.size
 return [im.crop((0,0,w,h//2)),im.crop((0,h//2,w,h))] if axis=='v' else [im.crop((0,0,w//2,h)),im.crop((w//2,0,w,h))]
def fit_pair(file,axis,logical,colors=None,first_scale=1):
 cs=cells(file,axis);boxes=[binary(c).getbbox() for c in cs];w,h=logical;scale=min((w-8)/max(b[2]-b[0] for b in boxes),(h-8)/max(b[3]-b[1] for b in boxes));out=[]
 for j,(c,b) in enumerate(zip(cs,boxes)):
  c=c.crop(b);f=scale*(first_scale if j==0 else 1);c=binary(c.resize((max(1,round(c.width*f)),max(1,round(c.height*f))),Image.Resampling.NEAREST))
  if colors:
   palette=Image.new('P',(1,1));palette.putpalette(sum(colors,[])+colors[-1]*(256-len(colors)));al=c.getchannel('A');c=c.convert('RGB').quantize(palette=palette,dither=Image.Dither.NONE).convert('RGBA');c.putalpha(al)
  im=Image.new('RGBA',(w,h));im.alpha_composite(c,((w-c.width)//2,(h-c.height)//2));out.append(im.resize((w*2,h*2),Image.Resampling.NEAREST))
 return out

def save(name,pair,note,**meta):
 a=assets[name];a.update(meta);a['review_note']=note;a['art_revision']=3
 for info,im in zip(a['keyframes'],pair):
  im=binary(im);assert im.size==tuple(a['physical_size']);im.save(R/info['file']);info['sha256']=H(R/info['file'])
 changed.append(name)

def readpair(name):return [Image.open(R/x['file']).convert('RGBA') for x in assets[name]['keyframes']]
# Own color ranges: shared gold mapping previously erased orange fire.
fire=[[40,26,29],[91,34,25],[151,43,23],[208,64,22],[243,105,28],[255,157,54],[255,205,115],[255,242,214]]
save('fx_ult_exusiai_burst_front',fit_pair('revision_burst.png','h',(64,64),fire),'白热小芯、橙红碎火花；金色仅作少量高光。',source_candidate='revision_burst.png',palette_reference='revision2 orange/white; current game gun-impact contrast')
watercols=[[12,29,43],[22,47,62],[32,75,87],[47,112,122],[69,155,166],[109,197,199],[163,224,216],[69,20,39],[113,32,53]]
wp=fit_pair('revision_water.png','v',(160,48),watercols)
save('fx_ult_skalter_seaborn_back',wp,'蓝黑水体与青色破碎边，中心留空；少量深红共鸣边。',source_candidate='revision_water.png')
# Reuse current game's Ishar laser material and its stable core geometry.
beam_source=GAME/'fx_kp_ishar_mid.png';src=Image.open(beam_source).convert('RGBA');beam=[]
for source_frame in (0,2):
 cell=src.crop((source_frame*16,16,(source_frame+1)*16,32)).resize((16,22),Image.Resampling.NEAREST);ar=np.array(cell);out=np.zeros_like(ar)
 for y in range(22):
  for x in range(16):
   rr,gg,bb,al=map(int,ar[y,x]);L=max(rr,gg,bb)/255
   if al<96:continue
   dist=abs(y-10.5)
   if dist<1.6 and L>.65:col=[198,239,222]
   elif dist<3.2 and L>.50:col=[74,177,157]
   elif L>.83:col=[181,49,66]
   elif L>.58:col=[132,29,48]
   elif L>.3:col=[87,20,39]
   else:col=[48,14,29]
   out[y,x,:3]=col;out[y,x,3]=255
 tile=Image.fromarray(out);im=Image.new('RGBA',(96,40))
 for i in range(6):im.alpha_composite(tile,(i*16,9))
 beam.append(im.resize((192,80),Image.Resampling.NEAREST))
for j,im in enumerate(beam):im.save(P/f'beam_existing_material_r3_f{(0,3)[j]:02}@2x.png')
# Main candidate: steady core with a small amount of rough material volume, no braided motif.
beam=[]
for c in cells('revision3_beam.png','v'):
 b=binary(c).getbbox();hh=b[3]-b[1];ww=min(c.width,round(hh*96/40));cx=c.width//2;c=c.crop((cx-ww//2,b[1],cx+(ww+1)//2,b[3]));c=binary(c.resize((96,40),Image.Resampling.NEAREST));al=c.getchannel('A');c=c.convert('RGB').quantize(colors=12,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE).convert('RGBA');c.putalpha(al);beam.append(c.resize((192,80),Image.Resampling.NEAREST))
save('fx_ult_skalter_beam_front',beam,'稳定直芯、深红粗糙外层；去掉编织波纹，现有Boss光束结构另列对照。',source_candidate='revision3_beam.png',palette_reference='dedicated source crimson/teal;12 flat shades',source_frames=[0,3],beam_design_revision=3,review_draw_width=80,review_previous_draw_width=40,review_width_scale=2.0,existing_game_alternative_source=str(beam_source),existing_game_alternative_hash=H(beam_source))
# Original Mon3tr body is a guide, never baked into the FX delivery.
mel=fit_pair('revision_melt.png','h',(192,192),None,.34);native_guides=[];poses=[]
for j,frame in enumerate((5,9)):
 folder=N/'mon3tr/Skill_2';m0=json.loads((folder/'manifest.json').read_text(encoding='utf-8'));rows=m0['parts'][frame];body=Image.new('RGBA',(256,256))
 for p in rows:
  if p.get('body_included',True):body.alpha_composite(Image.open(folder/p['path']).convert('RGBA'))
 strip=Image.open(folder/'full_motion_strip.png').convert('RGBA');assert body.tobytes()==strip.crop((frame*256,0,(frame+1)*256,256)).tobytes()
 p=next(p for p in rows if p['slot']=='C_Body_III');factor=m0['source_scale']*m0['pixel_scale'];core=[128+p['bone_world']['x']*factor,184-p['bone_world']['y']*factor];shift=[round(192-core[0]),round(192-core[1])];guide=Image.new('RGBA',(384,384));guide.alpha_composite(body,shift);assert np.count_nonzero(np.array(guide)[:,:,3])==np.count_nonzero(np.array(body)[:,:,3]);guide.save(P/f'mon3tr_melt_native_f{(0,4)[j]:02}.png');native_guides.append(guide);poses.append({'action':'Skill_2','source_frame':frame,'source_time':m0['sample_times'][frame],'core_bone':'C_Body_III','core_in_source_canvas':core,'body_offset':shift,'body_pixels_unchanged':True,'source_manifest':str(folder/'manifest.json')})
save('fx_ult_kaltsit_melt_front',mel,'原骨架Skill_2蓄势/释放姿态对位，爆炸层独立于本体；已移除石球核心。',source_candidate='revision_melt.png',body_policy='native Skill_2 guide; FX-only texture',native_pose_guides=poses)
# Rigid native anchor: pixelize original attachments on one shared rotated grid.
folder=R/'references/native_anchor';src=json.loads((folder/'source.json').read_text(encoding='utf-8'));rot=-12.0;parts=[]
for slot in src['slots']:
 im=Image.open(folder/'parts'/(slot['slot']+'.png')).convert('RGBA').rotate(rot,Image.Resampling.BICUBIC,center=(256,256));parts.append(im)
full=Image.new('RGBA',(512,512))
for im in parts:full.alpha_composite(im)
alpha=np.array(full.getchannel('A'));ys,xs=np.where(alpha>=96);radius=max(np.sqrt((xs-256)**2+(ys-256)**2));scale=42/radius
outparts=folder/'pixel_parts';outparts.mkdir(exist_ok=True);anchor=Image.new('RGBA',(96,96));transform=(1/scale,0,256-48/scale,0,1/scale,256-48/scale)
for slot,im in zip(src['slots'],parts):
 im=im.transform((96,96),Image.Transform.AFFINE,transform,Image.Resampling.BICUBIC);ar=np.array(im);ar[:,:,3]=np.where(ar[:,:,3]>=96,255,0);ar[ar[:,:,3]==0]=0;im=Image.fromarray(ar);im.save(outparts/(slot['slot']+'.png'));anchor.alpha_composite(im)
anchor2=anchor.resize((192,192),Image.Resampling.NEAREST);anchor90=anchor2.transpose(Image.Transpose.ROTATE_270)
save('fx_ult_ulpianus_anchor_front',[anchor2,anchor90],'同一原作Spine武器附件，去链条；代表帧严格平面旋转90度。',source_candidate='references/native_anchor/source.json',body_policy='original Spine weapon attachments, shared pixel grid',rotation_degrees=[0,90],rotation_pivot=[96,96])
assert readpair('fx_ult_ulpianus_anchor_front')[1].tobytes()==readpair('fx_ult_ulpianus_anchor_front')[0].transpose(Image.Transpose.ROTATE_270).tobytes()
checks.append({'name':'anchor_rigid_rotation','passed':True})
# User revision: use the exact sword currently selected by Texas's rain runtime branch.
sword_source=GAME/'fx_texas_sword_drop@2x.png';source=Image.open(sword_source).convert('RGBA');fw=source.width//5;swords=[]
for frame in (0,4):
 cell=source.crop((frame*fw,0,(frame+1)*fw,source.height));out=Image.new('RGBA',(64,224));out.alpha_composite(cell,(20,148));swords.append(out)
 assert np.count_nonzero(np.asarray(out)[:,:,3])==np.count_nonzero(np.asarray(cell)[:,:,3])
 check=out.crop((20,148,20+fw,148+source.height));visible=np.asarray(cell)[:,:,3]>0
 assert np.array_equal(np.asarray(check)[visible],np.asarray(cell)[visible])
save('fx_ult_texas_sword_front',swords,'原样复用当前余像剑雨优先调用的fx_texas_sword_drop；下落帧0与插地帧4，保留蓝灰剑身和金色内刃。',source_candidate=str(sword_source),canonical_visual_verified=False,current_game_sword_exact=True,current_game_source_hash=H(sword_source),source_frames=[0,4],source_ground_anchor=[12,76],delivery_ground_anchor=[32,224],source_to_delivery_offset=[20,148],runtime_selection_reference='game/data/characters/texas.json:1110-1112')
for field in ['original_weapon_attachment','original_texture_hash','s2_color_reference']:
 assets['fx_ult_texas_sword_front'].pop(field,None)
# Target lock is native UI geometry: four thin corners, an empty center.
locks=[]
for inset in (6,12):
 im=Image.new('RGBA',(48,48));d=ImageDraw.Draw(im);far=47-inset
 for x,sx in [(inset,1),(far,-1)]:
  for y,sy in [(inset,1),(far,-1)]:d.line((x+sx*5,y,x,y,x,y+sy*5),fill=(231,169,58,255),width=1)
 locks.append(im.resize((96,96),Image.Resampling.NEAREST))
save('fx_ult_exusiai_lock_orbit',locks,'四角收拢，1逻辑像素细线，中心留空；完整碎裂帧待制作。',source_candidate='native corner geometry matching current impact scale')
# Six repeatable segments: remove transparent side padding, normalize arc geometry, then close seam.
seams=[]
for name in ['fx_ult_texas_scar_back','fx_ult_skalter_beam_front','fx_ult_skalter_domain_back','fx_ult_kaltsit_crack_back','fx_ult_ulpianus_chain_front','fx_ult_ulpianus_crack_back']:
 pair=[];arc=any(s in name for s in ('crack','domain'));w,h=assets[name]['logical_size'];radius=w/(2*math.sin(math.pi/12)) if arc else None
 for im in readpair(name):
  small=im.resize((w,h),Image.Resampling.NEAREST);b=small.getbbox();small=small.crop((b[0],0,b[2],h)).resize((w,h),Image.Resampling.NEAREST);a=np.array(small)
  if arc:
   out=np.zeros_like(a)
   for x in range(w):
    ys=np.where(a[:,x,3]>0)[0]
    if not len(ys):continue
    center=float(np.median(ys));target=h/2+radius-math.sqrt(radius*radius-(x-(w-1)/2)**2);shift=round(target-center)
    for y in ys:
     dest=y+shift
     if 1<=dest<h-1:out[dest,x]=a[y,x]
   a=out
  edge=np.maximum(a[:,0,3],a[:,-1,3])>0
  profile=np.zeros_like(a[:,0]);profile[edge,:3]=np.round((a[edge,0,:3].astype(float)+a[edge,-1,:3].astype(float))/2);profile[edge,3]=255
  if not edge.any():raise AssertionError(name+' empty seam')
  # Repeat boundary uses identical color/coverage; transition in existing edge texels.
  for x in range(min(4,w//4)):
   wt=(4-x)/4
   for col in (x,w-1-x):
    mix=np.round(a[:,col].astype(float)*(1-wt)+profile.astype(float)*wt).astype('uint8');mix[:,3]=np.where(mix[:,3]>=96,255,0);mix[mix[:,3]==0]=0;a[:,col]=mix
  a[:,0]=profile;a[:,-1]=profile
  small=binary(Image.fromarray(a));pair.append(small.resize((w*2,h*2),Image.Resampling.NEAREST))
 save(name,pair,'拼接修订：端点色值与覆盖一致；直线重复或参考半径环形摆放见预览。',tile_axis='x',seam_endpoint_equal=True,arc_reference_radius=radius,arc_span_degrees=30 if arc else None,arc_overlap_2x_pixels=2 if arc else None)
 for j,im in enumerate(pair):
  a=np.array(im);assert np.array_equal(a[:,0],a[:,-1]);assert (a[:,0,3]>0).any();seams.append({'name':name,'frame':assets[name]['keyframes'][j]['frame'],'matching_endpoint_pixels':True,'edge_occupied_rows':int((a[:,0,3]>0).sum())})
# Reconstruction structure paths follow original attachment centers and original body outline.
a=assets['fx_ult_kaltsit_rebuild_orbit'];pair=[]
for j,record in enumerate(a['native_sources']):
 folder=Path(record['source_manifest']).parent;meta=json.loads((folder/'manifest.json').read_text(encoding='utf-8'));frame=record['source_frame'];off=record['offset_only'];im=Image.new('RGBA',(256,256));d=ImageDraw.Draw(im);nodes={}
 for part in meta['parts'][frame]:
  if not part.get('body_included',True):continue
  b=Image.open(folder/part['path']).getbbox()
  if b:nodes[part['slot']]=((b[0]+b[2])//2+off[0],(b[1]+b[3])//2+off[1])
 core=nodes.get('C_Body_III',(128,210))
 if j==0:
  for dx,dy in [(-48,-36),(46,-44),(-38,2),(40,8),(-6,-65)]:
   x,y=core[0]+dx,core[1]+dy;d.line((x,y,x+(core[0]-x)//2,y+(core[1]-y)//2),fill=(96,151,50,255),width=1);d.point((x,y),fill=(181,220,99,255))
 else:
  for seq in [('C_Body_I','C_Body_II','C_Body_III','C_Body_IV'),('C_L_Arm_A','C_L_Arm_B'),('C_R_Arm_A','C_R_Arm_B')]:
   pts=[nodes[k] for k in seq if k in nodes]
   if len(pts)>1:d.line(pts,fill=(126,186,62,255),width=1)
  body=Image.open(P/'mon3tr_native_body_f09@2x.png').convert('RGBA');al=body.getchannel('A');edge=np.array(al)>np.array(al.filter(ImageFilter.MinFilter(3)));yy,xx=np.indices(edge.shape);edge &= ((xx+yy)//14)%3==0;ar=np.array(im);ar[edge]=[99,159,48,255];im=Image.fromarray(ar)
 pair.append(im)
save('fx_ult_kaltsit_rebuild_orbit',pair,'结构线按原附件中心连成路径，沿原生轮廓显现；完整收拢运动待动画阶段。',source_candidate='native attachment graph + Start body guide')
# Rebuild all preview cards from delivered keyframes, with native body only in guides.
cards=[];overview=Image.new('RGB',(1200,16*160),'#283542');draw=ImageDraw.Draw(overview)
for idx,a in enumerate(m['assets']):
 pair=readpair(a['name']);shows=[]
 for j,im in enumerate(pair):
  if a['name']=='fx_ult_kaltsit_melt_front':im=Image.alpha_composite(native_guides[j],im)
  elif a['name']=='fx_ult_kaltsit_rebuild_orbit':im=Image.alpha_composite(Image.open(P/f'mon3tr_native_body_f{(0,9)[j]:02}@2x.png').convert('RGBA'),im)
  shows.append(im)
 w,h=pair[0].size;plate=Image.new('RGB',(max(400,w*2+24),max(150,h+40)),'#283542');d=ImageDraw.Draw(plate)
 for j,im in enumerate(shows):x=12+j*(plate.width//2);plate.paste(im,(x,30),im);d.text((x,8),'f0 / start' if j==0 else f'f{a["representative_frame"]} / representative',fill='white')
 plate.save(P/(a['name']+'.png'));thumb=plate.copy();thumb.thumbnail((850,145),Image.Resampling.NEAREST);overview.paste(thumb,(340,idx*160+5));draw.text((10,idx*160+12),a['name'].replace('fx_ult_',''),fill='white')
 cards.append(f'<section><h2>{a["name"]}</h2><p>{a["physical_size"]} @2x · f0 + f{a["representative_frame"]}</p><p>{a["review_note"]}</p><img src="previews/{a["name"]}.png"></section>')
 # Meaningful delivery checks include RGBA values, framing and native source/rotation invariants above.
 for info in a['keyframes']:
  im=Image.open(R/info['file']);assert im.size==tuple(a['physical_size']);assert set(np.unique(np.array(im)[:,:,3]))<={0,255};assert H(R/info['file'])==info['sha256']
overview.save(R/'keyframe_overview.png');m.update(art_revision=3,refinement_complete_for_keyframe_review=True,changed_assets=sorted(set(changed)),seam_validation='matching endpoints on 6 keyframe pairs; placement review required');(R/'manifest.json').write_text(json.dumps(m,ensure_ascii=False,indent=2),encoding='utf-8');(R/'revision2_qa.json').write_text(json.dumps({'seams':seams,'checks':checks,'all_keyframes_dimensions_alpha_hashes':True,'native_body_guides':'original per-attachment recomposition exact','canonical_texas_fx_verification':'original F_Weapon geometry and documented S2 red-orange hue; separate original FX sequence not available','runtime_verified':False},ensure_ascii=False,indent=2),encoding='utf-8')
page='''<!doctype html><meta charset="utf-8"><title>终结技 · 第三轮关键帧</title><style>body{background:#18232e;color:#e4ebee;font:16px system-ui;margin:28px}section{padding:16px;margin:20px 0;background:#283542}img{max-width:100%;image-rendering:pixelated}h2{font-size:17px}a{color:#9dd8f0}</style><h1>终结技第一批 · 第三轮关键帧</h1><p>原作骨架本体、稳定细芯光束、核心熔毁、原锚严格旋转。32张关键帧；完整动画与实机验收待进行。</p><p>拼接端点已做色值和覆盖核验；排列预览见下方。剑雨原样复用当前游戏的fx_texas_sword_drop；光束改为稳定直芯和粗糙深红外层，现有Boss光束另列对照。</p><h2>本轮对位与拼接预览</h2><img src="previews/beam_scene_r2.png"><img src="previews/melt_scene_r2.png"><img src="previews/segment_repeat_r2.png"><h2>当前游戏风格参照</h2><img src="references/current_game_fx_board.png">'''+''.join(cards)
(R/'review.html').write_text(page,encoding='utf-8');print('Refined',len(set(changed)),'assets; verified',len(seams),'seam keyframes; native anchor rigid90 exact')
