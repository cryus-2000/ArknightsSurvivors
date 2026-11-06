# 能天使「对空优先」改版对照（docs/297）：图鉴演示精零普攻 + 成长节点 1，exu_prefer 0 / 1 / 2 × 有控制（演示每 2 秒眩晕最近 3 只）/ 无控制，
# 30 帧连拍（--fixed-fps 30，原速），每段 7 秒；本机再拼成三栏 mp4
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/exu_pf_rec.sh'
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
run() {   # $1 场景 ctrl|noctrl  $2 模式 0|1|2
    d="$(realpath -m "$OUT/$1_m$2")"; mkdir -p "$d"
    x=""; [ "$1" = noctrl ] && x="--nodemoctrl"
    timeout -k 30 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=exusiai --shot_stage=0 --shot_mode=3 --shot_nodes=1 --shot_dir="$d" --shot_start=2.0 --shot_every=1 --shot_n=${N:-210} --shot_w=960 --shot_h=540 --quality=high \
        --bal=growth_nodes/exu_prefer=$2 $x > "$d.log" 2>&1
    echo "$1 m$2 rc=$? $(ls $d/f_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
up() { ( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots.tar.gz -T - ) && gcloud storage cp /work/shots.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传（$1）" | tee "$OUT/shots.txt"; }
for s in ctrl noctrl; do
    for m in ${MODES:-0 1 2 3}; do run $s $m; done
    up $s
done
exit 0
