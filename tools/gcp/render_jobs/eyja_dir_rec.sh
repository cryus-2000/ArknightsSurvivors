# 艾雅法拉普攻朝向核对（11-06）：图鉴演示普攻 E0/E1/E2 × 抬升 0 / 缺省 × 调试线开 / 关，30 帧连拍（--fixed-fps 30，原速）
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/eyja_dir_rec.sh'
# 结果：$OUT/e<档>_<变体>/f_*.png 打包传 $GS/shots.tar.gz
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
run() {   # $1 档 $2 变体名 $3.. 参数
    t=$1; v=$2; shift 2
    d="$(realpath -m "$OUT/e${t}_$v")"; mkdir -p "$d"
    timeout -k 30 900 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=eyjafjalla --shot_stage=$t --shot_mode=3 --shot_dir="$d" --shot_start=1.0 --shot_every=1 --shot_n=105 --shot_w=1280 --shot_h=720 --quality=high "$@" > "$d.log" 2>&1
    echo "e$t $v rc=$? $(ls $d/f_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
for t in 0 1 2; do
    run $t old --bal=fx/eyja_ball_lift=0 &
    run $t new &
    run $t old_dbg --bal=fx/eyja_ball_lift=0 --balldbg &
    run $t new_dbg --balldbg &
    wait
done
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots.tar.gz -T - ) && gcloud storage cp /work/shots.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传 $GS/shots.tar.gz" | tee "$OUT/shots.txt"
exit 0
