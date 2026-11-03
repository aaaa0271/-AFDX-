from __future__ import annotations
import json
import re
import sys
from pathlib import Path

EXPECTED = {
    # name: (version,pdu,community,auth,priv,accepted,error,model,security)
    "v1_get": (0,0,1,0,0,1,0,0,1),
    "v1_set": (0,3,1,0,0,1,0,0,1),
    "v1_bad_community": (0,0,0,0,0,0,1,0,1),
    "v1_bad_pdu": (0,4,1,0,0,0,1,0,1),
    "v2c_get": (1,0,1,0,0,1,0,1,2),
    "v2c_bulk": (1,5,1,0,0,1,0,1,2),
    "v2c_bad_community": (1,0,0,0,0,0,2,1,2),
    "v2c_bad_pdu": (1,6,1,0,0,0,2,1,2),
    "v3_auth_priv": (3,0,0,1,1,1,0,3,3),
    "v3_auth_priv_bulk": (3,5,0,1,1,1,0,3,3),
    "v3_no_auth": (3,0,0,0,1,0,3,3,3),
    "v3_no_priv": (3,0,0,1,0,0,3,3,3),
    "v3_bad_pdu": (3,6,0,1,1,0,3,3,3),
    "unknown_v2": (2,0,1,0,0,0,4,0,0),
    "unknown_255": (255,0,1,0,0,0,4,0,0),
}
PAT = re.compile(r"SNMP_GATE_CASE name=(\S+) version=(\d+) pdu=(\d+) community=(\d+) auth=(\d+) priv=(\d+) accepted=(\d+) error=(\d+) model=(\d+) security=(\d+)")

def main() -> int:
    log = Path(sys.argv[1]).read_text(errors="replace")
    rows = []
    for m in PAT.finditer(log):
        name = m.group(1)
        if name not in EXPECTED:
            raise AssertionError(f"unexpected case {name}")
        observed = tuple(map(int, m.groups()[1:]))
        expected = EXPECTED[name]
        if observed != expected:
            raise AssertionError((name, observed, expected))
        rows.append({"name": name, "observed": observed, "status": "PASS"})
    if len(rows) != len(EXPECTED):
        raise AssertionError(f"case count {len(rows)} != {len(EXPECTED)}")
    out = Path(sys.argv[1]).with_name("snmp_wire_policy_matrix.json")
    out.write_text(json.dumps({"scope": "admission policy only; not a wire implementation claim", "cases": rows}, indent=2) + "\n")
    print(f"SNMP_WIRE_POLICY_AUDIT_PASS cases={len(rows)} output={out}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
