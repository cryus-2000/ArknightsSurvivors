# 寻访光效回归对照录像（11-08 iPhone Toy「寻访特效变少」）：在游戏副本上按发布包做 tools/web_half.py（WH=1），
# 重新导入后录单抽（定向）与十连，桌面 1280×720 / 手机横屏 1560×720（--touch --fxhalf = 手机网页读 @h）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'TAG=fixed WH=1 bash tools/gcp/render_jobs/hh_fx_rec.sh'
# 环境变量：WH（1 = 按发布包换 1 倍 / 出 @h；0 = 仓库原样，相当于 web_half 之前）、OLDHH（提交号：寻访脚本换回这版，录修前）、TAG、DEVS（缺省 "phone desktop"）
set +e
pgrep Xvfb >/dev/null || { Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 2; }
export DISPLAY=:99
mkdir -p "$MEDIA" "$OUT"
FF="$(command -v ffmpeg)"
if [ -z "$FF" ]; then
    pip3 install -q imageio-ffmpeg >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages imageio-ffmpeg >/dev/null 2>&1
    FF="$(python3 -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null)"
fi
TAG=${TAG:-new}; WH=${WH:-1}; DEVS=${DEVS:-"phone desktop"}
python3 tools/asset_index.py >/dev/null 2>&1
[ -n "$OLDHH" ] && git checkout "$OLDHH" -- game/scripts/screens/headhunt.gd
if [ "$WH" = "1" ]; then
    python3 -c "import sys; sys.path.insert(0,'tools'); import web_half; print(web_half.report(web_half.make('game')))" | tee -a "$OUT/runs.txt"
fi
"$GODOT" --headless --path game --import > "$OUT/import_${TAG}.log" 2>&1
for dev in $DEVS; do
  if [ "$dev" = "phone" ]; then RES=1560x720; EX="--touch"; [ "$WH" = "1" ] && EX="$EX --fxhalf"; else RES=1280x720; EX=""; fi
  for kind in one ten; do
    d="$(realpath -m "$OUT/fr_${TAG}_${dev}_${kind}")"; rm -rf "$d"; mkdir -p "$d"
    if [ "$kind" = "ten" ]; then KA="--huntten --rostertickets=10"; else KA="--rostertickets=5"; fi
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"
    XDG_DATA_HOME=$ud timeout -k 30 900 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution $RES --position 0,0 --fixed-fps 60 --path game -- \
        --autotest --huntshot --huntrec --roster=start5 $KA $EX --shotdir="$d" > "$d.log" 2>&1
    echo "$TAG $dev $kind：$(ls $d/rec_*.png 2>/dev/null | wc -l) 张；$(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误；$(grep -c 'ERROR' $d.log) 行 ERROR" | tee -a "$OUT/runs.txt"
    grep -m5 'ERROR' -A2 "$d.log" >> "$OUT/runs.txt"
    "$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$d/rec_*.png" -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -pix_fmt yuv420p -crf 18 "$MEDIA/hh_${TAG}_${dev}_${kind}.mp4" 2>>"$OUT/runs.txt"
  done
done
exit 0
