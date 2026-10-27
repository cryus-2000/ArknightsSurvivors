#!/usr/bin/env bash
# Boss 单场测试台云端对照（docs/170 §3）：同一台机器上 录快照（对照代码）→ 对照开打 → 改版开打 → 对照表 → 推结果分支。
# 云端单条命令有 10 分钟上限，所以拆成几步，每步都前台跑、可重复跑（已有的分块会跳过）：
#   export NAME=path-tide NEW=origin/claude/boss-path-tide BOSSES=path,bishop+archon,bishop+immortal BENCH=4121e81ee MAXT_REC=425
#   STEP=setup  bash tools/cloud/boss_bench_ab.sh                          # 环境记录 + 改版工作树（cherry-pick 测试台钩子）
#   STEP=record OP=wisadel META=0 SEEDS=1-16 bash tools/cloud/boss_bench_ab.sh   # 录快照（3 开局 × 2 档各一次；超时就把 SEEDS 拆成 1-8 / 9-16）
#   STEP=run SIDE=base OP=wisadel META=0 bash tools/cloud/boss_bench_ab.sh       # 开打（SIDE=base / new；每个 OP × META 各一次；可加 BOSSES=单只 拆小）
#   STEP=finish bash tools/cloud/boss_bench_ab.sh                          # 合并、出 compare.md、推 cloud-results/boss-bench-$NAME
# 对照 = 当前检出（测试台分支，基于 codex/boss-fx-rework 72f41c3c7，各 Boss 分支的共同起点）；改版 = $NEW + cherry-pick $BENCH。
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
[ -f tools/cloud/env.sh ] || { echo "先运行 bash tools/cloud/setup_linux.sh"; exit 1; }
# shellcheck disable=SC1091
source tools/cloud/env.sh
export PYTHONIOENCODING=utf-8
: "${NAME:?}" "${STEP:?}"
JOBS="${GODOT_MAX_PROCS:-$(nproc)}"
OUT="$REPO/build/boss_bench_cloud/$NAME"
WT="$REPO/../bench_new_$NAME"
mkdir -p "$OUT/snaps" "$OUT/parts"

case "$STEP" in
setup)
    : "${NEW:?}" "${BENCH:?}" "${BOSSES:?}"
    {
        echo "name: $NAME"; echo "control: $(git rev-parse --short HEAD) (测试台分支)"
        echo "new: $NEW @ $(git rev-parse --short "$NEW") + cherry-pick $BENCH"; echo "bosses: $BOSSES"
        echo "godot: $("$GODOT" --version)"; echo "cpu: $(nproc) jobs: $JOBS"; echo "start(UTC): $(date -u +%F_%T)"
    } | tee "$OUT/env.txt"
    rm -rf "$WT"; git worktree prune
    git worktree add --detach "$WT" "$NEW"
    # BENCH=- ：被测分支已自带测试台钩子（自己 cherry-pick 过），不再挑
    if [ "$BENCH" != "-" ] && ! ( cd "$WT" && git -c user.name=bench -c user.email=bench@local cherry-pick --no-edit $BENCH ); then
        ( cd "$WT" && git status -s && git diff ) > "$OUT/CHERRY_PICK_CONFLICT.txt" 2>&1 || true
        echo "cherry-pick 冲突：手动解决 $WT 里的冲突（测试台钩子行照抄 $BENCH，两边改动都保留）后 git -C $WT cherry-pick --continue"
        exit 2
    fi
    cp -r "$REPO/game/.godot" "$WT/game/" 2>/dev/null || true
    python3 -c "import sys; sys.path.insert(0,'tools'); import godot_runner as GR; GR.ensure_imported('$REPO/game'); GR.ensure_imported('$WT/game')"
    ;;
record)
    : "${OP:?}" "${META:?}"
    python3 tools/boss_bench.py record --ops "$OP" --metas "$META" --seeds "${SEEDS:-1-16}" --maxt "${MAXT_REC:-605}" \
        --out "$OUT/snaps" --jobs "$JOBS" 2>&1 | tee -a "$OUT/record.log"
    ;;
run)
    : "${SIDE:?}" "${OP:?}" "${META:?}" "${BOSSES:?}"
    GAME_DIR="$REPO/game"; [ "$SIDE" = new ] && GAME_DIR="$WT/game"
    TAG="${SIDE}_${OP}_m${META}_$(echo "$BOSSES" | tr ',+' '-_')"
    python3 tools/boss_bench.py run --snaps "$OUT/snaps" --bosses "$BOSSES" --ops "$OP" --metas "$META" --tag "$TAG" \
        --game "$GAME_DIR" --out "$OUT/parts" --jobs "$JOBS" 2>&1 | grep -v "^|" | tee -a "$OUT/run_$SIDE.log"
    ;;
finish)
    python3 tools/boss_bench.py merge --tag base --out "$OUT/base.json" "$OUT"/parts/base_*.json
    python3 tools/boss_bench.py merge --tag new --out "$OUT/new.json" "$OUT"/parts/new_*.json
    python3 tools/boss_bench.py table "$OUT/base.json" "$OUT/new.json" | tee "$OUT/compare.md"
    echo "end(UTC): $(date -u +%F_%T)" >> "$OUT/env.txt"
    tar -czf "$OUT/snaps.tar.gz" -C "$OUT" snaps && rm -rf "$OUT/snaps" "$OUT/parts"
    git checkout -B "cloud-results/boss-bench-$NAME"
    git add -f "$OUT"
    git -c user.name=bench -c user.email=bench@local commit -q -m "boss-bench $NAME"
    git push -f origin "cloud-results/boss-bench-$NAME"
    echo "已推 cloud-results/boss-bench-$NAME"
    ;;
*)
    echo "STEP 只能是 setup / record / run / finish"; exit 1 ;;
esac
