"""Generate the integrated defense top using the existing public core ports."""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    source = (ROOT / 'rtl/AFDX_security_plugin_top.v').read_text(encoding='utf-8')
    end = source.index(');\nfunction')
    header = source[:end].replace('AFDX_security_plugin_top', 'AFDX_defense_top', 1)
    header = header.replace(', parameter integer SECURITY_BOOT_MODE=2',
                            ', parameter integer SECURITY_BOOT_MODE=2,\n'
                            ' parameter integer MIMIC_DEADLINE_CYCLES=65536,AI_BLOCK_CYCLES=125000,\n'
                            ' parameter AI_WEIGHTS="aihw_plugin/rtl/weights.mem",AI_BIASES="aihw_plugin/rtl/biases.mem",\n'
                            ' parameter AI_THRESHOLDS="aihw_plugin/rtl/thresholds.mem",AI_SHIFTS="aihw_plugin/rtl/shifts.mem"')
    extra = ''',
 input wire defense_cfg_valid,defense_cfg_write,input wire [15:0] defense_cfg_addr,input wire [31:0] defense_cfg_wdata,
 output wire defense_cfg_ready,defense_cfg_error,output wire [31:0] defense_cfg_rdata,
 output wire ai_alarm,ai_block,output wire [7:0] ai_candidates,output wire [15:0] ai_status,
 output wire [31:0] ai_results,ai_actions,mimic_forwarded,mimic_blocked,mimic_timeouts,mimic_overflows,
 output wire mimic_request
);
'''
    helper = source[source.index('function '):source.index('endfunction') + len('endfunction')]
    core_start = source.index('AFDX_competition_top #(')
    core_end = source.index('\n);', core_start) + 3
    core = source[core_start:core_end]
    core = core.replace('.data_a_rxd(guarded_a)', '.data_a_rxd(final_a)').replace('.data_b_rxd(guarded_b)', '.data_b_rxd(final_b)')
    for suffix in ('v', 'e'):
        core = core.replace('(guarded_a' + suffix + ')', '(final_a' + suffix + ')').replace('(guarded_b' + suffix + ')', '(final_b' + suffix + ')')
    core = core.replace('(guarded_a_delay)', '(final_a_delay)').replace('(guarded_b_delay)', '(final_b_delay)')
    security = source[source.index('afdx_security_plugin #('):source.rindex('endmodule')]
    security=security.replace('.core_a_rx(guarded_a)', '.defense_telemetry(security_telemetry),.core_a_rx(guarded_a)')
    security = security.replace('.core_safe(!loading&&!management_busy&&!data_a_tx_en&&!data_b_tx_en)',
                                '.core_safe(defense_idle&&!loading&&!management_busy&&!data_a_tx_en&&!data_b_tx_en)')
    declarations = '''
wire [7:0] guarded_a,guarded_b,final_a,final_b;
wire guarded_av,guarded_bv,guarded_ae,guarded_be,final_av,final_bv,final_ae,final_be;
wire [63:0] guarded_a_delay,guarded_b_delay,final_a_delay,final_b_delay;
wire defense_idle,gate_idle,ai_idle;
reg [63:0] cycle;always @(posedge clk)begin if(rst)cycle<=0;else cycle<=cycle+1'b1;end
reg [SERVICE_DOMAIN_WIDTH-1:0] prior_domain;
always @(posedge clk)begin if(rst)prior_domain<=service_app_domain;else prior_domain<=service_app_domain;end
wire time_reanchor=prior_domain!==service_app_domain;
wire gate_select=defense_cfg_addr>=16'h1000;
wire gate_ready,gate_error,control_ready,control_error;
wire [31:0] gate_rdata,control_rdata,ai_blocked,stale_responses;
wire [63:0] last_request,last_latency;wire [2:0] last_reason;
wire [159:0] security_telemetry;
assign defense_cfg_ready=gate_select?gate_ready:control_ready;
assign defense_cfg_error=gate_select?gate_error:control_error;
assign defense_cfg_rdata=gate_select?gate_rdata:control_rdata;
assign defense_idle=gate_idle&&ai_idle;
'''
    integration = '''
afdx_defense_gate #(.DEADLINE_CYCLES(MIMIC_DEADLINE_CYCLES)) mimic(
 .clk(clk),.rst(rst),.cycle(cycle),.policy_epoch(sec_epoch),
 .a_data(guarded_a),.b_data(guarded_b),.a_valid(guarded_av),.b_valid(guarded_bv),.a_error(guarded_ae),.b_error(guarded_be),
 .a_delay(guarded_a_delay),.b_delay(guarded_b_delay),.ai_block(ai_block),
 .out_a(final_a),.out_b(final_b),.out_av(final_av),.out_bv(final_bv),.out_ae(final_ae),.out_be(final_be),.out_a_delay(final_a_delay),.out_b_delay(final_b_delay),
 .cfg_valid(defense_cfg_valid&&gate_select),.cfg_write(defense_cfg_write),.cfg_addr(defense_cfg_addr),.cfg_wdata(defense_cfg_wdata),
 .cfg_ready(gate_ready),.cfg_error(gate_error),.cfg_rdata(gate_rdata),.idle(gate_idle),.request_valid(mimic_request),
 .forwarded(mimic_forwarded),.blocked(mimic_blocked),.timeouts(mimic_timeouts),.ai_blocked(ai_blocked),.stale_responses(stale_responses),
 .overflows(mimic_overflows),.last_request(last_request),.last_latency(last_latency),.last_reason(last_reason));
afdx_defense_control #(.CLK_HZ(CLK_HZ),.AI_BLOCK_CYCLES(AI_BLOCK_CYCLES),.WEIGHTS_FILE(AI_WEIGHTS),.BIASES_FILE(AI_BIASES),.THRESHOLDS_FILE(AI_THRESHOLDS),.SHIFTS_FILE(AI_SHIFTS)) defense(
 .clk(clk),.rst(rst),.cycle(cycle),.utc(utc_ntp),.policy_epoch(sec_epoch),
 .sec_allow(sec_would_allow),.sec_block(sec_would_block),.sec_overflow(sec_queue_overflows),.ab_conflicts(sec_ab_conflicts),.hash_failures(sec_hash_failures),.time_alarms(sec_time_alarms),
 .a_rx(data_a_rxd),.b_rx(data_b_rxd),.a_valid(data_a_rx_dv),.b_valid(data_b_rx_dv),.a_error(data_a_rx_er),.b_error(data_b_rx_er),
 .loading(loading),.load_complete(load_complete),.load_failed(load_failed),.rtc_locked(rtc_locked),.package_generation(package_generation),
 .mimic_forwarded(mimic_forwarded),.mimic_blocked(mimic_blocked),.mimic_overflow(mimic_overflows),.mimic_latency(last_latency),
 .service_telemetry(service_telemetry),.security_telemetry(security_telemetry),
 .cfg_valid(defense_cfg_valid&&!gate_select),.cfg_write(defense_cfg_write),.cfg_addr(defense_cfg_addr),.cfg_wdata(defense_cfg_wdata),
 .cfg_ready(control_ready),.cfg_error(control_error),.cfg_rdata(control_rdata),.ai_block(ai_block),.ai_alarm(ai_alarm),.ai_candidates(ai_candidates),.ai_status(ai_status),.ai_results(ai_results),.ai_actions(ai_actions),.ai_idle(ai_idle));
endmodule
'''
    (ROOT / 'rtl/AFDX_defense_top.v').write_text(header + extra + helper + '\n' + declarations + core + '\n' + security + integration, encoding='utf-8')
    print('DEFENSE_TOP_GENERATED')


if __name__ == '__main__':
    main()
