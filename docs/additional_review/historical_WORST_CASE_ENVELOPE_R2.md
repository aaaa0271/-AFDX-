# AFDX R2 admitted envelope and analytical bounds (simulation-only)

The project does not claim a universal ARINC worst-case proof. This record states the exact admitted parameter envelope and the formulas that must hold for the finite implementation.

## Fixed link model

- 100 Mbit/s per network, 1 byte = 80 ns.
- Ethernet IFG model: 12 byte times = 960 ns.
- A captured physical frame of `F` bytes occupies `T_wire(F) = 80 ns * (F + 12)` in the project byte model.
- Two redundant networks are analyzed independently; redundancy duplicates traffic but does not increase a single network's physical service rate.

## Admitted configuration envelope

- 4 VLs; 4 Sub-VLs per VL; 16 communication ports.
- BAG values in the project profile: 12500, 25000, 50000, 100000, 200000, 400000, 800000, 1600000 clock cycles at 12.5 MHz.
- LMAX 64..1518 MAC bytes; application capacity is `LMAX - 47` for the UDP/IP/Ethernet overhead used by the implementation.
- Queue depth: 2 messages per port; sampling stores the latest pending value.
- Primary ports 0..3: 8192-byte message memory; extended ports 4..15: 2048-byte message memory.

## Bounds used by the checker

For a VL with BAG `B` seconds and maximum physical frame `F`, a sufficient line-rate admissibility check is:

`rho_vl = T_wire(F) / B <= 1`.

For a set of VLs sharing one network:

`rho_total = sum(rho_vl) <= 1`.

A conservative store-and-forward backlog bound for a port with at most `Q` queued messages is:

`backlog_bytes <= Q * max_payload + active_fragment_payload`.

The implementation's no-overflow condition is checked against its finite memory allocation, not asserted for arbitrary values outside the admitted envelope. Worst-case phase sweeps must include simultaneous eligibility at the BAG boundary, A/B skew, management/service contention, queue-full arrival, and sampling replacement.

## Current evidence

The line-rate and integrated stress tests exercise minimum and maximum frames, shared service/management arbitration, A/B degradation, configured VLs, 16 ports, queueing, sampling and fragmentation. They are measurements and bounded assertions, not a proof over every real-valued phase.

Status: **OPEN analytical closure**. A future normative closure needs an exhaustive enumerator over all admitted discrete configurations plus independently reviewed phase/backlog inequalities.
