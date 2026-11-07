# 灯标驱散环修前 / 修后同帧（11-08 iPhone「粗白椭圆圈」）：--vfxdemo 第 20 秒在主控旁点燃灯标，从 20.0 秒起逐帧截 24 张（30 帧 / 秒）。
# old = --bal=beacon/sweep_px=0（旧 HDR 平滑线），new = 1。中画质；另跑一套 --lookdbg=nobloom 近似网页（无辉光）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/beacon_sweep_ab.sh'
set +e
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
run() {   # $1 名  $2 sweep_px  $3 附加
    d="$(realpath -m "$OUT/$1")"; mkdir -p "$d"
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 900 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 --op=wisadel --squad=angelina --bot=master --quality=medium --vfxdemo \
        --shotdir="$d" --flashrec=19.95,24,1920 --maxt=22 --bal=beacon/sweep_px=$2 $3 > "$d/run.log" 2>&1
    echo "$1：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    for f in "$d"/fr_*.png; do cp "$f" "$MEDIA/$1_$(basename "$f")"; done
}
run old 0 "" & run new 1 "" & run old_nb 0 "--lookdbg=nobloom" & run new_nb 1 "--lookdbg=nobloom" &
wait
exit 0
