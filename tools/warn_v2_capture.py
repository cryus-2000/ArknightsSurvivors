"""Capture real late-game warnings through the shared silent/off-screen runner."""
from pathlib import Path
import json, sys
import godot_runner as runner
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'build/warn_v2';OUT.mkdir(parents=True,exist_ok=True)
args=[runner.find_godot(),'--path',str(ROOT/'game'),'--audio-driver','Dummy',
      '--resolution','1280x720','--fixed-fps','30','res://tests/warn_v2_probe.tscn','--',
      '--balance','--nodeath','--bot=expert','--seed=11','--op=logos',
      '--squad=texas,suzuran','--rtfrom=478','--maxt=510',
      '--bal=render/warn_v2=1','--warn-shot-dir='+OUT.as_posix()]
if "--perf" in sys.argv: args.append("--warn-perf")
import time
started=time.time()
stdout,stderr,timeout=runner.run_godot(args,900)
(OUT/'run.log').write_text(' '.join(args)+'\n'+stdout+'\n'+stderr,encoding='utf8')
errors=runner.script_errors(stdout,stderr)
print(json.dumps(dict(errors=errors,timeout=timeout),ensure_ascii=False))
if timeout or errors or not (OUT/'capture.json').exists() or (OUT/'capture.json').stat().st_mtime<started:sys.exit(1)
