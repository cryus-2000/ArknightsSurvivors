#!/usr/bin/env bash
set -u
cd /home/user/ArknightsSurvivors
source tools/cloud/env.sh
export PYTHONIOENCODING=utf-8
OPS="texas lappland mizuki skadi hoshiguma saria"
for op in $OPS; do
    if [ -f "build/cloud/tx-diag/op_${op}.done" ]; then
        continue
    fi
    python3 -u tools/probes/melee_diag.py --game game --ops "$op" --seeds 8 --t 300 --jobs "$GODOT_MAX_PROCS" --label main --out "build/cloud/tx-diag/op_${op}.json" > "build/cloud/tx-diag/op_${op}.log" 2>&1
    echo $? > "build/cloud/tx-diag/op_${op}.done"
done
# 全部 op 完成：拼 main.log / main.json
cat build/cloud/tx-diag/op_*.log > build/cloud/tx-diag/main.log
python3 -u -c "
import json, glob
summary = {}
runs = {}
for p in sorted(glob.glob('build/cloud/tx-diag/op_*.json')):
    d = json.load(open(p, encoding='utf-8'))
    summary.update(d['summary'])
    runs.update(d['runs'])
json.dump({'label': 'main', 'summary': summary, 'runs': runs}, open('build/cloud/tx-diag/main.json', 'w', encoding='utf-8'), ensure_ascii=False)
"
echo 0 > build/cloud/tx-diag/main.flag
