# itch 截图补拍 Boss（11-07 用户「加几个Boss的画面」）：itch_shots2 真实步长整局在云端软件渲染太慢、只跑到 2:30 没见 Boss，
# 改按 vis_shots.sh 的办法：批跑快进到 6:40，--flashspawn 在队长旁刷 Boss，之后真实步长 + --flashrec 全尺寸逐帧存、每 15 帧留一张。
# 用法：python tools/gcp_render.py --branch HEAD --job itch_boss_shots --name <名>
# 结果：$MEDIA/<Boss>_<队>/fr_*.png（1920×1080，带 HUD）
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
run() {   # $1 Boss $2 队名 $3 种子 $4 队长 $5 队友
    d="$(realpath -m "$MEDIA/$1_$2")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n[video]\nquality="high"\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=$3 --op=$4 --slot4 --squad=$5 --prog=6 --bot=master \
        --shotdir="$d" --rtfrom=400 --flashspawn=$1 --flashrec=403,240,1920 --maxt=412 > "$OUT/$1_$2.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 15 != 1' | xargs -r rm -f
    echo "$1 $2：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$1_$2.log) 处脚本错误"
}
run izumik deep 3 mizuki skadi,gladiia,specter_unchained &
run knight_boss rhodes 5 kaltsit exusiai,wisadel,logos &
wait
run paranoia abyss 7 skalter suzuran,eyjafjalla,angelina &
run ishar lungmen 11 texas lappland,hoshiguma,irene &
wait
run carmen deep 3 mizuki skadi,gladiia,specter_unchained &
run bishop lungmen 11 texas lappland,hoshiguma,irene &
wait
exit 0
