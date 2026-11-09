# GCP 合入 CI 的批跑命令（tools/gcp/batch.py run ci-<sha>[-rN] --commit <sha> --cmd-file tools/gcp/ci_cmd.sh，docs/41 §3.9）
# 在虚拟机的仓库根目录、bash -euo pipefail 下运行；vm_startup.sh 已导出 TAG / OUT（build/cloud/<tag>）。
# 1) 重录积木等价金样 → $OUT/golden/（本机取回提交）  2) 真全量快检 → run.log（vm_startup 收）+ $OUT/ci_logs/
# 11-09 起放进仓库：原来放在协调人临时目录，清理临时文件时丢过一次。
mkdir -p "$OUT/golden" "$OUT/ci_logs"
python3 -c "import numpy" 2>/dev/null || true
python3 tools/check.py --rerecord-golden > "$OUT/rerecord.log" 2>&1 || true
cp game/tests/golden_current/*.json "$OUT/golden/" 2>/dev/null || true
rc=0
bash tools/cloud/ci_pack.sh || rc=$?
cp build/ci_logs/* "$OUT/ci_logs/" 2>/dev/null || true
exit $rc
