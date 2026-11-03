`timescale 1ns / 1ps

module tb_afdx_m6d_integration;
    localparam integer MAX_MSG_BYTES = 128;
    localparam integer MAX_VB_BYTES = 64;
    localparam integer MAX_RESPONSE_BYTES = 96;

    reg clk, rst_n, req;
    reg [7:0] msg_length;
    reg [MAX_MSG_BYTES*8-1:0] msg_bytes;
    wire response_done, response_valid, response_error;
    wire [7:0] response_error_code, response_length;
    wire [MAX_RESPONSE_BYTES*8-1:0] response_bytes;
    integer errors;
    integer timeout_count;

    integer parsed_version, parsed_status, parsed_index;
    reg [39:0] parsed_value;
    reg [7:0] parsed_value_bytes [0:MAX_RESPONSE_BYTES-1];
    integer completed, envelope_ok, oid_match, i;
    integer parse_ok;
    integer parse_version_ok;
    integer parse_community_ok;
    integer parse_pdu_ok;
    integer parse_status_ok;
    integer parse_oid_ok;
    integer parse_value_ok;
    integer parsed_value_tag;
    integer parsed_value_len;
    reg [31:0] parsed_request_id;
    integer parsed_request_id_len;
    reg [31:0] parsed_request_id_bytes;
    localparam integer QUIET_CYCLES = 200;
    integer valid_edges, done_pulses, monitor_errors;
    reg previous_valid, previous_done;
    integer physical_requests;
    reg rejection_mode = 1'b0;
    reg request_rejection = 1'b0;
    integer rejection_samples_before;
    integer reset_assertions = 0;
    integer reset_releases = 0;

    always @(negedge rst_n) begin
        reset_assertions = reset_assertions + 1;
        if (reset_assertions != 1) begin
            $display("FINAL FAIL unexpected reset; STOP");
            $finish;
        end
    end
    always @(posedge rst_n) reset_releases = reset_releases + 1;

    always @(errors or monitor_errors) begin
        if ((rst_n === 1'b1) && ((errors > 0) || (monitor_errors > 0))) begin
            $display("FINAL FAIL failed=%0d monitor=%0d at %0t; STOP; later requests NOT RUN",
                errors, monitor_errors, $time);
            $finish;
        end
    end
    reg [7:0] current_oid [0:31];
    integer current_oid_len;
    integer visited [1:25];
    integer transaction_starts, builder_starts, valid_high_samples;
    reg previous_transaction_req, previous_builder_req, previous_req;

    always @(posedge clk) begin
        if (rst_n === 1'b0) begin
            physical_requests = 0;
            previous_req = 0;
        end else if (rst_n === 1'b1) begin
            if (req === 1'b1) physical_requests = physical_requests + 1;
            begin
                if (((req !== 1'b0) && (req !== 1'b1)) ||
                    ((req === 1'b1) && (previous_req !== 1'b0))) begin
                    monitor_errors = monitor_errors + 1;
                    $display("MONITOR FAIL unknown or repeated req at %0t", $time);
                end
            end
            previous_req = req;
        end
    end
    integer parsed_oid_len;
    reg [7:0] parsed_oid [0:31];

    afdx_m6d_integration #(
        .MAX_MSG_BYTES(MAX_MSG_BYTES), .MAX_VB_BYTES(MAX_VB_BYTES),
        .MAX_RESPONSE_BYTES(MAX_RESPONSE_BYTES), .CLK_HZ(1000)
    ) dut (
        .clk(clk), .rst_n(rst_n), .req(req), .msg_length(msg_length), .msg_bytes(msg_bytes),
        .response_done(response_done), .response_valid(response_valid),
        .response_error(response_error), .response_error_code(response_error_code),
        .response_length(response_length), .response_bytes(response_bytes),
        .m5_network_a_enable(1'b0), .m5_network_b_enable(1'b0), .m5_degraded_mode(1'b0),
        .m5_redundancy_ok(1'b0), .m5_frame_count_match(1'b0),
        .m5_active_byte_count_match(1'b0), .m5_fault_applied_event(1'b0),
        .m5_rx_accepted_count(32'd0), .m5_rx_accepted_a_count(32'd0),
        .m5_rx_accepted_b_count(32'd0), .m5_rx_duplicate_count(32'd0),
        .m5_rx_cross_network_duplicate_count(32'd0), .m5_rx_same_network_repeat_count(32'd0),
        .m5_rx_stale_count(32'd0), .m5_rx_sequence_gap_count(32'd0),
        .m5_tx_a_frame_count(32'd0), .m5_tx_b_frame_count(32'd0),
        .m5_tx_a_active_byte_count(32'd0), .m5_tx_b_active_byte_count(32'd0),
        .m5_tx_byte_mismatch_count(32'd0), .m5_tx_frame_skew_cycle_count(32'd0),
        .m5_tx_frame_done_skew_count(32'd0), .m5_tx_er_mismatch_count(32'd0),
        .m5_tx_a_error_cycle_count(32'd0), .m5_tx_b_error_cycle_count(32'd0),
        .m5_tx_a_underrun_count(32'd0), .m5_tx_b_underrun_count(32'd0)
    );

    always #5 clk = ~clk;
    integer model_cycles=0, model_snapshots=0, model_snap_uptime=0;
    always @(posedge clk) begin
        if (!rst_n) begin model_cycles=0; model_snapshots=0; model_snap_uptime=0; end
        else begin
            if (dut.snapshot_req_q) begin
                model_snapshots=model_snapshots+1;
                model_snap_uptime=model_cycles/10;
            end
            model_cycles=model_cycles+1;
        end
    end


    // Sample after DUT nonblocking updates; task checks use #2 to avoid races.
    always @(posedge clk) begin
        // Select the new contract on the request acceptance edge, before NBA sampling.
        if ((rst_n === 1'b1) && (req === 1'b1)) begin
            rejection_mode = request_rejection;
            if (request_rejection) rejection_samples_before = valid_high_samples;
        end
        #1;
        if (rst_n === 1'b1) begin
            if (((response_valid !== 1'b0) && (response_valid !== 1'b1)) ||
                ((response_done !== 1'b0) && (response_done !== 1'b1)) ||
                ((rejection_mode !== 1'b1) &&
                 ((response_error !== 1'b0) || (response_error_code !== 8'd0)))) begin
                monitor_errors = monitor_errors + 1;
                $display("MONITOR FAIL unknown control or response error at %0t", $time);
            end
            if ((response_valid === 1'b1) && (previous_valid === 1'b0))
                valid_edges = valid_edges + 1;
            if (response_done === 1'b1) begin
                done_pulses = done_pulses + 1;
                if ((previous_done !== 1'b0) ||
                    ((rejection_mode !== 1'b1) && (response_valid !== 1'b1))) begin
                    monitor_errors = monitor_errors + 1;
                    $display("MONITOR FAIL repeated done or done without valid at %0t", $time);
                end
            end
        end
        if (rst_n === 1'b0) begin
            transaction_starts = 0; builder_starts = 0; valid_high_samples = 0;
            previous_transaction_req = 0; previous_builder_req = 0;
        end else if (rst_n === 1'b1) begin
            if (dut.transaction_req === 1'b1) transaction_starts = transaction_starts + 1;
            if (dut.builder_req === 1'b1) builder_starts = builder_starts + 1;
            if (response_valid === 1'b1) valid_high_samples = valid_high_samples + 1;
            if (rejection_mode === 1'b1) begin
                if (((dut.transaction_req !== 1'b0) && (dut.transaction_req !== 1'b1)) ||
                    ((dut.builder_req !== 1'b0) && (dut.builder_req !== 1'b1)) ||
                    ((dut.transaction_req === 1'b1) && (previous_transaction_req !== 1'b0)) ||
                    ((dut.builder_req === 1'b1) && (previous_builder_req !== 1'b0)) ||
                    (response_valid !== 1'b0) ||
                    ((response_error !== 1'b0) && (response_error !== 1'b1)) ||
                    (^response_error_code === 1'bx) ||
                    (response_length !== 8'd0) ||
                    (response_bytes !== {MAX_RESPONSE_BYTES*8{1'b0}})) begin
                    monitor_errors = monitor_errors + 1;
                    $display("MONITOR FAIL rejection output or internal start pulse contract at %0t", $time);
                end
            end
            if (rejection_mode !== 1'b1) begin
                if (((dut.transaction_req !== 1'b0) && (dut.transaction_req !== 1'b1)) ||
                    ((dut.builder_req !== 1'b0) && (dut.builder_req !== 1'b1)) ||
                    ((dut.transaction_req === 1'b1) && (previous_transaction_req !== 1'b0)) ||
                    ((dut.builder_req === 1'b1) && (previous_builder_req !== 1'b0))) begin
                    monitor_errors = monitor_errors + 1;
                    $display("MONITOR FAIL unknown or repeated internal start at %0t", $time);
                end
            end
            previous_transaction_req = dut.transaction_req;
            previous_builder_req = dut.builder_req;
        end
        previous_valid = response_valid;
        previous_done = response_done;
    end

    function [7:0] rsp_byte;
        input integer index;
        begin
            rsp_byte = 8'hxx;
            if ((index >= 0) && (index < MAX_RESPONSE_BYTES) && (index < response_length))
                rsp_byte = response_bytes[(MAX_RESPONSE_BYTES*8-1)-index*8 -: 8];
        end
    endfunction

    task set_msg_byte;
        input integer index;
        input [7:0] value;
        begin msg_bytes[index*8 +: 8] = value; end
    endtask

    task make_request;
        input op;
        input [7:0] oid;
        input [31:0] rid;
        begin
            msg_bytes = '0;
            msg_length = 8'd46;
            set_msg_byte(0,8'h30); set_msg_byte(1,8'h2C);
            set_msg_byte(2,8'h02); set_msg_byte(3,8'h01); set_msg_byte(4,8'h01);
            set_msg_byte(5,8'h04); set_msg_byte(6,8'h06);
            set_msg_byte(7,8'h70); set_msg_byte(8,8'h75); set_msg_byte(9,8'h62);
            set_msg_byte(10,8'h6C); set_msg_byte(11,8'h69); set_msg_byte(12,8'h63);
            set_msg_byte(13, op ? 8'hA1 : 8'hA0); set_msg_byte(14,8'h1F);
            set_msg_byte(15,8'h02); set_msg_byte(16,8'h04);
            set_msg_byte(17,rid[31:24]); set_msg_byte(18,rid[23:16]);
            set_msg_byte(19,rid[15:8]); set_msg_byte(20,rid[7:0]);
            set_msg_byte(21,8'h02); set_msg_byte(22,8'h01); set_msg_byte(23,8'h00);
            set_msg_byte(24,8'h02); set_msg_byte(25,8'h01); set_msg_byte(26,8'h00);
            set_msg_byte(27,8'h30); set_msg_byte(28,8'h11);
            set_msg_byte(29,8'h30); set_msg_byte(30,8'h0F);
            set_msg_byte(31,8'h06); set_msg_byte(32,8'h0B);
            set_msg_byte(33,8'h2B); set_msg_byte(34,8'h06); set_msg_byte(35,8'h01);
            set_msg_byte(36,8'h04); set_msg_byte(37,8'h01); set_msg_byte(38,8'h81);
            set_msg_byte(39,8'hFD); set_msg_byte(40,8'h59); set_msg_byte(41,8'h01);
            set_msg_byte(42,8'h01); set_msg_byte(43,oid);
            set_msg_byte(44,8'h05); set_msg_byte(45,8'h00);
        end
    endtask

    task run_request;
        input op;
        input [7:0] oid;
        input [31:0] rid;
        begin
            make_request(op, oid, rid);
            send_request;
        end
    endtask

    task send_request;
        integer j;
        begin
            $write("REQUEST len=%0d hex=", msg_length);
            for (j=0; j<msg_length; j=j+1) $write("%02h", msg_bytes[j*8 +: 8]);
            $display("");
            completed = 0;
            #1; @(negedge clk); req = 1'b1;
            @(negedge clk); req = 1'b0;
            timeout_count = 0;
            while ((response_done !== 1'b1) && (timeout_count < 200)) begin
                @(posedge clk); #2; timeout_count = timeout_count + 1;
            end
            if (response_done !== 1'b1) begin
                $display("ERROR timeout after 200 cycles");
            end else completed = 1;
            $display("RESPONSE done=%b valid=%b error=%b code=%02h len=%0d timeout=%0d cycles=%0d",
                response_done, response_valid, response_error, response_error_code,
                response_length, !completed, timeout_count);
            $write("RESPONSE hex=");
            if ((^response_length !== 1'bx) && (response_length <= MAX_RESPONSE_BYTES))
                for (j=0; j<response_length; j=j+1) $write("%02h", rsp_byte(j));
            else $write("<invalid length>");
            $display("");
        end
    endtask

    // All TLVs are short-form and contained in their immediate parent.
    task read_tlv;
        inout integer p;
        input integer parent_end;
        input integer expected_tag;
        output integer n;
        begin
            n = 0;
            if (parse_ok) begin
                if ((p < 0) || (p+2 > parent_end)) parse_ok = 0;
                else if ((^rsp_byte(p) === 1'bx) || (^rsp_byte(p+1) === 1'bx)) parse_ok = 0;
                else if ((expected_tag >= 0) && (rsp_byte(p) != expected_tag)) parse_ok = 0;
                else if (rsp_byte(p+1) >= 128) parse_ok = 0;
                else begin
                    n = rsp_byte(p+1);
                    p = p + 2;
                    if (p+n > parent_end) parse_ok = 0;
                end
            end
        end
    endtask

    task read_integer;
        inout integer p;
        input integer parent_end;
        output reg [31:0] value;
        integer n, j;
        reg [7:0] first;
        begin
            value = 0;
            read_tlv(p, parent_end, 2, n);
            if (parse_ok) begin
                if ((n < 1) || (n > 4)) parse_ok = 0;
                else begin
                    first = rsp_byte(p);
                    value = first[7] ? 32'hFFFFFFFF : 0;
                    for (j=0; j<n; j=j+1) value = (value << 8) | rsp_byte(p+j);
                    p = p+n;
                end
            end
        end
    endtask

    task parse_response;
        integer p, n, j, msg_end, pdu_end, list_end, vb_end;
        begin
            parse_ok = 0; parse_version_ok = 0; parse_community_ok = 0;
            parse_pdu_ok = 0; parse_status_ok = 0; parse_oid_ok = 0; parse_value_ok = 0;
            parsed_request_id_len = 0; parsed_request_id_bytes = 0;
            parsed_request_id = 0; parsed_oid_len = 0; parsed_value_tag = 0; parsed_value_len = 0;
            parsed_version = -1; parsed_status = -1; parsed_index = -1; parsed_value = 0;
            envelope_ok = 0;
            for (j=0; j<32; j=j+1) parsed_oid[j] = 0;
            for (j=0; j<MAX_RESPONSE_BYTES; j=j+1) parsed_value_bytes[j] = 0;
            begin : decode
                if ((^response_length === 1'bx) || (response_length < 2) ||
                    (response_length > MAX_RESPONSE_BYTES)) disable decode;
                for (j=0; j<response_length; j=j+1)
                    if (^rsp_byte(j) === 1'bx) disable decode;
                parse_ok = 1; p = 0;
                read_tlv(p, response_length, 48, n); msg_end = p+n;
                if (!parse_ok || (msg_end != response_length)) begin parse_ok=0; disable decode; end
                read_integer(p, msg_end, parsed_version);
                read_tlv(p, msg_end, 4, n);
                if (!parse_ok) disable decode;
                parse_community_ok = (n == 6) && (rsp_byte(p) === 8'h70) &&
                    (rsp_byte(p+1) === 8'h75) && (rsp_byte(p+2) === 8'h62) &&
                    (rsp_byte(p+3) === 8'h6C) && (rsp_byte(p+4) === 8'h69) && (rsp_byte(p+5) === 8'h63);
                p = p+n;
                read_tlv(p, msg_end, 162, n); pdu_end = p+n;
                if (!parse_ok || (pdu_end != msg_end)) begin parse_ok=0; disable decode; end
                read_tlv(p, pdu_end, 2, n);
                if (!parse_ok || (n < 1) || (n > 4)) begin parse_ok=0; disable decode; end
                parsed_request_id_len = n;
                for (j=0; j<n; j=j+1)
                    parsed_request_id_bytes = (parsed_request_id_bytes << 8) | rsp_byte(p+j);
                p = p-2;
                read_integer(p, pdu_end, parsed_request_id);
                read_integer(p, pdu_end, parsed_status);
                read_integer(p, pdu_end, parsed_index);
                read_tlv(p, pdu_end, 48, n); list_end = p+n;
                if (!parse_ok || (list_end != pdu_end)) begin parse_ok=0; disable decode; end
                read_tlv(p, list_end, 48, n); vb_end = p+n;
                if (!parse_ok || (vb_end != list_end)) begin parse_ok=0; disable decode; end
                read_tlv(p, vb_end, 6, n);
                if (!parse_ok || (n < 1) || (n > 32)) begin parse_ok=0; disable decode; end
                parsed_oid_len = n;
                for (j=0; j<n; j=j+1) parsed_oid[j] = rsp_byte(p+j);
                if ((parsed_oid[n-1] & 8'h80) != 0) begin parse_ok=0; disable decode; end
                p = p+n;
                parsed_value_tag = rsp_byte(p);
                read_tlv(p, vb_end, -1, n);
                if (!parse_ok || (p+n != vb_end)) begin parse_ok=0; disable decode; end
                parsed_value_len = n;
                for (j=0; j<n; j=j+1) parsed_value_bytes[j] = rsp_byte(p+j);
                case (parsed_value_tag)
                    2: if ((n < 1) || (n > 4)) parse_ok=0;
                    65, 67: if ((n < 1) || (n > 5) || (rsp_byte(p) >= 128) ||
                        ((n == 5) && (rsp_byte(p) != 0))) parse_ok=0;
                    5, 128, 129, 130: if (n != 0) parse_ok=0;
                    default: parse_ok=0;
                endcase
                if (!parse_ok) disable decode;
                for (j=0; j<n; j=j+1) parsed_value = (parsed_value << 8) | parsed_value_bytes[j];
            end
            // Format validity is independent of the expected object and value.
            parse_version_ok = parse_ok && (parsed_version == 1);
            parse_pdu_ok = parse_ok;
            parse_status_ok = parse_ok && (parsed_status == 0) && (parsed_index == 0);
            parse_value_ok = parse_ok && (parsed_value_tag == 2) &&
                (parsed_value_len == 3) && (parsed_value == 40'h060A01);
            envelope_ok = completed && parse_ok && parse_version_ok && parse_community_ok && parse_status_ok;
            $display("PARSED format=%0d version=%0d rid=%08h status=%0d index=%0d",
                parse_ok, parsed_version, parsed_request_id, parsed_status, parsed_index);
            $display("PARSED rid_length=%0d rid_raw=%08h", parsed_request_id_len, parsed_request_id_bytes);
            $write("PARSED oid[%0d]=", parsed_oid_len);
            for (j=0; j<parsed_oid_len; j=j+1) $write("%02h", parsed_oid[j]);
            $write(" value tag=%02h len=%0d hex=", parsed_value_tag, parsed_value_len);
            for (j=0; j<parsed_value_len; j=j+1) $write("%02h", parsed_value_bytes[j]);
            $display("");
        end
    endtask

    task compare_request_oid;
        input successor;
        integer j, n;
        reg [7:0] expected;
        begin
            n = msg_bytes[32*8 +: 8];
            oid_match = parse_ok && (n == 11) && (parsed_oid_len == n);
            for (j=0; j<n; j=j+1) begin
                expected = msg_bytes[(33+j)*8 +: 8];
                if (successor && (j == n-1)) expected = expected + 1;
                if (j < 32) begin
                    if (parsed_oid[j] !== expected) oid_match = 0;
                end else oid_match = 0;
            end
        end
    endtask

    task formal_request;
        input integer number;
        input [7:0] oid;
        input [31:0] rid;
        integer start_valid, start_done, start_errors, functional_ok, quiet_ok, j;
        integer start_requests, start_transaction, start_builder;
        begin
            start_requests = physical_requests;
            start_transaction = transaction_starts; start_builder = builder_starts;
            start_valid = valid_edges; start_done = done_pulses; start_errors = monitor_errors;
            $display("M6D-0%0d v2c GET canonical object%0d RID=%08h", number, oid, rid);
            run_request(1'b0, oid, rid);
            parse_response; compare_request_oid(1'b0);
            functional_ok = (envelope_ok === 1) && (oid_match === 1) &&
                (response_valid === 1'b1) && (response_error === 1'b0) &&
                (response_error_code === 8'd0) && (parsed_request_id_len === 4) &&
                (parsed_request_id_bytes === rid) && (parsed_request_id === rid);
            if (oid === 8'd1)
                functional_ok = functional_ok && (parse_value_ok === 1) &&
                    (parsed_value_bytes[0] === 8'h06) && (parsed_value_bytes[1] === 8'h0A) &&
                    (parsed_value_bytes[2] === 8'h01);
            else
                functional_ok = functional_ok && (parsed_value_tag === 65) &&
                    (parsed_value_len === 1) && (parsed_value_bytes[0] === 8'h00);
            quiet_ok = 1;
            for (j=0; j<QUIET_CYCLES; j=j+1) begin
                @(posedge clk); #2;
                if ((response_done !== 1'b0) || (response_valid !== 1'b1) ||
                    (valid_edges !== start_valid+1) || (done_pulses !== start_done+1)) quiet_ok = 0;
            end
            $display("M6D-0%0d CHECK functional=%0d valid_rises=%0d done_pulses=%0d quiet_cycles=%0d quiet_ok=%0d monitor_errors=%0d latency=%0d (informational)",
                number, functional_ok, valid_edges-start_valid, done_pulses-start_done,
                QUIET_CYCLES, quiet_ok, monitor_errors-start_errors, timeout_count);
            $display("M6D-0%0d STARTS physical=%0d txn=%0d builder=%0d", number,
                physical_requests-start_requests, transaction_starts-start_transaction, builder_starts-start_builder);
            if ((functional_ok === 1) && (quiet_ok === 1) &&
                (physical_requests === start_requests+1) &&
                (transaction_starts === start_transaction+1) && (builder_starts === start_builder+1) &&
                (valid_edges === start_valid+1) && (done_pulses === start_done+1) &&
                (monitor_errors === start_errors)) $display("M6D-0%0d PASS", number);
            else begin errors = errors+1; $display("M6D-0%0d FAIL", number); end
        end
    endtask

    task formal_getnext;
        input integer number;
        input [7:0] oid;
        input [31:0] rid;
        integer start_valid, start_done, start_errors, start_requests;
        integer start_transaction, start_builder;
        integer functional_ok, quiet_ok, transport_ok, j;
        reg [7:0] saved_length;
        reg [MAX_RESPONSE_BYTES*8-1:0] saved_bytes;
        begin
            start_valid = valid_edges; start_done = done_pulses;
            start_errors = monitor_errors; start_requests = physical_requests;
            start_transaction = transaction_starts; start_builder = builder_starts;
            $display("M6D-0%0d v2c GETNEXT canonical object%0d RID=%08h", number, oid, rid);
            run_request(1'b1, oid, rid);
            parse_response;
            compare_request_oid(number != 7);
            functional_ok = (envelope_ok === 1) && (parse_pdu_ok === 1) &&
                (response_valid === 1'b1) && (response_done === 1'b1) &&
                (response_error === 1'b0) && (response_error_code === 8'd0) &&
                (parsed_request_id_len === 4) && (parsed_request_id_bytes === rid) &&
                (parsed_request_id === rid) && (parsed_status === 0) && (parsed_index === 0);
            case (number)
                4: functional_ok = functional_ok && (parsed_value_tag === 65) &&
                    (parsed_value_len === 1) && (parsed_value_bytes[0] === 8'h00);
                6: functional_ok = functional_ok && (oid_match === 1) &&
                    (parse_value_ok === 1) && (parsed_value_bytes[0] === 8'h06) &&
                    (parsed_value_bytes[1] === 8'h0A) && (parsed_value_bytes[2] === 8'h01);
                7: functional_ok = functional_ok && (oid_match === 1) &&
                    (parsed_value_tag === 130) && (parsed_value_len === 0);
                default: functional_ok = 0;
            endcase
            saved_length = response_length; saved_bytes = response_bytes;
            quiet_ok = 1;
            for (j=0; j<QUIET_CYCLES; j=j+1) begin
                @(posedge clk); #2;
                if ((response_done !== 1'b0) || (response_valid !== 1'b1) ||
                    (valid_edges !== start_valid+1) || (done_pulses !== start_done+1) ||
                    (response_length !== saved_length) || (response_bytes !== saved_bytes)) quiet_ok = 0;
            end
            transport_ok = (quiet_ok === 1) && (valid_edges === start_valid+1) &&
                (done_pulses === start_done+1) && (monitor_errors === start_errors) &&
                (physical_requests === start_requests+1) &&
                (transaction_starts === start_transaction+1) && (builder_starts === start_builder+1);
            $display("M6D-0%0d STARTS txn=%0d builder=%0d", number,
                transaction_starts-start_transaction, builder_starts-start_builder);
            $display("M6D-0%0d CHECK functional=%0d valid_rises=%0d done_pulses=%0d physical_requests=%0d quiet_cycles=%0d quiet_ok=%0d monitor_errors=%0d latency=%0d (informational)",
                number, functional_ok, valid_edges-start_valid, done_pulses-start_done,
                physical_requests-start_requests, QUIET_CYCLES, quiet_ok,
                monitor_errors-start_errors, timeout_count);
            if ((functional_ok === 1) && (transport_ok === 1))
                $display("M6D-0%0d PASS", number);
            else begin errors = errors+1; $display("M6D-0%0d FAIL", number); end
            if (number == 4) begin
                $display("M6D-05 CHECK same physical request as 04; complete final BER canonical object6 OID match=%0d", oid_match);
                if ((parse_ok === 1) && (oid_match === 1) && (transport_ok === 1))
                    $display("M6D-05 PASS");
                else begin errors = errors+1; $display("M6D-05 FAIL"); end
            end
        end
    endtask

    task formal_rejection;
        input integer number;
        input [31:0] rid;
        input integer mutation_index;
        input [7:0] mutation_value;
        input [7:0] expected_code;
        integer start_requests, start_done, start_valid, start_samples, start_errors;
        integer start_transaction, start_builder, differences, mutation_ok;
        integer functional_ok, transport_ok, quiet_ok, j;
        reg [MAX_MSG_BYTES*8-1:0] legal_bytes;
        reg [7:0] legal_length, saved_code;
        begin
            start_requests = physical_requests; start_done = done_pulses;
            start_valid = valid_edges; start_samples = valid_high_samples;
            start_errors = monitor_errors;
            start_transaction = transaction_starts; start_builder = builder_starts;
            make_request(1'b0, 8'd1, rid);
            legal_bytes = msg_bytes; legal_length = msg_length;
            set_msg_byte(mutation_index, mutation_value);
            differences = 0; mutation_ok = 1;
            for (j=0; j<MAX_MSG_BYTES; j=j+1) begin
                if (msg_bytes[j*8 +: 8] !== legal_bytes[j*8 +: 8]) begin
                    differences = differences + 1;
                    if (j !== mutation_index) mutation_ok = 0;
                end
            end
            mutation_ok = (mutation_ok === 1) && (differences === 1) &&
                (msg_length === legal_length) && (msg_length === 8'd46) &&
                (msg_bytes[mutation_index*8 +: 8] === mutation_value);
            $display("M6D-%02d rejection canonical object1 RID=%08h mutation_index=%0d before=%02h after=%02h differences=%0d isolated=%0d expected_code=%0d",
                number, rid, mutation_index, legal_bytes[mutation_index*8 +: 8],
                mutation_value, differences, mutation_ok, expected_code);
            functional_ok = 1;
            request_rejection = 1'b1;
            send_request;
            start_samples = rejection_samples_before;
            functional_ok = (functional_ok === 1) && (mutation_ok === 1) &&
                (completed === 1) && (response_done === 1'b1) &&
                (response_valid === 1'b0) && (response_error === 1'b1) &&
                (response_error_code === expected_code) && (response_length === 8'd0) &&
                (response_bytes === {MAX_RESPONSE_BYTES*8{1'b0}});
            saved_code = response_error_code;
            quiet_ok = 1;
            for (j=0; j<QUIET_CYCLES; j=j+1) begin
                @(posedge clk); #2;
                if ((response_done !== 1'b0) || (response_valid !== 1'b0) ||
                    (response_error !== 1'b1) || (response_error_code !== saved_code) ||
                    (response_length !== 8'd0) ||
                    (response_bytes !== {MAX_RESPONSE_BYTES*8{1'b0}}) ||
                    (valid_edges !== start_valid) || (valid_high_samples !== start_samples) ||
                    (done_pulses !== start_done+1) || (physical_requests !== start_requests+1) ||
                    (transaction_starts !== start_transaction) ||
                    (builder_starts !== start_builder)) quiet_ok = 0;
            end
            transport_ok = (quiet_ok === 1) && (valid_edges === start_valid) &&
                (valid_high_samples === start_samples) && (done_pulses === start_done+1) &&
                (physical_requests === start_requests+1) && (monitor_errors === start_errors) &&
                (transaction_starts === start_transaction) && (builder_starts === start_builder);
            $display("M6D-%02d STARTS transaction_before=%0d after=%0d delta=%0d builder_before=%0d after=%0d delta=%0d",
                number, start_transaction, transaction_starts, transaction_starts-start_transaction,
                start_builder, builder_starts, builder_starts-start_builder);
            $display("M6D-%02d CHECK functional=%0d transport=%0d physical_requests=%0d done=%0d valid_rises=%0d valid_high_samples=%0d expected_code=%0d actual_code=%0d quiet_cycles=%0d quiet_ok=%0d monitor_errors=%0d timeout=%0d",
                number, functional_ok, transport_ok, physical_requests-start_requests,
                done_pulses-start_done, valid_edges-start_valid, valid_high_samples-start_samples,
                expected_code, saved_code, QUIET_CYCLES, quiet_ok, monitor_errors-start_errors, !completed);
            if ((functional_ok === 1) && (transport_ok === 1))
                $display("M6D-%02d PASS", number);
            else begin errors = errors+1; $display("M6D-%02d FAIL", number); end
        end
    endtask

    task formal_batch_a;
      begin
        $display("Formal Batch A M6D-01~03; three GET requests; quiet window=%0d cycles", QUIET_CYCLES);
        begin : batch_a
            formal_request(1, 8'd1, 32'h12345678);
            if (errors !== 0) begin
                $display("Batch A STOP after 01; M6D-02~03 NOT RUN");
                disable batch_a;
            end
            formal_request(2, 8'd1, 32'h89ABCDEF);
            if (errors !== 0) begin
                $display("Batch A STOP after 02; M6D-03 NOT RUN");
                disable batch_a;
            end
            formal_request(3, 8'd6, 32'h23456789);
        end
        $display("TOTAL physical_requests_issued=%0d responses=%0d done=%0d monitor_errors=%0d failed_cases=%0d",
            physical_requests, valid_edges, done_pulses, monitor_errors, errors);
        if ((physical_requests === 3) && (errors === 0) && (monitor_errors === 0) &&
            (valid_edges === 3) && (done_pulses === 3))
            $display("Formal Batch A M6D-01~03 PASS");
        else begin errors = errors+1; $display("Formal Batch A FAIL; STOP"); $finish; end
      end
    endtask

    task formal_batch_b;
      begin
        rejection_mode = 1'b0;
        $display("Formal Batch B M6D-04~07; continuing after Batch A without reset; quiet window=%0d cycles", QUIET_CYCLES);
        begin : batch_b
            formal_getnext(4, 8'd5, 32'h3456789A);
            if (errors !== 0) begin
                $display("Batch B STOP after 04/05; M6D-06~07 NOT RUN");
                disable batch_b;
            end
            formal_getnext(6, 8'd0, 32'h456789AB);
            if (errors !== 0) begin
                $display("Batch B STOP after 06; M6D-07 NOT RUN");
                disable batch_b;
            end
            formal_getnext(7, 8'd25, 32'h56789ABC);
        end
        $display("TOTAL physical_requests_issued=%0d responses=%0d done=%0d monitor_errors=%0d failed_cases=%0d",
            physical_requests, valid_edges, done_pulses, monitor_errors, errors);
        if ((physical_requests === 6) && (valid_edges === 6) && (done_pulses === 6) &&
            (monitor_errors === 0) && (errors === 0))
            $display("Formal Batch B M6D-04~07 PASS; Batch A preserved");
        else begin errors = errors+1; $display("Formal Batch B FAIL; STOP"); $finish; end
      end
    endtask

    initial begin
        clk = 0; rst_n = 0; req = 0; msg_length = 0; msg_bytes = 0; errors = 0;
        valid_edges = 0; done_pulses = 0; monitor_errors = 0; physical_requests = 0;
        previous_valid = 0; previous_done = 0;
        transaction_starts = 0; builder_starts = 0; valid_high_samples = 0;
        previous_transaction_req = 0; previous_builder_req = 0; previous_req = 0;
        repeat (4) @(posedge clk); @(negedge clk); rst_n = 1;
        repeat (2) begin @(posedge clk); #2; end
        $display("M6D-13 serial final A->B->C->D; one initial reset; no extra physical request");
        formal_batch_a;
        formal_batch_b;
        formal_batch_c;
        formal_batch_d;
    end

    task formal_batch_c;
      begin
        $display("Formal Batch C M6D-08~11; continuing after Batch B without reset; quiet window=%0d cycles", QUIET_CYCLES);
        // Error codes follow afdx_snmp_request_decoder ERR_* definitions.
        formal_rejection(8, 32'h6789ABCD, 12, 8'h78, 8'd2);
        formal_rejection(9, 32'h789ABCDE, 1, 8'h2D, 8'd1);
        formal_rejection(10, 32'h1234ABCD, 13, 8'hA5, 8'd3);
        formal_rejection(11, 32'h2345BCDE, 13, 8'hA3, 8'd4);
        $display("TOTAL physical_requests=%0d done=%0d valid_edges=%0d transaction_starts=%0d builder_starts=%0d valid_high_samples=%0d monitor_errors=%0d failed_cases=%0d",
            physical_requests, done_pulses, valid_edges, transaction_starts,
            builder_starts, valid_high_samples, monitor_errors, errors);
        if ((physical_requests === 10) && (done_pulses === 10) && (valid_edges === 6) &&
            (transaction_starts === 6) && (builder_starts === 6) &&
            (monitor_errors === 0) && (errors === 0))
            $display("Formal Batch C M6D-08~11 PASS; A/B preserved; each rejection valid_high_samples delta=0");
        else begin errors = errors+1; $display("Formal Batch C FAIL; STOP"); $finish; end
      end
    endtask
    // The request OID is the manager's byte array, never an expected object index.
    task make_walk_request;
        input [31:0] rid;
        integer j;
        begin
            msg_bytes = '0;
            msg_length = 35 + current_oid_len;
            set_msg_byte(0,8'h30); set_msg_byte(1,33+current_oid_len);
            set_msg_byte(2,8'h02); set_msg_byte(3,8'h01); set_msg_byte(4,8'h01);
            set_msg_byte(5,8'h04); set_msg_byte(6,8'h06);
            set_msg_byte(7,8'h70); set_msg_byte(8,8'h75); set_msg_byte(9,8'h62);
            set_msg_byte(10,8'h6C); set_msg_byte(11,8'h69); set_msg_byte(12,8'h63);
            set_msg_byte(13,8'hA1); set_msg_byte(14,20+current_oid_len);
            set_msg_byte(15,8'h02); set_msg_byte(16,8'h04);
            set_msg_byte(17,rid[31:24]); set_msg_byte(18,rid[23:16]);
            set_msg_byte(19,rid[15:8]); set_msg_byte(20,rid[7:0]);
            set_msg_byte(21,8'h02); set_msg_byte(22,8'h01); set_msg_byte(23,8'h00);
            set_msg_byte(24,8'h02); set_msg_byte(25,8'h01); set_msg_byte(26,8'h00);
            set_msg_byte(27,8'h30); set_msg_byte(28,6+current_oid_len);
            set_msg_byte(29,8'h30); set_msg_byte(30,4+current_oid_len);
            set_msg_byte(31,8'h06); set_msg_byte(32,current_oid_len);
            for (j=0; j<current_oid_len; j=j+1) set_msg_byte(33+j,current_oid[j]);
            set_msg_byte(33+current_oid_len,8'h05);
            set_msg_byte(34+current_oid_len,8'h00);
        end
    endtask

    task formal_walk;
        integer step, j, returned_id, canonical_ok, functional_ok, quiet_ok, transport_ok;
        integer start_requests, start_valid, start_done, start_errors, start_transaction, start_builder;
        integer expected_tag, expected_len, expected_id;
        reg [39:0] expected_value;
        reg [87:0] expected_oid;
        reg [31:0] rid;
        reg [7:0] saved_length;
        reg [MAX_RESPONSE_BYTES*8-1:0] saved_bytes;
        begin : walk
            current_oid_len = 11;
            {current_oid[0],current_oid[1],current_oid[2],current_oid[3],
             current_oid[4],current_oid[5],current_oid[6],current_oid[7],
             current_oid[8],current_oid[9],current_oid[10]} = 88'h2b0601040181fd59010100;
            for (j=1; j<=25; j=j+1) visited[j] = 0;
            for (step=1; step<=26; step=step+1) begin
                rid = 32'h60000000 + step;
                start_requests = physical_requests; start_valid = valid_edges;
                start_done = done_pulses; start_errors = monitor_errors;
                start_transaction = transaction_starts; start_builder = builder_starts;
                $display("M6D-12 STEP %0d GETNEXT RID=%08h", step, rid);
                request_rejection = 1'b0;
                make_walk_request(rid);
                send_request;
                parse_response;
                expected_id = (step <= 25) ? step : 25;
                expected_oid = {80'h2b0601040181fd590101,8'h00};
                expected_oid[7:0] = expected_id;
                canonical_ok = (parse_ok === 1) && (parsed_oid_len === 11);
                for (j=0; j<11; j=j+1)
                    if (parsed_oid[j] !== expected_oid[87-j*8 -: 8]) canonical_ok = 0;
                functional_ok = (envelope_ok === 1) && (parse_pdu_ok === 1) &&
                    (canonical_ok === 1) && (response_done === 1'b1) &&
                    (response_valid === 1'b1) && (response_error === 1'b0) &&
                    (response_error_code === 8'd0) && (parsed_status === 0) &&
                    (parsed_index === 0) && (parsed_request_id_len === 4) &&
                    (parsed_request_id === rid);
                for (j=0; j<4; j=j+1)
                    if (parsed_request_id_bytes[31-j*8 -: 8] !== rid[31-j*8 -: 8]) functional_ok = 0;
                // MIB objects 1..5: version, snapshot_id, captured uptime, status, events.
                // Each valid query gets a new snapshot; the oracle counts capture
                // handshakes and elapsed clocks. All M5 inputs in this legacy test are zero.
                expected_tag = 65; expected_len = 1; expected_value = 0;
                case (step)
                    1: begin expected_tag = 2; expected_len = 3; expected_value = 40'h060A01; end
                    2: expected_value = model_snapshots;
                    3: begin expected_tag = 67; expected_value = model_snap_uptime;
                        if (expected_value>127) expected_len=2; end
                    4,5: expected_tag = 2;
                    26: begin expected_tag = 130; expected_len = 0; end
                endcase
                functional_ok = functional_ok && (parsed_value_tag === expected_tag) &&
                    (parsed_value_len === expected_len) && (parsed_value === expected_value);
                for (j=0; j<expected_len; j=j+1)
                    if (parsed_value_bytes[j] !== ((expected_value >> ((expected_len-1-j)*8)) & 8'hFF))
                        functional_ok = 0;
                if (step <= 25) begin
                    if (canonical_ok === 1) begin
                        returned_id = parsed_oid[parsed_oid_len-1];
                        if ((returned_id < 1) || (returned_id > 25)) functional_ok = 0;
                        else begin
                            if (visited[returned_id] !== 0) functional_ok = 0;
                            visited[returned_id] = visited[returned_id] + 1;
                        end
                    end
                end else begin
                    if (parsed_oid_len !== current_oid_len) functional_ok = 0;
                    for (j=0; j<current_oid_len; j=j+1)
                        if ((parsed_oid[j] !== current_oid[j]) ||
                            (parsed_oid[j] !== msg_bytes[(33+j)*8 +: 8])) functional_ok = 0;
                end
                if ((functional_ok !== 1) || (monitor_errors !== start_errors)) begin
                    errors = errors + 1;
                    $display("M6D-12 STEP %0d FAIL functional=%0d monitor_delta=%0d; STOP", step, functional_ok, monitor_errors-start_errors);
                    disable walk;
                end
                saved_length = response_length; saved_bytes = response_bytes;
                quiet_ok = 1;
                for (j=0; j<QUIET_CYCLES; j=j+1) begin
                    @(posedge clk); #2;
                    if ((response_done !== 1'b0) || (response_valid !== 1'b1) ||
                        (response_error !== 1'b0) || (response_error_code !== 8'd0) ||
                        (response_length !== saved_length) || (response_bytes !== saved_bytes) ||
                        (valid_edges !== start_valid+1) || (done_pulses !== start_done+1) ||
                        (physical_requests !== start_requests+1) ||
                        (transaction_starts !== start_transaction+1) ||
                        (builder_starts !== start_builder+1) || (monitor_errors !== start_errors)) quiet_ok = 0;
                    if (quiet_ok !== 1) begin
                        errors = errors + 1;
                        $display("M6D-12 STEP %0d FAIL quiet cycle=%0d; STOP", step, j+1);
                        disable walk;
                    end
                end
                transport_ok = (physical_requests === start_requests+1) &&
                    (valid_edges === start_valid+1) && (done_pulses === start_done+1) &&
                    (transaction_starts === start_transaction+1) &&
                    (builder_starts === start_builder+1) && (monitor_errors === start_errors);
                $display("M6D-12 STEP %0d STARTS transaction_before=%0d after=%0d delta=%0d builder_before=%0d after=%0d delta=%0d",
                    step, start_transaction, transaction_starts, transaction_starts-start_transaction,
                    start_builder, builder_starts, builder_starts-start_builder);
                $display("M6D-12 STEP %0d CHECK oid=%0d tag=%02h len=%0d value=%010h functional=%0d physical=%0d valid_rises=%0d done=%0d quiet=%0d quiet_ok=%0d monitor=%0d latency=%0d (informational)",
                    step, expected_id, parsed_value_tag, parsed_value_len, parsed_value, functional_ok,
                    physical_requests-start_requests, valid_edges-start_valid, done_pulses-start_done,
                    QUIET_CYCLES, quiet_ok, monitor_errors-start_errors, timeout_count);
                if (transport_ok !== 1) begin
                    errors = errors + 1;
                    $display("M6D-12 STEP %0d FAIL transport; STOP", step);
                    disable walk;
                end
                $display("M6D-12 STEP %0d PASS", step);
                // Only the strictly parsed response supplies the next request OID.
                current_oid_len = parsed_oid_len;
                for (j=0; j<parsed_oid_len; j=j+1) current_oid[j] = parsed_oid[j];
            end
            for (j=1; j<=25; j=j+1) begin
                $display("M6D-12 VISITED object=%0d count=%0d", j, visited[j]);
                if (visited[j] !== 1) begin
                    errors = errors + 1;
                    $display("M6D-12 FAIL missing/duplicate object=%0d; STOP", j);
                    disable walk;
                end
            end
        end
    endtask

    task formal_batch_d;
      begin
        $display("Formal Batch D M6D-12; continuing after Batch C without reset; 26 chained GETNEXT requests; quiet=%0d", QUIET_CYCLES);
        $display("Read-only scope: GETNEXT wire requests and existing pulse/output monitors; M6D has no M5 write port; full M5 isolation NOT proven here");
        formal_walk;
        $display("TOTAL physical=%0d responses=%0d done=%0d txn=%0d builder=%0d monitor=%0d failed=%0d",
            physical_requests, valid_edges, done_pulses, transaction_starts, builder_starts, monitor_errors, errors);
        $display("RESET assertions=%0d releases=%0d", reset_assertions, reset_releases);
        if ((physical_requests === 36) && (valid_edges === 32) && (done_pulses === 36) &&
            (transaction_starts === 32) && (builder_starts === 32) &&
            (reset_assertions === 1) && (reset_releases === 1) &&
            (monitor_errors === 0) && (errors === 0)) begin
            $display("Formal Batch D M6D-12 PASS; 26 actual-OID driven requests; visited 1..25 exactly once plus endOfMibView");
            $display("M6D-13 Formal final A->B->C->D PASS physical=36 responses=32 done=36 txn=32 builder=32 reset=1; M6E / repair NOT RUN; no freeze");
        end else begin errors = errors+1; $display("Formal final A->B->C->D FAIL; STOP; no RTL repair; M6E / repair NOT RUN"); end
        $finish;
      end
    endtask
endmodule
