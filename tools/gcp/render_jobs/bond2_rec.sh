# 羁绊技（docs/294 / 314）一条录一段：开关 link/bond_v2=1、22 秒解锁，自动对局里录到第一次释放，截释放前 0.8 秒起 3.5 秒，30 帧原速
# 用法：python tools/gcp_render.py --branch <提交> --job custom --cmd 'bash tools/gcp/render_jobs/bond2_rec.sh rival' [--cmd '... tide' ...]
# 键：rival penguin inq lesson tide vortex fins hunt；输出 $MEDIA/bond2_<键>.mp4
set +e
K="$1"
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"
Xvfb :99 -screen 0 1280x720x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
python3 tools/asset_index.py >/dev/null 2>&1
mkdir -p "$MEDIA"
FF="$(python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')"
case "$K" in
  rival) OP=texas; MATE=lappland ;;
  penguin) OP=exusiai; MATE=texas ;;
  inq) OP=irene; MATE=lumen ;;
  lesson) OP=ulpianus; MATE=skadi ;;
  tide) OP=gladiia; MATE=specter_unchained ;;
  vortex) OP=gladiia; MATE=ulpianus ;;
  fins) OP=skadi; MATE=specter_unchained ;;
  hunt) OP=skadi; MATE=gladiia,specter_unchained ;;
esac
d="$OUT/q_$K"; mkdir -p "$d"
timeout -k 30 1500 "$GODOT" --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 --position 0,0 --fixed-fps 30 --path game -- \
  --balance --nodeath --seed=3 --bot=expert --op=$OP --squad=$MATE --prog=8 --bal=link/bond_v2=1 --bal=bond2/log=1 \
  --realtime --rtfrom=21 --recframes=22.4,270 --shotdir="$d" --maxt=32 --bal=bond2/unlock_at=22 > "$d.log" 2>&1
CT=$(grep -m1 -o "BOND2 cast [a-z_]* t=[0-9.]*" "$d.log" | sed 's/.*t=//')
echo "$K rc=$? cast=$CT $(ls $d/rec_*.png 2>/dev/null | wc -l) 帧 $(grep -c 'SCRIPT ERROR' $d.log) 处脚本错误" | tee -a "$OUT/runs.txt"
grep -m3 -A3 "SCRIPT ERROR" "$d.log" | tee -a "$OUT/runs.txt"
if [ -n "$CT" ]; then
  I0=$(python3 -c "print(max(0, int(round(($CT - 22.4) * 30)) - 24))")
  "$FF" -v error -y -framerate 30 -start_number $I0 -i "$d/rec_%05d.png" -frames:v 105 -c:v libx264 -crf 22 -pix_fmt yuv420p "$MEDIA/bond2_$K.mp4"
fi
ls -la "$MEDIA" | tee -a "$OUT/runs.txt"
exit 0
