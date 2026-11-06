# 封面实机截图第二轮：怪密度 1（原行为）+ 绕圈机器人，让怪群围上来（cover_shots.sh 的高手机器人清得太快）
# 用法：python tools/gcp_render.py --branch HEAD --job cover_shots --name cover1107
# 结果：$MEDIA/<场景>/fr_*.png（每 6 帧留一张）
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
SQUAD="${COVER_SQUAD:-skadi,gladiia,specter_unchained,ulpianus}"
run() {   # $1 场景名 $2 起始秒
    d="$(realpath -m "$MEDIA/$1")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=false\n[video]\nquality="high"\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 --op=mizuki --slot4 --squad=$SQUAD --prog=6 --bot=circle --nohud --bal=enemy/density=1 \
        --shotdir="$d" --rtfrom=$(( $2 - 4 )) --flashrec=$2,120,1920 --maxt=$(( $2 + 6 )) > "$OUT/$1.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 6 != 1' | xargs -r rm -f
    rm -f "$d"/flashrec.csv
    echo "$1：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$1.log) 处脚本错误"
}
run h300 300 & run h360 360 & wait
run h450 450 & run h560 560 & wait
exit 0
