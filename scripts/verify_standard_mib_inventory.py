# py-based consistency checks for the SNMP/MIB sidecar
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INV = ROOT / "docs" / "STANDARD_MIB_SNMP_INVENTORY.json"


def sha256(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    d = json.loads(INV.read_text(encoding="utf-8"))
    assert "not a complete" in d["scope"].lower()
    assert d["object_count"] == len(d["objects"])
    assert d["missing_module_count"] >= 3
    assert {x["protocol"] for x in d["protocol_policy"]} == {"SNMPv1", "SNMPv2c", "SNMPv3"}
    p = {x["protocol"]: x for x in d["protocol_policy"]}
    assert p["SNMPv1"]["wire_status"] == "BOUNDED_MAC_PATH_PASS"
    assert p["SNMPv2c"]["wire_status"] == "BOUNDED_MAC_PATH_PASS"
    assert p["SNMPv3"]["wire_status"] == "NOAUTH_NOPRIV_MAC_PATH_PASS"
    assert any(x["module"] == "IF-MIB" and not x["vendor_source_available"] for x in d["selected_standard_policy"])
    assert all(x["implementation_status"] == "OPEN" for x in d["objects"])
    assert (ROOT / "rtl" / "afdx_snmp_wire.v").is_file()
    assert p["SNMPv3"]["security_scope"] == "noAuthNoPriv; authenticated/privacy-protected packets rejected"
    for x in d["objects"]:
        source = ROOT / x["source"] if x["source"].startswith("vendor/") else ROOT / "vendor" / "pysnmp" / "smi" / "mibs" / x["source"]
        assert source.exists(), source
        assert sha256(source) == x["source_sha256"], x["name"]
        assert x["oid"] and x["module"] and x["evidence_boundary"]
    print(f"SNMP_MIB_SIDECAR_CHECK_PASS objects={len(d['objects'])} modules={len(d['selected_standard_policy'])}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
