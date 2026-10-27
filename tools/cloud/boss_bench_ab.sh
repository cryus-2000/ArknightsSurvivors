#!/usr/bin/env bash
# Boss 单场测试台云端对照（docs/170 §4）：同一台机器上 录快照（对照代码）→ 对照开打 → 改版开打 → 出对照表 → 推结果分支。
#   NAME=path-tide NEW=origin/claude/boss-path-tide BOSSES=path,bishop+archon,bishop+immortal BENCH=<测试台代码提交> \
#   SEEDS=1-16 MAXT_REC=425 bash tools/cloud/boss_bench_ab.sh
# 对照 = 当前检出（测试台分支，基于 codex/boss-fx-rework 72f41c3c7，各 Boss 分支的共同起点）；
# 改版 = $NEW 上 cherry-pick 测试台代码提交 $BENCH（只动钩子，不碰 Boss）。快照只录一次，两边用同一批。
# 所有步骤前台顺序跑；结果推 cloud-results/boss-bench-$NAME。
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
[ -f tools/cloud/env.sh ] || { echo "先运行 bash tools/cloud/setup_linux.sh"; exit 1; }
# shellcheck disable=SC1091
source tools/cloud/env.sh
export PYTHONIOENCODING=utf-8
: "${NAME:?}" "${NEW:?}" "${BOSSES:?}" "${BENCH:?}"
SEEDS="${SEEDS:-1-16}"
OPS="${OPS:-wisadel,skadi,kaltsit}"
METAS="${METAS:-0,18}"
MAXT_REC="${MAXT_REC:-605}"
JOBS="${GODOT_MAX_PROCS:-$(nproc)}"
OUT="$REPO/build/boss_bench_cloud/$NAME"
mkdir -p "$OUT"
BASE_SHA="$(git rev-parse --short HEAD)"
NEW_SHA="$(git rev-parse --short "$NEW")"
{
    echo "name: $NAME"; echo "control: $BASE_SHA (测试台分支)"; echo "new: $NEW @ $NEW_SHA + cherry-pick $BENCH"
    echo "bosses: $BOSSES"; echo "ops: $OPS metas: $METAS seeds: $SEEDS maxt_rec: $MAXT_REC"
    echo "godot: $("$GODOT" --version)"; echo "cpu: $(nproc) jobs: $JOBS"; echo "start(UTC): $(date -u +%F_%T)"
} | tee "$OUT/env.txt"

# 1. 快照（对照代码，高手机器人 --nodeath 跑到 MAXT_REC 秒）
python3 tools/boss_bench.py record --ops "$OPS" --metas "$METAS" --seeds "$SEEDS" --maxt "$MAXT_REC" \
    --out "$OUT/snaps" --jobs "$JOBS" 2>&1 | tee "$OUT/record.log"
# 2. 对照
python3 tools/boss_bench.py run --snaps "$OUT/snaps" --bosses "$BOSSES" --tag base --out "$OUT" --jobs "$JOBS" 2>&1 | tee "$OUT/run_base.log"
# 3. 改版：独立工作树 + cherry-pick 测试台钩子
WT="$REPO/../bench_new_$NAME"
rm -rf "$WT"; git worktree prune
git worktree add --detach "$WT" "$NEW"
( cd "$WT" && git -c user.name=bench -c user.email=bench@local cherry-pick --no-edit "$BENCH" ) || {
    echo "cherry-pick 冲突：$NEW 与测试台钩子撞行，见 $WT 的 git status" | tee "$OUT/CHERRY_PICK_CONFLICT.txt"
    ( cd "$WT" && git status -s && git diff ) >> "$OUT/CHERRY_PICK_CONFLICT.txt" 2>&1 || true
    exit 2
}
cp -r "$REPO/game/.godot" "$WT/game/" 2>/dev/null || true   # 导入缓存（ensure_imported 会补缺的）
python3 tools/boss_bench.py run --snaps "$OUT/snaps" --bosses "$BOSSES" --tag new --game "$WT/game" --out "$OUT" --jobs "$JOBS" 2>&1 | tee "$OUT/run_new.log"
# 4. 对照表
python3 tools/boss_bench.py table "$OUT/base.json" "$OUT/new.json" | tee "$OUT/compare.md"
echo "end(UTC): $(date -u +%F_%T)" >> "$OUT/env.txt"
rm -rf "$OUT/snaps"/*.json.tmp 2>/dev/null || true
tar -czf "$OUT/snaps.tar.gz" -C "$OUT" snaps && rm -rf "$OUT/snaps"
# 5. 推结果
git checkout -B "cloud-results/boss-bench-$NAME"
git add -f "$OUT"
git -c user.name=bench -c user.email=bench@local commit -q -m "boss-bench $NAME: control $BASE_SHA vs $NEW_SHA"
git push -f origin "cloud-results/boss-bench-$NAME"
echo "已推 cloud-results/boss-bench-$NAME"
