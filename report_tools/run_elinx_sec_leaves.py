from tool_paths import elinx as find_elinx
"""Elaborate leaf security sub-modules one by one with wrapper tops.

Each run gets its own evidence dir under report_20261020/evidence/elinx_sec_<name>/.
"""
import json
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RPT = ROOT / "results/report"
ELINX = find_elinx()

MODULES = ["afdx_sec_sha256", "afdx_sec_policy", "afdx_sec_time_monitor",
           "afdx_sec_events", "afdx_sec_frame_queue", "afdx_sec_replay"]


def run(top, out, extra_params=None):
    out.mkdir(parents=True, exist_ok=False)
    sources = sorted((ROOT / "rtl").glob("*.v")) + [ROOT / "aihw_plugin/rtl/afdx_ai_tcn_plugin.v"]
    params = ""
    if extra_params:
        params = " #(" + ",".join(f".{k}({v})" for k, v in extra_params.items()) + ")"
    wrapper = out / "AFDX_sec_elab_top.v"
    wrapper.write_text(
        "module AFDX_sec_elab_top;\n"
        f" {top}{params} dut();\n"
        "endmodule\n", encoding="utf-8")
    sources.append(wrapper)
    q = ["set_global_assignment -name DEVICE EP1S80F1508C6",
         "set_global_assignment -name FAMILY Stratix",
         "set_global_assignment -name TOP_LEVEL_ENTITY AFDX_sec_elab_top",
         "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output",
         "set_global_assignment -name VERILOG_INPUT_VERSION VERILOG_2001"]
    q += ['set_global_assignment -name VERILOG_FILE "' + p.as_posix() + '"' for p in sources]
    (out / "ARINC.qsf").write_text("\n".join(q) + "\n", encoding="utf-8")
    (out / "ARINC.qpf").write_text('PROJECT_REVISION = "ARINC"\n', encoding="utf-8")
    (out / "command.json").write_text(json.dumps([top, extra_params], indent=2) + "\n", encoding="utf-8")

    started = time.time()
    with (out / "elaboration.log").open("wb") as logf:
        p = subprocess.run([str(ELINX), "--read_settings_files=on", "--write_settings_files=off",
                            "--analysis_and_elaboration", "ARINC"],
                           cwd=out, stdout=logf, stderr=subprocess.STDOUT, timeout=1800,
                           creationflags=subprocess.CREATE_NO_WINDOW)
    text = (out / "elaboration.log").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"Analysis & Elaboration was successful\. 0 errors, (\d+) warnings", text)
    oom = re.search(r"Out of memory in module quartus_map\.exe \((\d+) megabytes used\)", text)
    ok = p.returncode == 0 and m is not None
    result = dict(status="PASS" if ok else "FAIL", exit=p.returncode, tool=str(ELINX), top=top,
                  service_domains=1, errors=0 if ok else None,
                  warnings=int(m.group(1)) if m else None,
                  seconds=round(time.time() - started, 1), sources=len(sources),
                  params=extra_params or {},
                  oom_mb=int(oom.group(1)) if oom else None,
                  scope=f"{top} analysis/elaboration only; no fitting/timing claim")
    (out / "status.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("status", "top", "errors", "warnings", "seconds", "oom_mb")},
                     ensure_ascii=False), flush=True)
    return result


if __name__ == "__main__":
    ev = RPT / "evidence"
    for name in MODULES:
        print("==", name, flush=True)
        run(name, ev / ("elinx_sec_" + name.replace("afdx_sec_", "")))
