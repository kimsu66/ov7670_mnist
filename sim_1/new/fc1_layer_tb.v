`timescale 1ns / 1ps

module fc1_layer_tb;

    // =========================================================
    // 클럭 / 리셋
    // =========================================================
    reg clk;
    reg rst;

    always #5 clk = ~clk;  // 100MHz (10ns 주기)

    // =========================================================
    // DUT 포트
    // =========================================================
    reg        start;
    reg [7:0]  pixel_data;
    reg        pixel_valid;
    wire [7:0] out_data;
    wire       out_valid;
    wire       done;

    // DUT 인스턴스
    fc1_layer dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .pixel_data  (pixel_data),
        .pixel_valid (pixel_valid),
        .out_data    (out_data),
        .out_valid   (out_valid),
        .done        (done)
    );

    // =========================================================
    // 테스트용 픽셀 데이터
    // 실제로는 MNIST 이미지 1장 (784픽셀)이어야 하지만
    // 여기서는 간단히 고정값으로 테스트
    //   패턴 A: 전부 0      → 출력이 전부 bias만 반영
    //   패턴 B: 전부 1      → 최소 자극
    //   패턴 C: 전부 255    → 최대 자극
    // =========================================================
    integer i;
    reg [7:0] out_result [0:63];  // FC1 출력 저장
    integer   out_cnt;

    // =========================================================
    // 출력 캡처
    // =========================================================
    always @(posedge clk) begin
        if (out_valid) begin
            out_result[out_cnt] <= out_data;
            out_cnt <= out_cnt + 1;
        end
    end

    // =========================================================
    // 태스크: 픽셀 784개 전송
    // =========================================================
    task send_pixels;
        input [7:0] val;  // 전송할 픽셀값 (고정값)
        integer j;
        begin
            for (j = 0; j < 784; j = j + 1) begin
                @(posedge clk);
                pixel_data  <= val;
                pixel_valid <= 1;
            end
            @(posedge clk);
            pixel_valid <= 0;
        end
    endtask

    // =========================================================
    // 메인 테스트
    // =========================================================
    initial begin
        // 초기화
        clk         = 0;
        rst         = 1;
        start       = 0;
        pixel_data  = 0;
        pixel_valid = 0;
        out_cnt     = 0;

        // 리셋 해제
        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // -----------------------------------------------
        // 테스트 1: 픽셀 전부 0
        // -----------------------------------------------
        $display("=== Test 1: 픽셀 전부 0 ===");
        out_cnt = 0;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        send_pixels(8'd0);

        // done 대기
        wait(done);
        @(posedge clk);

        $display("FC1 출력 (픽셀=0):");
        for (i = 0; i < 64; i = i + 1)
            $display("  out[%0d] = %0d", i, out_result[i]);

        repeat(10) @(posedge clk);

        // -----------------------------------------------
        // 테스트 2: 픽셀 전부 1
        // -----------------------------------------------
        $display("=== Test 2: 픽셀 전부 1 ===");
        out_cnt = 0;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        send_pixels(8'd1);

        wait(done);
        @(posedge clk);

        $display("FC1 출력 (픽셀=1):");
        for (i = 0; i < 64; i = i + 1)
            $display("  out[%0d] = %0d", i, out_result[i]);

        repeat(10) @(posedge clk);

        // -----------------------------------------------
        // 테스트 3: 픽셀 전부 255
        // -----------------------------------------------
        $display("=== Test 3: 픽셀 전부 255 ===");
        out_cnt = 0;

        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        send_pixels(8'd255);

        wait(done);
        @(posedge clk);

        $display("FC1 출력 (픽셀=255):");
        for (i = 0; i < 64; i = i + 1)
            $display("  out[%0d] = %0d", i, out_result[i]);

        $display("=== 시뮬레이션 완료 ===");
        $finish;
    end

    // =========================================================
    // 타임아웃 (무한루프 방지)
    // 64뉴런 * 784클럭 * 2 = 약 100,352클럭 → 여유있게 200,000
    // =========================================================
    initial begin
        #2000000;
        $display("TIMEOUT: 시뮬레이션 강제 종료");
        $finish;
    end

endmodule

// =========================================================
// 시뮬레이션용 BRAM 스텁
// 실제 Vivado IP 대신 고정값을 반환하는 behavioral 모델
//   weight = 1, bias = 0 기준
//   pixel=0 → out=0, pixel=1 → out=127(saturate), pixel=255 → out=127
// =========================================================
module blk_mem_gen_0 (  // fc1 weight BRAM (64*784=50176 entries, INT8)
    input  wire        clka,
    input  wire [15:0] addra,
    output reg  [7:0]  douta
);
    always @(posedge clka)
        douta <= 8'd1;  // weight = 1 (all)
endmodule

module blk_mem_gen_1 (  // fc1 bias BRAM (64 entries, INT8)
    input  wire       clka,
    input  wire [5:0] addra,
    output reg  [7:0] douta
);
    always @(posedge clka)
        douta <= 8'd0;  // bias = 0 (all)
endmodule