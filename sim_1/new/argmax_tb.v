`timescale 1ns / 1ps

module argmax_tb;

    reg clk;
    reg rst;

    always #5 clk = ~clk;

    reg        start;
    reg signed [15:0] score_data;
    reg        score_valid;
    wire [3:0] result;
    wire       done;

    argmax dut (
        .clk         (clk),
        .rst         (rst),
        .start       (start),
        .score_data  (score_data),
        .score_valid (score_valid),
        .result      (result),
        .done        (done)
    );

    // =========================================================
    // 테스트용 score 데이터
    // =========================================================
    reg signed [15:0] test_scores [0:9];
    integer i;

    task send_scores;
        integer j;
        begin
            for (j = 0; j < 10; j = j + 1) begin
                @(posedge clk);
                score_data  <= test_scores[j];
                score_valid <= 1;
            end
            @(posedge clk);
            score_valid <= 0;
        end
    endtask

    initial begin
        clk         = 0;
        rst         = 1;
        start       = 0;
        score_data  = 0;
        score_valid = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // -----------------------------------------------
        // 테스트 1: 마지막(9번)이 최댓값 → result=9
        // -----------------------------------------------
        $display("=== Test 1: 최댓값이 score[9] ===");
        test_scores[0] = 100;
        test_scores[1] = 50;
        test_scores[2] = 200;
        test_scores[3] = 30;
        test_scores[4] = 10;
        test_scores[5] = 80;
        test_scores[6] = 120;
        test_scores[7] = 60;
        test_scores[8] = 90;
        test_scores[9] = 500;  // ← 최댓값, result=9 기대

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_scores();
        wait(done);
        @(posedge clk);
        $display("  result = %0d (기대값: 9)", result);

        repeat(5) @(posedge clk);

        // -----------------------------------------------
        // 테스트 2: 첫 번째(0번)가 최댓값 → result=0
        // -----------------------------------------------
        $display("=== Test 2: 최댓값이 score[0] ===");
        test_scores[0] = 999;  // ← 최댓값, result=0 기대
        test_scores[1] = 100;
        test_scores[2] = 200;
        test_scores[3] = 300;
        test_scores[4] = 50;
        test_scores[5] = 80;
        test_scores[6] = 120;
        test_scores[7] = 60;
        test_scores[8] = 90;
        test_scores[9] = 10;

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_scores();
        wait(done);
        @(posedge clk);
        $display("  result = %0d (기대값: 0)", result);

        repeat(5) @(posedge clk);

        // -----------------------------------------------
        // 테스트 3: 중간(5번)이 최댓값 → result=5
        // -----------------------------------------------
        $display("=== Test 3: 최댓값이 score[5] ===");
        test_scores[0] = 100;
        test_scores[1] = 50;
        test_scores[2] = 200;
        test_scores[3] = 30;
        test_scores[4] = 10;
        test_scores[5] = 8000;  // ← 최댓값, result=5 기대
        test_scores[6] = 120;
        test_scores[7] = 60;
        test_scores[8] = 90;
        test_scores[9] = 500;

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_scores();
        wait(done);
        @(posedge clk);
        $display("  result = %0d (기대값: 5)", result);

        // -----------------------------------------------
        // 테스트 4: 음수 포함 → result=3
        // -----------------------------------------------
        $display("=== Test 4: 음수 포함 ===");
        test_scores[0] = -500;
        test_scores[1] = -200;
        test_scores[2] = -100;
        test_scores[3] = 50;   // ← 최댓값, result=3 기대
        test_scores[4] = -300;
        test_scores[5] = -10;
        test_scores[6] = -50;
        test_scores[7] = -80;
        test_scores[8] = -90;
        test_scores[9] = -1;

        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        send_scores();
        wait(done);
        @(posedge clk);
        $display("  result = %0d (기대값: 3)", result);

        $display("=== 시뮬레이션 완료 ===");
        $finish;
    end

    initial begin
        #1000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule