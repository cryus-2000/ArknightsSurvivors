"""Build Mizuki's exact-source strip overview; runtime captures remain separate evidence."""
from pathlib import Path
import json, html
from PIL import Image, ImageDraw
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/mizuki_runtime_review'
BG = (45,55,69)

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    d=json.loads((ROOT/'game/data/characters/mizuki.json').read_text(encoding='utf8'))
    manifest=json.loads((ROOT/'art/incoming/mizuki_runtime_manifest.json').read_text(encoding='utf8'))
    cards=[]
    keys=['idle','run','attack','skill_s1_attack','skill_s2','skill_s2_loop','skill_s2_attack','skill_s2_end','skill_s3','skill_s3_loop','skill_s3_attack','skill_s3_end','hurt','death']
    for key in keys:
        s=d['sprites'][key]; im=Image.open(ROOT/'art/incoming'/(s['tex']+'@2x.png')).convert('RGBA'); n=s['frames']; w=im.width//n
        frames=[]; contact=Image.new('RGB',(w*4,(im.height+24)*((n+3)//4)),BG); draw=ImageDraw.Draw(contact)
        for i in range(n):
            crop=im.crop((i*w,0,(i+1)*w,im.height)); f=Image.new('RGB',crop.size,BG);f.paste(crop,mask=crop.getchannel('A'));frames.append(f)
            x=i%4*w;y=i//4*(im.height+24);contact.paste(f,(x,y));draw.text((x+6,y+im.height+4),f'f{i}'+(' FIRE' if s.get('fire')==i else ''),fill='white')
        contact.save(OUT/(key+'_contact.png'))
        ms=max(10,round(1000/s['fps']/10)*10)
        frames[0].save(OUT/(key+'.gif'),save_all=True,append_images=frames[1:],duration=ms,loop=0,disposal=2)
        cards.append(f'<article><h2>{html.escape(key)}</h2><p>{n} 帧；参考预览 {s["fps"]:.2f} fps。'+('攻击实际时长由出手／收势配置决定。' if 'attack_timing' in s else '')+f'</p><img src="{key}.gif"><details><summary>逐帧</summary><img class="contact" src="{key}_contact.png"></details></article>')
    path=OUT/'review.html'
    path.write_text('<!doctype html><meta charset="utf-8"><title>水月 · 全动作接入核对</title><style>body{background:#202a36;color:#eee;font:17px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(3,1fr);gap:16px}article{background:#2d3745;padding:12px}img{image-rendering:pixelated;width:384px;max-width:100%}.contact{width:768px}a{color:skyblue}</style><h1>水月 · 原生 Spine 像素动作</h1><p>完整192像素 @2x 帧，保持共享脚底锚点。这里用于检查帧条；实际技能衔接与攻击间隔以实机录制为准。</p><p><a href="../mizuki_runtime_capture/review.html">打开实机时序与录像</a></p><p>S2/S3 共用已核对的 Skill_2 参考动作；保留本作各自机制，未宣称原作 S3 绑定一致。待机第6帧伞尖低于脚底属于原动作。</p><main>'+''.join(cards)+'</main>',encoding='utf8')
    print(path)

if __name__=='__main__': main()
