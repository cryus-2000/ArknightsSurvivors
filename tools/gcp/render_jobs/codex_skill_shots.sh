# 图鉴技能页「点一行展开全文」截图（11-07）：桌面 1920×1080 + 触屏手机比例 1560×720（--touch），展开前 / 展开后各一张。
# 用法：python tools/gcp_render.py --branch <提交> --job codex_skill_shots --name <名>
#   可选变量：OP=干员 id（缺省 gladiia）、ROWS=要展开的行号逗号表（缺省 0,3,5）
# 结果：$MEDIA/<desk|phone>_<none|rowN>.png
set +e
OP="${OP:-gladiia}"
ROWS="${ROWS:-0,3,5}"
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
shot() {   # $1 名  $2 分辨率  $3 附加参数
    d=$(mktemp -d); ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
    XDG_DATA_HOME=$ud timeout 300 "$GODOT" --audio-driver Dummy --resolution "$2" --position 0,0 --path game -- \
        --unlockall --galleryshot=0,0,0,1.5 --galleryid=$OP --infotab=2 --shotdir="$d" $3 > "$OUT/$1.log" 2>&1
    cp "$d/shot_gallery_ui.png" "$MEDIA/$1.png" 2>/dev/null
    echo "$1：$(ls $MEDIA/$1.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$1.log) 处脚本错误"
}
for v in "desk:1920x1080:" "phone:1560x720:--touch"; do
    IFS=: read -r name res flag <<< "$v"
    shot "${name}_none" "$res" "$flag"
    for r in ${ROWS//,/ }; do
        shot "${name}_row$r" "$res" "$flag --galleryrow=$r"
    done
done
# 相关快检项（docs/36）：图鉴输入 / 界面冒烟 / 触屏版式 / 卡面说明
for t in codex ui_smoke touch_layout card_desc; do
    timeout 900 python3 tools/check.py --only $t --jobs 4 > "$OUT/check_$t.txt" 2>&1
    echo "check $t rc=$?"; tail -6 "$OUT/check_$t.txt"
done
exit 0
