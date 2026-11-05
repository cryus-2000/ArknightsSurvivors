# 代码整理（docs/282）的一次性验证：被测提交跑真全量快检（不重录金样：整理要求积木等价金样原样通过），
# 再与基线提交逐行比同种子 TRACE（画画面跑，绘制代码也执行）。
# 用法：python tools/gcp/batch.py run <tag> --commit <提交> --cmd 'BASE=<基线完整提交号> bash tools/gcp/render_jobs/cleanup_verify.sh'
# 结果：$OUT/ci_check.log、$OUT/ci_logs/、$OUT/trace_ab.md、$OUT/trace/；最后一行 RESULT check=<rc> trace=<rc>
set +e
: "${BASE:?需要 BASE=<基线提交>}"
CASES="${CASES:-mizuki:11:240,wisadel:23:240,texas:5:240,kaltsit:7:240,siege:3:240,eyjafjalla:9:240,skadi:23:240,exusiai:4:240,irene:8:240,hoshiguma:12:240,skalter:6:240,specter_unchained:2:240}"
bash tools/cloud/ci_pack.sh --nocache --jobs "$GODOT_MAX_PROCS"
crc=$?
mkdir -p "$OUT"
cp -r build/ci_check.log build/ci_logs "$OUT/" 2>/dev/null
# 基线检出 + 导入
git fetch -q --depth 1 origin "$BASE" && git worktree add -q --detach /work/base FETCH_HEAD
( cd /work/base && python3 tools/asset_index.py >/dev/null 2>&1; "$GODOT" --headless --path game --import >/dev/null 2>&1 )
python3 tools/asset_index.py >/dev/null 2>&1
Xvfb :99 -screen 0 1920x1080x24 -nolisten tcp >/tmp/xvfb.log 2>&1 &
export DISPLAY=:99
sleep 2
TRACE_CASES="$CASES" TRACE_A="" TRACE_B="" TRACE_EXTRA="" TRACE_WINDOWED=1 TRACE_GAME_B=/work/base/game python3 tools/gcp/render_trace_ab.py
trc=$?
echo "RESULT check=$crc trace=$trc" | tee "$OUT/result.txt"
[ $crc -eq 0 ] && [ $trc -eq 0 ]
