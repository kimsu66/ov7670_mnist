`timescale 1ns / 1ps

module fc2_layer_tb;

    reg clk;
    reg rst;

    always #5 clk = ~clk;

    reg        start;
    reg [7:0]  act_data;
    reg        act_valid;
    wire signed [15:0] out_data;
    wire               out_valid;
    wire               done;

    fc2_layer dut (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .act_data  (act_data),
        .act_valid (act_valid),
        .out_data  (out_data),
        .out_valid (out_valid),
        .done      (done)
    );

    integer i;
    reg signed [15:0] out_result [0:9];
    integer           out_cnt;

    always @(posedge clk) begin
        if (out_valid) begin
            out_result[out_cnt] <= out_data;
            out_cnt <= out_cnt + 1;
        end
    end

    task send_activations;
        input [7:0] val;
        integer j;
        begin
            for (j = 0; j < 64; j = j + 1) begin
                @(posedge clk);
                act_data  <= val;
                act_valid <= 1;
            end
            @(posedge clk);
            act_valid <= 0;
        end
    endtask

    initial begin
        clk       = 0;
        rst       = 1;
        start     = 0;
        act_data  = 0;
        act_valid = 0;
        out_cnt   = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // 테스트 1: activation 전부 0
        $display("=== Test 1: activation 전부 0 ===");
        out_cnt = 0;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_activations(8'd0);
        wait(done);
        @(posedge clk);  // IDLE 진입: out_result[9] NBA 예약
        @(posedge clk);  // NBA 반영 완료 후 읽기
        for (i = 0; i < 10; i = i + 1)
            $display("  score[%0d] = %0d", i, out_result[i]);

        repeat(10) @(posedge clk);

        // 테스트 2: activation 전부 1
        $display("=== Test 2: activation 전부 1 ===");
        out_cnt = 0;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_activations(8'd1);
        wait(done);
        @(posedge clk);  // IDLE 진입: out_result[9] NBA 예약
        @(posedge clk);  // NBA 반영 완료 후 읽기
        for (i = 0; i < 10; i = i + 1)
            $display("  score[%0d] = %0d", i, out_result[i]);

        repeat(10) @(posedge clk);

        // 테스트 3: activation 전부 127
        $display("=== Test 3: activation 전부 127 ===");
        out_cnt = 0;
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_activations(8'd127);
        wait(done);
        @(posedge clk);  // IDLE 진입: out_result[9] NBA 예약
        @(posedge clk);  // NBA 반영 완료 후 읽기
        for (i = 0; i < 10; i = i + 1)
            $display("  score[%0d] = %0d", i, out_result[i]);

        $display("=== 시뮬레이션 완료 ===");
        $finish;
    end

    initial begin
        #5000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule

// =========================================================
// BRAM 스텁 (tb 모듈 밖)
// =========================================================
module fc2_weight (
    input  wire        clka,
    input  wire [9:0]  addra,
    output reg  [7:0]  douta
);
    always @(posedge clka)
        douta <= 8'd1;
endmodule

module fc2_bias (
    input  wire       clka,
    input  wire [3:0] addra,
    output reg  [7:0] douta
);
    always @(posedge clka)
        douta <= 8'd0;
endmodule