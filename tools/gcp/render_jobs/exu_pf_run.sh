# 能天使「对空优先」改版实机对照（docs/298）：能天使当队长、成长节点 1（--prog=1），绕圈机器人、怪密度 1，
# exu_prefer 0 / 1 / 2 / 3 × 有控制队友（安洁莉娜 + 德克萨斯）/ 无控制队友（塞雷娅 + 铃兰），T 秒起原速 30 帧录 N 帧（1280 宽）
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/exu_pf_run.sh'
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
T=${T:-200}; N=${N:-240}
run() {   # $1 场景 ctrl|noctrl  $2 模式
    d="$(realpath -m "$OUT/$1_m$2")"; mkdir -p "$d"
    sq="saria,suzuran"; [ "$1" = ctrl ] && sq="angelina,texas"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=false\n[video]\nquality="high"\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 3300 "$GODOT" --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=${SEED:-5} --op=exusiai --squad=$sq --prog=1 --bot=circle --nohud --bal=enemy/density=1 --bal=growth_nodes/exu_prefer=$2 \
        --shotdir="$d" --rtfrom=$(( T - 4 )) --flashrec=$T,$N,1280 --maxt=$(( T + N / 30 + 4 )) > "$d.log" 2>&1
    rm -f "$d"/flashrec.csv
    echo "$1 m$2：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
up() { ( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots_$BASHPID.tar.gz -T - ) && gcloud storage cp /work/shots_$BASHPID.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传（$1）" | tee "$OUT/shots.txt"; }
# 一场一传：先录无控四档，再录有控四档（每档单独上传，超时也留得下已录的）
for s in noctrl ctrl; do
    for m in 0 1 2 3; do ( run $s $m; up "$s m$m" ) & done; wait
done
exit 0
