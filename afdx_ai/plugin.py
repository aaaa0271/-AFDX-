"""Read-only diagnostic plugin. Scores are hypotheses, never hardware commands."""
import numpy as np
from .models import load_models
from .schema import FEATURES,PREDICTORS,LABELS_ZH,validate_observation

RELEVANT={
 'normal':['queue_overflow_ratio','fcs_error_ratio','ab_unpaired_ratio'],
 'congestion':['observed_pps','queue_overflow_ratio','latency_p95_us','arrival_cv'],
 'link_degradation':['ab_unpaired_ratio','fcs_error_ratio','loader_retry_ratio'],
 'replica_divergence':['ab_payload_mismatch_ratio','ab_unpaired_ratio'],
 'time_anomaly':['ntp_offset_abs_ms','clock_step_abs_ms','ntp_rtt_ms'],
 'loader_stall':['loader_progress_ratio','loader_retry_ratio','active_context_ratio'],
 'fragment_pressure':['fragment_orphan_ratio','active_context_ratio','queue_overflow_ratio'],
 'management_burst':['management_fraction','observed_pps','latency_p95_us']}
TOOLS={
 'normal':['summarize_events'], 'congestion':['inspect_queue_metrics','summarize_events'],
 'link_degradation':['inspect_link_metrics','summarize_events'],
 'replica_divergence':['compare_ab_frames','summarize_events'],
 'time_anomaly':['inspect_time_metrics','summarize_events'],
 'loader_stall':['inspect_loader_metrics','summarize_events'],
 'fragment_pressure':['inspect_fragment_metrics','summarize_events'],
 'management_burst':['inspect_management_metrics','summarize_events']}

class DiagnosticPlugin:
    def __init__(self,model_directory):self.registry,self.models=load_models(model_directory)

    def analyze(self,observation):
        vector=validate_observation(observation);x=np.asarray([vector])
        forest=self.models['diagnosis'];votes=forest.predict(x)[0];order=np.argsort(-votes)
        label=forest.classes[int(order[0])];score=float(votes[order[0]])
        margin=float(votes[order[0]]-votes[order[1]])
        anomaly=float(-self.models['anomaly'].predict(x)[0]);outlier=anomaly>self.registry['anomaly_threshold']
        outside=[f for f,value in zip(FEATURES,vector)
                 if not self.registry['support'][f][0]<=value<=self.registry['support'][f][1]]
        status='candidate'
        if score<self.registry['confidence_threshold'] or margin<.15 or (label=='normal' and outlier):status='uncertain'
        if outside:status='out_of_support'
        p=np.asarray([[observation['metrics'][f] for f in PREDICTORS]])
        predicted_log=float(self.models['latency'].predict(p)[0]);radius=self.registry['latency_log_interval_radius']
        transform=lambda z:float(max(0,np.expm1(min(z,40))))
        return dict(schema=1,model_version=self.registry['model_version'],source=observation['source'],
            window_id=observation['window_id'],status=status,confirmed_cause=None,
            candidates=[dict(cause=forest.classes[int(i)],name=LABELS_ZH[forest.classes[int(i)]],vote_share=float(votes[i])) for i in order[:3]],
            vote_share_is_calibrated_probability=False,
            anomaly=dict(score=anomaly,threshold=self.registry['anomaly_threshold'],outside_normal_model=outlier),
            out_of_support_features=outside,
            observed_evidence=[dict(metric=f,value=observation['metrics'][f]) for f in RELEVANT[label]],
            suggested_tools=TOOLS[label] if status=='candidate' else ['check_measurement_coverage','summarize_events'],
            latency_forecast=dict(target='next_window_latency_p95_us',estimate=transform(predicted_log),
                interval=[transform(predicted_log-radius),transform(predicted_log+radius)],
                nominal_scenario_coverage=.90,calibration_unit=self.registry['interval_unit'],is_timing_guarantee=False,
                usable_within_training_support=not any(f in PREDICTORS for f in outside)),
            training_domain=self.registry['trained_on'],hardware_validation=False,
            conclusion='模型输出候选原因；结合工具证据核实。' if status=='candidate' else '信息不足、分布超界或模型意见不明确，需要补充证据。')
