"""Existing security plugin ABI adapters, read-only and fail on missing data."""
from collections import Counter
import math
from .schema import FEATURES,InputError

COUNTERS={'accepted':0x40,'blocked':0x44,'queue_overflows':0x48,'event_overflows':0x4c,
          'ab_conflicts':0x50,'hash_failures':0x54,'time_alarms':0x58,'context_timeouts':0x5c,'observed':0x60}
FLAGS={1:'format',2:'acl',4:'ab_content',8:'phase',16:'rate',32:'quota',64:'authorization',
       128:'tid_or_retransmission',256:'time',512:'orphan_fragment',1024:'sha_or_length',2048:'fragment_overlap'}

def decode_event(value):
    if type(value) is not int or not 0<=value<2**160:raise InputError('160-bit event')
    return dict(epoch=value>>128,cycle=value>>64&0xffffffffffffffff,flags=value>>48&65535,
       rule=value>>44&15,channel=value>>42&3,allow=bool(value&(1<<41)),duplicate=bool(value&(1<<40)),
       phase=value>>33&7,length=value>>16&65535,sequence=value>>8&255,mode=value&3)

def summarize_events(path):
    flags=Counter();channels=Counter();modes=Counter();lengths=[];count=0;blocked=0
    with path.open() as stream:
        for line in stream:
            if not line.strip():continue
            parts=line.split()
            if len(parts) not in (2,3):raise InputError('event log must contain two or three columns')
            try:
                for p in parts[:-1]:int(p)
                e=decode_event(int(parts[-1],16))
            except ValueError as error:raise InputError('invalid event log') from error
            count+=1;channels[e['channel']]+=1;modes[e['mode']]+=1;lengths.append(e['length'])
            if not e['allow']:blocked+=1
            for mask,name in FLAGS.items():
                if e['flags']&mask:flags[name]+=1
    return dict(source='security_plugin_actual_event_abi',events=count,channels=dict(channels),
        modes=dict(modes),check_denials=blocked,reason_counts=dict(flags),
        mean_wire_bytes=sum(lengths)/max(count,1),ready_for_ml=False,
        missing_metrics=FEATURES,
        note='原因码仅作独立证据；事件日志不足以计算完整测量向量，未填零或伪造模型输入。')

def read_counters(read32,boot_id):
    if not isinstance(boot_id,str) or not boot_id:raise InputError('boot_id required')
    epoch=read32(8);mode=read32(0)
    result={name:read32(address) for name,address in COUNTERS.items()}
    if read32(8)!=epoch:raise InputError('policy changed during counter collection')
    for value in [epoch,mode,*result.values()]:
        if type(value) is not int or not 0<=value<2**32:raise InputError('counter encoding')
    return dict(boot_id=boot_id,epoch=epoch,mode=mode,counters=result)

def counter_metrics(start,end,duration_s):
    if start['boot_id']!=end['boot_id'] or start['epoch']!=end['epoch']:raise InputError('reset/policy boundary')
    if type(duration_s) not in (int,float) or not math.isfinite(duration_s) or duration_s<=0:raise InputError('duration')
    if start['mode']!=end['mode']:raise InputError('mode boundary')
    delta={}
    for name in COUNTERS:
        a,b=start['counters'][name],end['counters'][name]
        if any(type(v) is not int or not 0<=v<2**32 for v in (a,b)):raise InputError('counter range')
        if b<a and not (a>=0xf0000000 and b<=0x0fffffff):raise InputError('counter reset or ambiguous wrap')
        delta[name]=(b-a)&0xffffffff
    total=delta['observed']+delta['queue_overflows']
    available=dict(observed_pps=total/duration_s,queue_overflow_ratio=delta['queue_overflows']/max(total,1))
    return dict(metrics=available,missing_metrics=[f for f in FEATURES if f not in available],
                ready_for_ml=False,raw_counter_deltas=delta)

def compare_ab(first,second):
    import binascii
    for raw in (first,second):
        if not 72<=len(raw)<=1536 or raw[:8]!=b'\x55'*7+b'\xd5':raise InputError('raw AFDX frame format')
        if binascii.crc32(raw[8:-4]).to_bytes(4,'little')!=raw[-4:]:raise InputError('raw frame FCS invalid')
    differences=[]
    for i in range(8,max(len(first),len(second))-4):
        a=first[i] if i<len(first)-4 else None;b=second[i] if i<len(second)-4 else None
        if i==19 and a is not None and b is not None:a,b=a&0x9f,b&0x9f
        if a!=b:differences.append(dict(wire_offset=i,first=a,second=b))
    return dict(tool='compare_ab_frames',both_fcs_valid=True,equal_after_interface_normalization=not differences,
                first_length=len(first),second_length=len(second),differences=differences,
                trusted_side=None,note='调用方须确认同一逻辑消息；不据此判断哪一侧可信。')
