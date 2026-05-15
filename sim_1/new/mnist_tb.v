`timescale 1ns / 1ps

module mnist_tb;

    reg clk;
    reg rst;
    always #5 clk = ~clk;  // 100MHz

    // =========================================================
    // UART 물리 신호
    // =========================================================
    reg  rx;   // testbench → uart_rx → mnist_core
    wire tx;   // mnist_core → uart_tx → testbench

    localparam BIT_PERIOD = 8680;  // 115200 baud = 8680ns/bit

    // =========================================================
    // uart_rx: rx 핀 → rx_data/rx_valid
    // =========================================================
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx u_rx (
        .clk     (clk),
        .rst     (rst),
        .rx      (rx),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    // =========================================================
    // mnist_core: rx_data/rx_valid → FC1→FC2→argmax → tx_data/tx_start
    // =========================================================
    wire [7:0] tx_data;
    wire       tx_start;
    wire       tx_busy;

    mnist_core dut (
        .clk     (clk),
        .rst     (rst),
        .rx_data (rx_data),
        .rx_valid(rx_valid),
        .tx_data (tx_data),
        .tx_start(tx_start),
        .tx_busy (tx_busy)
    );

    // =========================================================
    // uart_tx: tx_data/tx_start → tx 핀
    // =========================================================
    uart_tx u_tx (
        .clk     (clk),
        .rst     (rst),
        .tx_start(tx_start),
        .tx_data (tx_data),
        .tx      (tx),
        .tx_busy (tx_busy),
        .tx_done ()
    );

    // =========================================================
    // Task: UART 1바이트 전송 (rx 핀 직접 구동)
    // =========================================================
    task uart_send_byte;
        input [7:0] data;
        integer j;
        begin
            rx = 0;           // start bit
            #(BIT_PERIOD);
            for (j = 0; j < 8; j = j + 1) begin
                rx = data[j]; // LSB first
                #(BIT_PERIOD);
            end
            rx = 1;           // stop bit
            #(BIT_PERIOD);
        end
    endtask

    // =========================================================
    // Task: UART 1바이트 수신 (tx 핀 디코딩)
    // =========================================================
    task uart_decode;
        output [7:0] data;
        integer j;
        begin
            @(negedge tx);        // start bit 하강 엣지 대기
            #(BIT_PERIOD / 2);    // start bit 중앙으로 이동
            if (tx !== 1'b0)
                $display("  [WARN] start bit LOW 아님");
            for (j = 0; j < 8; j = j + 1) begin
                #(BIT_PERIOD);
                data[j] = tx;     // LSB first 샘플링
            end
            #(BIT_PERIOD);        // stop bit
            if (tx !== 1'b1)
                $display("  [WARN] stop bit HIGH 아님");
        end
    endtask

    // =========================================================
    // Task: 784바이트 전송 + 결과 수신 (동시 진행)
    // =========================================================
    task run_inference;
        input [7:0] pixel_val;
        output [7:0] result;
        integer k;
        begin
            fork
                begin : send_pixels
                    for (k = 0; k < 784; k = k + 1)
                        uart_send_byte(pixel_val);
                end
                begin : recv_result
                    uart_decode(result);
                end
            join
        end
    endtask

    integer   pass_cnt;
    integer   fail_cnt;
    reg [7:0] result_byte;

    // =========================================================
    // 메인 테스트
    // =========================================================
    initial begin
        clk      = 0;
        rst      = 1;
        rx       = 1;    // UART idle = HIGH
        pass_cnt = 0;
        fail_cnt = 0;

        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5) @(posedge clk);

        // -------------------------------------------------------
        // Test 1: 픽셀 전부 0x00 → argmax=0 기대
        //
        // FC1: ReLU(0×784) = 0 (64개 모두)
        // FC2: 0×weight = 0 (10개 모두)
        // argmax: score[0]=0 > 초기 -32768 → result=0
        //         이후 score[1..9]=0 (동점, 갱신 없음) → result=0
        // -------------------------------------------------------
        $display("=== Test 1: pixel=0x00 x 784  →  argmax 예상=0 ===");
        run_inference(8'h00, result_byte);
        $display("  결과: digit=%0d", result_byte);

        if (result_byte === 8'h00) begin
            $display("  [PASS] argmax=0 (zero input)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] argmax=%0d, 예상=0", result_byte);
            fail_cnt = fail_cnt + 1;
        end

        #(BIT_PERIOD * 15);

        // -------------------------------------------------------
        // Test 2: 픽셀 전부 0x01 → argmax=5 기대
        //
        // FC1 weight=1, bias=0:
        //   acc = 1×784 = 784 → ReLU → 포화 → 127 (64개 모두)
        //
        // FC2 weight 스텁:
        //   neuron 5 (addr 320~383) = weight 1  →  score=127×64=8128
        //   나머지 neuron             = weight 0  →  score=0
        //
        // argmax: score[0..4]=0, score[5]=8128 > 0 → result=5
        //         score[6..9]=0 (갱신 없음) → result=5
        // -------------------------------------------------------
        $display("=== Test 2: pixel=0x01 x 784  →  argmax 예상=5 ===");
        run_inference(8'h01, result_byte);
        $display("  결과: digit=%0d", result_byte);

        if (result_byte === 8'h05) begin
            $display("  [PASS] argmax=5 (neuron5 winner 확인)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] argmax=%0d, 예상=5", result_byte);
            fail_cnt = fail_cnt + 1;
        end

        #(BIT_PERIOD * 15);

        // -------------------------------------------------------
        // Test 3: 픽셀 전부 0xFF → argmax=5 기대
        //
        // FC1: 255×784 = 199920 → ReLU → 포화 → 127 (Test 2와 동일)
        // FC2: score[5]=8128, 나머지=0 → argmax=5
        // -------------------------------------------------------
        $display("=== Test 3: pixel=0xFF x 784  →  argmax 예상=5 ===");
        run_inference(8'hFF, result_byte);
        $display("  결과: digit=%0d", result_byte);

        if (result_byte === 8'h05) begin
            $display("  [PASS] argmax=5 (포화 입력도 동일 winner)");
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] argmax=%0d, 예상=5", result_byte);
            fail_cnt = fail_cnt + 1;
        end

        #(BIT_PERIOD * 15);

        $display("================================");
        $display("  PASS: %0d  /  FAIL: %0d", pass_cnt, fail_cnt);
        $display("================================");
        $finish;
    end

    // =========================================================
    // 타임아웃
    // 테스트당 ~68ms (784B UART) + 연산 ~1ms
    // 3테스트 × 70ms = 210ms → 350ms로 설정
    // =========================================================
    initial begin
        #350000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule


// =========================================================
// BRAM 스텁 (시뮬레이션 전용, 실제 보드에서는 Vivado IP 사용)
//
// FC1 weight=1 (균일), FC1 bias=0
// FC2 weight: neuron5(addr 320~383)=1, 나머지=0
// FC2 bias=0
//
// 예상 동작:
//   pixel=0x00 → FC1 out=0   → FC2 score 전부 0 → argmax=0
//   pixel≠0x00 → FC1 out=127 → FC2 score[5]=8128, 나머지=0 → argmax=5
// =========================================================
module blk_mem_gen_0 (   // FC1 weight
    input  wire        clka,
    input  wire [15:0] addra,
    output reg  [7:0]  douta
);
    always @(posedge clka) douta <= 8'd1;
endmodule

module blk_mem_gen_1 (   // FC1 bias
    input  wire       clka,
    input  wire [5:0] addra,
    output reg  [7:0] douta
);
    always @(posedge clka) douta <= 8'd0;
endmodule

module fc2_weight (      // FC2 weight
    input  wire        clka,
    input  wire [9:0]  addra,
    output reg  [7:0]  douta
);
    // neuron 5 (addr 320~383) 만 weight=1, 나머지 weight=0
    // → pixel≠0일 때 FC2 score[5]만 양수, argmax=5
    always @(posedge clka)
        douta <= (addra >= 10'd320 && addra <= 10'd383) ? 8'd1 : 8'd0;
endmodule

module fc2_bias (        // FC2 bias
    input  wire       clka,
    input  wire [3:0] addra,
    output reg  [7:0] douta
);
    always @(posedge clka) douta <= 8'd0;
endmodule
