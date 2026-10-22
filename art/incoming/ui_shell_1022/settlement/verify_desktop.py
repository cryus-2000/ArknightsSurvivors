from pathlib import Path
from PIL import Image,ImageChops
import json,hashlib
P=Path(__file__).resolve().parent
m=json.loads((P/'manifest.json').read_text(encoding='utf-8'))
im=Image.open(P/'settlement_desktop.png').convert('RGB')
assert im.size==(1280,720)
assert hashlib.sha256((P/'settlement_desktop.png').read_bytes()).hexdigest()==m['sha256']
checks=['PNG decodes at 1280x720','Delivery hash matches manifest']
for asset in m['decorative_assets']:
    path=P/asset['file'];a=Image.open(path).convert('RGBA')
    assert hashlib.sha256(path.read_bytes()).hexdigest()==asset['sha256']
    assert list(a.size)==asset['size'] and min(a.getchannel('A').getextrema())==0
    b=a.resize((a.width//2,a.height//2),Image.Resampling.NEAREST).resize(a.size,Image.Resampling.NEAREST)
    assert ImageChops.difference(a,b).getbbox() is None
    checks.append(asset['file']+': transparent RGBA, hash and uniform 2px grid verified')
topo=Image.open(P/'decor/topography_sparse@2x.png').getchannel('A')
assert topo.crop((0,208,916,648)).getbbox() is None
occupied=sum(topo.histogram()[1:])/(1280*720)
assert 0<occupied<.03
checks.append('Sparse topography covers under 3 percent of canvas; squad/data region fully clear')
for item in m['placements']:
    source=P/item['file']
    provenance=json.loads((P/'source/provenance.json').read_text(encoding='utf-8'))
    expected=next(r['sha256'] for r in provenance if r['id']==item['id'])
    assert hashlib.sha256(source.read_bytes()).hexdigest()==expected==item['sha256']
    s=Image.open(source).convert('RGBA').crop(item['source_bbox'])
    s=s.resize((s.width*2,s.height*2),Image.Resampling.NEAREST)
    delta=ImageChops.difference(im.crop(item['display_bbox']),s.convert('RGB'))
    masked=Image.new('RGB',delta.size);masked.paste(delta,mask=s.getchannel('A'))
    assert masked.getbbox() is None,item['id']
    checks.append(item['id']+': approved source exact and visible pixels unchanged at integer 2x')
team=m['team_sample']
assert sum(r['damage'] for r in team)==1284620
assert sum(r['kills'] for r in team)==1284
assert sum(r['casts'] for r in team)==128
assert abs(sum(r['share'] for r in team)-100)<.00001
for r in team:assert abs(round(r['damage']/1284620*100,1)-r['share'])<.00001
checks.append('Sample damage, kills, casts and percentages are consistent')
boxes=json.loads((P/'layout_text_bounds.json').read_text(encoding='utf-8'))
for item in boxes:
    l,t,r,b=item['bbox']; assert 0<=l<r<=1280 and 0<=t<b<=720,item
required=['探索完成','探索用时','难度档','生机细胞','寻访凭证','RATING','SS','伤害占比','击杀','参与击杀','技能次数','关键事件','返回主界面','认知塑造','寻访  ×4']
words={item['text'] for item in boxes}
assert all(t in words for t in required)
assert m['rating_sample']['grade']=='SS' and m['rating_sample']['difficulty']=='困难'
assert '倒地次数' not in words
assert 'settlement_desktop.png' in (P/'review.html').read_text(encoding='utf-8')
checks+=['All required task fields present','All text bounding boxes on canvas','Review image reference resolves']
report={'passed':True,'checks':checks,'image_generation_used':False,'visual_approval':'accepted_for_handoff','engine_verified':False,'delivery_stage':'desktop victory only'}
(P/'qa.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
