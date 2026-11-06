# 后期特效控制诊断（docs/289）：四人精二满节点局，8:00 / 10:00 前后各几帧截图，同一局按层 / 按人隐藏各跑一遍
# （--clutterdbg=nofriend / nofoe / noenemy / nolead / nomates / noop_<id>，代码照跑、随机数照抽），本机逐像素差出各层掩码。
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --machine e2-standard-16 --cmd 'bash tools/gcp/render_jobs/late_fx_diag.sh'
# 结果：$OUT/<阵容>_<层>/run.log + shot_*.json（--clutterlog：同屏条目数、按人帧条数）；PNG 打包传 $GS/shots.tar.gz
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
# 先用无头短局查编译错误（有就直接退出，不白跑一小时）
timeout 300 "$GODOT" --headless --audio-driver Dummy --path game -- --balance --seed=11 --op=logos --squad=texas --maxt=3 --clutterdbg=noop_texas > "$OUT/precheck.log" 2>&1
if grep -q "SCRIPT ERROR" "$OUT/precheck.log"; then echo "预检有脚本错误，见 precheck.log" | tee "$OUT/runs.txt"; exit 1; fi
SPF=0.0659   # --fixed-fps 60 非实时，约 0.0659 局内秒 / 帧（docs/243 §1.3 同口径）
FR=$(python3 -c "print(','.join(str(int(round(t/$SPF))) for t in (470,480,490,500,590,600,610,620)))")
declare -A LU
LU[A]="--op=logos --squad=texas,suzuran,eyjafjalla"
LU[B]="--op=mizuki --squad=skadi,wisadel,exusiai"
declare -A MATES
MATES[A]="texas suzuran eyjafjalla"
MATES[B]="skadi wisadel exusiai"
jobs=()
for lu in A B; do
    for ly in full nofriend nofoe noenemy nolead nomates; do jobs+=("$lu $ly"); done
    for m in ${MATES[$lu]}; do jobs+=("$lu noop_$m"); done
done
run() {   # $1 阵容 $2 层
    d="$(realpath -m "$OUT/$1_$2")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    dbg=""; [ "$2" != full ] && dbg="--clutterdbg=$2"
    XDG_DATA_HOME=$ud timeout -k 30 3600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 60 --path game -- \
        --balance --nodeath --seed=11 ${LU[$1]} --quality=high --prog=20 --maxt=625 --shots=$FR --clutterlog --shotdir="$d" $dbg > "$d/run.log" 2>&1
    echo "$1 $2 rc=$? $(ls $d/shot_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d/run.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
export -f run; export OUT GODOT FR
export LU_A="${LU[A]}" LU_B="${LU[B]}"
P=${GODOT_MAX_PROCS:-6}
i=0
for j in "${jobs[@]}"; do
    run $j &
    i=$((i + 1))
    if [ $((i % P)) -eq 0 ]; then wait; fi
done
wait
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots.tar.gz -T - ) && gcloud storage cp /work/shots.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传 $GS/shots.tar.gz" | tee "$OUT/shots.txt"
exit 0
