"""只做候选PNG的只读核验、manifest与审阅排版，不修改f0素材。"""
from pathlib import Path
from io import BytesIO
from collections import Counter
import hashlib
import json
import re
import sys
import subprocess
import numpy as np
from PIL import Image, ImageDraw, ImageFont

R = Path(__file__).resolve().parent
ART = R.parent
BG = '#14222e'
FONT = {n: ImageFont.truetype('C:/Windows/Fonts/msyh.ttc', n) for n in (12, 14, 16, 20, 26)}
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
read = lambda p: json.loads(p.read_text(encoding='utf8'))


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf8', newline='\n')


def label(d, x, y, message, size=14, color='#d8e5ec'):
    d.text((x, y), message, fill=color, font=FONT[size])


def draw_at(image, source, center, foot, scale=1):
    if source.getbbox() is None: return
    crop = source.crop(source.getbbox())
    if scale != 1: crop = crop.resize((crop.width*scale, crop.height*scale), Image.Resampling.NEAREST)
    image.paste(crop, (center-crop.width//2, foot-crop.height), crop)


def verify():
    job = read(R/'job.json'); assets = []; reports = []; failures = []
    heads = {e['id']:e for e in read(R/'head_glow_layout.json')}
    light_palette={(84,23,47),(135,48,75),(180,77,104)}
    for entry in job['jobs']:
        key=entry['id']; prefix='e_'+key+'_idle_f0'; cw,ch=entry['canvas_1x']; origin=[cw//2,ch-4]
        base=Image.open(R/'f0'/f'{prefix}.png').convert('RGBA'); emit=Image.open(R/'f0'/f'{prefix}_emit.png').convert('RGBA')
        box=base.getbbox(); a=np.array(base); mask=a[:,:,3]>0; colors=np.unique(a[:,:,:3][mask],axis=0)
        if base.size!=(cw,ch) or emit.size!=base.size: failures.append(key+' canvas')
        if box is None or box[3]-box[1]!=entry['visible_height_1x']: failures.append(key+' visible height')
        if box is not None and (box[0]<1 or box[1]<1 or box[2]>=cw or box[3]!=origin[1]): failures.append(key+' border/origin')
        if len(colors)>entry['color_cap']: failures.append(key+' palette')
        for suffix, picture in [('',base),('_emit',emit)]:
            ap=np.array(picture); high=Image.open(R/'f0'/f'{prefix}{suffix}@2x.png').convert('RGBA')
            if not set(np.unique(ap[:,:,3]))<={0,255}: failures.append(key+suffix+' alpha')
            if not np.array_equal(np.array(high),ap.repeat(2,0).repeat(2,1)): failures.append(key+suffix+' exact x2')
            for density in (1,2):
                file=f'{prefix}{suffix}'+('@2x' if density==2 else '')+'.png'
                assets.append({'file':'f0/'+file,'character':key,'action':'idle_f0'+suffix,'frame_width':cw*density,'frame_height':ch*density,
                               'frame_count':1,'fps':1,'static':True,'loop':False,'event_frame_zero_based':None,
                               'anchor':[p*density for p in origin],'anchor_convention':'bottom-exclusive projected center' if key in ['bone','brood'] else 'bottom-exclusive foot center',
                               'density':density,'color_cap':entry['color_cap'],'sha256':sha(R/'f0'/file)})
                if suffix=='_emit': assets[-1]['emission_contract']='independent RGB overlay; use layer RGB, not body RGB'
        ea=np.array(emit); em=ea[:,:,3]>0
        if np.any(em & ~mask): failures.append(key+' emission outside body')
        baseline=Image.open(BytesIO(subprocess.check_output(['git','show','ab3c6195:art/incoming/enemy_redraw_1023/f0/'+prefix+'.png'],cwd=ART.parent.parent))).convert('RGBA')
        if not np.array_equal(a,np.array(baseline)): failures.append(key+' main body changed while adding separate light')
        if key=='brood':
            if not np.array_equal(ea[em],a[em]): failures.append(key+' original organ pixels drifted')
            if not em.any(): failures.append('brood missing red organ')
            ec=ea[:,:,:3][em]
            if np.any((ec[:,0]<ec[:,1]) | (ec[:,0]<ec[:,2]) | (ec[:,1]>ec[:,2])): failures.append('brood emission hue')
        else:
            layout=heads[key]; x0,y0,x1,y1=layout['roi']; coords={(int(x),int(y)) for y,x in zip(*np.where(em))}
            if len(coords)!=5 or coords!={tuple(p) for p in layout['pixels']}: failures.append(key+' missing head pixels')
            if not all(x0<=x<x1 and y0<=y<y1 for x,y in coords): failures.append(key+' misplaced head light')
            if {tuple(c) for c in ea[:,:,:3][em]}!=light_palette: failures.append(key+' head colour rule')
            if key=='carmen':
                old_light=Image.open(BytesIO(subprocess.check_output(['git','show','7297b8e1:art/incoming/enemy_redraw_1023/f0/'+prefix+'_emit.png'],cwd=ART.parent.parent))).convert('RGBA')
                old_light=np.array(old_light); translated=np.zeros_like(old_light)
                translated[:-1,:-7]=old_light[1:,7:]
                if not np.array_equal(ea,translated): failures.append('carmen must only translate the previous light (-7,-1)')
                if em[26:29,28:31].any(): failures.append('carmen light still on front emblem/forehead')
        # Coloured outline override in the 10-23 brief replaces old uniform-outline checks.
        edge=np.zeros_like(mask); dark_bottom=True
        for y,x in zip(*np.where(mask)):
            for dx,dy in [(-1,0),(1,0),(0,-1),(0,1)]:
                if not(0<=y+dy<ch and 0<=x+dx<cw) or not mask[y+dy,x+dx]: edge[y,x]=True
            if y==ch-1 or x==cw-1 or not mask[min(y+1,ch-1),x] or not mask[y,min(x+1,cw-1)]:
                if tuple(a[y,x,:3])!=(8,14,24): dark_bottom=False
        if not dark_bottom: failures.append(key+' lower shadow border')
        if np.any(a[:,:,:3][edge].mean(axis=1)>100): failures.append(key+' bright unoutlined edge')
        islands=[]
        for y,x in zip(*np.where(mask)):
            if mask[max(0,y-1):y+2,max(0,x-1):x+2].sum()==1: islands.append([int(x),int(y)])
        if islands: failures.append(key+' isolated opaque pixel')
        if sha(Path(entry['reference']))!=entry['reference_sha256']: failures.append(key+' changed original ref')
        if sha(R/'generated'/f'{key}.png')!=entry['generated_sha256']: failures.append(key+' changed generated source')
        if sha(R/entry['prompt'])!=entry['prompt_sha256']: failures.append(key+' changed prompt')
        if key in heads:
            guide=job['head_revision']['guides'][key]
            if sha(R/guide['file'])!=guide['sha256'] or sha(R/guide['prompt'])!=guide['prompt_sha256']: failures.append(key+' changed head guide')
        reports.append({'id':key,'bbox_1x':box,'body_size_1x':[box[2]-box[0],box[3]-box[1]],'screen_height':(box[3]-box[1])*2,
                        'opaque_colors':len(colors),'color_cap':entry['color_cap'],'opaque_pixels':int(mask.sum()),'emit_pixels':int(em.sum()),
                        'body_identical_to_ab3c6195':True,'new_head_light_in_body':False,
                        'new_head_light_layer_only':True if key!='brood' else None,'emission_layer_is_separate_png':True,
                        'emission_bbox_1x':emit.getbbox(),
                        'palette_hex':['#'+''.join(f'{int(v):02X}' for v in c) for c in colors],
                        'isolated_alpha_pixels':islands,'origin':origin,'binary_alpha':True,'exact_x2':True,
                        'lighting_review':'source-directed top-left; visual acceptance pending',
                        'static_shape_review':'pending user review','motion_review':'not started','engine_review':'not performed'})
    manifest={'kind':'first f0 checkpoint; not runtime strips','brief_commit':job['brief_commit'],'size_approval_version':job['size_approval_version'],
              'method':'built-in imagegen redraw sources -> registered 1x material-palette export and coloured contour cleanup -> exact x2',
              'rig_status':'static image only; not a pixel Spine rig; original pose parts archived separately',
              'working_palette':'new candidate HEX palette; not a user-approved exact colour chart',
              'head_emission_contract':'user revision: new head marks only in independent _emit; body pixels identical to ab3c6195; carmen uses same crimson-magenta palette',
              'export_script_sha256':sha(R/'export.ps1'),'jobs_sha256':sha(R/'job.json'),'assets':assets}
    manifest['head_layout_sha256']=sha(R/'head_glow_layout.json')
    manifest['carmen_light_placement']=job['head_revision']['carmen_placement']
    save(R/'manifest.json',manifest)
    qa={'status':'pass' if not failures else 'fail','failures':failures,'reports':reports,
        'scope':'4 static poses only; no claim that all enemies or animations are finished',
        'head_light_revision':'user requested head-area light even without original emissive organs; all 3 are separate layers; carmen orange highlight removed',
        'all_main_bodies_identical_to_ab3c6195':True,'carmen_light_only_translation_from_7297b8e1':[-7,-1],
        'not_certified':['native attachment motion reconstruction','all animation slots','per-material lighting and contour artistic approval','engine integration'],
        'technical_check':'dimensions, height, alpha, per-frame palette, lower/dark outline, isolated alpha, exact x2, emit/body alignment, hashes'}
    save(R/'qa.json',qa)
    print(json.dumps({'status':qa['status'],'reports':reports,'failures':failures},ensure_ascii=False))
    if failures: raise RuntimeError('candidate failed QA')
    return job,reports


def main():
    job,reports=verify(); entries=job['jobs']; by_id={r['id']:r for r in reports}
    table=read(ART/'size_compare_1023/table.json'); old={r['id']:r for r in table['enemies']}
    old_atlas=Image.open(ART/'size_compare_1023/target_samples_1x.png').convert('RGBA')
    board=Image.new('RGB',(1280,120+len(entries)*334),BG); d=ImageDraw.Draw(board)
    label(d,20,12,'怪物正式重画 · 第一批静帧候选',26)
    label(d,20,51,'新源稿按原作结构重画，再整理到1x；@2x只做精确×2。静帧候选，未做动作／接入。',16,'#b5c7d1')
    label(d,20,82,'新增头部光点仅交独立图层，本体不带光点；骨海／固海／卡门均为洋红深红。',14,'#bfa5ab')
    for i,e in enumerate(entries):
        key=e['id']; y=120+i*334; r=by_id[key]; base=Image.open(R/'f0'/f'e_{key}_idle_f0.png').convert('RGBA')
        emit=Image.open(R/'f0'/f'e_{key}_idle_f0_emit.png').convert('RGBA'); prev=old_atlas.crop(old[key]['atlas_rect_1x'])
        d.rectangle((8,y,1272,y+326),outline='#3d5363'); label(d,20,y+8,e['name']+f" · {r['body_size_1x'][1]}格→{r['screen_height']}px · {r['opaque_colors']}/{e['color_cap']}色",20)
        for cx,caption in [(155,'原作Spine参考'),(430,'已批体量示意 ×4'),(735,'本稿叠加预览 ×4'),(1040,'本稿本体／发光 ×2')]: label(d,cx-90,y+44,caption,14)
        source=Image.open(Path(e['reference'])).convert('RGBA'); source=source.crop(source.getbbox())
        source.thumbnail((235,210),Image.Resampling.LANCZOS);draw_at(board,source,155,y+285)
        draw_at(board,prev,430,y+285,4); draw_at(board,Image.alpha_composite(base,emit),735,y+285,4)
        draw_at(board,base,985,y+227,2); draw_at(board,emit,1125,y+227,2)
        label(d,922,y+243,'本体',12);label(d,1083,y+243,'发光层' if r['emit_pixels'] else '无发光器官',12)
        label(d,20,y+299,'沿用原作造型、武器与姿态；图中倍率仅用于审阅。',12,'#a4b9c8')
    board.save(R/'comparison.png')
    layers=Image.new('RGB',(1280,110+3*320),BG);ld=ImageDraw.Draw(layers)
    label(ld,20,12,'头部光点 · 本体与发光层分别交付',26)
    label(ld,20,52,'本体像素与上稿完全一致；光点只在_emit。第三列为审阅叠加，不是交付合图。',16,'#b5c7d1')
    for i,key in enumerate(['bone','stone','carmen']):
        e=next(e for e in entries if e['id']==key);y=110+i*320;cw,ch=e['canvas_1x'];foot=y+270
        base=Image.open(R/'f0'/f'e_{key}_idle_f0.png').convert('RGBA');emit=Image.open(R/'f0'/f'e_{key}_idle_f0_emit.png').convert('RGBA')
        ld.rectangle((8,y,1272,y+314),outline='#3d5363');label(ld,20,y+8,e['name']+' · '+str(e['visible_height_1x']*2)+'px',20)
        for cx,caption,pic in [(210,'本体单独：不含新增光点',base),(640,'发光层单独：5个1x像素',emit),(1070,'叠加预览：非交付合图',Image.alpha_composite(base,emit))]:
            label(ld,cx-115,y+44,caption,14)
            shown=pic.resize((cw*4,ch*4),Image.Resampling.NEAREST)
            layers.paste(shown,(cx-cw*2,foot-(ch-4)*4),shown)
            ld.line((cx-130,foot,cx+130,foot),fill='#3d5363')
        footer='卡门光点移至帽带侧后方；已移开额头正面，仍为独立_emit。' if key=='carmen' else '统一三阶：#54172F / #87304B / #B44D68；本体与_emit同画布同原点。'
        label(ld,20,y+294,footer,12,'#bfa5ab')
    layers.save(R/'head_glow_layers.png')
    lineup=Image.new('RGB',(1280,540),BG); d=ImageDraw.Draw(lineup)
    label(d,22,14,'第一批 · 100%屏幕比例与暗场读图',26)
    label(d,22,53,'仅本页叠加独立_emit预览；底行模拟变暗，不代表引擎辉光。实际文件分层交付。',14,'#b5c7d1')
    xlist=[120,300,480,680,900,1130]
    reference_files=[]
    for i,e in enumerate(entries):
        base=Image.open(R/'f0'/f"e_{e['id']}_idle_f0@2x.png").convert('RGBA')
        emit=Image.open(R/'f0'/f"e_{e['id']}_idle_f0_emit@2x.png").convert('RGBA')
        reference_files.append((e['name'],Image.alpha_composite(base,emit)))
    for ref in table['references'][:2]:
        # The art worktree is intentionally not synced to main. Read these unchanged references from pinned Git.
        blob=lambda path: subprocess.check_output(['git','show',table['source_commit']+':'+path],cwd=ART.parent.parent)
        im=Image.open(BytesIO(blob(ref['source']))).convert('RGBA')
        character=json.loads(blob('game/data/characters/'+ref['id']+'.json')); slot=character['sprites']['idle']
        count=slot.get('frames',max(1,round(im.width/im.height))) if isinstance(slot,dict) else max(1,round(im.width/im.height))
        frame_width=im.width//count
        im=im.crop((0,0,frame_width,im.height));im=im.crop(im.getbbox());im=im.resize(tuple(ref['size']),Image.Resampling.NEAREST)
        reference_files.append((ref['name']+'64px标尺',im))
    for row,foot in [(0,225),(1,440)]:
        d.line((14,foot,1264,foot),fill='#52687a')
        for x,(name,im) in zip(xlist,reference_files):
            shown=im
            if row:
                a=np.array(im).copy();a[:,:,:3]=(a[:,:,:3].astype(float)*.55).astype('uint8');shown=Image.fromarray(a)
            draw_at(lineup,shown,x,foot);label(d,x-55,foot+12,name,14)
    label(d,22,495,'静帧候选：原作参考一致性／像素整理待你看稿；动作、遮挡及引擎表现尚未验收。',14,'#b5c7d1')
    lineup.save(R/'lineup.png')
    (R/'review.html').write_text('''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>怪物静帧与独立头部发光层</title><style>body{margin:0;background:#14222e;color:#d8e5ec;font:16px/1.7 system-ui}main{max-width:1280px;margin:auto;padding:20px}img{display:block;max-width:100%;height:auto;margin:18px 0;image-rendering:pixelated}a{color:#b1d4df}</style><main><h1>首批四张静帧：头部光点分层修订</h1><p>用户最新要求：头部附近加光点，光点单独图层。骨海／固海／卡门的新标识只交独立_emit，本体与上稿完全相同；卡门也统一洋红深红，去掉橙色亮芯。</p><p>本体、发光层、叠加预览分列；叠加仅用于审阅，没有交付合图替代分层。三者均5个1x光点像素，同画布同原点。拟嗣保留原核心及34像素独立发光层。</p><img src="head_glow_layers.png" alt="本体单独、发光层单独、审阅叠加"><img src="lineup.png" alt="实际比例叠加预览"><img src="comparison.png" alt="原作与本稿对照"><p><a href="manifest.json">manifest</a> · <a href="qa.json">核验</a> · <a href="HANDOFF.md">交接</a></p><p>骨海40px，固海50px，卡门80px，拟嗣36px。静帧候选，尚未扩展动作或接入；生产资源和攻击事件均未修改。</p></main></html>''',encoding='utf8',newline='\n')


    html=R/'review.html'
    html.write_text(html.read_text(encoding='utf8').replace('卡门也统一洋红深红，去掉橙色亮芯。','卡门保持洋红深红，光点已由正面移至帽带侧后方；只移动独立发光层。'),encoding='utf8',newline='\n')


if __name__=='__main__':
    verify() if '--verify' in sys.argv else main()
