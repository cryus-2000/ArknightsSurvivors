# Godot 生成 uid（11-07 uid 撞号根治）：被测提交里去掉了 uid 行的 .import / 删掉的 .gd.uid，跑一次 --import 让 Godot 按规范补；
# 再跑第二次确认不再改写（稳定）。结果：$MEDIA/uid.diff（相对被测提交）、新出现的 .uid 文件内容、两次 git status。
# 用法：python tools/gcp_render.py --branch <提交> --job custom --name <名> --cmd 'bash tools/gcp/render_jobs/uid_import.sh'
set +e
mkdir -p "$MEDIA"
"$GODOT" --headless --path game --import > "$OUT/import1.log" 2>&1
echo "import1 rc=$?" | tee -a "$OUT/runs.txt"
git status --porcelain -- game > "$MEDIA/status1.txt"
git add -N game 2>/dev/null
git diff -- game ':!game/art/index.json' > "$MEDIA/uid.diff"
git ls-files -o --exclude-standard -- game | grep -E '\.uid$|\.import$' | while read f; do echo "$f $(head -c 200 "$f" | tr '\n' ' ')"; done > "$MEDIA/untracked_uid.txt"
# 第二次：已有 uid 不应再被改写
find game -path game/.godot -prune -o \( -name '*.import' -o -name '*.uid' \) -print0 | sort -z | xargs -0 sha1sum > /tmp/sum1.txt
"$GODOT" --headless --path game --import > "$OUT/import2.log" 2>&1
echo "import2 rc=$?" | tee -a "$OUT/runs.txt"
git status --porcelain -- game > "$MEDIA/status2.txt"
find game -path game/.godot -prune -o \( -name '*.import' -o -name '*.uid' \) -print0 | sort -z | xargs -0 sha1sum > /tmp/sum2.txt
diff /tmp/sum1.txt /tmp/sum2.txt > "$MEDIA/second_import_changes.txt" 2>&1
grep -c . "$MEDIA/status1.txt" "$MEDIA/status2.txt" "$MEDIA/second_import_changes.txt" | tee -a "$OUT/runs.txt"
exit 0
