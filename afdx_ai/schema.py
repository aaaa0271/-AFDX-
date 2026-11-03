"""Explicit measurement contract; labels and security reason flags are excluded."""
import json,math

FEATURES = [
 'observed_pps','mean_frame_bytes','frame_size_cv','arrival_cv',
 'ab_unpaired_ratio','ab_payload_mismatch_ratio','fcs_error_ratio',
 'queue_overflow_ratio','latency_p95_us','ntp_rtt_ms','ntp_offset_abs_ms',
 'clock_step_abs_ms','loader_progress_ratio','loader_retry_ratio',
 'fragment_orphan_ratio','management_fraction','active_context_ratio',
 'sha_jobs_per_1k_frames']
PREDICTORS = ['observed_pps','mean_frame_bytes','frame_size_cv','arrival_cv',
              'management_fraction','active_context_ratio','sha_jobs_per_1k_frames']
CLASSES = ['normal','congestion','link_degradation','replica_divergence',
           'time_anomaly','loader_stall','fragment_pressure','management_burst']
LABELS_ZH = dict(zip(CLASSES,['正常','处理拥塞','链路质量下降','双网内容分歧',
                            '授时异常','加载停滞','分片资源压力','管理流量突增']))
LIMITS = {name:(0.0,1.0) for name in FEATURES if name.endswith('_ratio') or name=='management_fraction'}
LIMITS.update(observed_pps=(0.0,200000.0),mean_frame_bytes=(64.0,1518.0),
              frame_size_cv=(0.0,4.0),arrival_cv=(0.0,20.0),latency_p95_us=(0.0,1e8),
              ntp_rtt_ms=(0.0,1e7),ntp_offset_abs_ms=(0.0,1e9),clock_step_abs_ms=(0.0,1e9),
              sha_jobs_per_1k_frames=(0.0,1000.0))

class InputError(ValueError):pass

def strict_json(path,max_bytes=32*1024*1024):
    raw=path.read_bytes()
    if len(raw)>max_bytes:raise InputError('JSON too large')
    def pairs(items):
        d={}
        for k,v in items:
            if k in d:raise InputError('duplicate JSON key '+k)
            d[k]=v
        return d
    return json.loads(raw,object_pairs_hook=pairs,
                      parse_constant=lambda s:(_ for _ in ()).throw(InputError('nonfinite JSON')))

def validate_metrics(metrics):
    if not isinstance(metrics,dict) or set(metrics)!=set(FEATURES):
        missing=sorted(set(FEATURES)-set(metrics or {})) if isinstance(metrics,dict) else FEATURES
        raise InputError('complete measured metrics required; missing='+','.join(missing))
    for key,value in metrics.items():
        if type(value) not in (int,float) or not math.isfinite(value):raise InputError('invalid '+key)
        lo,hi=LIMITS[key]
        if not lo<=value<=hi:raise InputError('out of physical/schema range: '+key)
    return [float(metrics[f]) for f in FEATURES]

def validate_observation(d):
    required={'schema','source','window_id','window_duration_s','scope','metrics'}
    if not isinstance(d,dict) or set(d)!=required or type(d['schema']) is not int or d['schema']!=1:
        raise InputError('observation schema/version')
    if d['source'] not in ('synthetic','rtl_capture','hardware'):raise InputError('source')
    if not isinstance(d['window_id'],str) or not 1<=len(d['window_id'])<=120:raise InputError('window_id')
    if type(d['window_duration_s']) not in (int,float) or not math.isfinite(d['window_duration_s']) or d['window_duration_s']<=0:
        raise InputError('window duration')
    scope=d['scope']
    if not isinstance(scope,dict) or set(scope)!={'clock_hz','link_mbps','security_mode'}:raise InputError('scope')
    if scope!={'clock_hz':12500000,'link_mbps':100,'security_mode':2}:raise InputError('unsupported operating profile')
    if any(type(v) is not int for v in scope.values()):raise InputError('scope integer types')
    return validate_metrics(d['metrics'])
