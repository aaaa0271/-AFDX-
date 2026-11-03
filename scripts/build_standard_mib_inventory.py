from __future__ import annotations
import hashlib, json, re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIB_DIR = ROOT / "vendor" / "pysnmp" / "smi" / "mibs"
OUT = ROOT / "docs" / "STANDARD_MIB_SNMP_INVENTORY.json"

# These are the modules that affect the declared management-plane scope.  The
# vendored PySNMP tree is an evidence source, not normative text.
MODULE_POLICY = [
    ("RFC1213-MIB", "RFC1213", "MIB-II legacy system/interfaces/ip/icmp/tcp/udp/snmp definitions", "conditional", "source_available_inventory_only"),
    ("SNMPv2-MIB", "SNMPv2-MIB", "system, SNMP counters, notification and conformance objects", "applicable", "source_available_inventory_only"),
    ("SNMP-FRAMEWORK-MIB", "SNMP-FRAMEWORK-MIB", "SNMP engine/context framework objects", "conditional_on_snmpv3", "source_available_inventory_only"),
    ("SNMP-MPD-MIB", "SNMP-MPD-MIB", "message-processing and dispatcher counters", "conditional_on_snmpv3", "source_available_inventory_only"),
    ("SNMP-USER-BASED-SM-MIB", "SNMP-USER-BASED-SM-MIB", "USM users, keys and counters", "conditional_on_snmpv3_usm", "source_available_inventory_only"),
    ("SNMP-VIEW-BASED-ACM-MIB", "SNMP-VIEW-BASED-ACM-MIB", "VACM contexts, views and access rules", "conditional_on_snmpv3_vacm", "source_available_inventory_only"),
    ("SNMP-COMMUNITY-MIB", "SNMP-COMMUNITY-MIB", "v1/v2c/v3 coexistence/proxy configuration", "conditional_on_coexistence_or_proxy", "source_available_inventory_only"),
    ("SNMP-TARGET-MIB", "SNMP-TARGET-MIB", "notification target configuration", "conditional_on_notification_originator", "source_available_inventory_only"),
    ("SNMP-NOTIFICATION-MIB", "SNMP-NOTIFICATION-MIB", "notification filters and event targets", "conditional_on_notification_originator", "source_available_inventory_only"),
    ("SNMP-PROXY-MIB", "SNMP-PROXY-MIB", "proxy forwarding configuration", "conditional_on_proxy", "source_available_inventory_only"),
    ("SNMP-USER-BASED-SM-3DES-MIB", "SNMP-USER-BASED-SM-3DES-MIB", "USM 3DES privacy extension", "conditional_on_3des", "source_available_inventory_only"),
    ("SNMP-USM-AES-MIB", "SNMP-USM-AES-MIB", "USM AES privacy extension", "conditional_on_usm_aes", "source_available_inventory_only"),
    ("SNMP-USM-HMAC-SHA2-MIB", "SNMP-USM-HMAC-SHA2-MIB", "USM HMAC-SHA2 extension", "conditional_on_usm_sha2", "source_available_inventory_only"),
    ("IF-MIB", "RFC2863", "current interface MIB", "applicable_if_claimed", "source_missing_from_vendor_tree"),
    ("IP-MIB", "RFC4293", "current IP MIB", "applicable_if_claimed", "source_missing_from_vendor_tree"),
    ("UDP-MIB", "RFC4113", "current UDP MIB", "applicable_if_claimed", "source_missing_from_vendor_tree"),
    ("TCP-MIB", "RFC4022", "current TCP MIB", "not_applicable_to_udp_only_scope", "source_missing_from_vendor_tree"),
]

OBJ_START = re.compile(r"^(?P<name>[A-Za-z][A-Za-z0-9_]*)\s*=\s*(?P<rhs>[_A-Za-z][A-Za-z0-9_]*)\s*\(")
ALIAS = re.compile(r"^(?P<alias>_[A-Za-z][A-Za-z0-9_]*_Object)\s*=\s*(?P<class>[A-Za-z][A-Za-z0-9_]*)\s*$")
TYPE = re.compile(r"^(?P<alias>_[A-Za-z][A-Za-z0-9_]*_Type)\s*=\s*(?P<class>[A-Za-z][A-Za-z0-9_]*)\s*$")
OID = re.compile(r"\(\s*(?P<oid>\d+(?:\s*,\s*\d+)*)\s*\)")
MAXACCESS = re.compile(r"\.setMaxAccess\(\s*[\"']([^\"']+)[\"']\s*\)")
STATUS = re.compile(r"\.setStatus\(\s*[\"']([^\"']+)[\"']\s*\)")
INDEX = re.compile(r"\.setIndexNames\(")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_module(path: Path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    aliases, types = {}, {}
    for line in lines:
        m = ALIAS.match(line.strip())
        if m:
            aliases[m.group("alias")] = m.group("class")
        m = TYPE.match(line.strip())
        if m:
            types[m.group("alias")] = m.group("class")
    starts = [i for i, line in enumerate(lines) if OBJ_START.match(line)]
    result = []
    for n, start in enumerate(starts):
        m = OBJ_START.match(lines[start])
        if not m:
            continue
        end = starts[n + 1] if n + 1 < len(starts) else len(lines)
        block = "\n".join(lines[start:end])
        oid_m = OID.search(block)
        if not oid_m:
            continue
        oid = ".".join(x.strip() for x in oid_m.group("oid").split(","))
        rhs = m.group("rhs")
        kind = aliases.get(rhs, rhs)
        if kind not in {"MibScalar", "MibTable", "MibTableRow", "MibTableColumn", "NotificationType", "ObjectIdentity", "ModuleIdentity", "MibIdentifier"}:
            continue
        # A generated MIB object has a type constructor after the OID.  The
        # alias is local to the generated file, so resolve it without import.
        type_name = None
        type_m = re.search(r"\),\s*(_[A-Za-z][A-Za-z0-9_]*_Type)\(\)", block)
        if type_m:
            type_name = types.get(type_m.group(1), type_m.group(1).lstrip("_"))
        access_m = MAXACCESS.search(block)
        status_m = STATUS.search(block)
        if kind in {"MibScalar", "MibTableColumn"}:
            instance = "scalar .0" if kind == "MibScalar" else "table row index required"
        elif kind in {"MibTable", "MibTableRow"}:
            instance = "conceptual table/row node"
        elif kind == "NotificationType":
            instance = "notification OID"
        else:
            instance = "identity/non-instance node"
        result.append({
            "name": m.group("name"),
            "oid": oid,
            "kind": kind,
            "asn1_type": type_name,
            "max_access": access_m.group(1) if access_m else None,
            "status": status_m.group(1) if status_m else None,
            "instance_policy": instance,
            "source": path.name,
            "source_sha256": sha256(path),
            "implementation_status": "OPEN",
            "evidence_boundary": "vendor_generated_MIB_metadata_only; no normative_certification",
        })
    # Keep one row per OID/name pair; generated modules can re-export symbols.
    unique = {}
    for row in result:
        unique[(row["name"], row["oid"], row["kind"])] = row
    return sorted(unique.values(), key=lambda x: tuple(int(v) for v in x["oid"].split(".")))


def main():
    module_rows, objects = [], []
    for module, standard, role, applicability, source_status in MODULE_POLICY:
        path = MIB_DIR / f"{module}.py"
        available = path.exists()
        row = {
            "module": module,
            "standard_reference": standard,
            "role": role,
            "applicability": applicability,
            "vendor_source_available": available,
            "source_status": source_status,
            "source_file": path.relative_to(ROOT).as_posix() if available else None,
            "source_sha256": sha256(path) if available else None,
            "object_count": 0,
            "module_status": "INVENTORY_ONLY" if available else "SOURCE_UNAVAILABLE_OPEN",
            "normative_claim": "none",
        }
        if available:
            rows = parse_module(path)
            for item in rows:
                item["module"] = module
                item["applicability"] = applicability
                item["implementation_status"] = "OPEN"
                objects.append(item)
            row["object_count"] = len(rows)
        module_rows.append(row)

    # Add explicit protocol baselines so absence of an RFC/MIB source cannot
    # be mistaken for implementation evidence.
    protocol_policy = [
        {"protocol": "SNMPv1", "message_version": 0, "wire_status": "BOUNDED_MAC_PATH_PASS", "policy_gate_status": "TESTED_WIRE", "independent_decode": "PySNMP RFC1157"},
        {"protocol": "SNMPv2c", "message_version": 1, "wire_status": "BOUNDED_MAC_PATH_PASS", "policy_gate_status": "TESTED_STANDALONE", "independent_decode": "pysnmp_v2c"},
        {"protocol": "SNMPv3", "message_version": 3, "wire_status": "NOAUTH_NOPRIV_MAC_PATH_PASS", "security_scope": "noAuthNoPriv; authenticated/privacy-protected packets rejected", "policy_gate_status": "TESTED_WIRE", "independent_decode": "PySNMP RFC3412/RFC3414"},
    ]
    data = {
        "generated_at": str(date.today()),
        "scope": "Standard MIB applicability and object sidecar generated from the vendored PySNMP generated MIB files. This is an inventory/evidence index, not normative text and not a complete ARINC/SNMP certification.",
        "source_root": "vendor/pysnmp/smi/mibs",
        "closure_rule": "A row remains OPEN until controlled normative source, applicability decision, exact RTL binding, positive and negative wire evidence, independent decode, and reproducible hashes are all present.",
        "selected_standard_policy": module_rows,
        "protocol_policy": protocol_policy,
        "objects": objects,
        "object_count": len(objects),
        "available_module_count": sum(1 for x in module_rows if x["vendor_source_available"]),
        "missing_module_count": sum(1 for x in module_rows if not x["vendor_source_available"]),
        "private_project_mib": {"object_count": 25, "status": "not_substituted_for_standard_MIB", "rtl": "rtl/afdx_snmp_extended.v; rtl/afdx_snmp_wire.v"},
        "rtl_sidecar": [
            {"file": "rtl/afdx_standard_mib_bank.v", "role": "bounded metadata/value bank", "status": "standalone_tested; not complete standard MIB implementation"},
            {"file": "rtl/afdx_snmp_version_gate.v", "role": "version/security admission policy gate", "status": "standalone policy tested; not a v1/v2c/v3 wire engine"},
            {"file": "rtl/afdx_snmp_mac.v", "role": "production SNMPv1/v2c/v3 MAC integration", "status": "v1/v2c community plus v3 USM noAuthNoPriv; authPriv not supported"},
        ],
    }
    OUT.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"STANDARD_MIB_INVENTORY_OBJECTS={len(objects)} AVAILABLE_MODULES={data['available_module_count']} MISSING_MODULES={data['missing_module_count']}")
    print(OUT)

if __name__ == "__main__":
    main()
