from tool_paths import modelsim as find_modelsim
from tool_paths import elinx as find_elinx
"""Static report extractor: environment, inventory, hierarchy, tests, feature matrix.

Run from the project root:  python report_tools/extract_static.py
Writes JSON/CSV/Markdown into report_20261020/data/.
"""
import json
import os
import platform
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "results/report" / "data"
OUT.mkdir(parents=True, exist_ok=True)


def write_json(name, obj):
    (OUT / name).write_text(json.dumps(obj, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run_text(cmd, cwd=None, timeout=40):
    try:
        p = subprocess.run(cmd, cwd=cwd, capture_output=True, timeout=timeout,
                           creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        return ((p.stdout or b"") + b"\n" + (p.stderr or b"")).decode("utf-8", "replace").strip()
    except Exception as e:  # noqa: BLE001
        return f"<unavailable: {e}>"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


# ---------------------------------------------------------------- environment
model_sim = find_modelsim()
elinx = find_elinx()
env = {
    "generated_at": __import__("datetime").datetime.now().astimezone().isoformat(timespec="seconds"),
    "os": platform.platform(),
    "machine": platform.machine(),
    "logical_cpus": os.cpu_count(),
    "python": sys.version.split()[0],
    "python_exe": sys.executable,
    "modelsim_exe": str(model_sim) if model_sim.is_file() else None,
    "modelsim_version": run_text([str(model_sim), "-version"]) if model_sim.is_file() else None,
    "elinx_exe": str(elinx) if elinx.is_file() else None,
    "elinx_version": run_text([str(elinx), "--version"]) if elinx.is_file() else None,
    "packages": {},
}
for pkg in ("numpy", "cryptography", "docx", "matplotlib"):
    try:
        mod = __import__(pkg)
        env["packages"][pkg] = getattr(mod, "__version__", "?")
    except Exception:  # noqa: BLE001
        env["packages"][pkg] = None
write_json("env.json", env)

# ---------------------------------------------------------------- inventory
rtl_files = sorted((ROOT / "rtl").glob("*.v"))
tb_files = sorted((ROOT / "tb").glob("*.v"))


def loc(path):
    return len(path.read_text(encoding="utf-8", errors="replace").splitlines())


rtl_loc = sum(loc(p) for p in rtl_files)
tb_loc = sum(loc(p) for p in tb_files)
plugin_loc = {}
for name in ("aihw_plugin", "mimic_plugin", "afdx_ai", "afdx_agent", "host", "security_lab"):
    d = ROOT / name
    if d.is_dir():
        vs = [p for p in d.rglob("*.v") if p.is_file()]
        pys = [p for p in d.rglob("*.py") if p.is_file()]
        plugin_loc[name] = {
            "v_files": len(vs), "v_loc": sum(loc(p) for p in vs),
            "py_files": len(pys), "py_loc": sum(loc(p) for p in pys),
        }

tests = json.loads((ROOT / "scripts/tests.json").read_text(encoding="utf-8"))
suites = OrderedDict()
for t in tests:
    suites.setdefault(t["suite"], []).append(t["name"])

inventory = {
    "rtl_files": len(rtl_files), "rtl_loc": rtl_loc,
    "tb_files": len(tb_files), "tb_loc": tb_loc,
    "tests": len(tests),
    "suites": {k: {"count": len(v), "tests": v} for k, v in suites.items()},
    "plugins": plugin_loc,
    "docs_files": len([p for p in (ROOT / "docs").rglob("*") if p.is_file()]),
    "scripts_files": len([p for p in (ROOT / "scripts").glob("*.py")]),
    "version": (ROOT / "VERSION.txt").read_text(encoding="utf-8", errors="replace").strip(),
}
write_json("inventory.json", inventory)

# ---------------------------------------------------------------- hierarchy
module_names = {}
for p in rtl_files:
    text = strip_comments(p.read_text(encoding="utf-8", errors="replace"))
    for m in re.finditer(r"(?m)^\s*module\s+(\w+)", text):
        module_names[m.group(1)] = p
# the project compiles the AI plugin RTL as part of every test; include it in the graph
ai_src = ROOT / "aihw_plugin" / "rtl" / "afdx_ai_tcn_plugin.v"
if ai_src.is_file():
    module_names.setdefault("afdx_ai_tcn_plugin", ai_src)

children = {}
for name, p in module_names.items():
    text = strip_comments(p.read_text(encoding="utf-8", errors="replace"))
    # drop the module header up to the first ');'
    body = text.split(");", 1)[1] if ");" in text else text
    kids = []
    for other in module_names:
        if other == name:
            continue
        if re.search(r"(?<![\w$])" + re.escape(other) + r"(?![\w$])", body):
            kids.append(other)
    children[name] = sorted(set(kids))


def tree(name, depth=0, seen=None):
    seen = seen or set()
    lines = ["  " * depth + name]
    if name in seen or depth > 8:
        return lines
    seen.add(name)
    for k in children.get(name, []):
        lines += tree(k, depth + 1, seen)
    return lines


tops = [t for t in ("AFDX_defense_top", "AFDX_competition_top", "AFDX_top",
                    "AFDX_security_plugin_top", "AFDX_security_8port_top",
                    "AFDX_legacy_top", "AFDX_basic_top") if t in module_names]
hierarchy = {"tops": tops, "children": children, "trees": {t: tree(t) for t in tops}}
write_json("hierarchy.json", hierarchy)
(OUT / "hierarchy.txt").write_text("\n\n".join("\n".join(v) for v in hierarchy["trees"].values()) + "\n",
                                   encoding="utf-8")

# ---------------------------------------------------------------- top port counts
def port_count(path):
    text = strip_comments(path.read_text(encoding="utf-8", errors="replace"))
    m = re.search(r"(?m)^\s*module\s+\w+", text)
    if not m:
        return None
    i = m.end()
    while i < len(text) and text[i].isspace():
        i += 1
    if i < len(text) and text[i] == "#":          # skip the parameter list
        i = text.find("(", i)
        depth = 0
        while i < len(text):
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    i += 1
                    break
            i += 1
        while i < len(text) and text[i].isspace():
            i += 1
    if i >= len(text) or text[i] != "(":
        return None
    depth = 0
    start = i
    while i < len(text):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = text[start + 1:i]
    if not body.strip():
        return 0
    depth = 0
    n = 1
    for ch in body:
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
        elif ch == "," and depth == 0:
            n += 1
    return n


ports = {t: port_count(module_names[t]) for t in tops}
write_json("top_ports.json", ports)

# ---------------------------------------------------------------- tests csv
rows = ["name,suite,file,marker,error_counter,run_ms,auditors,driver"]
for t in tests:
    aud = ";".join(a[0] for a in t.get("auditors", []))
    rows.append(",".join([t["name"], t["suite"], t["file"], t.get("marker", ""),
                          t.get("error_counter", ""), str(t.get("run_ms", "")), aud,
                          t.get("driver", "")]))
(OUT / "tests.csv").write_text("\n".join(rows) + "\n", encoding="utf-8")

# ---------------------------------------------------------------- feature matrix
spec = json.loads((ROOT / "docs/competition_requirements.json").read_text(encoding="utf-8"))
known = {t["name"] for t in tests}
matrix = []
for req in spec["requirements"]:
    listed = req["tests"]
    missing = [n for n in listed if n not in known]
    matrix.append({"id": req["id"], "name": req["name"], "tests": listed,
                   "missing_from_tests_json": missing})
write_json("feature_matrix.json", matrix)

print("wrote:", ", ".join(sorted(p.name for p in OUT.iterdir())))
print("rtl", len(rtl_files), "loc", rtl_loc, "| tb", len(tb_files), "loc", tb_loc, "| tests", len(tests))
print("tops:", tops, "ports:", ports)
