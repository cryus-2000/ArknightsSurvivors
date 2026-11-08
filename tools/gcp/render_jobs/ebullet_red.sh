# 杂兵弹改红对照截图（11-08 用户 iPhone 实测：敌弹青蓝与海嗣本体混在一起）：同一提交、同 seed，按 V 变体改 optical_col_ebullet_h / _s。
# 用法（每个变体一台）：python tools/gcp_render.py --branch <提交> --job custom --split --name ebred \
#   --cmd 'V=cur bash tools/gcp/render_jobs/ebullet_red.sh' --cmd 'V=r00 bash ...' --cmd 'V=r02 bash ...'
# 变体：cur = 现状青蓝 0.54 / 0.8；r00 = 正红 0.0 / 0.9；r02 = 红偏橙 0.02 / 0.9（红档神经弹换色下限 170，整颗换色）
# 场景（--touch 1560×720 手机比例，opengl3 = 兼容渲染器同网页一样无 HDR，--quality=medium 同用户 iPhone）：
#   mid 5:00 / late 8:00 / boss 3:10（+ 中期 Boss 卡门，专属暖色弹同屏）；都用 --flashring 在队长周围刷一圈远程杂兵保证画面有足够敌弹；
#   我方红色系特效：维什戴尔 / 艾雅法拉 / 能天使；30 帧实时每 15 帧留一张
# 结果：$MEDIA/<V>_<mid|late|boss>/fr_*.png
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
case "$V" in
    cur) B="" ;;
    r00) B="--bal=render/optical_col_ebullet_h=0.0 --bal=render/optical_col_ebullet_s=0.9 --bal=render/ebullet_recolor_lo_nerve=170" ;;
    r02) B="--bal=render/optical_col_ebullet_h=0.02 --bal=render/optical_col_ebullet_s=0.9 --bal=render/ebullet_recolor_lo_nerve=170" ;;
esac
SQ="--op=mizuki --squad=wisadel,eyjafjalla,exusiai"
RING="--flashring=stone:6,floater:5,skimmer:3,spitter:2"
ud() { u=$(mktemp -d); mkdir -p "$u/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$u/ArknightsSurvivors/settings.cfg"; echo "$u"; }
run() {   # $1 场景名 $2 快进到（秒） $3 其他参数
    d="$(realpath -m "$MEDIA/${V}_$1")"; mkdir -p "$d"
    t1=$(python3 -c "print($2 + 2.0)")
    t9=$(python3 -c "print($2 + 7)")
    XDG_DATA_HOME=$(ud) timeout -k 30 3000 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1560x720 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=11 $SQ --quality=medium --prog=${PROG:-12} --bot=master --touch --rtfrom=$2 --bal=command/bot_point=0 \
        --flashrec=$t1,120,1560 --maxt=$t9 --shotdir="$d" $B $3 > "$OUT/${V}_$1.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 15 != 1' | xargs -r rm -f
    echo "$V $1 $(ls $d/fr_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $OUT/${V}_$1.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
run mid 300 "$RING" & run late 480 "$RING" & run boss 190 "$RING --flashspawn=carmen" & wait
du -sh "$MEDIA"
exit 0
