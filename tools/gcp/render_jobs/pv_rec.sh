# PV 实机素材（11-08）：tools/promo/pv_runs.py 的一局（或 D = 图鉴演示）→ $MEDIA/<局>_seg_*.mp4 + 音效记录 sfx.json + pv.log
# 用法：python tools/gcp_render.py --branch <提交> --job custom --split --name pv1108 --cmd 'bash tools/gcp/render_jobs/pv_rec.sh H' …
set +e
OUT="$(realpath -m "$OUT")"; MEDIA="$(realpath -m "$MEDIA")"; export MEDIA
mkdir -p "$MEDIA"
python3 tools/promo/pv_runs.py "$1" "$OUT/run_$1" 2>&1 | tee -a "$OUT/runs.txt"
grep -h -m5 -A3 "SCRIPT ERROR" "$OUT/run_$1"/*.log "$OUT/run_$1"/*/*.log 2>/dev/null | tee -a "$OUT/runs.txt"
ls -la "$MEDIA" | tee -a "$OUT/runs.txt"
exit 0
