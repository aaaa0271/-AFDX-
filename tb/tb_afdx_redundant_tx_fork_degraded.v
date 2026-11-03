`timescale 1ns / 1ps

module tb_afdx_redundant_tx_fork_degraded;


    reg clk;
    reg rst_n;


    reg network_a_enable;
    reg network_b_enable;


    reg  [7:0] s_data;
    reg        s_valid;
    wire       s_ready;


    wire [7:0] a_data;
    wire       a_valid;
    reg        a_ready;


    wire [7:0] b_data;
    wire       b_valid;
    reg        b_ready;


    wire fork_fire;
    wire any_network_enabled;
    wire degraded_mode;


    integer error_count;
    integer src_count;
    integer a_count;
    integer b_count;


    afdx_redundant_tx_fork_degraded dut (
        .clk                 (clk),
        .rst_n               (rst_n),

        .network_a_enable    (network_a_enable),
        .network_b_enable    (network_b_enable),

        .s_data              (s_data),
        .s_valid             (s_valid),
        .s_ready             (s_ready),

        .a_data              (a_data),
        .a_valid             (a_valid),
        .a_ready             (a_ready),

        .b_data              (b_data),
        .b_valid             (b_valid),
        .b_ready             (b_ready),

        .fork_fire           (fork_fire),
        .any_network_enabled (any_network_enabled),
        .degraded_mode       (degraded_mode)
    );


    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end


    always @(posedge clk) begin

        if (!rst_n) begin

            src_count = 0;
            a_count   = 0;
            b_count   = 0;

        end

        else begin

            if (s_valid && s_ready)
                src_count = src_count + 1;

            if (a_valid && a_ready)
                a_count = a_count + 1;

            if (b_valid && b_ready)
                b_count = b_count + 1;

        end

    end


    task reset_dut;
    begin

        @(negedge clk);

        rst_n = 1'b0;

        network_a_enable = 1'b1;
        network_b_enable = 1'b1;

        s_data  = 8'h00;
        s_valid = 1'b0;

        a_ready = 1'b0;
        b_ready = 1'b0;


        repeat (2)
            @(posedge clk);


        @(negedge clk);

        rst_n = 1'b1;


        @(posedge clk);
        #1;

    end
    endtask


    task send_byte;

        input [7:0] value;

    begin

        @(negedge clk);

        s_data  = value;
        s_valid = 1'b1;


        while (!s_ready)
            @(posedge clk);


        @(negedge clk);

        s_valid = 1'b0;

    end
    endtask


    initial begin

        rst_n = 1'b0;

        network_a_enable = 1'b1;
        network_b_enable = 1'b1;

        s_data  = 0;
        s_valid = 0;

        a_ready = 0;
        b_ready = 0;

        error_count = 0;


        // ====================================================
        // C1-01 Dual healthy
        // ====================================================

        reset_dut();

        a_ready = 1'b1;
        b_ready = 1'b1;

        send_byte(8'h11);


        if ((src_count != 1) ||
            (a_count   != 1) ||
            (b_count   != 1)) begin

            $display(
                "ERROR: dual healthy count %0d/%0d/%0d",
                src_count,
                a_count,
                b_count
            );

            error_count = error_count + 1;

        end
        else
            $display(
                "TC-M5-C1-01 PASS: dual healthy"
            );


        // ====================================================
        // C1-02 A disabled, B alive
        //
        // A ready intentionally stays 0 forever.
        // ====================================================

        reset_dut();

        network_a_enable = 1'b0;
        network_b_enable = 1'b1;

        a_ready = 1'b0;
        b_ready = 1'b1;


        send_byte(8'h22);
        send_byte(8'h23);
        send_byte(8'h24);


        if ((src_count != 3) ||
            (a_count   != 0) ||
            (b_count   != 3)) begin

            $display(
                "ERROR: A-disabled count %0d/%0d/%0d",
                src_count,
                a_count,
                b_count
            );

            error_count = error_count + 1;

        end
        else
            $display(
                "TC-M5-C1-02 PASS: A disabled / B continues"
            );


        // ====================================================
        // C1-03 B disabled, A alive
        // ====================================================

        reset_dut();

        network_a_enable = 1'b1;
        network_b_enable = 1'b0;

        a_ready = 1'b1;
        b_ready = 1'b0;


        send_byte(8'h31);
        send_byte(8'h32);
        send_byte(8'h33);


        if ((src_count != 3) ||
            (a_count   != 3) ||
            (b_count   != 0)) begin

            $display(
                "ERROR: B-disabled count %0d/%0d/%0d",
                src_count,
                a_count,
                b_count
            );

            error_count = error_count + 1;

        end
        else
            $display(
                "TC-M5-C1-03 PASS: B disabled / A continues"
            );


        // ====================================================
        // C1-04 Both disabled
        // ====================================================

        reset_dut();

        network_a_enable = 1'b0;
        network_b_enable = 1'b0;

        a_ready = 1'b1;
        b_ready = 1'b1;

        @(negedge clk);

        s_data  = 8'h44;
        s_valid = 1'b1;


        repeat (5)
            @(posedge clk);


        if (s_ready !== 1'b0) begin

            $display(
                "ERROR: source ready while both networks disabled"
            );

            error_count = error_count + 1;

        end


        if ((src_count != 0) ||
            (a_count   != 0) ||
            (b_count   != 0)) begin

            $display(
                "ERROR: traffic consumed with no network"
            );

            error_count = error_count + 1;

        end
        else
            $display(
                "TC-M5-C1-04 PASS: no-network safe block"
            );


        @(negedge clk);
        s_valid = 1'b0;


        // ====================================================
        // C1-05 Mode flags
        // ====================================================

        network_a_enable = 1'b1;
        network_b_enable = 1'b0;

        #1;

        if (!any_network_enabled ||
            !degraded_mode) begin

            $display(
                "ERROR: degraded mode flags"
            );

            error_count = error_count + 1;

        end
        else
            $display(
                "TC-M5-C1-05 PASS: mode flags"
            );


        $display("");
        $display(
            "=============================================="
        );


        if (error_count == 0)
            $display(
                "M5-C1 DEGRADED FORK ALL TESTS PASS"
            );
        else
            $display(
                "M5-C1 FAILED: %0d error(s)",
                error_count
            );


        $display(
            "=============================================="
        );


        #20;
        $finish;

    end


endmodule
