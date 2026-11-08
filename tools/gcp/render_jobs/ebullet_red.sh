# 杂兵弹改红对照截图（11-08 用户 iPhone 实测：敌弹青蓝与海嗣本体混在一起）：同一提交、同 seed，按 V 变体改 optical_col_ebullet_h / _s。
# 用法（每个变体一台）：python tools/gcp_render.py --branch <提交> --job custom --split --name ebred \
#   --cmd 'V=cur bash tools/gcp/render_jobs/ebullet_red.sh' --cmd 'V=r00 bash ...' --cmd 'V=r02 bash ...'
# 变体：cur = 现状青蓝 0.54 / 0.8；r00 = 正红 0.0 / 0.9；r02 = 红偏橙 0.02 / 0.9
# 场景（--touch 1560×720 手机比例，opengl3 = 兼容渲染器同网页一样无 HDR，--quality=medium 同用户 iPhone）：
#   late：四人局 4:00–9:00 定时截图（多怪 + 攻击预警 + 我方红色系特效：维什戴尔 / 艾雅法拉 / 能天使）
#   boss：3:10 刷中期 Boss 卡门（专属暖色弹同屏），30 帧实时每 15 帧留一张
# 结果：$MEDIA/<V>_<late|boss>/*.png
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
case "$V" in
    cur) B="" ;;
    r00) B="--bal=render/optical_col_ebullet_h=0.0 --bal=render/optical_col_ebullet_s=0.9" ;;
    r02) B="--bal=render/optical_col_ebullet_h=0.02 --bal=render/optical_col_ebullet_s=0.9" ;;
esac
SQ="--op=mizuki --squad=wisadel,eyjafjalla,exusiai"
SPF=0.0659
FR=$(python3 -c "print(','.join(str(int(round(t/$SPF))) for t in (${TIMES:-240,330,420,480,540})))")
ud() { u=$(mktemp -d); mkdir -p "$u/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$u/ArknightsSurvivors/settings.cfg"; echo "$u"; }
late() {
    d="$(realpath -m "$MEDIA/${V}_late")"; mkdir -p "$d"
    XDG_DATA_HOME=$(ud) timeout -k 30 6000 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1560x720 --position 0,0 --fixed-fps 60 --path game -- \
        --balance --nodeath --seed=11 --slot4 $SQ --quality=medium --prog=20 --maxt=545 --touch --shots=$FR --shotdir="$d" $B > "$OUT/${V}_late.log" 2>&1
    echo "$V late rc=$? $(ls $d/shot_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $OUT/${V}_late.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
boss() {
    d="$(realpath -m "$MEDIA/${V}_boss")"; mkdir -p "$d"
    XDG_DATA_HOME=$(ud) timeout -k 30 1500 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1560x720 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 $SQ --quality=medium --prog=6 --bot=master --touch --rtfrom=190 --flashspawn=carmen --bal=command/bot_point=0 \
        --flashrec=192.0,120,1560 --maxt=197 --shotdir="$d" $B > "$OUT/${V}_boss.log" 2>&1
    ls "$d"/fr_*.png 2>/dev/null | awk 'NR % 15 != 1' | xargs -r rm -f
    echo "$V boss rc=$? $(ls $d/fr_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $OUT/${V}_boss.log) 处脚本错误" | tee -a "$OUT/runs.txt"
}
late & boss & wait
du -sh "$MEDIA"
exit 0
