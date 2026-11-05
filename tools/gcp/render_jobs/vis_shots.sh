# 磁铁 / 中期 Boss 看得见（docs/283、284）的实机截图：同一提交、同 seed，「新」（缺省）与「旧」（开关关掉）各一套。
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/vis_shots.sh'
# 场景：3:10 起。mag 用 --flashdrop 在主控旁 / 屏外各放一个磁铁；carmen / bishop / path 刷中期 Boss，command/bot_point=0 关掉机器人自动集火（否则锁定框让位给集火框）。云端软件渲染很慢（11-06 两次超时），本机跑每场景约 40 秒
# 结果：$OUT/<场景>_<new|old>/fr_*.png（每 10 帧留一张）打包传 $GS/shots.tar.gz；run.log 留在 $OUT
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
OFF="--bal=render/magnet_v2=0 --bal=render/mid_boss_scale=1 --bal=render/mid_boss_scale_path=1 --bal=render/boss_mark=0"
declare -A SC
SC[mag]="--rtfrom=190 --flashdrop --flashrec=190.1,60,1280 --maxt=193"
SC[carmen]="--rtfrom=190 --flashspawn=carmen --bal=command/bot_point=0 --flashrec=190.2,60,1280 --maxt=193"
SC[bishop]="--rtfrom=190 --flashspawn=bishop --bal=command/bot_point=0 --flashrec=190.2,60,1280 --maxt=193"
SC[path]="--rtfrom=190 --flashspawn=path --bal=command/bot_point=0 --flashrec=190.2,60,1280 --maxt=193"
run() {   # $1 场景 $2 new|old
    d="$(realpath -m "$OUT/$1_$2")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    extra=""; [ "$2" = old ] && extra="$OFF"
    XDG_DATA_HOME=$ud timeout -k 30 900 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 --op=mizuki --squad=skadi,saria,texas,exusiai,eyjafjalla --prog=6 --bot=master \
        --shotdir="$d" ${SC[$1]} $extra > "$d/run.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 10 != 1' | xargs -r rm -f
    echo "$1 $2：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误"
}
for s in mag carmen bishop path; do run $s new & run $s old & wait; done
GS="$(curl -s -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/batch-gs)"
( cd "$OUT" && find . -name '*.png' | tar -czf /work/shots.tar.gz -T - ) && gcloud storage cp /work/shots.tar.gz "$GS/shots.tar.gz" -q && echo "截图已传 $GS/shots.tar.gz" | tee "$OUT/shots.txt"
exit 0
