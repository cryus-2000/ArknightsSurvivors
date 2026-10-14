# B6 ① 后处理：`var x := … _F().fn(…) …` 推断不了类型 → 按 fn 的返回类型写成 `var x: T = …`（只在右边就是这一个调用时）；否则去掉 :=
import sys, os, re, glob
D = os.path.join(sys.argv[1], "scripts", "characters", "blocks")
sig = {}
for p in glob.glob(os.path.join(D, "*.gd")):
    for m in re.finditer(r"^static func ([A-Za-z_0-9]+)\(.*\)\s*->\s*([A-Za-z_0-9\[\]]+)\s*:", open(p, encoding="utf-8").read(), re.M):
        sig[m.group(1)] = m.group(2)
pat = re.compile(r"^(\s*var\s+[A-Za-z_0-9]+)\s*:=\s*(.*)$")
call1 = re.compile(r"^_F\(\)\.([A-Za-z_0-9]+)\((.*)\)(\s*(#.*)?)$")
n_typed = n_var = 0
for p in glob.glob(os.path.join(D, "*.gd")):
    L = open(p, encoding="utf-8", newline="").read().split("\n")
    ch = False
    for i, l in enumerate(L):
        if "_F()." not in l:
            continue
        m = pat.match(l)
        if not m:
            continue
        rhs = m.group(2)
        c = call1.match(rhs)
        t = sig.get(c.group(1)) if c else None
        # 右边恰好是一个 _F() 调用且括号配平
        if c and t and t != "void" and rhs.count("(") == rhs.count(")"):
            depth = 0
            ok = True
            body = rhs[len("_F()." + c.group(1)) + 1:]
            for k, chh in enumerate(body):
                depth += 1 if chh == "(" else (-1 if chh == ")" else 0)
                if depth < 0 and body[k + 1:].strip() and not body[k + 1:].strip().startswith("#"):
                    ok = False
                    break
            if ok:
                L[i] = "%s: %s = %s" % (m.group(1), t, rhs)
                n_typed += 1
                ch = True
                continue
        L[i] = "%s = %s" % (m.group(1), rhs)
        n_var += 1
        ch = True
    if ch:
        open(p, "w", encoding="utf-8", newline="").write("\n".join(L))
print("typed", n_typed, "untyped", n_var)
