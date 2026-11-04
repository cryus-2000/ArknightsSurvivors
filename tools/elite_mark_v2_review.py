"""Silent renderer review. All Godot starts use the shared machine-wide runner."""
from pathlib import Path
import sys, json
import godot_runner as gr
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/elite_mark_v2/revision_3'; OUT.mkdir(parents=True,exist_ok=True)
mode=sys.argv[1] if len(sys.argv)>1 else 'shots'
if mode=='import':
    args=[gr.find_godot(),'--headless','--editor','--import','--path',str(ROOT/'game'),'--audio-driver','Dummy']
else:
    args=[gr.find_godot(),'--path',str(ROOT/'game'),'--audio-driver','Dummy','--fixed-fps','30']
    if mode=='sanity':
        args+=['--headless','--','--balance','--nodeath','--seed=11','--op=logos','--maxt=5','--dccheck','--bal=render/elite_mark_v2=1']
    else:
        args+=['res://tests/elite_mark_v2_review.tscn','--','--balance','--nodeath','--seed=11','--op=logos','--dccheck','--review-dir='+OUT.as_posix()]
stdout,stderr,timeout=gr.run_godot(args,900)
(OUT/(mode+'.log')).write_text(' '.join(args)+'\n'+stdout+'\n'+stderr,encoding='utf8')
errors=gr.script_errors(stdout,stderr)
print(json.dumps(dict(mode=mode,timeout=timeout,errors=errors),ensure_ascii=False))
if timeout or errors:sys.exit(1)
if mode=='shots':
    from PIL import Image, ImageDraw, ImageFont
    font=ImageFont.truetype('C:/Windows/Fonts/msyh.ttc',24)
    panel=Image.new('RGB',(1800,420),'#131e29')
    draw=ImageDraw.Draw(panel)
    for row,(name,title) in enumerate([('off','关闭：旧橙红标记 / 小队红边'),('on','开启：精英白▼ / 小队沉珊瑚红▼'),('squad_flash','开启：小队同步白边（0.15秒）')]):
        src=Image.open(OUT/(name+'.png')).convert('RGB')
        crop=src.crop((340,228,940,340))
        panel.paste(crop,(0,row*140+28))
        draw.text((6,row*140+1),title,font=font,fill='white')
    panel.crop((0,0,600,420)).save(OUT/'compare.png')
    Image.open(OUT/'on.png').crop((470,228,685,313)).resize((645,255),Image.Resampling.NEAREST).save(OUT/'mark_3x.png')
