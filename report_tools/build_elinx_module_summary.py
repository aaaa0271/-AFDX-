"""Summarize all eLinx evidence dirs into a report-ready table.

Usage: python report_tools/build_elinx_module_summary.py
Writes data/elinx_modules.md and prints the table.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RPT = ROOT / "results/report"
EV = RPT / "evidence"
DATA = RPT / "data"


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


rows = []
for d in sorted(EV.glob("elinx_*")):
    st = d / "status.json"
    if not st.is_file():
        rows.append((d.name, "(running/no status)", "", "", "", "", ""))
        continue
    s = json.loads(st.read_text(encoding="utf-8"))
    log = d / "elaboration.log"
    text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    m = re.search(r"Analysis & Elaboration was successful\. 0 errors, (\d+) warnings", text)
    oom = re.search(r"Out of memory in module quartus_map\.exe \((\d+) megabytes used\)", text)
    note = ""
    if s.get("status") == "PASS":
        note = m.group(0) if m else "PASS"
    elif oom:
        note = f"OOM {int(oom.group(1)) // 1000} GB"
    elif s.get("status") == "FAIL":
        note = "FAIL (interrupted/error)"
    rows.append((d.name, s.get("top"), s.get("status"), s.get("errors"), s.get("warnings"),
                 round((s.get("seconds") or 0) / 60, 1), note))

lines = ["# eLinx 分模块展开汇总（报告引用）", "",
         "| 证据目录 | 顶层 | 结果 | errors | warnings | 耗时(min) | 说明 | status.json SHA-256 |",
         "|---|---|---|---:|---:|---:|---|---|"]
for name, top, status, err, warn, mins, note in rows:
    st = EV / name / "status.json"
    sig = sha(st)[:16] + "…" if st.is_file() else "—"
    lines.append(f"| `{name}` | `{top}` | **{status}** | {err} | {warn} | {mins} | {note} | `{sig}` |")
lines += ["", "注：仅 analysis/elaboration，非布局布线/时序收敛；统一防御顶层两次 OOM 作为资源需求证据保留。", ""]
(DATA / "elinx_modules.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
