# itch 截图位换新（11-07 用户「itch上面截图也该换一批了」）：1920×1080 高画质，带 HUD（玩家实际看到的画面）。
# 用法：python tools/gcp_render.py --branch HEAD --job itch_shots --name <名>
#   可选（--args）：STEP=间隔帧（缺省 450 = 15 秒，--fixed-fps 30）、FROM / TO=起止帧
# 结果：$MEDIA/run_<队>/shot_<帧>.png（四支小队各一局）、$MEDIA/choice/shot_choice_<n>.png（升级 / 藏品三选一）、
#       $MEDIA/ui/shot_<title|op|gallery|win>.png
set +e
[ -n "${RENDER_ARGS:-}" ] && eval "$RENDER_ARGS"
STEP="${STEP:-450}"; FROM="${FROM:-1800}"; TO="${TO:-18000}"
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
FR=$(seq -s, "$FROM" "$STEP" "$TO")
udir() { ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n[video]\nquality="high"\n' > "$ud/ArknightsSurvivors/settings.cfg"; echo "$ud"; }
game() {   # $1 名 $2 输出目录 $3 超时 $4… 游戏参数
    n=$1; d="$(realpath -m "$2")"; t=$3; shift 3; mkdir -p "$d"
    XDG_DATA_HOME=$(udir) timeout -k 30 "$t" "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --shotdir="$d" "$@" > "$OUT/$n.log" 2>&1
    echo "$n：$(ls $d/*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$n.log) 处脚本错误"
}
run() {   # $1 队名 $2 种子 $3 队长 $4 队友
    game "run_$1" "$MEDIA/run_$1" 2400 --balance --nodeath --seed=$2 --op=$3 --slot4 --squad=$4 --prog=6 --bot=master \
        --maxt=$(( TO / 30 + 5 )) --shots="$FR"
}
run deep 3 mizuki skadi,gladiia,specter_unchained &
run rhodes 5 kaltsit exusiai,wisadel,logos &
wait
run abyss 7 skalter suzuran,eyjafjalla,angelina &
run lungmen 11 texas lappland,hoshiguma,irene &
wait
game choice "$MEDIA/choice" 900 --balance --nodeath --seed=3 --op=mizuki --squad=skadi,saria --bot=master --maxt=240 --choiceshots &
game ui_title "$MEDIA/ui" 120 --titleshot &
wait
game ui_op "$MEDIA/ui" 120 --opshot --opid=mizuki &
game ui_gallery "$MEDIA/ui" 120 --unlockall --galleryshot=0,0,0,1.5 --galleryid=skadi --infotab=0 &
wait
game ui_win "$MEDIA/ui" 300 --balance --seed=3 --op=mizuki --squad=skadi,saria --winshot=deep
ls "$MEDIA"/ui
exit 0
