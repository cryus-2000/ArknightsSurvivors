# 磁铁 / 中期 Boss 看得见（docs/283、284）的实机截图：同一提交、同 seed，「新」（缺省）与「旧」（开关关掉）各一套。
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/vis_shots.sh'
# 场景（参数同 tools/design_shots_1106.py）：mag 8 分钟后期局、磁铁掉率调高；carmen 7:00 前主控旁刷圣徒卡门；bishop 3:30 前刷主教。
# 结果：$OUT/<场景>_<new|old>/fr_*.png（每 15 帧留一张）打包传 $GS/shots.tar.gz；run.log 留在 $OUT
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
OFF="--bal=render/magnet_v2=0 --bal=render/mid_boss_scale=1 --bal=render/mid_boss_scale_path=1 --bal=render/boss_mark=0"
declare -A SC
SC[mag]="--rtfrom=470 --flashrec=472,150,1280 --maxt=480 --bal=pickup/magnet_kill_chance=0.2 --bal=pickup/elite_magnet_share=1.0"
SC[carmen]="--rtfrom=400 --flashspawn=carmen --flashrec=402,150,1280 --maxt=410"
SC[bishop]="--rtfrom=190 --flashspawn=bishop --flashrec=192,150,1280 --maxt=200"
SC[path]="--rtfrom=190 --flashspawn=path --flashrec=192,150,1280 --maxt=200"
run() {   # $1 场景 $2 new|old
    d="$(realpath -m "$OUT/$1_$2")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    extra=""; [ "$2" = old ] && extra="$OFF"
    XDG_DATA_HOME=$ud timeout 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 --op=mizuki --squad=skadi,saria,texas,exusiai,eyjafjalla --prog=6 --bot=master \
        --shotdir="$d" ${SC[$1]} $extra > "$d/run.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 15 != 1' | xargs -r rm -f
    echo "$1 $2：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误"
}
for s in mag carmen bishop path; do run $s new & run $s old & wait; done
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots.tar.gz -T - ) && gcloud storage cp /work/shots.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传 $GS/shots.tar.gz" | tee "$OUT/shots.txt"
exit 0
