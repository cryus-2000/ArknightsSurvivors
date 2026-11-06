# 能天使「对空优先」改版（docs/298）胜率配对：ARM=0（原样）/ 2（B 版），每条一台。
# 能天使当队长、--prog=1 开局点出节点 1；4 种编队 × 普通 / 高手 × 4 种子 × 安慰剂 0,1,2；--keep EXUPF 存量测行。
# 用法：python tools/gcp/batch.py run exupf-ab<ARM> --commit <提交> --cmd 'ARM=2 bash tools/gcp/render_jobs/exu_pf_ab.sh'
set +e
ARM=${ARM:-2}
for sq in exusiai exusiai,saria,suzuran exusiai,angelina,texas exusiai,wisadel,eyjafjalla; do
    python3 tools/balance_run.py --squad $sq --bots normal,expert --seeds 4 --placebos 0,1,2 --jobs $(nproc) --nocache --keep EXUPF \
        --extra "--prog=1 --exupf --bal=growth_nodes/exu_prefer=$ARM" --out "$OUT/${sq//,/_}" > "$OUT/${sq//,/_}.log" 2>&1
    echo "$sq rc=$? $(grep -m1 -E '胜率' $OUT/${sq//,/_}.log)" | tee -a "$OUT/runs.txt"
done
exit 0
