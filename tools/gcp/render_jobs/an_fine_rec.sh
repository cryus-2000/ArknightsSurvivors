# 安洁莉娜终结技精细版新旧对照（11-06）：图鉴演示终结技（精二、mode 4）30 帧原速连拍，旧 = --bal=ult/an_fine=0，新 = 缺省；
# 两段拼成一个 mp4（左上标「旧版 / 精细版」），放 $MEDIA/angelina_ult_old_new.mp4
# 用法：python tools/gcp_render.py --branch <提交> --job custom --cmd 'bash tools/gcp/render_jobs/an_fine_rec.sh'
set +e
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
run() {   # $1 变体名 $2.. 参数
    v=$1; shift
    d="$(realpath -m "$OUT/$v")"; mkdir -p "$d"
    timeout -k 30 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=angelina --shot_stage=2 --shot_mode=4 --shot_dir="$d" --shot_start=0.8 --shot_every=1 --shot_n=180 --shot_w=1280 --shot_h=720 --quality=high "$@" > "$d.log" 2>&1
    echo "$v rc=$? $(ls $d/f_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    grep -m3 -A3 "SCRIPT ERROR" "$d.log" | tee -a "$OUT/runs.txt"
}
run old --bal=ult/an_fine=0
run new
FONT=$(fc-list :lang=zh -f '%{file}\n' | head -1)
for v in old new; do
    lab="旧版"; [ "$v" = new ] && lab="精细版"
    ffmpeg -v error -y -framerate 30 -pattern_type glob -i "$OUT/$v/f_*.png" -vf "drawtext=fontfile=$FONT:text='$lab':fontsize=36:fontcolor=white:borderw=3:x=24:y=20" -c:v libx264 -pix_fmt yuv420p -r 30 "$OUT/$v.mp4"
done
printf "file '%s'\nfile '%s'\nfile '%s'\nfile '%s'\n" "$OUT/old.mp4" "$OUT/new.mp4" "$OUT/old.mp4" "$OUT/new.mp4" > "$OUT/list.txt"
ffmpeg -v error -y -f concat -safe 0 -i "$OUT/list.txt" -c copy "$MEDIA/angelina_ult_old_new.mp4"
ls -la "$MEDIA" | tee -a "$OUT/runs.txt"
for v in old new; do mkdir -p "$MEDIA/$v"; ls "$OUT/$v"/f_*.png | awk 'NR%15==0' | xargs -I{} cp {} "$MEDIA/$v/"; done
exit 0
