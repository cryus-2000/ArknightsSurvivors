# 博士帧条局内验收录像（11-08，Codex 原生 @2x 待机 / 跑步接入）：--bot=walk 走走停停，博士跟着队长跑 / 停，
# --realtime --fixed-fps 30 逐帧截图 → 30 帧原速 mp4；另出一份画面中心 2 倍最近邻放大版（看清博士）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/doctor_walk_rec.sh'
# 环境变量：OP（缺省 lappland）、SQUAD（缺省 skadi）、T0（缺省 6）、NF（缺省 480 帧 = 16 秒）、TAG（文件名后缀，缺省 new）
set +e
pgrep Xvfb >/dev/null || { Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 2; }
export DISPLAY=:99
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA" "$OUT"
FF="$(command -v ffmpeg)"
if [ -z "$FF" ]; then
    pip3 install -q imageio-ffmpeg >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages imageio-ffmpeg >/dev/null 2>&1
    FF="$(python3 -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null)"
fi
T0=${T0:-6}; NF=${NF:-480}; TAG=${TAG:-new}
d="$(realpath -m "$OUT/frames")"; rm -rf "$d"; mkdir -p "$d"
ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
XDG_DATA_HOME=$ud timeout -k 30 1200 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
    --balance --realtime --nodeath --seed=${SEED:-3} --op=${OP:-lappland} --squad=${SQUAD:-skadi} --bot=walk --quality=high \
    --shotdir="$d" --rtfrom=$T0 --flashrec=$T0,$NF,1920 --maxt=$((T0 + NF / 30 + 2)) > "$d.log" 2>&1
echo "录像：$(ls $d/fr_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
grep -m5 'SCRIPT ERROR' -A3 "$d.log" >> "$OUT/runs.txt"
"$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$d/fr_*.png" -c:v libx264 -pix_fmt yuv420p -crf 18 "$MEDIA/doctor_walk_${TAG}.mp4" 2>>"$OUT/runs.txt"
"$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$d/fr_*.png" -vf "crop=960:540:480:270,scale=1920:1080:flags=neighbor" -c:v libx264 -pix_fmt yuv420p -crf 16 "$MEDIA/doctor_walk_${TAG}_x2.mp4" 2>>"$OUT/runs.txt"
f=$(ls "$d"/fr_*.png | sed -n "$((NF / 4))p"); [ -n "$f" ] && cp "$f" "$MEDIA/still_${TAG}.png"
exit 0
