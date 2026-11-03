"""Collect evidence for one eLinx run after it finishes.

Usage:
    python report_tools/finalize_elinx.py --run report_20261020/evidence/elinx_defense_48g
Writes <run>/EVIDENCE.md + <run>/evidence_index.json, merges into data/evidence_index.json,
and writes data/elinx_evidence.md (report-ready summary with file hashes).
"""
import argparse
import hashlib
import json
import re
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RPT = ROOT / "results/report"
DATA = RPT / "data"


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True)
    a = ap.parse_args()
    run = (ROOT / a.run).resolve() if not a.run.is_absolute() else a.run.resolve()
    status_p = run / "status.json"
    log_p = run / "elaboration.log"
    if not status_p.is_file():
        print("status.json missing; run not finished:", run)
        return 2
    st = json.loads(status_p.read_text(encoding="utf-8"))
    log = log_p.read_text(encoding="utf-8", errors="replace") if log_p.is_file() else ""
    m = re.search(r"Analysis & Elaboration was successful\. 0 errors, (\d+) warnings", log)
    oom = re.search(r"Out of memory in module quartus_map\.exe \((\d+) megabytes used\)", log)
    error_lines = [l for l in log.splitlines() if re.search(r"Error \(\d+\)", l)][:20]

    files = ["status.json", "elaboration.log", "command.json", "ARINC.qsf", "ARINC.qpf",
             "env_before.json", "env_finish.json"]
    idx = {}
    for name in files:
        p = run / name
        if p.is_file():
            idx[name] = {"bytes": p.stat().st_size, "sha256": sha(p)}

    summary = {
        "run": str(run),
        "finished_at": st.get("finished_at") or datetime.now().astimezone().isoformat(timespec="seconds"),
        "top": st.get("top"),
        "service_domains": st.get("service_domains"),
        "status": st.get("status"),
        "exit": st.get("exit"),
        "errors": st.get("errors"),
        "warnings": st.get("warnings"),
        "seconds": st.get("seconds"),
        "sources": st.get("sources"),
        "log_success_line": m.group(0) if m else None,
        "out_of_memory": (int(oom.group(1)) if oom else None),
        "error_lines": error_lines,
        "files": idx,
    }
    (run / "evidence_index.json").write_text(json.dumps(idx, indent=2) + "\n", encoding="utf-8")

    md = [f"# eLinx 证据：{summary['run']}", ""]
    md.append(f"- 顶层：`{summary['top']}`（service_domains={summary['service_domains']}）")
    md.append(f"- 结果：**{summary['status']}**，exit={summary['exit']}，errors={summary['errors']}，warnings={summary['warnings']}")
    md.append(f"- 耗时：{summary['seconds']} s（{(summary['seconds'] or 0) / 60:.1f} min）")
    md.append(f"- 源文件：{summary['sources']} 个")
    if summary["log_success_line"]:
        md.append(f"- 成功行：`{summary['log_success_line']}`")
    if summary["out_of_memory"]:
        md.append(f"- 内存耗尽：{summary['out_of_memory']} MB")
    for e in error_lines:
        md.append(f"- 错误行：`{e.strip()[:200]}`")
    md.append("")
    md.append("| 文件 | 字节 | SHA-256 |")
    md.append("|---|---:|---|")
    for name, v in idx.items():
        md.append(f"| `{name}` | {v['bytes']} | `{v['sha256']}` |")
    md.append("")
    (run / "EVIDENCE.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    DATA.mkdir(parents=True,exist_ok=True)
    DATA.mkdir(parents=True,exist_ok=True)
    # merge into the report-wide evidence index
    ep = DATA / "evidence_index.json"
    merged = json.loads(ep.read_text(encoding="utf-8")) if ep.is_file() else {}
    for name, v in idx.items():
        merged[f"{summary['run']}/{name}"] = v
    ep.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")

    # report-ready one-liner
    if summary["status"] == "PASS" and summary["log_success_line"]:
        line = (f"eLinx 对 `{summary['top']}` 做 analysis/elaboration："
                f"0 error / {summary['warnings']} warning（{summary['seconds'] / 60:.1f} 分钟，{summary['sources']} 个源文件）。")
    elif summary["out_of_memory"]:
        line = (f"eLinx 对 `{summary['top']}` 的展开在 {summary['out_of_memory']} MB 处内存耗尽（本机提交上限 93.6 GB）。")
    else:
        line = f"eLinx 对 `{summary['top']}` 的展开未完成（status={summary['status']}，见 {summary['run']}/elaboration.log）。"
    (DATA / "elinx_evidence.md").write_text(
        "\n".join(["# eLinx 结果（报告引用）", "", line, "",
                   f"证据目录：`{summary['run']}`（`EVIDENCE.md` 内含逐文件 SHA-256）", ""]) + "\n",
        encoding="utf-8")
    print(line)
    print("evidence:", (run / "EVIDENCE.md").relative_to(ROOT).as_posix())
    return 0 if summary["status"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
