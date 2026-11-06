# 性能自检浮层（core/perf_hud.gd）截图：桌面 1280×720 + 触屏手机比例 1560×720（--touch），局内 15 / 40 秒各一张，外加标题页
# 用法：python tools/gcp_render.py --branch <提交> --job custom --cmd 'bash tools/gcp/render_jobs/perf_hud_shots.sh'
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
for v in "desk:1280x720:" "phone:1560x720:--touch"; do
    IFS=: read -r name res flag <<< "$v"
    d="$MEDIA/$name"; mkdir -p "$d"
    timeout 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution "$res" --position 0,0 --fixed-fps 30 --path game -- \
        --balance --seed=3 --op=mizuki --squad=skadi,saria --bot=expert --nodeath --maxt=50 --shots=450,1200 --shotdir="$d" --perfhud $flag > "$OUT/$name.log" 2>&1
    echo "$name: $(ls $d/*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $OUT/$name.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    grep -m5 -A4 "SCRIPT ERROR\|Parse Error" "$OUT/$name.log" | tee -a "$OUT/runs.txt"
done
cp game/scripts/core/perf_hud.gd.uid "$OUT/perf_hud_uid.txt" 2>/dev/null
exit 0
