# 转平面试验出图（docs/246 §7）：tools/pxplane_shots.py 的 demo（三栏对比 + 2 倍局部 + 三档并排）、rec（同种子 8:00 起 20 秒左关右开 mp4，同局 TRACE 逐行比）、
# trace（fx/px_plane 0 / 1 / 2 三局 TRACE 两两比）。被测提交里要有 tools/pxplane_shots.py。
# 参数（--args，分号隔开多段，每段是 pxplane_shots.py 的一条子命令；缺省三段全跑）：
#   demo                                      → $MEDIA/（cmp_*.png、cmp_*_x2.png、tiers_*.png）
#   rec --seed 11 --from 480 --secs 20        → $MEDIA/late_8m00_onoff.mp4
#   trace --seed 23 --maxt 300 --extra "--elite2 --sptest"
# 三栏是「当前游戏 / 旧做法 / 转平面」；原作参照图不上 GCP，要「原作」一栏由本机事后拼（docs/256 §4）
RARGS="${RENDER_ARGS:-demo;rec --seed 11 --from 480 --secs 20;trace --seed 23 --maxt 300 --extra \"--elite2 --sptest\"}"
IFS=';' read -ra PARTS <<< "$RARGS"
RC=0
for P in "${PARTS[@]}"; do
    P="$(echo "$P" | sed 's/^ *//;s/ *$//')"
    [ -z "$P" ] && continue
    echo "== pxplane_shots.py $P"
    T=$(date +%s)
    eval "python3 tools/pxplane_shots.py $P --out \"$MEDIA\"" > "$OUT/pxplane_$(echo "$P" | cut -d' ' -f1).log" 2>&1 || RC=$?
    echo "   rc=$RC  $(( $(date +%s) - T )) 秒"
    tail -5 "$OUT/pxplane_$(echo "$P" | cut -d' ' -f1).log"
done
# 中间帧与 Godot 日志（看 SCRIPT ERROR 用）
mkdir -p "$OUT/logs" && cp build/pxplane*/logs/*.log "$OUT/logs/" 2>/dev/null || true
grep -l "SCRIPT ERROR" "$OUT"/logs/*.log 2>/dev/null | head && echo "有 SCRIPT ERROR，见上面的日志" || true
exit $RC
