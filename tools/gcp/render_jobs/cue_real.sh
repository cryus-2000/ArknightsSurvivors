# 成长节点提示的实机局对照（docs/310 §8：图鉴里触发不到的倒钩 / 共鸣 / 澄明 / 技力光点）：同 seed 一局 node_cue 关 / 开各跑一遍，
# T0–T1 秒每 STEP 帧截一张，tools/cue_real_sheet.py 挑差最大的帧裁 1 倍小块拼图。
# 用法（每条一台）：python tools/gcp_render.py --branch <提交> --job custom --split --name <名> \
#   --cmd 'NAME=gl SQ="--op=gladiia --squad=skalter,lumen,texas" bash tools/gcp/render_jobs/cue_real.sh'
# 可选：LAG（触发后再往后几张截图，缺省 0）SEED（缺省 11）T0 / T1（秒，缺省 40 / 160）STEP（帧，缺省 2）EXTRA（追加参数，如 --route=wisadel:mark）
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
SPF=0.0659
FR=$(python3 -c "print(','.join(str(f) for f in range(int(${T0:-40}/$SPF), int(${T1:-160}/$SPF), ${STEP:-2})))")
run() {
    d="$(realpath -m "/tmp/cr/${NAME}_c$1")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
    XDG_DATA_HOME=$ud timeout -k 30 5000 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 60 --path game -- \
        --balance --nodeath --seed=${SEED:-11} --slot4 $SQ --quality=high --prog=${PROG:-6} --sptest --maxt=$(( ${T1:-160} + 5 )) --shots=$FR --shotdir="$d" --bal=fx/px_plane=1 --bal=fx/node_cue=$1 --cuelog $EXTRA > "$OUT/${NAME}_c$1.log" 2>&1
    echo "${NAME} cue=$1 rc=$? $(ls $d/*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $OUT/${NAME}_c$1.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
run 0 &
run 1 &
wait
python3 tools/cue_real_sheet.py "/tmp/cr/${NAME}_c0" "/tmp/cr/${NAME}_c1" "$MEDIA/real_${NAME}.png" --top ${TOP:-8} | tee -a "$OUT/runs.txt"
python3 tools/cue_real_tags.py "$OUT/${NAME}_c1.log" "/tmp/cr/${NAME}_c0" "/tmp/cr/${NAME}_c1" "$MEDIA" "$NAME" --lag ${LAG:-0} | tee -a "$OUT/runs.txt"
exit 0
