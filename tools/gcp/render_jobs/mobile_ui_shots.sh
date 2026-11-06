# 手机触屏界面对照（11-06 用户「手机版图鉴卡片重叠、局内右上角属性没标、右上角偏小」）：
# 图鉴干员页（选中歌蕾蒂娅 / 第二行）+ 局内 HUD（--touch 1560×720），被测提交 cur + 基线 BASE 各一套，PNG 放 $MEDIA/<cur|base>/
# 用法：python tools/gcp_render.py --branch <提交> --job custom --cmd 'BASE=<提交> bash tools/gcp/render_jobs/mobile_ui_shots.sh'
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
shoot() {   # $1 = game 目录  $2 = 输出目录
    d="$(realpath -m "$2")"; mkdir -p "$d"
    for res in 1560x720 1280x720; do
        for id in gladiia mizuki; do
            g="$d/gal_${res}_$id"; mkdir -p "$g"
            timeout 300 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution "$res" --position 0,0 --path "$1" -- \
                --galleryshot=0,0,0,1.5 --galleryid=$id --touch --shotdir="$g" > "$g.log" 2>&1
            mv "$g/shot_gallery_ui.png" "$d/gallery_${res}_$id.png" 2>/dev/null
        done
    done
    h="$d/hud"; mkdir -p "$h"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
    XDG_DATA_HOME=$ud timeout 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1560x720 --position 0,0 --fixed-fps 30 --path "$1" -- \
        --balance --seed=3 --op=mizuki --squad=skadi,saria --bot=expert --nodeath --maxt=80 --shots=450,1800 --shotdir="$h" --touch > "$h.log" 2>&1
    echo "$2: $(find $d -name '*.png' | wc -l) 张；$(cat $d/*.log | grep -c 'SCRIPT ERROR\|Parse Error') 处脚本错误" | tee -a "$OUT/runs.txt"
    grep -h -m3 -A3 "SCRIPT ERROR\|Parse Error" $d/*.log | tee -a "$OUT/runs.txt"
}
shoot game "$MEDIA/cur"
if [ -n "${BASE:-}" ]; then
    git fetch -q --depth 1 origin "$BASE" && git worktree add -q --detach /work/base FETCH_HEAD
    ( cd /work/base && python3 tools/asset_index.py >/dev/null 2>&1; "$GODOT" --headless --path game --import >/dev/null 2>&1 )
    shoot /work/base/game "$MEDIA/base"
fi
exit 0
