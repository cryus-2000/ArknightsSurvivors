#!/bin/bash
# GCP 批跑虚拟机的启动脚本（由 tools/gcp/batch.py 通过 metadata 下发，docs/41 §3.9）。以 root 运行。
# 做的事：拉指定提交 → setup_linux.sh → 跑 batch-cmds → 把 build/cloud/<tag>/ 传到 Cloud Storage → 删除自己。
# 虚拟机上没有 GitHub 令牌：只读拉公开仓库，结果只写 Cloud Storage，推 cloud-results/<tag> 由本机做。
set -uo pipefail
MDA=http://metadata.google.internal/computeMetadata/v1/instance
md() { curl -sf -H Metadata-Flavor:Google "$MDA/$1"; }
TAG="$(md attributes/batch-tag)"
SHA="$(md attributes/batch-commit)"
GS="$(md attributes/batch-gs)"                 # gs://<桶>/<tag>
BASE="$(md attributes/batch-bundle-base || true)"
LIMIT="$(md attributes/batch-timeout || echo 7200)"
NAME="$(md name)"
ZONE="$(md zone | awk -F/ '{print $NF}')"
export HOME=/root
WORK=/work/repo
LOG=/work/vm.log

# 启动脚本在重启后会再跑一次；只跑一次（抢占式机器被回收时直接删掉，不会重启）
if [ -f /work/started ]; then exit 0; fi
mkdir -p /work && touch /work/started
exec > >(tee -a "$LOG") 2>&1

status() { echo "$*" | gcloud storage cp - "$GS/status" -q 2>/dev/null || true; }
selfdelete() {
    gcloud storage cp "$LOG" "$GS/vm.log" -q 2>/dev/null || true
    gcloud compute instances delete "$NAME" --zone "$ZONE" --quiet
}
trap selfdelete EXIT

fail() { status "fail $1"; echo "$2" | gcloud storage cp - "$GS/done" -q; exit 1; }
T0=$(date +%s)
status "apt"
apt-get update -qq && apt-get install -y -qq git python3-pip >/dev/null || fail apt 97
status "fetch $SHA"
mkdir -p "$WORK" && cd "$WORK" || exit 1
git init -q && git remote add origin https://github.com/cryus-2000/ArknightsSurvivors.git
if [ -n "$BASE" ]; then
    # 提交不在 origin 上：浅拉基准提交，再从桶里的 bundle 补上之后的提交
    git fetch -q --depth 1 origin "$BASE" || fail "fetch base" 98
    gcloud storage cp "$GS/repo.bundle" /work/repo.bundle -q
    git fetch -q /work/repo.bundle "$SHA" || fail bundle 98
else
    git fetch -q --depth 1 origin "$SHA" || fail fetch 98
fi
git -c advice.detachedHead=false checkout -q --detach "$SHA"
T1=$(date +%s)

status "setup"
bash tools/cloud/setup_linux.sh || fail setup 97
T2=$(date +%s)

OUT="build/cloud/$TAG"
mkdir -p "$OUT"
md attributes/batch-cmds > /work/cmds.sh
# 进度：每分钟把运行日志尾部写到桶里，本机 batch.py 轮询时打印
( while sleep 60; do tail -c 4000 /work/run.log 2>/dev/null | gcloud storage cp - "$GS/progress" -q 2>/dev/null; done ) &
PROG=$!
status "run"
(
    source tools/cloud/env.sh
    export PYTHONIOENCODING=utf-8 TAG OUT
    timeout "$LIMIT" bash -euo pipefail /work/cmds.sh
) > /work/run.log 2>&1
RC=$?
T3=$(date +%s)
kill $PROG 2>/dev/null
cp /work/run.log "$OUT/run.log"
{
    echo "commit: $SHA"
    echo "godot_version: $(source tools/cloud/env.sh && "$GODOT" --version)"
    echo "nproc: $(nproc)"
    echo "date_utc: $(date -u)"
    echo "runner: gcp $(md machine-type | awk -F/ '{print $NF}') $ZONE preemptible=$(md scheduling/preemptible)"
    echo "secs: fetch $((T1-T0)) setup $((T2-T1)) run $((T3-T2))"
    echo "rc: $RC"
} > "$OUT/env.txt"
cat "$OUT/env.txt"
# 只带报告、原始 json、日志（同例行任务推的内容）
( cd build/cloud && find "$TAG" -type f \( -name '*.md' -o -name '*.json' -o -name '*.txt' -o -name '*.log' \) -print0 \
    | tar -czf /work/result.tar.gz --null -T - )
gcloud storage cp /work/result.tar.gz "$GS/result.tar.gz" -q
echo "$RC" | gcloud storage cp - "$GS/done" -q
status "done rc=$RC"
