#!/usr/bin/env bash
# 云端批跑（docs/36 §7）：快检 + 一轮机器人批跑，结果打包到 build/cloud/<时间>/ 与同名 .tar.gz。
#   bash tools/cloud/run_cloud.sh                    # 快检 + 标准矩阵（普通 / 高手 × 7 开局 × SEEDS）
#   SEEDS=8 PRESET=starts BOTS=expert,normal bash tools/cloud/run_cloud.sh
#   ONLY=check bash tools/cloud/run_cloud.sh         # 只跑快检
#   AB=<提交> bash tools/cloud/run_cloud.sh          # 改跑 A/B（check.py --ab）
# 并发：GODOT_MAX_PROCS（缺省 = 核数；云端机器只跑这一批，不用像本机那样给别的会话留余量）。
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
[ -f tools/cloud/env.sh ] || { echo "先运行 bash tools/cloud/setup_linux.sh"; exit 1; }
# shellcheck disable=SC1091
source tools/cloud/env.sh
export PYTHONIOENCODING=utf-8

STAMP="$(date -u +%m%d_%H%M)"
OUT="build/cloud/$STAMP"
mkdir -p "$OUT"
{
    echo "commit: $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
    echo "godot: $("$GODOT" --version)"
    echo "cpu: $(nproc) 核; max_procs: $GODOT_MAX_PROCS"
    echo "time(UTC): $STAMP"
} | tee "$OUT/env.txt"

rc=0
if [ -n "${AB:-}" ]; then
    python3 tools/check.py --ab "$AB" 2>&1 | tee "$OUT/ab.log" || rc=$?
    cp -r build/check/ab_* "$OUT/" 2>/dev/null || true
else
    python3 tools/check.py 2>&1 | tee "$OUT/check.log" || rc=$?
    if [ "${ONLY:-}" != "check" ]; then
        python3 tools/balance_run.py --preset "${PRESET:-starts}" --bots "${BOTS:-expert,normal}" \
            --seeds "${SEEDS:-4}" --jobs "$GODOT_MAX_PROCS" --tag cloud --out "$OUT" 2>&1 | tee "$OUT/balance.log" || rc=$?
    fi
fi

tar -czf "build/cloud/cloud_${STAMP}.tar.gz" -C build/cloud "$STAMP"
echo
echo "结果：$OUT/（报告 .md、原始 .json、日志）  打包：build/cloud/cloud_${STAMP}.tar.gz"
exit $rc
