"""Wait for a running quartus_map to exit, then write status.json + finalize evidence.

Usage: python report_tools/attach_elinx_wait.py --run report_20261020/evidence/elinx_security --tool <path> --top <name> --domains 1 --sources 120 --started <ISO8601>
"""
import argparse
import json
import re
import subprocess
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True)
    ap.add_argument("--tool", required=True)
    ap.add_argument("--top", required=True)
    ap.add_argument("--domains", type=int, default=1)
    ap.add_argument("--sources", type=int, default=120)
    ap.add_argument("--started", required=True)
    ap.add_argument("--max-hours", type=float, default=8.0)
    a = ap.parse_args()
    run = (ROOT / a.run).resolve() if not a.run.is_absolute() else a.run.resolve()
    log = run / "elaboration.log"
    started = datetime.fromisoformat(a.started)
    print("attaching to", run, "started", a.started, flush=True)

    deadline = time.time() + a.max_hours * 3600
    while time.time() < deadline:
        r = subprocess.run(["powershell", "-NoProfile", "-Command",
                            "if(Get-Process quartus_map -ErrorAction SilentlyContinue){'RUN'}else{'GONE'}"],
                           capture_output=True, timeout=60,
                           creationflags=subprocess.CREATE_NO_WINDOW if __import__("os").name == "nt" else 0)
        if b"GONE" in r.stdout:
            break
        time.sleep(60)
    else:
        print("max wait reached; quartus still running", flush=True)
        return 3

    time.sleep(5)
    text = log.read_text(encoding="utf-8", errors="replace") if log.is_file() else ""
    m = re.search(r"Analysis & Elaboration was successful\. 0 errors, (\d+) warnings", text)
    oom = re.search(r"Out of memory in module quartus_map\.exe \((\d+) megabytes used\)", text)
    seconds = (datetime.now().astimezone() - started).total_seconds()
    ok = m is not None and "Out of memory" not in text
    result = dict(status="PASS" if ok else "FAIL", exit=0 if ok else 1, tool=a.tool, top=a.top,
                  service_domains=a.domains, errors=0 if ok else None,
                  warnings=int(m.group(1)) if m else None,
                  seconds=round(seconds, 1), sources=a.sources,
                  scope=f"{a.top} analysis/elaboration only; no fitting, routed timing or hardware claim",
                  note="attached to an orphaned quartus_map after the launcher shell exited; "
                       "log captured in full, verdict derived from the log")
    (run / "status.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "top", "errors", "warnings", "seconds")}, ensure_ascii=False), flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit('Legacy detached-task finalization is disabled: a log line cannot recover a missing process exit code.\nRun report_tools/run_elinx_defense.py --out NEW_DIRECTORY, which records exit status and raw output.\nUse report_tools/finalize_elinx.py --run FINISHED_DIRECTORY only to index evidence.\n')
