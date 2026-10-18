"""Capture real Mizuki actions with fixed simulation steps and package local GIF evidence."""
from pathlib import Path
import argparse,json,os,sys,statistics,html
from concurrent.futures import ThreadPoolExecutor
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import godot_runner as gr
OUT=ROOT/'build/mizuki_runtime_capture'
CASES=[(-1,1,120),(-1,4,120),(0,1,120),(1,1,280),(1,4,280),(2,1,320),(2,4,320)]

def capture(case):
    slot,rate,count=case; key=f's{slot+1}_x{rate}'; folder=OUT/key;folder.mkdir(parents=True,exist_ok=True)
    cmd=[gr.find_godot(),'--path',str(ROOT/'game'),'res://tests/mizuki_runtime_capture.tscn','--','--regression','--balance','--seed=1','--op=mizuki',f'--capture-skill={slot}',f'--capture-rate={rate}',f'--capture-frames={count}']
    if OUT.name=="mizuki_s3_fx_capture": cmd.append("--s3-fx")
    out,err,to=gr.run_godot(cmd,240);(folder/'run.log').write_text(out+'\n'+err,encoding='utf8')
    assert not to and not gr.script_errors(out,err) and 'MIZUKI RUNTIME CAPTURE' in out,(key,out[-1000:],err[-1000:])
    print(key,'captured',flush=True)

def package():
    cards=[];report=[]
    for slot,rate,count in CASES:
        key=f's{slot+1}_x{rate}';folder=OUT/key;data=json.loads((folder/'evidence.json').read_text())
        files=sorted(folder.glob('s2_*.png'));assert len(files)==count,(key,len(files),count)
        imgs=[]
        for file in files:
            im=Image.open(file).convert('RGB');w,h=im.size
            # Gameplay center and targets, no resampling; full original PNGs remain alongside.
            imgs.append(im.crop((max(0,w//2-280),max(0,h//2-220),min(w,w//2+340),min(h,h//2+180))))
        imgs[0].save(OUT/(key+'.gif'),save_all=True,append_images=imgs[1:],duration=50,loop=0,optimize=False)
        indices=[0,count//6,count//3,count//2,count*2//3,count-1];w,h=imgs[0].size
        sheet=Image.new('RGB',(w*3,(h+28)*2),(32,42,54));draw=ImageDraw.Draw(sheet)
        for j,i in enumerate(indices):
            x=j%3*w;y=j//3*(h+28);sheet.paste(imgs[i],(x,y));q=data['samples'][i];draw.text((x+8,y+h+5),f'{i*.05:.2f}s {q["kind"]} f{q["pose"]} left{q["remaining"]:.2f}',fill='white')
        sheet.save(OUT/(key+'_contact.png'))
        starts=data['starts'];intervals=[b['time']-a['time'] for a,b in zip(starts,starts[1:])];observed=round(statistics.median(intervals),4) if intervals else None
        row=dict(case=key,requested_interval=max(.18,.9/rate*(.5 if slot==1 else 1)),minimum_cycle=.45,recorded_action_durations=sorted({round(s['duration'],4) for s in starts}),observed_median_start_interval=observed,releases=len(data['releases']),frames=count,final_remaining=data['samples'][-1]['remaining'])
        report.append(row);title=('普通攻击' if slot<0 else f'S{slot+1}')+f' · {rate}倍攻速'
        cards.append(f'<section><h2>{title}</h2><p>配置间隔 {row["requested_interval"]:.3f}s；动作与停顿合计下限 0.45s。整段实测起手间隔中位数 {observed}s（受目标移动、击退及技能结束影响，不等于理论攻速）。命中事件 {row["releases"]} 次。</p><img src="{key}.gif"><details><summary>阶段截图</summary><img src="{key}_contact.png"></details><a href="{key}/evidence.json">逐步记录</a></section>')
    (OUT/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
    intro='<p>S3 整范围触手试版：14 秒，伤害 ×1.8、范围 ×1.45；群攻不限目标，低生命额外目标眩晕 0.6 秒。不扣血，无倒影追加伤害。整片触手由实际攻击触发，6 帧 / 0.3 秒。</p>' if OUT.name=='mizuki_s3_fx_capture' else ''
    (OUT/'review.html').write_text('<!doctype html><meta charset="utf-8"><title>水月实机时序</title><style>body{background:#202a36;color:#eee;font:17px system-ui;margin:24px}main{display:grid;grid-template-columns:repeat(2,1fr);gap:20px}img{width:100%;image-rendering:pixelated}section{background:#2d3745;padding:16px}a{color:skyblue}</style><h1>水月 · 实机攻击与技能</h1><p>固定60Hz游戏模拟，每50ms截帧；GIF为常速。完整动作后再起手；倍率提升仍受可读性下限约束。</p><p><a href="../mizuki_runtime_review/review.html">全部原帧条与逐帧图</a></p><main>'+''.join(cards)+'</main>'+intro,encoding='utf8')
    print(OUT/'review.html')

def main():
    global OUT, CASES
    p=argparse.ArgumentParser();p.add_argument('--package-only',action='store_true');p.add_argument('--s3-only',action='store_true');a=p.parse_args()
    if a.s3_only: OUT=ROOT/'build/mizuki_s3_fx_capture';CASES=[(2,1,320),(2,4,320)]
    temp=ROOT/'build/tmp';temp.mkdir(parents=True,exist_ok=True);os.environ['TEMP']=os.environ['TMP']=str(temp)
    if not a.package_only:
        with ThreadPoolExecutor(max_workers=2) as pool:list(pool.map(capture,CASES))
    package()
if __name__=='__main__':main()
