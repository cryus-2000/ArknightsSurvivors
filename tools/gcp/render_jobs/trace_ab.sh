# 同种子 TRACE 开 / 关对比（只改画面的改动必跑，docs/36 §3）：同一提交、同一局，A 组 / B 组各跑一遍 --balance --trace=1，逐行比。
# 参数（--args，空格隔开的 键=值；缺省见下）：
#   cases=skadi:23:300,mizuki:11:300   每局「队长:种子:秒数」，逗号隔开，多局并行
#   a="--bal=fx/px_plane=0"            A 组附加参数（引号里可放多个）
#   b="--bal=fx/px_plane=1"            B 组附加参数
#   extra="--elite2 --sptest"          两组都加的参数
#   base=<提交>                        B 组改用另一个提交（虚拟机上浅拉 + 导入 + 生成 index.json），跨提交比 TRACE
#   windowed=1                        画画面跑（Xvfb + opengl3，画面代码也执行；缺省 --headless 更快）
# 结果：$OUT/trace_ab.md（每局行数、是否逐行一致、第一处差异）+ $OUT/trace/<局>_<组>.txt；有差异时任务退出码 1
eval "$RENDER_ARGS" 2>/dev/null || true
export TRACE_CASES="${cases:-skadi:23:300}" TRACE_A="${a:---bal=fx/px_plane=0}" TRACE_B="${b:---bal=fx/px_plane=1}" TRACE_EXTRA="${extra:-}" TRACE_WINDOWED="${windowed:-0}"
if [ -n "${base:-}" ]; then
    git fetch -q --depth 1 origin "$base" && git worktree add -q --detach /work/base FETCH_HEAD
    ( cd /work/base && python3 tools/asset_index.py >/dev/null 2>&1; "$GODOT" --headless --path game --import >/dev/null 2>&1 || true )
    export TRACE_GAME_B=/work/base/game
    echo "B 组用提交 $base（/work/base）"
fi
python3 /work/render_trace_ab.py
