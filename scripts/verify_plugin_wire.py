"""Independent comparison of captured DUT output with injected raw frames."""
import binascii,json,sys
from pathlib import Path
R=Path(__file__).resolve().parents[1]


def require(condition,message):
    if not condition:raise ValueError(message)


def audit(directory):
    d=Path(directory);vectors=json.loads((R/'tb/scenarios.json').read_text())
    raw=[int(line,16).to_bytes(1536,'little') for line in
         (R/'tb/frames.hex').read_text().splitlines()]
    events={};forward={}
    for line in (d/'security_events.txt').read_text().splitlines():
        case,cycle,value=line.split();case=int(case);v=int(value,16)
        if case:events.setdefault(case,[]).append(v)
    for line in (d/'forwarded_wire.txt').read_text().splitlines():
        case,ch,cycle,h=line.split();case=int(case)
        if case:forward.setdefault(case,[]).append((int(ch),bytes.fromhex(h)))
    rows=[]
    for c in vectors['cases']:
        ident=c['id'];e=events.get(ident,[])
        require(len(e)==1,f'case {ident}: event count')
        v=e[0];require((v>>48&65535)==c['expected_flags'],f'case {ident}: flags')
        require(bool(v&(1<<41))==c['expected_allow'],f'case {ident}: verdict')
        require((v>>42&3)==c['channel'],f'case {ident}: channel')
        require((v&3)==c['mode'],f'case {ident}: mode')
        expected=[]
        if c['channel']<2 and (c['mode']!=2 or c['expected_allow']):
            n=vectors['frame_lengths'][c['frame']]
            expected=[(c['channel'],raw[c['frame']][:n])]
        require(forward.get(ident,[])==expected,f'case {ident}: bytes/whole-frame delivery')
        rows.append({'id':ident,'name':c['name'],'status':'PASS','forwarded':len(expected)})
    result={'status':'PASS','packet_scenarios':len(rows),'scenarios':rows,
            'checks':['raw frame byte equality','no output for rejected enforce frames',
                      'transparent shadow/bypass','actual event flags/mode/channel/verdict']}
    (d/'independent_audit.json').write_text(json.dumps(result,indent=2)+'\n')
    return result
if __name__=='__main__':
    print('SEC_PLUGIN_WIRE_AUDIT_PASS',audit(sys.argv[1])['packet_scenarios'])
