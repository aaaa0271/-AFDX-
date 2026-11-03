"""Exact capacity arithmetic and counterexamples; no unbound RTL latency claim.

LMAX includes FCS, excludes preamble/SFD and IFG. This script exhausts discrete
BAG assignments, and proves monotonic serialization by its affine formula.
The ideal link theorem is not a service curve for the implemented pipeline.
"""
from pathlib import Path
from fractions import Fraction
import argparse, hashlib, itertools, json
ROOT=Path(__file__).resolve().parents[1]

def wire_ns(lmax,link=100_000_000):
    if not 64<=lmax<=1518:raise ValueError('LMAX outside declared profile')
    return Fraction((lmax+20)*8*1_000_000_000,link)

def fragment_count(payload,lmax):
    if not 1<=payload<=8192 or not 64<=lmax<=1518:raise ValueError('invalid packet bounds')
    available=lmax-39
    quantum=available//8*8
    remaining=payload+8
    # All preceding fragments are multiples of eight; last need not be.
    return 1+max(0,(remaining-available+quantum-1)//quantum)

def verify():
    profile_path=ROOT/'docs/competition_profile.json'
    profile=json.loads(profile_path.read_text(encoding='utf-8'))
    bags=profile['bag_cycles']['legal_at_default_clock']; hz=profile['clock_hz']
    if hz!=12_500_000 or profile['wire_bit_rate_per_network']!=100_000_000:
        raise ValueError('This envelope assumes the declared 80ns byte-clock profile')
    # Conservative: allow each of the six externally shaped classes full LMAX.
    # Management/service actual lengths <=563 MAC bytes only reduce this envelope.
    loads=[Fraction(1538,b) for b in bags]
    max_load=Fraction(0); max_cfg=None; count=0
    for indices in itertools.product(range(len(bags)),repeat=6):
        u=sum((loads[i] for i in indices),Fraction(0));count+=1
        if u>max_load:max_load=u;max_cfg=[bags[i] for i in indices]
    for length in range(64,1519):
        assert wire_ns(length)==80*(length+20)
    # Affine arrival envelope for six ideal BAG regulators at physical wire
    # start: A(t) <= sigma + rho*t. Under a work-conserving unit-rate ideal
    # link, backlog <= sigma; delay <= sigma (units: byte clocks). This is
    # conditional on the link model, not an application or HDL bound.
    sigma=6*1538
    # Constructive legal counterexample to the withdrawn R2 application bound:
    # 8192-byte message, LMAX=64, BAG=128ms, no Sub-VL competitors needed.
    fragments=fragment_count(8192,64)
    min_completion_cycles=(fragments-1)*max(bags)+84
    prior_claim_ns=384738240
    min_completion_ns=Fraction(min_completion_cycles*1_000_000_000,hz)
    assert min_completion_ns>prior_claim_ns
    input_files=['docs/competition_profile.json','rtl/afdx_datagram_tx.v',
                 'rtl/afdx_datagram_rx.v','rtl/afdx_shared_tx_mux.v']
    return dict(
        status='CAPACITY_ENVELOPE_CHECKED_UNIVERSAL_LATENCY_NOT_PROVEN',
        normative_conformance='OPEN',
        input_sha256={f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in input_files},
        enumeration=dict(bag_assignments=count,integer_lmax_values=1455,
                         dimensions=['VL0','VL1','VL2','VL3','management','shared_service']),
        wire_capacity=dict(max_utilization_exact=str(max_load),max_utilization=float(max_load),
                           max_bags_cycles=max_cfg,frame_min_ns=int(wire_ns(64)),frame_max_ns=int(wire_ns(1518))),
        ideal_link_theorem=dict(assumptions=['six independent wire-start BAG regulators',
              'each frame MAC length <=1518','100 Mbit/s work-conserving link',
              'no additional packet-processing stalls','unit is byte clocks including preamble and IFG'],
              arrival_envelope='sigma + rho*t',sigma_wire_bytes=sigma,rho=str(max_load),
              backlog_bound_wire_bytes=sigma,delay_bound_ns=sigma*80,
              rtl_service_curve_established=False),
        refutations=[dict(claim='R2 application queue-to-wire bound 384738240ns',
              payload=8192,lmax=64,bag_cycles=max(bags),fragments=fragments,
              completion_lower_bound_ns=int(min_completion_ns),reason='every fragment consumes its own VL BAG'),
              dict(claim='finite end-to-end delay under all application loads/phases',
              permitted_trace='payload_ready=0 forever',
              consequence='no application delivery occurs; finite RX queues can fill',
              required_assumption='bounded reader stall and admitted source arrival envelope')],
        remaining=['HDL pipeline service curve','Sub-VL/fragment fairness and backlog',
                   'external switch/hop configuration','clock tolerance and failure duration',
                   'bounded consumer service','per-domain buffer admission'],
        full_worst_case_proof=False,formal_arinc_certification=False)

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=Path);args=ap.parse_args()
    result=verify()
    if args.out:
        args.out.parent.mkdir(parents=True,exist_ok=True)
        args.out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result,indent=2))
    return 0
if __name__=='__main__':raise SystemExit(main())
