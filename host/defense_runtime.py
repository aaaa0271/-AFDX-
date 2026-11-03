"""Trusted runtime for AFDX_defense_top, using completed read/write callbacks.

Callbacks own physical bus timeouts. No raw network packet can call this API.
Windows jobs or POSIX limits bound native workers; neither is an OS sandbox.
"""
import copy
import math
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'mimic_plugin'))
sys.path.insert(0, str(ROOT / 'aihw_plugin'))
from afdx_mimic.build import SPECS
from afdx_mimic.contract import request, semantic_hash, policy as validate_policy
from afdx_mimic.controller import MimicPlugin
from afdx_ai_hw.csr import HardwareCsrPlugin
from afdx_ai_hw.fixed import FEATURES


class DefenseRuntime:
    def __init__(self, read32, write32, pool, policy, source='hardware', deadline_ms=5000,advance=None,multiplexed_rules=()):
        if source not in ('hardware', 'rtl_simulation'):
            raise ValueError('explicit transport provenance required')
        self.read32, self.write32 = read32, write32
        self.mimic = MimicPlugin(pool, policy, mode='enforce', deadline_ms=deadline_ms)
        self.ai = HardwareCsrPlugin(read32, write32, source=source, poll_budget=30000)
        self.records = []
        self.history = []
        self.last_snapshot = None
        self.window_records = []
        self.source = source
        self.advance=advance
        self.last_inference=None
        self.last_window_seconds=None
        self.last_window_capture=None
        self.last_measurement_issue=None
        self.declared_policy=copy.deepcopy(policy)
        self.multiplexed_rules=set(multiplexed_rules)
        if not self.multiplexed_rules.issubset({row['id'] for row in policy['rules']}):raise ValueError('unknown multiplexed rule id')

    def service_one(self):
        if not self.read32(0x1004) & 1:
            return None
        rid = self.read32(0x1008) | self.read32(0x100c) << 32
        epoch, generation = self.read32(0x1010), self.read32(0x1014)
        active = self.read32(0x1018)
        packed = self.read32(0x101c)
        length, channel = packed & 0x7ff, packed >> 16 & 1
        stamp = self.read32(0x1020) | self.read32(0x1024) << 32
        baseline = bool(self.read32(0x1028) & 1)
        if not 1 <= length <= 1536:
            raise RuntimeError('invalid live frame length')
        raw = b''.join(self.read32(0x1800 + n).to_bytes(4, 'little') for n in range(0, length, 4))[:length]
        # The firmware queue, not the host controller's local sequence, owns
        # live ids. Bind the actual bytes and declared policy to that snapshot.
        if self.mimic.policy['epoch'] != epoch or self.mimic.generation != generation:
            raise RuntimeError('host/RTL policy epoch or scheduler generation mismatch')
        expected_mask = sum(1 << list(SPECS).index(e) for e in self.mimic.active)
        if active != expected_mask:
            raise RuntimeError('host/RTL active executor set mismatch')
        effective=copy.deepcopy(self.declared_policy)
        for row in effective['rules']:
            if row['id'] in self.multiplexed_rules:
                # The original RTL still owns loader phase/TID authorization.
                # Here only resolve this trusted, explicitly multiplexed rule
                # to the actual packet for stateless heterogeneous parsing.
                same=(len(raw)>=50 and int.from_bytes(raw[34:38],'big')==row['peer_ip'] and int.from_bytes(raw[38:42],'big')==row['local_ip'] and int.from_bytes(raw[8:14],'big')==row['rx_mac'])
                if same:
                    row['source_port']=int.from_bytes(raw[42:44],'big')
                    row['destination_port']=int.from_bytes(raw[44:46],'big')
        self.mimic.policy=effective
        self.mimic.next_id = rid
        result = self.mimic.evaluate(raw, channel, stamp, baseline)
        submitted = 0
        for record in result['worker_results']:
            if record['status'] != 'ok':
                continue
            eid = list(SPECS).index(record['executor_id'])
            response = record['response']
            digest = int(semantic_hash(response), 16)
            words = [response['request_id'] & 0xffffffff, response['request_id'] >> 32,
                     response['epoch'], response['generation'], int(response['verdict'] == 'allow')]
            words += [(digest >> (32 * i)) & 0xffffffff for i in range(8)]
            for i, value in enumerate(words):
                self.write32(0x1100 + eid * 64 + i * 4, value)
            submitted |= 1 << eid
        if submitted:
            self.write32(0x1040, submitted)
        for _ in range(70000):
            status = self.read32(0x1004)
            if status & 2:
                break
            if self.advance is not None:self.advance(128)
        else:
            raise TimeoutError('RTL adjudication result not available')
        allowed, quorum = bool(status & 4), bool(status & 8)
        reason = self.read32(0x102c)
        latency=self.read32(0x1070)|(self.read32(0x1074)<<32)
        if reason != 4 and allowed != result['final_allow']:
            raise RuntimeError('host/RTL final decision mismatch')
        next_active = sum(1 << list(SPECS).index(e) for e in result['next_active'])
        if next_active.bit_count() != 3:
            # Keep the exhausted frame parked fail-closed until explicit
            # recovery restores three independently self-tested executors.
            raise RuntimeError('executor pool exhausted; live traffic remains blocked')
        self.write32(0x1048, next_active)
        self.write32(0x104c, result['next_generation'])
        self.write32(0x1044, 1)
        result.update(rtl_allow=allowed, rtl_quorum=quorum, rtl_reason=reason,
                      frame_hex=raw.hex(), source=self.source, actual_data_path=True,
                      safety='baseline AND matching semantic quorum AND bounded AI actuator')
        self.records.append(result)
        self.window_records.append(dict(raw=raw,latency=latency))
        return result

    def snapshot(self):
        self.write32(0x100, 1)
        words = [self.read32(0x100 + i * 4) for i in range(64)]
        if words[0] != 0x44454631:
            raise RuntimeError('defense telemetry identity')
        return words

    def _invalidate_history(self, reason):
        """Break temporal continuity and discard all evidence from the old window."""
        self.history = []
        self.last_inference = None
        self.last_window_capture = None
        self.last_window_seconds = None
        self.window_records = []
        self.last_measurement_issue = reason

    def acknowledge_policy(self, policy):
        """Adopt a trusted controller's committed policy; never infer a policy from RTL.

        The caller commits the matching RTL policy first. No queued frame may be
        reinterpreted under a new host policy. Scheduler generation is unchanged.
        """
        policy = validate_policy(policy)
        if not self.mimic.lock.acquire(blocking=False):
            raise RuntimeError('policy update requires no in-flight host request')
        try:
            if self.read32(0x1004) & 1:
                raise RuntimeError('drain the pending frame before changing host policy')
            current = self.snapshot()
            if current[6] != policy['epoch']:
                raise ValueError('trusted policy does not match committed RTL epoch')
            if not self.multiplexed_rules.issubset({row['id'] for row in policy['rules']}):
                raise ValueError('unknown multiplexed rule id')
            self.declared_policy = copy.deepcopy(policy)
            self.mimic.policy = copy.deepcopy(policy)
            self._invalidate_history('policy_changed')
            self.last_snapshot = current
        finally:
            self.mimic.lock.release()

    def collect_window(self):
        try:
            current = self.snapshot()
        except (ValueError, RuntimeError, OSError, TimeoutError):
            self._invalidate_history('snapshot_unavailable')
            self.last_snapshot = None
            raise
        if len(current) != 64 or current[7] <= 0:
            self._invalidate_history('invalid_snapshot')
            self.last_snapshot = None
            return dict(status='invalid_measurements', reason='invalid_snapshot',
                        inference_submitted=False, missing_values_imputed=False)
        if current[6] != self.declared_policy['epoch']:
            self._invalidate_history('unacknowledged_policy_epoch')
            self.last_snapshot = None
            return dict(status='policy_transition_required',
                        reason='acknowledge the trusted committed policy before resuming',
                        inference_submitted=False, missing_values_imputed=False)
        previous = self.last_snapshot
        if previous is None:
            self._invalidate_history('initial_baseline')
            self.last_snapshot = current
            return dict(status='warming_up', samples=0, inference_submitted=False,
                        missing_values_imputed=False)
        if current[6] != previous[6] or current[7] != previous[7]:
            self._invalidate_history('policy_or_clock_boundary')
            self.last_snapshot = current
            return dict(status='warming_up', samples=0,
                        reason='policy_or_clock_boundary', inference_submitted=False,
                        missing_values_imputed=False)
        try:
            window = measured_window(previous, current)
        except ValueError as exc:
            self._invalidate_history(str(exc))
            self.last_snapshot = current
            return dict(status='invalid_measurements', reason=str(exc),
                        inference_submitted=False, missing_values_imputed=False)
        self.last_window_seconds = ((current[2] | current[3] << 32) -
                                    (previous[2] | previous[3] << 32)) / current[7]
        self.last_window_capture = None
        if self.window_records:
            self.last_window_capture = self.window_records[-1]['raw']
            values = sorted(row['latency'] * 1e6 / current[7] for row in self.window_records)
            window['metrics']['latency_p95_us'] = values[max(0, math.ceil(len(values) * .95) - 1)]
            window['provenance']['latency_p95_us'] = 'physical RX SOF to actual RTL quorum decision, per captured frame'
        window['missing'] = sorted(set(FEATURES) - set(window['metrics']))
        self.last_snapshot = current
        self.window_records = []
        if window['missing']:
            self._invalidate_history('incomplete_measurements')
            return dict(window, status='incomplete_measurements', inference_submitted=False)
        self.last_measurement_issue = None
        result = self.append_measurement(window['metrics'], window['provenance'])
        return dict(window, status=result['status'], inference=result,
                    inference_submitted=result['status'] != 'warming_up')

    def append_measurement(self, metrics, provenance):
        # Every feature must have a named measurement source. Do not fill an
        # unavailable measurement with a plausible zero to obtain valid AI.
        if set(metrics) != set(FEATURES) or set(provenance) != set(FEATURES):
            self._invalidate_history('missing_features')
            raise ValueError('18 measured features and 18 provenance entries required')
        if any(not isinstance(provenance[k], str) or not provenance[k] for k in FEATURES):
            self._invalidate_history('missing_provenance')
            raise ValueError('feature provenance required')
        if any(isinstance(metrics[k], bool) or not isinstance(metrics[k], (int, float)) or
               not math.isfinite(metrics[k]) for k in FEATURES):
            self._invalidate_history('nonfinite_or_nonnumeric_measurement')
            raise ValueError('finite numeric measurements required')
        self.last_measurement_issue = None
        self.history.append(dict(metrics=copy.deepcopy(metrics), provenance=copy.deepcopy(provenance)))
        self.history = self.history[-8:]
        if len(self.history) != 8:
            return dict(status='warming_up', samples=len(self.history))
        result = self.ai.analyze([[row['metrics'][key] for key in FEATURES] for row in self.history], job_id=self.read32(0x210) + 1)
        result.update(actual_data_path=True, feature_provenance=copy.deepcopy(self.history))
        self.last_inference=result
        return result

    def investigate(self, output):
        """Connect actual live measurements/captures to the existing agent.

        Agent recommendations remain evidence-backed candidates. Only the
        separately enabled hardware actuator may change frame admission.
        """
        import json
        from afdx_agent.agent import Agent
        output=Path(output).resolve()
        if output.exists():raise ValueError('choose a fresh investigation directory')
        if self.last_measurement_issue or not self.history or not self.records:raise RuntimeError('live measurements and captures required')
        output.mkdir(parents=True);case=output/'case';case.mkdir()
        flow={key:self.mimic.policy['rules'][0][key] for key in ('peer_ip','local_ip','rx_mac','peer_mac','source_port','destination_port')}
        flow['tx_mac']=flow['rx_mac']
        window='live_defense_'+str(len(self.records))
        observation=dict(schema=1,source='rtl_capture' if self.source=='rtl_simulation' else 'hardware',window_id=window,window_duration_s=self.last_window_seconds,
                         scope=dict(clock_hz=self.last_snapshot[7],link_mbps=100,security_mode=2),metrics=self.history[-1]['metrics'])
        (case/'observation.json').write_text(json.dumps(observation),encoding='utf-8')
        if self.last_window_capture is None:raise RuntimeError('no frame from measured window')
        (case/'capture.bin').write_bytes(self.last_window_capture)
        (case/'defense.log').write_text(json.dumps(dict(hardware_ai=self.last_inference,mimic=self.records[-1]),ensure_ascii=False),encoding='utf-8')
        manifest=dict(schema=1,case_id='live_defense',observation='observation.json',expected_flow=flow,artifacts=[
            dict(id='live_frame',type='frame',paths=['capture.bin'],binding='same_window',source='rtl_fixture' if self.source=='rtl_simulation' else 'hardware_capture',window_id=window),
            dict(id='defense_log',type='log',paths=['defense.log'],binding='same_window',source='rtl_fixture' if self.source=='rtl_simulation' else 'hardware_capture',window_id=window)])
        (case/'case.json').write_text(json.dumps(manifest),encoding='utf-8')
        report=Agent(root=ROOT,rtl_mode='off').run(case,output/'agent')
        return dict(status='PASS' if report['integrity_ok'] and not report['errors'] else 'FAIL',report=report,
                    actual_live_evidence=True,configuration_writes_applied=False,hardware_ai=self.last_inference)

    def configure_ai_response(self, enabled=False, candidate_mask=0xff):
        if type(enabled) is not bool or type(candidate_mask) is not int or not 0 <= candidate_mask <= 255:
            raise ValueError('AI response control')
        self.write32(0x204, candidate_mask)
        self.write32(0x200, int(enabled))


def measured_window(previous, current):
    """Return only features supported by actual atomic RTL snapshots.

The caller must add the explicitly missing protocol/context measurements
from its capture/session collector before append_measurement accepts a job.
"""
    if len(previous) != 64 or len(current) != 64 or current[6] != previous[6] or current[7] != previous[7] or current[7] <= 0:
        raise ValueError('snapshot shape or policy/clock boundary')
    u64 = lambda row, n: row[n] | row[n + 1] << 32
    delta32 = lambda n: (current[n] - previous[n]) & 0xffffffff
    delta64 = lambda n: (u64(current, n) - u64(previous, n)) & ((1 << 64) - 1)
    ticks = delta64(2)
    count = delta32(8) + delta32(9)
    if ticks <= 0 or ticks>=(1<<63) or count == 0 or current[1] == previous[1] or u64(current,2)<=u64(previous,2):
        raise ValueError('empty or nonmonotonic measurement window')
    byte_count = delta64(12)
    if byte_count == 0:
        raise ValueError('frames_without_measured_bytes')
    mean = byte_count / count
    variance = max(0, delta64(14) / count - mean * mean)
    gaps = delta32(16)
    gap_mean = delta64(17) / gaps if gaps else None
    metrics = dict(observed_pps=count * current[7] / ticks, mean_frame_bytes=mean,
                   frame_size_cv=math.sqrt(variance) / mean,
                   fcs_error_ratio=(delta32(10) + delta32(11)) / count,
                   ab_payload_mismatch_ratio=min(1, delta32(24) / max(1, count / 2)),
                   queue_overflow_ratio=min(1, (delta32(23) + delta32(29)) / count),
                   clock_step_abs_ms=abs(((delta64(4)+(1<<63))%(1<<64)-(1<<63)) / (1 << 32) - ticks / current[7]) * 1000)
    if gap_mean:
        metrics['arrival_cv'] = math.sqrt(max(0, delta64(19) / gaps - gap_mean ** 2)) / gap_mean
    metrics.update(ab_unpaired_ratio=max(0,min(1,1-2*delta32(47)/count)),
                   loader_retry_ratio=min(1,delta32(42)/count),
                   fragment_orphan_ratio=min(1,delta32(46)/count),
                   management_fraction=min(1,delta32(45)/count),
                   active_context_ratio=min(1,current[48]/16),
                   sha_jobs_per_1k_frames=delta32(44)*1000/count)
    if current[40]!=0 and current[32]&8:
        offset=u64(current,38);offset=offset-(1<<64) if offset>>63 else offset
        metrics['ntp_rtt_ms']=u64(current,36)*1000/(1<<32)
        metrics['ntp_offset_abs_ms']=abs(offset)*1000/(1<<32)
    if current[43]>0:
        metrics['loader_progress_ratio']=min(1,current[41]/current[43])
    elif not current[32]&1:
        metrics['loader_progress_ratio']=0.0
    return dict(metrics=metrics, missing=sorted(set(FEATURES) - set(metrics)),
                provenance={key:'AFDX_defense_top atomic raw-counter window' for key in metrics},
                missing_values_imputed=False)
