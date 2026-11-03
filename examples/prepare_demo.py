"""Prepare TEST-ONLY two-loader grants from the frozen, genuinely signed fixtures.

Uses fixture time=150 because fixture validity is [100,200], not wall-clock
production time. No private signing key is shipped or required.
"""
import argparse,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1];sys.path.insert(0,str(R/'host'))
from authorizer import initialize_state,authorize
from control import transaction
from policy import Rule


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out',type=Path,required=True);a=p.parse_args()
    a.out.mkdir(parents=True,exist_ok=False)
    fixture=json.loads((R/'tb/core_signed_authorizations.json').read_text())
    public=bytes.fromhex(fixture['public_key']);rules={};receipts=[]
    for domain,item in enumerate(fixture['domains']):
        doc=item['document'];state=a.out/f'test_loader_{domain}_state.json'
        initialize_state(state,doc['target'],doc['hardware_id'],6)
        receipt=authorize(doc,bytes.fromhex(item['signature']),public,
                          state_path=state,target=doc['target'],hardware_id=doc['hardware_id'],
                          nonce=doc['nonce'],now=150,rule_id=domain,lease_cycles=5000000)
        receipts.append(receipt)
        for kind in (2,3):
            i=domain if kind==2 else domain+2
            rules[i]=Rule(0x0a000001+domain if kind==2 else 0x0a000101+domain,
                          0x0a000010,0x030000000010+domain*2+(kind==3),
                          0x020000000002,kind=kind,
                          source_port=123 if kind==3 else 0,
                          destination_port=40001 if kind==3 else 0,
                          tx_mac=0x030000000020+domain*2+(kind==3),
                          signed_loading=kind==2,timeout=300000,max_contexts=4)
    writes=transaction(rules,receipts,mode=2)
    (a.out/'test_transaction.json').write_text(json.dumps({'test_only':True,'fixture_time':150,'writes':writes},indent=2)+'\n')
    (a.out/'test_transaction.hex').write_text(''.join(f"{w['address']:04x} {w['value']:08x}\n" for w in writes))
    print('TEST_DEMO_READY rules=4 loaders=2 grants=6; simulated fixture time=150')
if __name__=='__main__':main()
