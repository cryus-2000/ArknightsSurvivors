"""Isolated GPU-particle visual study; uses the repository runner for silent offscreen rendering."""
from pathlib import Path
import sys, json, subprocess, argparse, shutil, re
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import godot_runner as gr

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--capture',action='store_true')
    ap.add_argument('--bench',action='store_true')
    ap.add_argument('--effect',choices=['eyja','lappland','gladiia','mizuki'],default='eyja')
    ap.add_argument('--stress-only',action='store_true')
    ap.add_argument('--body',action='store_true')
    a=ap.parse_args()
    dest=ROOT/'build/eyja_particle_trial_1024'
    if a.effect!='eyja': dest=dest/a.effect
    if a.body:
        assert a.effect=='lappland'
        dest=dest/'body'
    dest.mkdir(parents=True,exist_ok=True)
    project=Path(__file__).parent
    def run(name,args,fixed=False):
        cmd=[gr.find_godot(),'--path',str(project),'--audio-driver','Dummy']
        if fixed: cmd+=['--fixed-fps','60']
        cmd+=['--','--effect='+a.effect]+args
        if a.body: cmd+=['--body']
        out,err,to=gr.run_godot(cmd,150)
        (dest/(name+'.log')).write_text(out+'\n'+err,encoding='utf-8')
        assert not to and not gr.script_errors(out,err),(name,to,err)
        print(out.strip(),flush=True)
        return out
    if a.capture:
        import imageio_ffmpeg
        for name,extra in [('compare',[]),('particles',['--particles-only'])]:
            frames=dest/(name+'_frames');frames.mkdir(exist_ok=True)
            run(name,['--capture','--mode=compare','--out='+str(frames)]+extra,True)
            assert len(list(frames.glob('frame_*.png')))>=150
            subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-y','-loglevel','error','-framerate','60','-i',str(frames/'frame_%04d.png'),'-frames:v','150','-c:v','libx264','-pix_fmt','yuv420p','-crf','16',str(dest/(name+'.mp4'))],check=True)
            for side,x in [('left',0),('right',480)]:
                subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(),'-y','-loglevel','error','-i',str(dest/(name+'.mp4')),'-vf','crop=480:220:%d:200'%x,'-c:v','libx264','-pix_fmt','yuv420p','-crf','16',str(dest/(name+'_'+side+'.mp4'))],check=True)
        page=(project/'review.html').read_text(encoding='utf-8')
        metadata={
            'lappland':('拉普兰德','剑气','沿剑弧剥离，向挥砍方向飞散','剑气材质试验','粒子沿宽弧面生成，顺着挥砍方向脱落；浅色刃屑先亮后暗，不再从中心炸成一团。','4 帧 / 10 fps'),
            'gladiia':('歌蕾蒂娅','水龙卷','水滴沿旋转外缘卷动','水流材质试验','水滴从椭圆外缘生成，切向卷动并轻微向内收；颜色从浅灰蓝转深，避免白色烟花感。','6 帧 / 12 fps（循环展示 1.3 秒）'),
            'mizuki':('水月','水母刺击','漂浮、聚拢，再逐渐消隐','水母材质试验','细小冷光颗粒从周围缓慢聚拢，轻微盘旋上浮，亮起后收暗；避免火星式下坠。','5 帧 / 18 fps')}
        if a.effect in metadata:
            who,skill,subtitle,label,caption,timing=metadata[a.effect]
            page=page.replace('艾雅法拉',who).replace('熔岩弹',skill).replace('让火星、熔渣各自运动',subtitle).replace('EYJAFJALLA',a.effect.upper()).replace('熔岩材质试验',label)
            page=page.replace('熔渣向下落并冷却变暗；细火星向上漂；烟灰在尾段保留少量层次。',caption).replace('6 帧 / 18 fps',timing).replace('落地时的通用 GPU 点缀层','对应的通用 GPU 点缀层')
            if a.effect=='gladiia':
                page=page.replace('大特效的火星、余烬、烟同时出现。','对照用相同连续发射时段，左边沿用通用运动参数。').replace('同一技能主体、相同 23 颗 GPU 粒子、相同 3 个发射器。','同一技能主体、两边相同 23 颗同时存活上限、相同 3 个连续发射器。')
        if a.body:
            page=page.replace('沿剑弧剥离，向挥砍方向飞散','剑气主体，直接碎成粒子').replace('剑气材质试验','主体碎解试验')
            page=page.replace('同一技能主体、相同 23 颗 GPU 粒子、相同 3 个发射器。先看爆发之后的运动与冷却。','A 保留完整帧条；B 只保留 0.15 秒起手，随后由原帧像素碎片承担主体。此版增加粒子数，不再是等粒子预算对照。')
            page=page.replace('粒子沿宽弧面生成，顺着挥砍方向脱落；浅色刃屑先亮后暗，不再从中心炸成一团。','起手 0.10 秒后，原剑气像素开始剥离；0.15 秒后不再绘制主体贴图，碎片独立飞散并熄灭。')
            page=re.sub(r'(<b>这版比较什么</b>)<p>.*?</p>',r'\1<p>A 为原帧条 + 通用点缀的隔离复现。B 从原剑气第二帧取色与取形，最多 192 颗主体碎片 + 13 颗点缀，仍用 3 个 GPU 发射器；不增加动态光源，不做碰撞。两边没有完整实战后期。主体贴图由原 0.40 秒缩短到 0.15 秒，末尾 0.05 秒与颗粒交接；攻击逻辑未接入或改变。</p>',page)
        (dest/'review.html').write_text(page,encoding='utf-8')
        if a.body:
            hub=ROOT/'build/eyja_particle_trial_1024/index.html'
            if hub.exists():
                html=hub.read_text(encoding='utf-8')
                if 'lappland/body/review.html' not in html:
                    html=html.replace('class="on"','').replace('<nav>','<nav><button class="on" data-src="lappland/body/review.html">新 · 剑气主体碎解</button>')
                    html=html.replace('src="lappland/review.html"></iframe>','src="lappland/body/review.html"></iframe>')
                    hub.write_text(html,encoding='utf-8')
        (dest/'perf.js').write_text('document.querySelector("#perf").textContent="该样例尚未完成性能测量。";',encoding='utf-8')
    if a.bench:
        rows=[]
        counts=[12] if a.stress_only else [1,12]
        for count in counts:
            for rep,mode in enumerate(['base','trial','trial','base']):
                out=run('bench_%s_%s_%s'%(count,rep,mode),['--mode='+mode,'--count='+str(count)])
                row=json.loads(next(x[5:] for x in out.splitlines() if x.startswith('PERF ')))
                row['repeat']=rep;rows.append(row)
                (dest/'perf.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
        table='<table><tr><th>同时喷发</th><th>方案</th><th>平均帧耗时，两次范围</th><th>P95，两次范围</th></tr>'
        for count in counts:
            for mode,label in [('base','A 通用参数'),('trial','B 材质运动试验')]:
                matching=[r for r in rows if r['groups']==count and r['mode']==mode]
                values=[]
                for field in ['mean_ms','p95_ms']:
                    values.append('%.2f–%.2f ms'%(min(r[field] for r in matching),max(r[field] for r in matching)))
                table+='<tr><td>%d 组 / %d 颗</td><td>%s</td><td>%s</td><td>%s</td></tr>'%(count,count*matching[0].get('particles_per_burst',23),label,*values)
        table+='</table><p>RTX 4060 Laptop GPU · 两次测量仍受负载波动影响，不能据此判断哪种更快。<a href="perf.json">原始数据</a></p>'
        (dest/'perf.js').write_text('document.querySelector("#perf").innerHTML='+json.dumps(table,ensure_ascii=False)+';',encoding='utf-8')
    print(dest,flush=True)

if __name__=='__main__': main()
