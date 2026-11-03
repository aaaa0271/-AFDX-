# Standard MIB / SNMP sidecar evidence review

This sidecar is deliberately an **evidence inventory**, not a declaration of complete
SNMP or ARINC certification. It is generated from the vendored PySNMP-generated
MIB modules and from the RTL policy boundaries already present in the project.

## Controlled inputs

- Inventory generator: `scripts/build_standard_mib_inventory.py`
- Generated inventory: `docs/STANDARD_MIB_SNMP_INVENTORY.json`
- Vendored source tree: `vendor/pysnmp/smi/mibs`
- RTL metadata bank: `rtl/afdx_standard_mib_bank.v`
- Version/policy gate: `rtl/afdx_snmp_version_gate.v`
- Existing bounded MAC agent: `rtl/afdx_snmp_extended.v`, `rtl/afdx_snmp_mac.v`

The generated JSON records per-module and per-object source hashes. A missing module
is recorded as `SOURCE_UNAVAILABLE_OPEN`; a present vendor-generated file is recorded
as `INVENTORY_ONLY`. Neither state is a normative closure.

## Applicability policy

| Area | Declared policy | Current evidence boundary |
|---|---|---|
| SNMPv1 | In scope for existing management path | Bounded MAC-path community GET/GETNEXT/GETBULK and read-only SET error; independent BER evidence via the shared version vectors |
| SNMPv2c | In scope for existing management path | Bounded MAC-path GET/GETNEXT/GETBULK/BER/PySNMP evidence; private project bank remains distinct from standard MIB completeness |
| SNMPv3 | USM `noAuthNoPriv` in scope; authenticated/private profiles excluded by decision | Bounded production wire engine (`rtl/afdx_snmp_wire.v`): ScopedPDU, engine discovery/REPORT, unknown engine/user counters, GET/GETNEXT/GETBULK, read-only SET; `authNoPriv`/`authPriv` are rejected with `usmStatsUnsupportedSecLevels` (REPORT for reportable messages, silent drop otherwise). USM HMAC/DES/AES and VACM are not implemented. |
| RFC1213/MIB-II | Legacy applicability review | Vendored inventory only; not a claim that all legacy objects are implemented |
| SNMPv2-MIB | Applicable to a responder profile | Vendored inventory only; no object-by-object wire closure |
| Framework/MPD/USM/VACM/community/notification/proxy MIBs | Conditional on the corresponding SNMP service/profile | Inventory only unless an independent wire path is explicitly added |
| IF-MIB/IP-MIB/UDP-MIB | Applicable if those standard objects are claimed | Vendor tree does not contain these module files; status is open, not inferred from the private bank |
| TCP-MIB | Not applicable to the current UDP-only responder profile | Explicitly excluded by profile; must be revisited if TCP management is added |

## Wire-policy matrix

`accepted` below means only policy-gate admission. It does not mean that a complete
SNMP message processor, security model, PDU encoder/decoder, or MIB agent exists.

| Version | Message model | Security model | Positive condition | Negative condition | Production MAC status | Independent decode |
|---|---:|---:|---|---|---|---|
| v1 (`version=0`) | 0 | 1/community | community accepted and `pdu_kind <= 3` | bad community or unsupported PDU | BOUNDED PASS through the community MAC path | PySNMP v1 |
| v2c (`version=1`) | 1 | 2/community | community accepted and `pdu_kind <= 5` | bad community or unsupported PDU | BOUNDED PASS through existing v2c path | PySNMP v2c |
| v3 (`version=3`) | 3 | 3/USM | known engine/user, `noAuthNoPriv` flags, empty auth/priv fields and `pdu_kind <= 5` | unknown engine/user, authNoPriv/authPriv, non-empty auth/priv fields, unsupported PDU | BOUNDED PASS for noAuthNoPriv; REPORT/silent rejection per msgFlags; no HMAC/DES/AES | PySNMP v3 vectors |
| other | none | none | none | explicit unsupported-version error | NOT APPLICABLE | none |

The v3 row covers engine discovery/REPORT, ScopedPDU parse/encapsulation,
`usmStatsUnknownEngineIDs`, `usmStatsUnknownUserNames` and
`usmStatsUnsupportedSecLevels` counting. It still does not imply USM HMAC
authentication, DES/AES privacy cryptography, VACM authorization, or a
standards-complete MIB agent.

## Object inventory and closure rule

The generated JSON currently contains the object and node metadata available in the
vendored modules, including OID, generated ASN.1 type name, MAX-ACCESS, status,
instance shape, module source, and source SHA-256. It includes table and row nodes as
well as scalar/column objects so that an object tree cannot be mistaken for a flat
list of implemented leaves.

For this project a row can be marked closed only when all of the following exist:

1. a controlled normative source for the selected edition/RFC;
2. an applicability decision and rationale;
3. an exact RTL object binding and value/type semantics;
4. positive and negative wire tests for each applicable operation;
5. scalar `.0` and table-index behavior where applicable;
6. independent BER/PDU decoding;
7. reproducible test/source hashes and review evidence.

The sidecar therefore keeps all generated objects `OPEN` and keeps the private 25-object
project bank explicitly separate. It does not convert the current 64-entry metadata
bank into a standards-complete MIB implementation.

## Evidence status

- Existing ModelSim test `tb_afdx_standard_mib` exercises the bounded metadata bank's
  sequential walk, end-of-MIB, write rejection, and policy-gate v1 positive case.
- `tb_snmp_versions` (direct wire and MAC-path parameterizations, vectors generated
  by `scripts/gen_snmp_versions.py`) covers v1/v2c/v3 positive operations, wrong
  engine/user, `authNoPriv`/`authPriv` unsupported-level REPORTs, silent security
  failures and malformed-flag rejection; `verify_snmp_interop.py` provides the
  independent PySNMP decode cross-check.
- The bounded v1/v2c and v3-noAuthNoPriv wire engines live in
  `rtl/afdx_snmp_mac.v`/`rtl/afdx_snmp_wire.v`; this sidecar inventory itself never
  changed core SNMP RTL.
- The generated inventory must be regenerated after any vendor-MIB change; its source
  hashes are part of the evidence record.

**Conclusion:** SNMP/MIB sidecar complete as an applicability/object/evidence index;
standard MIB and SNMPv1/v2c/v3 full certification remains OPEN by design.
