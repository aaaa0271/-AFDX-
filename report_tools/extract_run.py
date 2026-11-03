"""Extract report data from one run_all output directory.

Usage (from project root):
    python report_tools/extract_run.py [run_dir]
Defaults to the newest directory under results/.
"""
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results/report" / "data"
OUT.mkdir(parents=True, exist_ok=True)

if len(sys.argv) > 1:
    run = Path(sys.argv[1])
else:
    runs = sorted((p for p in (ROOT / "results").iterdir() if p.is_dir()), key=lambda p: p.name)
    run = runs[-1]
print("run:", run)


def read_json(p, default=None):
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return default


acc = read_json(run / "acceptance.json", {})
comp = read_json(run / "competition_acceptance.json", {})
rows = list(csv.DictReader((run / "results.csv").open(encoding="utf-8"))) if (run / "results.csv").is_file() else []

suites = {}
for r in rows:
    s = suites.setdefault(r["suite"], {"total": 0, "pass": 0, "fail": 0})
    s["total"] += 1
    s["pass" if r["status"] == "PASS" else "fail"] += 1

summary = {
    "run": run.as_posix(),
    "started_at": acc.get("started_at"),
    "finished_at": acc.get("finished_at"),
    "release": acc.get("release"),
    "functional_status": acc.get("functional_status"),
    "full_functional_regression": acc.get("full_functional_regression"),
    "delivery_status": acc.get("delivery_status"),
    "competition_status": comp.get("status"),
    "competition_complete": comp.get("competition_prototype_complete"),
    "competition_issues": comp.get("issues"),
    "competition_requirements": comp.get("requirements"),
    "conformance_status": acc.get("conformance_status"),
    "production_hdl": [acc.get("production_hdl_passed"), acc.get("production_hdl_total")],
    "experimental": [acc.get("experimental_model_passed"), acc.get("experimental_model_total")],
    "changed_inputs": acc.get("changed_inputs"),
    "preflight_gates": acc.get("preflight_gates"),
    "elinx": acc.get("elinx"),
    "tests_total": len(rows),
    "tests_pass": sum(1 for r in rows if r["status"] == "PASS"),
    "suites": suites,
}
(OUT / "results_summary.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# per-test + audits
with (OUT / "per_test.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["name", "suite", "status", "exit", "log"])
    for r in rows:
        w.writerow([r["name"], r["suite"], r["status"], r["exit"], r["log"]])

with (OUT / "suite_summary.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["suite", "total", "pass", "fail"])
    for k, v in suites.items():
        w.writerow([k, v["total"], v["pass"], v["fail"]])

audit_rows = []
for r in rows:
    st = read_json(run / r["name"] / "status.json", {})
    for a in st.get("audits", []) or []:
        audit_rows.append([r["name"], a.get("script"), a.get("exit"), a.get("log", "")])
with (OUT / "audits.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["test", "auditor", "exit", "log"])
    w.writerows(audit_rows)

# metric-ish lines from every test log (curate later)
patterns = re.compile(
    r"(MEASURE|FINAL|SUMMARY|_PASS|CASES=|cycles=|signals=|errors=|"
    r"\b\d+(?:\.\d+)?\s*(?:ns|us|µs|ms|s|cycles|Mbps|Mbit/s|bytes|KB|%)\b)", re.I)
metric_rows = []
for r in rows:
    for log in (run / r["name"] / "result.log", run / r["name"] / "console.log"):
        if not log.is_file():
            continue
        seen = set()
        for i, line in enumerate(log.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
            s = re.sub(r"^#\s?", "", line).strip()
            if not s or s in seen:
                continue
            if patterns.search(s):
                seen.add(s)
                metric_rows.append([r["name"], r["suite"], f"{log.name}:{i}", s[:300]])
with (OUT / "metric_lines.csv").open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["test", "suite", "where", "line"])
    w.writerows(metric_rows)

# evidence index (sha256 of key files, not the whole tree)
index = {}
for rel in ("results.csv", "acceptance.json", "competition_acceptance.json", "conformance.json",
            "source_hashes.json", "source_changes.json", "project_audit.json"):
    p = run / rel
    if p.is_file():
        index[rel] = {"bytes": p.stat().st_size, "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
for sub in ("elinx", "elinx_multi"):
    for name in ("status.json", "elaboration.log"):
        p = run / sub / name
        if p.is_file():
            index[f"{sub}/{name}"] = {"bytes": p.stat().st_size,
                                      "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
(OUT / "evidence_index.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")

print("tests:", summary["tests_pass"], "/", summary["tests_total"], "| delivery:", summary["delivery_status"],
      "| competition:", summary["competition_status"], "| fw:", summary["functional_status"])
print("wrote results_summary.json, per_test.csv, suite_summary.csv, audits.csv, metric_lines.csv, evidence_index.json")
