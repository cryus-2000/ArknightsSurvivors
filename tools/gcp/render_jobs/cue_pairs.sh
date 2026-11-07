# 成长节点提示同帧对照（docs/310 §8）：tools/node_cue_pairs.py 在虚拟机上跑。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'BEFORE=<基线提交> ITEMS="saria:3 logos:1" bash tools/gcp/render_jobs/cue_pairs.sh'
#   BEFORE 留空 = 同一份代码 node_cue 关 / 开对照；给了 = 选前用基线提交的临时工作树（直接改了绘制的项用这个）
# 结果：$MEDIA/<干员_节点>.png（上排选前、下排选后，1 倍），$OUT/pairs.txt
set +e
BG=""
if [ -n "$BEFORE" ]; then
    git fetch -q origin "$BEFORE" 2>/dev/null || git fetch -q --unshallow 2>/dev/null || true
    git worktree add -f --detach /tmp/base "$BEFORE" > "$OUT/base.log" 2>&1
    cp -r game/.godot /tmp/base/game/ 2>/dev/null
    (cd /tmp/base && python3 tools/asset_index.py >/dev/null 2>&1)
    timeout 1800 "$GODOT" --headless --path /tmp/base/game --import >> "$OUT/base.log" 2>&1
    BG="--before-game /tmp/base/game"
fi
timeout 1800 "$GODOT" --headless --path game --import > "$OUT/import.log" 2>&1
python3 tools/node_cue_pairs.py --out "$MEDIA" --jobs ${JOBS:-4} $BG $ITEMS > "$OUT/pairs.txt" 2>&1
cat "$OUT/pairs.txt"
exit 0
