# 维什戴尔原作弹体对照（11-07）：图鉴演示 招式 × 精英档，fx/wd_shell_v = 0（旧：3×3 黑铁小丸）/ 1（新：原作弹体）各录一遍，
# --fixed-fps 30 连拍 = 30 帧原速，ffmpeg 左旧右新拼 mp4 放 $MEDIA。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --split --name wdshell \
#         --cmd 'bash tools/gcp/render_jobs/wd_shell_rec.sh 3' --cmd 'bash tools/gcp/render_jobs/wd_shell_rec.sh 0' --cmd 'bash tools/gcp/render_jobs/wd_shell_rec.sh 1 2'
# 参数：招式号（3 普攻 / 0 S1 / 1 S2 / 2 S3），可多个
set +e
pgrep Xvfb >/dev/null || { Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 & sleep 2; }
export DISPLAY=:99
python3 tools/asset_index.py >/dev/null 2>&1
# 预装镜像里没有 ffmpeg（11-07 第一次只回来静帧）：缺就装 imageio-ffmpeg 的静态版
FF="$(command -v ffmpeg)"
if [ -z "$FF" ]; then
    pip3 install -q imageio-ffmpeg >/dev/null 2>&1 || python3 -m pip install -q --break-system-packages imageio-ffmpeg >/dev/null 2>&1
    FF="$(python3 -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null)"
fi
[ -z "$FF" ] && { sudo apt-get update -qq >/dev/null 2>&1; sudo apt-get install -y -qq ffmpeg >/dev/null 2>&1; FF="$(command -v ffmpeg)"; }
echo "ffmpeg=$FF" | tee -a "$OUT/runs.txt"
FR="$(realpath -m "${OUT:-/work/out}/frames")"; mkdir -p "$FR" "$MEDIA"
declare -A NAME=([3]=atk [0]=s1 [1]=s2 [2]=s3)
declare -A TIERS=([3]="0 1 2" [0]="0 1 2" [1]="1 2" [2]="2")
declare -A NF=([3]=120 [0]=150 [1]=180 [2]=180)
run() {   # $1 档 $2 招 $3 变体 $4 开关值
    d="$FR/e$1_${NAME[$2]}_$3"; rm -rf "$d"; mkdir -p "$d"
    timeout -k 30 480 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game res://tests/elite_demo_shot.tscn -- \
        --shot_op=wisadel --shot_stage=$1 --shot_mode=$2 --shot_dir="$d" --shot_start=0.6 --shot_every=1 --shot_n=${NF[$2]} --shot_w=1280 --shot_h=720 --quality=high --bal=fx/wd_shell_v=$4 > "$d.log" 2>&1
    echo "e$1 ${NAME[$2]} $3 rc=$? $(ls $d/f_*.png 2>/dev/null | wc -l) 张 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
    grep -m5 'SCRIPT ERROR' -A3 "$d.log" >> "$OUT/runs.txt"
}
for m in "$@"; do
    for t in ${TIERS[$m]}; do
        run $t $m old 0
        run $t $m new 1
        a="$FR/e${t}_${NAME[$m]}_old"; b="$FR/e${t}_${NAME[$m]}_new"
        "$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$a/f_*.png" -framerate 30 -pattern_type glob -i "$b/f_*.png" \
            -filter_complex "[0:v]drawtext=text='old':x=16:y=16:fontsize=28:fontcolor=white[l];[1:v]drawtext=text='new':x=16:y=16:fontsize=28:fontcolor=white[r];[l][r]hstack=inputs=2" \
            -c:v libx264 -pix_fmt yuv420p -crf 18 "$MEDIA/wd_shell_e${t}_${NAME[$m]}.mp4" 2>>"$OUT/runs.txt" \
          || "$FF" -y -loglevel error -framerate 30 -pattern_type glob -i "$a/f_*.png" -framerate 30 -pattern_type glob -i "$b/f_*.png" \
            -filter_complex "[0:v][1:v]hstack=inputs=2" -c:v libx264 -pix_fmt yuv420p -crf 18 "$MEDIA/wd_shell_e${t}_${NAME[$m]}.mp4" 2>>"$OUT/runs.txt"
        # 两张静帧（中间一帧）留作快速看图
        f=$(ls "$b"/f_*.png 2>/dev/null | sed -n "$(( ${NF[$m]} / 3 ))p"); [ -n "$f" ] && cp "$f" "$MEDIA/still_e${t}_${NAME[$m]}_new.png"
        f=$(ls "$a"/f_*.png 2>/dev/null | sed -n "$(( ${NF[$m]} / 3 ))p"); [ -n "$f" ] && cp "$f" "$MEDIA/still_e${t}_${NAME[$m]}_old.png"
    done
done
exit 0
