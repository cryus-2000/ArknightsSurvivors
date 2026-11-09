#!/bin/bash
# GCP 批跑虚拟机的启动脚本（由 tools/gcp/batch.py 通过 metadata 下发，docs/41 §3.9）。以 root 运行。
# 做的事：拉指定提交 → setup_linux.sh → 跑 batch-cmds → 把 build/cloud/<tag>/ 传到 Cloud Storage → 删除自己。
# 虚拟机只读拉仓库：公开时匿名，私有时用 Secret Manager 的 github-ro 只读令牌；结果只写 Cloud Storage，推 cloud-results/<tag> 由本机做。
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
# 开机用了多久（创建 → 启动脚本开始），写进 env.txt 量提速（docs/256 §7）
BOOT=$(( T0 - $(date -d "$(gcloud compute instances describe "$NAME" --zone "$ZONE" --format="value(creationTimestamp)" 2>/dev/null)" +%s 2>/dev/null || echo $T0) ))
# 预装镜像（family arkr-render，tools/gcp/build_image.py）：apt / pip / Godot / 中文字体都装好了，跳过安装
READY=0
if [ -f /opt/arkr/ready ]; then READY=1; fi
if [ "$READY" = 0 ]; then
    status "apt"
    apt-get update -qq && apt-get install -y -qq git python3-pip >/dev/null || fail apt 97
fi
status "fetch $SHA"
mkdir -p "$WORK" && cd "$WORK" || exit 1
git init -q && git remote add origin https://github.com/cryus-2000/ArknightsSurvivors.git
# 私有仓库（11-09）：Secret Manager 里有 github-ro（只读细粒度令牌）就用它拉；没有就照旧匿名拉（公开仓库）。令牌不写日志、不落盘
GH_RO="$(gcloud secrets versions access latest --secret=github-ro 2>/dev/null || true)"
if [ -n "$GH_RO" ]; then
    git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_RO" | base64 -w0)"
    echo "github: 用只读令牌拉取"
fi
unset GH_RO
if [ -n "$BASE" ]; then
    # 提交不在 origin 上：浅拉基准提交，再从桶里的 bundle 补上之后的提交
    # BASE = 空格隔开的全部前置提交（bundle 头里的 - 行，batch.py 读出）；逐个浅拉，缺一个 bundle 就取不出
    git fetch -q --depth 1 origin $BASE || fail "fetch base" 98
    gcloud storage cp "$GS/repo.bundle" /work/repo.bundle -q
    git fetch -q /work/repo.bundle "$SHA" || fail bundle 98
else
    git fetch -q --depth 1 origin "$SHA" || fail fetch 98
fi
git -c advice.detachedHead=false checkout -q --detach "$SHA"
T1=$(date +%s)

status "setup"
if [ "$READY" = 1 ]; then
    # 镜像里的 Godot + 预热过的导入缓存：拷进检出目录，只增量导入改过的素材；env.sh 照 setup_linux.sh 的格式写
    cp -a /opt/arkr/godot_cache game/.godot
    /opt/arkr/godot/godot --headless --path game --import >/dev/null 2>&1 || true
    test -d game/.godot/imported || fail import 97
    printf 'export GODOT="/opt/arkr/godot/godot"\nexport GODOT_MAX_PROCS="${GODOT_MAX_PROCS:-$(nproc)}"\n' > tools/cloud/env.sh
else
    bash tools/cloud/setup_linux.sh || fail setup 97
fi
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
    echo "secs: boot $BOOT fetch $((T1-T0)) setup $((T2-T1)) run $((T3-T2)) image $READY"
    echo "rc: $RC"
} > "$OUT/env.txt"
cat "$OUT/env.txt"
# 只带报告、原始 json、日志（同例行任务推的内容）
( cd build/cloud && find "$TAG" -type f \( -name '*.md' -o -name '*.json' -o -name '*.txt' -o -name '*.log' \) -print0 \
    | tar -czf /work/result.tar.gz --null -T - )
gcloud storage cp /work/result.tar.gz "$GS/result.tar.gz" -q
# 出图任务（tools/gcp_render.py）：$OUT/media/ 下的 PNG / MP4 不进上面的包，原样传到桶里 $GS/media/，由本机下载
if [ -d "$OUT/media" ] && [ -n "$(ls -A "$OUT/media")" ]; then
    gcloud storage cp -r "$OUT/media" "$GS/" -q || echo "media 上传失败"
fi
echo "$RC" | gcloud storage cp - "$GS/done" -q
status "done rc=$RC"
