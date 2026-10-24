"""Isolated GPU-particle visual study; uses the repository runner for silent offscreen rendering."""
from pathlib import Path
import sys, json, subprocess, argparse, shutil
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import godot_runner as gr

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--capture',action='store_true')
    ap.add_argument('--bench',action='store_true')
    a=ap.parse_args()
    dest=ROOT/'build/eyja_particle_trial_1024'
    dest.mkdir(parents=True,exist_ok=True)
    project=Path(__file__).parent
    def run(name,args,fixed=False):
        cmd=[gr.find_godot(),'--path',str(project),'--audio-driver','Dummy']
        if fixed: cmd+=['--fixed-fps','60']
        cmd+=['--']+args
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
        shutil.copyfile(project/'review.html',dest/'review.html')
    if a.bench:
        rows=[]
        for count in [1,12]:
            for rep,mode in enumerate(['base','trial','trial','base']):
                out=run('bench_%s_%s_%s'%(count,rep,mode),['--mode='+mode,'--count='+str(count)])
                row=json.loads(next(x[5:] for x in out.splitlines() if x.startswith('PERF ')))
                row['repeat']=rep;rows.append(row)
                (dest/'perf.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
        table='<table><tr><th>同时喷发</th><th>方案</th><th>平均帧耗时，两次范围</th><th>P95，两次范围</th></tr>'
        for count in [1,12]:
            for mode,label in [('base','A 当前通用参数'),('trial','B 熔岩材质试验')]:
                matching=[r for r in rows if r['groups']==count and r['mode']==mode]
                values=[]
                for field in ['mean_ms','p95_ms']:
                    values.append('%.2f–%.2f ms'%(min(r[field] for r in matching),max(r[field] for r in matching)))
                table+='<tr><td>%d 组 / %d 颗</td><td>%s</td><td>%s</td><td>%s</td></tr>'%(count,count*23,label,*values)
        table+='</table><p>RTX 4060 Laptop GPU · 两次测量仍受负载波动影响，不能据此判断哪种更快。<a href="perf.json">原始数据</a></p>'
        (dest/'perf.js').write_text('document.querySelector("#perf").innerHTML='+json.dumps(table,ensure_ascii=False)+';',encoding='utf-8')
    print(dest,flush=True)

if __name__=='__main__': main()
