# -*- coding: utf-8 -*-
"""网页包验证（docs/33）：把 export_web.py 的分片拼回 index.pck，用 4.7.2 release 诊断模板（Windows，encrypted_release.diagnostic_verifier）加载它跑一段探针，
在发布构建里实测 build.json 的 audience / commit、发布版开发参数屏蔽、全部解锁与 Boss 演练入口是否与 audience 一致，
以及存档：对外包新存档进度为空；对内包解锁只在内存（写一次存档再读回，文件里进度仍为空）。另查单文件 ≤ 25 MB。

    python tools/verify_web_build.py --dir build/release/final_<提交>/web_internal --audience internal [--commit <提交>]

网页 PCK 不加密、与平台无关，所以可以在 Windows 上用 release 模板加载；用户目录放进临时目录（不碰本机存档）。
报告写到 <dir>/../web_verification_<audience>_<提交>.json（release_all.py 收进 final_<提交>/）。
"""
import argparse, glob, gzip, json, os, re, tempfile
from pathlib import Path
import godot_runner
import encrypted_release

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 25 * 1000 * 1000
PROBE = r'''extends SceneTree
var audience = __AUDIENCE__
func _initialize():
    AudioServer.set_bus_mute(0, true)
    call_deferred("_verify")
func _empty_progress(c) -> bool:
    return int(c.get_value("progress", "diff_unlocked", 0)) == 0 and c.get_value("progress", "seen_relics", []).is_empty() and c.get_value("progress", "endings_cleared", []).is_empty() and c.get_value("progress", "gallery_seen", []).is_empty()
func _verify():
    var failures: Array = []
    var info = JSON.parse_string(FileAccess.get_file_as_string("res://data/build.json"))
    if not info is Dictionary or info.get("audience", "") != audience or info.get("platform", "") != "web" or info.get("commit", "dev") == "dev":
        failures.append("build_metadata")
    var cfg = root.get_node_or_null("Cfg")
    if cfg == null:
        failures.append("cfg_missing")
    else:
        if OS.is_debug_build() or not cfg.dev_args().is_empty():
            failures.append("release_debug_gate")
        if cfg.build_audience() != audience:
            failures.append("build_audience")
        if cfg.unlock_all != (audience == "internal"):
            failures.append("unlock_all_audience")
        if cfg.can_boss_trial() != (audience == "internal"):
            failures.append("boss_trial_audience")
        if audience == "internal":
            if cfg.diff_unlocked == 0 or cfg.endings_cleared.is_empty() or cfg.seen_relics.is_empty():
                failures.append("internal_unlock_incomplete")
            cfg.save()
            var saved = ConfigFile.new()
            if saved.load("user://settings.cfg") != OK:
                failures.append("internal_save_missing")
            elif not _empty_progress(saved):
                failures.append("unlock_written_to_save")
        elif cfg.diff_unlocked != 0 or not cfg.endings_cleared.is_empty() or not cfg.seen_relics.is_empty() or not cfg.gallery_seen.is_empty():
            failures.append("fresh_progress")
    var result = {"audience": audience, "commit": str(info.get("commit", "")) if info is Dictionary else "", "unlock_all": cfg != null and cfg.unlock_all, "boss_trial": cfg != null and cfg.can_boss_trial(), "failures": failures}
    print("WEB_VERIFY_JSON=" + JSON.stringify(result))
    quit(0 if failures.is_empty() else 2)
'''


def reassemble(web_dir, out_path):
    parts = sorted(glob.glob(os.path.join(web_dir, "index.pck.*.gz")), key=lambda p: int(re.search(r"\.(\d+)\.gz$", p).group(1)))
    if not parts:
        raise SystemExit("没有 index.pck 分片：%s" % web_dir)
    with open(out_path, "wb") as fh:
        for p in parts:
            fh.write(gzip.decompress(open(p, "rb").read()))
    return len(parts)


def isolated_run(args, timeout, directory):
    saved = {k: os.environ.get(k) for k in ("APPDATA", "LOCALAPPDATA", "ARK_REAL_USERDIR")}
    try:
        os.environ["ARK_REAL_USERDIR"] = "1"   # 用这里的临时用户目录，不要 godot_runner 换成测试设置目录
        for k in ("APPDATA", "LOCALAPPDATA"):
            d = Path(directory) / k
            d.mkdir(exist_ok=True)
            os.environ[k] = str(d)
        return godot_runner.run_godot(args, timeout)
    finally:
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, type=Path)
    ap.add_argument("--audience", required=True, choices=["public", "internal"])
    ap.add_argument("--commit", default=None)
    a = ap.parse_args()
    web = a.dir.resolve()
    if not (web / "index.html").is_file():
        raise SystemExit("不是网页包目录：%s" % web)
    big = max(p.stat().st_size for p in web.iterdir() if p.is_file())
    if big > LIMIT:
        raise SystemExit("有文件超过 25 MB：%.2f MiB" % (big / 1048576))
    # 普通 release 模板编译时关了路径覆盖（不认 --main-pack），用加密发布那套自编译的 release 诊断模板（同 4.7.2 源码，
    # verify_encrypted_game.py 也用它）；它带密钥，但网页 PCK 不加密，照样能读
    template = encrypted_release.diagnostic_verifier()
    (ROOT / "build").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="web_probe_", dir=ROOT / "build") as d:
        pck = Path(d) / "index.pck"
        n = reassemble(str(web), pck)
        probe = Path(d) / "probe.gd"
        probe.write_text(PROBE.replace("__AUDIENCE__", json.dumps(a.audience)), encoding="utf-8")
        out, err, timeout = isolated_run([str(template), "--headless", "--audio-driver", "Dummy", "--main-pack", str(pck), "--script", str(probe)], 180, d)
    line = next((l for l in out.splitlines() if l.startswith("WEB_VERIFY_JSON=")), None)
    errors = [l for l in (out + "\n" + err).splitlines() if ("SCRIPT ERROR" in l or "Parse Error" in l)]
    if timeout or line is None or errors:
        raise SystemExit("网页包探针失败（超时=%s）：\n%s" % (timeout, "\n".join((out + "\n" + err).splitlines()[-30:])))
    result = json.loads(line.split("=", 1)[1])
    result.update({"pck_parts": n, "max_file_mib": round(big / 1048576, 2), "dir": str(web)})
    if a.commit and result.get("commit") != a.commit:
        result["failures"].append("commit_mismatch:%s" % result.get("commit"))
    report = web.parent / ("web_verification_%s_%s.json" % (a.audience, result.get("commit") or "unknown"))
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
    print("Report:", report)
    raise SystemExit(0 if not result["failures"] else 1)


if __name__ == "__main__":
    main()
