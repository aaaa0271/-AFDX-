from tool_paths import elinx as find_elinx
"""Snapshot the environment used for an eLinx run (evidence for the report).

Usage:
    python report_tools/record_env.py --run report_20261020/evidence/elinx_defense_48g
Writes <run>/env_before.json (or env_at_finish.json with --phase finish) and merges the
memory fields into report_20261020/data/env.json.
"""
import argparse
import hashlib
import json
import os
import platform
import subprocess
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RPT = ROOT / "results/report"
DATA = RPT / "data"

PS = r"""
[Console]::OutputEncoding=[System.Text.Encoding]::UTF8
$OutputEncoding=[System.Text.Encoding]::UTF8
$ErrorActionPreference='SilentlyContinue'
$cs = Get-CimInstance Win32_ComputerSystem
$pf = Get-CimInstance Win32_PageFileSetting | ForEach-Object { [pscustomobject]@{name=$_.Name; initial=$_.InitialSize; maximum=$_.MaximumSize} }
$pu = Get-CimInstance Win32_PageFileUsage | ForEach-Object { [pscustomobject]@{name=$_.Name; allocated_mb=$_.AllocatedBaseSize; peak_mb=$_.PeakUsage} }
$cpu = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
[pscustomobject]@{
  cpu=$cpu
  logical_cpus=$cs.NumberOfLogicalProcessors
  ram_gb=[math]::Round($cs.TotalPhysicalMemory/1GB,1)
  automatic_managed_pagefile=$cs.AutomaticManagedPagefile
  pagefiles=$pf
  pagefile_usage=$pu
  commit_limit_gb=[math]::Round((Get-Counter '\Memory\Commit Limit').CounterSamples[0].CookedValue/1GB,1)
} | ConvertTo-Json -Depth 4
"""


def ps_json():
    p = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", PS],
                       capture_output=True, timeout=60,
                       creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
    text = p.stdout.decode("utf-8", "replace")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return json.loads(p.stdout.decode("gbk", "replace"))


def tool_version(exe):
    try:
        p = subprocess.run([str(exe), "--version"], capture_output=True, timeout=30,
                           creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0)
        text = ((p.stdout or b"") + (p.stderr or b"")).decode("utf-8", "replace")
        return text.strip().splitlines()[0]
    except Exception as e:  # noqa: BLE001
        return f"<unavailable: {e}>"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run", type=Path, required=True)
    ap.add_argument("--phase", choices=("before", "finish"), default="before")
    ap.add_argument("--top", default="AFDX_defense_top")
    a = ap.parse_args()
    run = (ROOT / a.run).resolve() if not a.run.is_absolute() else a.run.resolve()
    run.mkdir(parents=True, exist_ok=True)

    elinx = find_elinx()
    snap = {
        "captured_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "phase": a.phase,
        "run_dir": str(run),
        "top": a.top,
        "os": platform.platform(),
        "tool": str(elinx) if elinx.is_file() else None,
        "tool_version": tool_version(elinx) if elinx.is_file() else None,
        "python": sys.version.split()[0],
        "platform": platform.platform(),
        "sources": len(list((ROOT / "rtl").glob("*.v"))) + 1,
        "memory": ps_json(),
    }
    out = run / (f"env_{a.phase}.json")
    out.write_text(json.dumps(snap, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    DATA.mkdir(parents=True,exist_ok=True)
    DATA.mkdir(parents=True,exist_ok=True)
    # merge into the report's env.json so the document data stays consistent
    envp = DATA / "env.json"
    env = json.loads(envp.read_text(encoding="utf-8")) if envp.is_file() else {}
    env["memory_at_" + a.phase] = snap["memory"]
    env["elinx_tool_version"] = snap["tool_version"]
    env["elinx_snapshot_" + a.phase] = str(out)
    envp.write_text(json.dumps(env, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print("wrote", str(out))
    print("sha256", hashlib.sha256(out.read_bytes()).hexdigest()[:16])
    print(json.dumps(snap["memory"], indent=2, ensure_ascii=False)[:800])


if __name__ == "__main__":
    main()
