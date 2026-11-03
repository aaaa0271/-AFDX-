# Closure audit, 2026-10-12

This is a development increment, not full AFDX/ARINC certification or a completed
hardware product. R1/R2 archives remain historical artifacts. Use the new run's
acceptance, source snapshot and raw logs for current results.

## Real MAC integration

`AFDX_competition_top` has a `SERVICE_DOMAINS` elaboration parameter. Default 1
retains the previous interface behavior. The tested extension is 2 Loader and
2 independent NTP servers on the same redundant A/B byte interfaces. Each lane
owns a package bank, transfer state and RTC. Loader and clock frames have separate
VL/SN histories. A frame-atomic intermediate mux obeys outer egress admission.
An implementation slot for a third pair exists but is NOT validated or advertised
as an arbitrary-domain guarantee. Peer tables are static elaboration parameters.

Domain 0: Loader 10.0.0.1, clock 10.0.1.1; RX VL 0x10/0x11, TX VL 0x20/0x21.
Domain 1: Loader 10.0.0.2, clock 10.0.1.2; RX VL 0x12/0x13, TX VL 0x22/0x23.
`service_app_domain` selects the application bank/clock view. An invalid selection
returns no image. Polling is shared, but RTC synchronization/recovery is per server;
this is not NTP peer election, voting, or an aircraft-wide time service proof.
Two-domain tests use a 24ms service response timeout; this is a fixture setting,
not a standard-prescribed timeout. BAG/latency admission must budget all domains.

The integrated test runs LUI/LUR/LUH/A.LUP/B.LUP/final LUS for both loaders,
checks all 1724 application bytes per bank, stalls and recovers one clock, and
audits captured A/B frames for FCS, checksums, routing, independent SN and BAG.

## 615A/665 compatibility

The existing A4 upload path remains a bounded subset. `tb_665_header_compat`
exercises the actual parser with 14 byte fixtures: 0x8002/0x8004 subset acceptance,
multiple hardware IDs, duplicate name rejection, invalid/overflowed pointers,
reserved fields and CRC errors. Unsupported 0x8003, support and UDD are rejected.
The load part-number pointer can no longer point inside fixed fields or overflow
into another region. Original package rollback tests must still pass.

The TFTP control server now releases LUI_WAIT and LUR_CHECK after application
response timeout. A dedicated test checks new-session recovery and wrong Loader
rejection. This does not implement the complete standard Wait/Abort taxonomy.

The abstract 615A process and 665 admission models have no file/MAC parser and
are NOT conformance evidence. Their statuses and tests are explicitly experimental.
In particular, their numeric `edition` input and invented support/UDD admission
rules do NOT establish cross-edition compatibility. Full information/download,
remote abort, wait/error status reporting, multi-header transactions, support/UDD,
batch/media and all revision layouts remain implementation gaps, not paperwork.

## Worst-case correction

The earlier provisional R2 proof script ignored its `lmax` argument and gave a
message delay bound without counting fragments. Those claims are withdrawn.
The replacement uses exact rational arithmetic, 262144 BAG combinations, and
1455 integer frame sizes. 73.824% is a conservative six-class wire offered-load
envelope, NOT achieved HDL throughput, schedulability, or a latency guarantee.

Counterexample: 8192 payload bytes at LMAX=64 consume 342 frames. With BAG=128ms,
completion is at least 43.648006720 seconds even without competing traffic.
`payload_ready=0` forever also prevents any finite application-delivery bound.
A complete proof needs bounded consumer stalls/arrival bursts, per-Sub-VL
service, fragmentation, physical pipeline processing and external hop models.

## Normative sources and MIB

The 321 inventory entries include identity/table nodes, not 321 implemented
objects. There are 13 vendor modules present and 4 absent, NOT 17 present modules.
Production management remains the bounded private SNMPv2c agent. A version gate
with Boolean auth/priv inputs is not SNMPv1/v3 wire support or cryptography.
The standard-MIB implementation, v1/v3 engine and full object mapping remain OPEN.

Selected ARINC editions are unchanged. Their controlled full texts and complete
clause inventory are not available. Existing historical Part7 PDF and local
Wireshark/LSPB source copies can guide engineering tests but cannot supply missing
selected-edition normative clauses. Web search/open returned no usable text;
an attempted direct official-source download was rejected by tool policy. No
clause numbers, reviewer approvals or source availability flags are fabricated.

## Device and hardware

The project contains EP1S80F1508C6 and a nominal 80ns clock constraint. This is not
confirmation of the user's target board. No pin map, I/O timing budgets, clock
architecture, board schematic, or identifiable board/AFDX peer has been supplied.
Read-only jtagconfig discovery reported: No JTAG hardware available.

Analysis/elaboration, fitted timing and board interoperability are separate gates.
Neither clock-constraint creation nor a behavioral GMII test establishes routed
setup/hold closure or electrical interoperability. Hardware gates stay NOT_RUN
until the actual target and connected test setup are available. No bitstream is
programmed and no physical verification is claimed.

## Evidence accounting

The suite contains 89 implementation-related HDL tests and 5 abstract-model tests.
Only fresh results decide PASS. eLinx must elaborate both SERVICE_DOMAINS=1 and 2.
Running all tests does not close the standard clause gate. Release artifacts must
include raw results or label themselves source-only; archive integrity alone is
not verification of referenced evidence availability.
