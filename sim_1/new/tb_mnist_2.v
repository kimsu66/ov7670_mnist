`timescale 1ns / 1ps

// ============================================================
//  tb_mnist_2.v  —  mnist_top (top_mnist_2.v) 전용 testbench
//
//  인터페이스 차이 (mnist_tb.v 대비):
//    - UART 없음: sampled_pixel / sampled_valid 직접 스트리밍
//    - 픽셀은 상위 4비트로 전송 → {pixel_val[3:0], 4'b0}
//      (내부에서 sampled_pixel[7:4]만 사용)
//    - result / result_valid 직접 모니터링
// ============================================================

module tb_mnist_2;

    reg clk;
    reg rst;
    always #5 clk = ~clk;   // 100 MHz

    // ── DUT ─────────────────────────────────────────────────
    reg  [7:0] sampled_pixel;
    reg        sampled_valid;
    wire [3:0] result;
    wire       result_valid;

    mnist_top dut (
        .clk           (clk),
        .rst           (rst),
        .sampled_pixel (sampled_pixel),
        .sampled_valid (sampled_valid),
        .result        (result),
        .result_valid  (result_valid)
    );

    // ── 픽셀 배열 ────────────────────────────────────────────
    localparam integer LABEL = 1;   // 정답 레이블
    reg [7:0] pixels [0:783];

    integer pi;
    initial begin
        for (pi = 0; pi < 784; pi = pi + 1) pixels[pi] = 8'h00;
        // 비영 픽셀 (mnist_tb.v 동일)
        pixels[128]=8'h02; pixels[129]=8'h0F; pixels[130]=8'h06;
        pixels[156]=8'h05; pixels[157]=8'h0F; pixels[158]=8'h05;
        pixels[184]=8'h08; pixels[185]=8'h0E;
        pixels[211]=8'h03; pixels[212]=8'h0E; pixels[213]=8'h09;
        pixels[239]=8'h05; pixels[240]=8'h0F; pixels[241]=8'h04;
        pixels[267]=8'h0C; pixels[268]=8'h0D; pixels[269]=8'h01;
        pixels[294]=8'h02; pixels[295]=8'h0F; pixels[296]=8'h0D;
        pixels[322]=8'h06; pixels[323]=8'h0F; pixels[324]=8'h0B;
        pixels[350]=8'h08; pixels[351]=8'h0F; pixels[352]=8'h05;
        pixels[377]=8'h03; pixels[378]=8'h0E; pixels[379]=8'h0C;
        pixels[405]=8'h07; pixels[406]=8'h0F; pixels[407]=8'h0A;
        pixels[433]=8'h0A; pixels[434]=8'h0F; pixels[435]=8'h05;
        pixels[460]=8'h01; pixels[461]=8'h0E; pixels[462]=8'h0D;
        pixels[488]=8'h07; pixels[489]=8'h0F; pixels[490]=8'h09;
        pixels[516]=8'h09; pixels[517]=8'h0F; pixels[518]=8'h08;
        pixels[544]=8'h0D; pixels[545]=8'h0F; pixels[546]=8'h04;
        pixels[571]=8'h04; pixels[572]=8'h0F; pixels[573]=8'h0F; pixels[574]=8'h04;
        pixels[599]=8'h08; pixels[600]=8'h0F; pixels[601]=8'h0C;
        pixels[626]=8'h01; pixels[627]=8'h0D; pixels[628]=8'h0F; pixels[629]=8'h07;
        pixels[655]=8'h0C; pixels[656]=8'h0A; pixels[657]=8'h01;
    end

    // ── 메인 시퀀스 ─────────────────────────────────────────
    integer k;
    initial begin
        clk           = 0;
        rst           = 1;
        sampled_pixel = 8'h00;
        sampled_valid = 1'b0;

        repeat(10) @(posedge clk);
        rst = 0;
        repeat(5)  @(posedge clk);

        $display("=== top_mnist_2 추론 시작 ===");
        $display("    label(정답): %0d", LABEL);

        // 784픽셀 스트리밍: 픽셀값(0~15)을 상위 4비트에 실어 전송
        for (k = 0; k < 784; k = k + 1) begin
            @(posedge clk);
            sampled_pixel <= {pixels[k][3:0], 4'b0};
            sampled_valid <= 1'b1;
        end
        @(posedge clk);
        sampled_valid <= 1'b0;

        // result_valid 대기
        @(posedge clk);
        while (!result_valid) @(posedge clk);

        $display("    추론 결과: %0d", result);
        if (result == LABEL[3:0])
            $display("    [PASS]");
        else
            $display("    [FAIL] 정답=%0d, 결과=%0d", LABEL, result);

        #100;
        $finish;
    end

    // ── FC1 완료 모니터 ──────────────────────────────────────
    integer fi;
    initial begin
        forever begin
            @(posedge clk);
            if (dut.u_fc1.done) begin
                $display("FC1 출력 (Python numpy와 비교):");
                for (fi = 0; fi < 64; fi = fi + 1)
                    $display("  act[%0d] = %0d",
                        fi, dut.u_fc1.act1_flat[fi*7 +: 7]);
            end
        end
    end

    // ── FC2 완료 모니터 ──────────────────────────────────────
    integer li;
    initial begin
        forever begin
            @(posedge clk);
            if (dut.u_fc2.done) begin
                $display("FC2 logit:");
                for (li = 0; li < 10; li = li + 1)
                    $display("  logit[%0d] = %0d",
                        li, $signed(dut.u_fc2.logit_flat[li*32 +: 32]));
            end
        end
    end

    // ── 타임아웃 (FC1: 64×787≈50k cyc, FC2: 10×67≈670 cyc) ─
    initial begin
        #10000000;   // 10ms (실제 ~0.5ms면 충분)
        $display("TIMEOUT");
        $finish;
    end

endmodule
