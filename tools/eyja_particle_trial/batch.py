"""Render and profile three more isolated material studies, sequentially through godot_runner."""
from pathlib import Path
import subprocess,sys,json,re
here=Path(__file__).resolve().parent
dest=here.parents[1]/'build/eyja_particle_trial_1024'
for effect in ['lappland','gladiia','mizuki']:
    subprocess.run([sys.executable,str(here/'run.py'),'--effect',effect,'--capture','--bench','--stress-only'],check=True)
    data=json.loads((dest/effect/'perf.json').read_text())
    assert len(data)==4 and all(r['groups']==12 and r['frames']>0 for r in data)
    print('VERIFIED',effect,flush=True)
page='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><title>技能粒子材质对照 · 四组</title>
<style>body{margin:0;background:#11191c;color:#e2e8e6;font:16px system-ui}header{padding:20px 28px;border-bottom:1px solid #344247}h1{font-size:22px}p{color:#a7b9b7;font-size:14px}button{padding:10px 18px;margin:0 8px 8px 0;background:#233136;border:1px solid #405054;color:#e2e8e6;border-radius:5px;cursor:pointer}button.on{border-color:#e5b567;color:#f5ca8c}iframe{width:100%;height:1250px;border:0}</style>
<header><h1>四种技能，四种粒子运动</h1><p>独立 GPU 视觉试验 · 技能主体保持相同 · 未接入正式游戏</p><nav>
<button data-src="review.html">艾雅法拉 · 熔渣与余烬</button><button class="on" data-src="lappland/review.html">拉普兰德 · 剑弧碎屑</button><button data-src="gladiia/review.html">歌蕾蒂娅 · 旋转水流</button><button data-src="mizuki/review.html">水月 · 聚拢冷光</button></nav></header>
<iframe title="技能对照" src="lappland/review.html"></iframe><script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{document.querySelectorAll('button').forEach(x=>x.classList.remove('on'));b.classList.add('on');document.querySelector('iframe').src=b.dataset.src;});</script></html>'''
(dest/'index.html').write_text(page,encoding='utf-8')
print('REVIEW',dest/'index.html',flush=True)
