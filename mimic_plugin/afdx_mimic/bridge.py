"""Read-only evidence bridge; original agent and ML weights remain untouched."""
import json,shutil,sys
from pathlib import Path
from .contract import ContractError,load_json
from .evidence import verify,write_json

def inspect_mimic(directory):
    root=Path(directory).resolve();audit=verify(root);r=load_json((root/'report.json').read_bytes())
    return dict(tool='inspect_mimic_evidence',status='ok' if r['input_integrity_ok'] else 'integrity_failure',audit=audit,
      domain=r['source'],scenario=r['scenario'],frame_count=r['frame_count'],
      disagreements=[dict(request_id=f['request_id'],dissenters=f['quorum']['dissenters'],errors=f['quorum']['errors'],result_file=f['result_file']) for f in r['frames'] if f['quorum']['dissenters'] or f['quorum']['errors']],
      scheduler_events=r['scheduler_events'],confirmed_physical_attack=False,device_writes=False)

def export_agent_case(directory,output):
    root=Path(directory).resolve();evidence=inspect_mimic(root);report=load_json((root/'report.json').read_bytes());out=Path(output).resolve()
    if out.exists() or out.is_relative_to(root):raise ContractError('new export directory outside run required')
    if not report['input_integrity_ok']:raise ContractError('invalidated input evidence cannot be exported')
    p=load_json((root/'policy.json').read_bytes());rule=p['rules'][0]
    flow={k:rule[k] for k in ('peer_ip','local_ip','rx_mac','peer_mac','source_port','destination_port')};flow['tx_mac']=0x030000000012
    out.mkdir(parents=True)
    lines=['mimic evidence; reference laboratory investigation, not a new measured ML window']
    for f in report['frames']:
        lines.append('mimic '+('error ' if f['quorum']['dissenters'] or f['quorum']['errors'] else 'normal ')+json.dumps(dict(request_id=f['request_id'],quorum=f['quorum'],result_file=f['result_file']),ensure_ascii=False))
    for e in report['scheduler_events']:lines.append('mimic error scheduling '+json.dumps(e,ensure_ascii=False))
    (out/'mimic.log').write_text('\n'.join(lines)+'\n',encoding='utf8');write_json(out/'mimic_evidence.json',evidence)
    artifacts=[dict(id='mimic_log',type='log',paths=['mimic.log'],source=report['source'],binding='reference_fixture',window_id=None),
               dict(id='mimic_structured',type='log',paths=['mimic_evidence.json'],source=report['source'],binding='reference_fixture',window_id=None)]
    for i,f in enumerate(report['frames'][:8]):
        relative=f['input_file'];capture=(root/relative).resolve()
        if Path(relative).is_absolute() or '..' in Path(relative).parts or not capture.is_relative_to(root) or not capture.is_file() or capture.stat().st_size>2048:raise ContractError('capture export path/size')
        name=f'capture_{i:02d}.bin';shutil.copyfile(capture,out/name)
        artifacts.append(dict(id=f'capture_{i:02d}',type='frame',paths=[name],source=report['source'],binding='reference_fixture',window_id=None))
    write_json(out/'case.json',dict(schema=1,case_id='mimic_'+(report['scenario'] or report['case_id']),observation=None,artifacts=artifacts,expected_flow=flow))
    return dict(status='exported',case=str(out),complete_model_metrics_available=False,reference_binding_only=True)

def investigate_with_existing_agent(directory,agent_root,output):
    root=Path(agent_root).resolve();out=Path(output).resolve()
    if out.exists():raise ContractError('new integration output required')
    if not (root/'afdx_agent/agent.py').is_file() or not (root/'models/registry.json').is_file():raise ContractError('trusted agent project root required')
    out.mkdir(parents=True);export_agent_case(directory,out/'case');sys.path.insert(0,str(root))
    from afdx_agent.agent import Agent
    report=Agent(root=root,rtl_mode='off').run(out/'case',out/'agent_run')
    result=dict(status='completed',mimic_tool=inspect_mimic(directory),existing_agent_report='agent_run/report.json',
       agent_steps=report['steps'],agent_integrity_ok=report['integrity_ok'],original_models_retrained=False,
       no_missing_metrics_imputed=report['model'] is None,device_writes=False)
    write_json(out/'combined_report.json',result);return result
