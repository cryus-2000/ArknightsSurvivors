"""Run the gem regression and real-render review through the shared runner."""
from pathlib import Path
import sys,json
import godot_runner as gr
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/gem_v2';OUT.mkdir(parents=True,exist_ok=True)
mode=sys.argv[1] if len(sys.argv)>1 else 'test'
args=[gr.find_godot(),'--path',str(ROOT/'game'),'--audio-driver','Dummy']
if mode=='import': args+=['--headless','--editor','--import']
elif mode=='test':args+=['--headless','res://tests/gem_v2_test.tscn','--','--gem-v2-test']
elif mode=='tiers':args+=['--resolution','1280x720','res://tests/gem_v2_tiers.tscn','--','--gem-review-out='+OUT.as_posix()]
else:args+=['--resolution','1280x720','--fixed-fps','30','res://tests/gem_v2_capture.tscn','--','--balance','--nodeath','--bot=expert','--seed=11','--op=logos','--squad=texas,suzuran','--maxt=490','--rtfrom=479','--gem-review-out='+OUT.as_posix()]
stdout,stderr,timeout=gr.run_godot(args,1200)
(OUT/(mode+'.log')).write_text(' '.join(args)+'\n'+stdout+'\n'+stderr,encoding='utf8')
errors=gr.script_errors(stdout,stderr)
print(json.dumps(dict(mode=mode,timeout=timeout,errors=errors[:8],test='GEM_V2 failures=0' in stdout)))
if timeout or errors or (mode=='test' and 'GEM_V2 failures=0' not in stdout):raise SystemExit(1)
