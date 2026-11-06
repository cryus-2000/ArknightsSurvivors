# 图鉴技能 / 成长页「点一行展开全文」截图（11-07）：桌面 1920×1080 + 触屏手机比例 1560×720（--touch），展开前 / 展开后。
# 用法：python tools/gcp_render.py --branch <提交> --job codex_skill_shots --name <名>
#   可选变量：OPS=干员 id 表（缺省 gladiia,specter_unchained）、BASE=<提交>（同参数在旧提交上拍「修前」一套到 $MEDIA/base_*）
# 结果：$MEDIA/<op>_<desk|phone>_<skill|growth>_<none|rowN>.png；$OUT/audit.txt（全部干员说明清点）；$OUT/check_*.txt
set +e
OPS="${OPS:-gladiia,specter_unchained}"
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
shot() {   # $1 game 目录  $2 输出名  $3 分辨率  $4 附加参数
    d=$(mktemp -d); ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
    XDG_DATA_HOME=$ud timeout 300 "$GODOT" --audio-driver Dummy --resolution "$3" --position 0,0 --path "$1" -- \
        --unlockall --galleryshot=0,0,0,1.5 --shotdir="$d" $4 > "$OUT/$2.log" 2>&1
    cp "$d/shot_gallery_ui.png" "$MEDIA/$2.png" 2>/dev/null
    echo "$2：$(ls $MEDIA/$2.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$2.log) 处脚本错误"
}
shoot_all() {   # $1 game 目录  $2 文件名前缀  $3 = 1 时拍展开后
    for op in ${OPS//,/ }; do
        for v in "desk:1920x1080:" "phone:1560x720:--touch"; do
            IFS=: read -r name res flag <<< "$v"
            shot "$1" "$2${op}_${name}_skill_none" "$res" "$flag --galleryid=$op --infotab=2"
            shot "$1" "$2${op}_${name}_growth_none" "$res" "$flag --galleryid=$op --infotab=3"
            if [ "$3" = 1 ]; then
                shot "$1" "$2${op}_${name}_skill_row3" "$res" "$flag --galleryid=$op --infotab=2 --galleryrow=3"
                shot "$1" "$2${op}_${name}_skill_row8" "$res" "$flag --galleryid=$op --infotab=2 --galleryrow=8"
                shot "$1" "$2${op}_${name}_growth_row3" "$res" "$flag --galleryid=$op --infotab=3 --galleryrow=3"
            fi
        done
    done
}
shoot_all game "" 1
"$GODOT" --headless --audio-driver Dummy --path game -s "$(pwd)/tools/probes/codex_desc_audit.gd" > "$OUT/audit.txt" 2>&1
echo "audit：$(grep -c '^AUDIT ' $OUT/audit.txt) 行；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/audit.txt) 处脚本错误"
if [ -n "${BASE:-}" ]; then
    git fetch -q --depth 1 origin "$BASE" && git worktree add -q --detach /work/base FETCH_HEAD
    ( cd /work/base && python3 tools/asset_index.py >/dev/null 2>&1; "$GODOT" --headless --path game --import >/dev/null 2>&1 )
    shoot_all /work/base/game "base_" 0
fi
# 相关快检项（docs/36）：图鉴输入 / 界面冒烟 / 触屏版式 / 卡面说明
for t in codex ui_smoke touch_layout card_desc; do
    timeout 900 python3 tools/check.py --only $t --jobs 4 > "$OUT/check_$t.txt" 2>&1
    echo "check $t rc=$?"; tail -6 "$OUT/check_$t.txt"
done
exit 0
