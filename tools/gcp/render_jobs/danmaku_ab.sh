# Boss 弹幕第二版新旧对照录像（docs/302 §8）：同一提交、同 seed，render/danmaku_v2 = 0（旧）/ 1（新）各录一遍，左右拼成一段 mp4（30 帧原速）。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --split --cmd 'SPEC=carmen MOVES=环射,环射,环射 bash tools/gcp/render_jobs/danmaku_ab.sh' …
#   SPEC = --bossmoves 参数（二阶段加 2）；MOVES = --bossonly（重复几次，录满 SECS 秒）；SECS 缺省 7
# 结果：$MEDIA/ab_<SPEC>.mp4（左旧右新，各取画面中央 1280×720 原像素，不缩放）+ $MEDIA/<SPEC>_<old|new>_still.png（第 150 帧）
set +e
SECS="${SECS:-7}"
N=$((SECS * 30))
python3 tools/asset_index.py >/dev/null 2>&1
for v in old new; do
    d="$(realpath -m "$OUT/${SPEC}_$v")"; mkdir -p "$d"
    k=1; [ "$v" = old ] && k=0
    ud=$(mktemp -d); mkdir -p "$ud/ArknightsSurvivors"; printf '[game]\ndmg_numbers=true\n' > "$ud/ArknightsSurvivors/settings.cfg"
    XDG_DATA_HOME=$ud timeout -k 30 1500 "$GODOT" --audio-driver Dummy --resolution 1920x1080 --position 0,0 --fixed-fps 30 --path game -- \
        --balance --realtime --nodeath --seed=3 --op=mizuki --bossmoves="$SPEC" --bossonly="$MOVES" --flashrec=151.0,$N,1920 \
        --bal=render/danmaku_v2=$k --shotdir="$d" > "$d/run.log" 2>&1
    echo "$SPEC $v：$(ls $d/fr_*.png 2>/dev/null | wc -l) 帧；$(grep -c 'SCRIPT ERROR\|Parse Error' $d/run.log) 处脚本错误"
    cp "$d/fr_00150.png" "$MEDIA/${SPEC}_${v}_still.png" 2>/dev/null
done
FONT="${CJK_FONT:-/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc}"
ffmpeg -loglevel error -y -framerate 30 -i "$OUT/${SPEC}_old/fr_%05d.png" -framerate 30 -i "$OUT/${SPEC}_new/fr_%05d.png" \
    -filter_complex "[0:v]crop=1280:720:320:180,drawtext=fontfile=$FONT:text='现在':x=20:y=16:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.5[a];[1:v]crop=1280:720:320:180,drawtext=fontfile=$FONT:text='新版':x=20:y=16:fontsize=34:fontcolor=white:box=1:boxcolor=black@0.5[b];[a][b]hstack=inputs=2" \
    -c:v libx264 -pix_fmt yuv420p -crf 18 -r 30 "$MEDIA/ab_${SPEC}.mp4"
ls -la "$MEDIA"
exit 0
