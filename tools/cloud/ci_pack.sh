#!/usr/bin/env bash
# 云端 CI 收口（docs/204 §6 第 1 期）：跑 check.py，并把「每一项一份日志」收进 build/ci_logs/，随结果分支一起推回。
#   bash tools/cloud/ci_pack.sh [check.py 参数...]     # 缺省跑全量；改动分级用 --changed <base>
# 之前 ci/<sha> 只推 build/ci_check.log（汇总），红项没有分日志，事后查不了原因（ci/7306d6bf1 的 3 项就是这样丢的）。
# 产物：build/ci_check.log（汇总）、build/ci_logs/<项>.log（每项 stdout/stderr）、build/ci_logs/last_quick.{txt,json}（每项耗时）。
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO"
[ -f tools/cloud/env.sh ] && source tools/cloud/env.sh
export PYTHONIOENCODING=utf-8
mkdir -p build
python3 tools/check.py "$@" 2>&1 | tee build/ci_check.log
rc=${PIPESTATUS[0]}
LAST="$(ls -d build/check/quick_* 2>/dev/null | sort | tail -1)"
rm -rf build/ci_logs && mkdir -p build/ci_logs
if [ -n "$LAST" ]; then cp "$LAST"/*.log build/ci_logs/ 2>/dev/null || true; fi
cp build/check/last_quick.txt build/check/last_quick.json build/ci_logs/ 2>/dev/null || true
echo "分项日志：build/ci_logs/（$(ls build/ci_logs | wc -l) 个文件）；退出码 $rc" | tee -a build/ci_check.log
exit $rc
