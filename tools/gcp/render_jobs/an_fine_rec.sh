# 安洁莉娜终结技「奇点坠落」版本对照：图鉴演示终结技（精二、mode 4）30 帧原速连拍，每版一段（左上标版本名），按顺序拼两遍成一个 mp4
#   ult/an_fine：0 旧版帧条 / 1 细螺旋（11-06）/ 2 引力黑洞（11-07，缺省）
# 输出：$MEDIA/angelina_ult_versions.mp4；$MEDIA/<版本>/ 每 10 帧一张抽样
# 用法：python tools/gcp_render.py --branch <提交> --job custom --cmd 'bash tools/gcp/render_jobs/an_fine_rec.sh'
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"   # concat 列表按列表所在目录解析相对路径
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
FONT="$CJK_FONT"
FF="$(python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')"
VERS="${VERS:-old:旧版:0 thin:细螺旋:1 bh:引力黑洞:2}"
: > "$OUT/list1.txt"
for spec in $VERS; do
    IFS=: read -r v lab val <<< "$spec"
    d="$OUT/$v"; mkdir -p "$d"
    timeout -k 30 600 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=angelina --shot_stage=2 --shot_mode=4 --shot_dir="$d" --shot_start=0.8 --shot_every=1 --shot_n=180 --shot_w=1280 --shot_h=720 --quality=high --bal=ult/an_fine=$val > "$d.log" 2>&1
    echo "$v rc=$? $(ls $d/f_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    grep -m3 -A3 "SCRIPT ERROR" "$d.log" | tee -a "$OUT/runs.txt"
    mkdir -p "$OUT/lab_$v"
    python3 -c "
import sys, glob
from PIL import Image, ImageDraw, ImageFont
f = ImageFont.truetype(sys.argv[1], 36); n = 0
for p in sorted(glob.glob(sys.argv[2] + '/f_*.png')):
    im = Image.open(p).convert('RGB'); ImageDraw.Draw(im).text((24, 20), sys.argv[3], font=f, fill='white', stroke_width=3, stroke_fill='black')
    im.save(sys.argv[4] + '/l_%04d.png' % n); n += 1
" "$FONT" "$d" "$lab" "$OUT/lab_$v"
    "$FF" -v error -y -framerate 30 -i "$OUT/lab_$v/l_%04d.png" -c:v libx264 -pix_fmt yuv420p -r 30 "$OUT/$v.mp4"
    echo "file '$OUT/$v.mp4'" >> "$OUT/list1.txt"
    mkdir -p "$MEDIA/$v"; ls "$d"/f_*.png | awk 'NR%10==0' | xargs -I{} cp {} "$MEDIA/$v/"
done
cat "$OUT/list1.txt" "$OUT/list1.txt" > "$OUT/list.txt"
"$FF" -v error -y -f concat -safe 0 -i "$OUT/list.txt" -c copy "$MEDIA/angelina_ult_versions.mp4"
ls -la "$MEDIA" | tee -a "$OUT/runs.txt"
exit 0
