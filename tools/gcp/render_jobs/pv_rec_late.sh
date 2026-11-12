# PV 实机素材第三批（11-12）：tools/promo/pv_runs_late.py 跑一局 → $MEDIA/<名>_<段>.mp4 + .json + pv.log
# 用法：python tools/gcp_render.py --branch <提交> --job custom --split --name pv1112 --dest <本机目录> \
#         --cmd 'bash tools/gcp/render_jobs/pv_rec_late.sh <名> <宽x高> <传给游戏的参数…>'
# 宽高超过 1920×1080 时另开一块同尺寸的 Xvfb 虚拟屏（render_prep 的 :99 只有 1920×1080，窗口会被压小）
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"; export MEDIA
mkdir -p "$MEDIA"
NAME="$1"; RES="$2"; shift 2
W="${RES%x*}"; H="${RES#*x}"
if [ "$W" -gt 1920 ] || [ "$H" -gt 1080 ]; then
    Xvfb :98 -screen 0 ${W}x${H}x24 -nolisten tcp >/work/xvfb98.log 2>&1 &
    export DISPLAY=:98
    sleep 2
fi
python3 tools/promo/pv_runs_late.py "$NAME" "$OUT/run_$NAME" --res="$RES" -- "$@" 2>&1 | tee -a "$OUT/runs.txt"
grep -h -m5 -A3 "SCRIPT ERROR" "$OUT/run_$NAME"/*.log 2>/dev/null | tee -a "$OUT/runs.txt"
ls -la "$MEDIA" | tee -a "$OUT/runs.txt"
exit 0
