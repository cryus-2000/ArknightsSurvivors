# 局内指挥台截图（桌面 1920×1080 + 触屏手机比例 1560×720，--touch）：被测提交 + 可选基线（BASE=<提交>）各一套，前后对照。
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'bash tools/gcp/render_jobs/hud_shots.sh'
#   可选变量：BASE=<完整提交号>（同样参数再拍一套到 $OUT/base/）、FRAMES=帧号逗号表（--fixed-fps 30）、EXTRA=附加参数
# 结果：$OUT/<cur|base>/<desk|phone>/shot_<帧>.png
set +e
FRAMES="${FRAMES:-450,1800,4500,7200}"
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
shoot() {   # $1 = game 目录  $2 = 输出目录
    for v in "desk:1920x1080:" "phone:1560x720:--touch"; do
        IFS=: read -r name res flag <<< "$v"
        d="$2/$name"; mkdir -p "$d"
        ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
        printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
        XDG_DATA_HOME=$ud timeout 900 "$GODOT" --audio-driver Dummy --resolution "$res" --position 0,0 --fixed-fps 30 --path "$1" -- \
            --balance --seed=3 --op=mizuki --squad=skadi,saria --bot=expert --nodeath --maxt=260 \
            --shots="$FRAMES" --shotdir="$d" $flag $EXTRA > "$d/run.log" 2>&1
        echo "$name: $(ls $d/*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误"
    done
}
shoot game "$OUT/cur"
if [ -n "${BASE:-}" ]; then
    git fetch -q --depth 1 origin "$BASE" && git worktree add -q --detach /work/base FETCH_HEAD
    ( cd /work/base && python3 tools/asset_index.py >/dev/null 2>&1; "$GODOT" --headless --path game --import >/dev/null 2>&1 )
    shoot /work/base/game "$OUT/base"
fi
exit 0
