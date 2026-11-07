# itch 截图补拍（11-07 用户「加几个Boss的画面和选卡的画面」）：tools/promo_shots.gd 监视真实步长整局，
# Boss 出招 / 预警、圣徒出招、泡影破壳、骑士破绽、升级三选一、藏品选择时截图（1920×1080 高画质，带 HUD）。
# 用法：python tools/gcp_render.py --branch HEAD --job itch_shots2 --name <名>
# 结果：$MEDIA/<队>/<类>_<帧>_s<分>_t<秒>.png
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
run() {   # $1 名 $2 种子 $3 队长 $4 队友
    d="$(realpath -m "$MEDIA/$1")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n[video]\nquality="high"\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 3000 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 60 --path game \
        -s "$(pwd)/tools/promo_shots.gd" -- \
        --balance --realtime --nodeath --seed=$2 --op=$3 --slot4 --squad=$4 --prog=6 --bot=master --diff=4 \
        --promo_out="$d" --promo_maxt=640 --promo_only=boss_warn,saint,hatch,stake,levelup,relic > "$OUT/$1.log" 2>&1
    echo "$1：$(ls $d/*.png 2>/dev/null | wc -l) 张（$(ls $d 2>/dev/null | cut -d_ -f1 | sort | uniq -c | tr '\n' ' ')）；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$1.log) 处脚本错误"
}
run deep 3 mizuki skadi,gladiia,specter_unchained &
run rhodes 5 kaltsit exusiai,wisadel,logos &
wait
run abyss 21 skalter suzuran,eyjafjalla,angelina &
run lungmen 11 texas lappland,hoshiguma,irene &
wait
exit 0
