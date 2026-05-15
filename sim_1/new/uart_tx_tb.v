`timescale 1ns / 1ps

module uart_tx_tb;

    reg clk;
    reg rst;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx;
    wire       tx_busy;
    wire       tx_done;

    always #5 clk = ~clk;  // 100MHz

    uart_tx dut (
        .clk      (clk),
        .rst      (rst),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (tx),
        .tx_busy  (tx_busy),
        .tx_done  (tx_done)
    );

    // =========================================================
    // 115200 baud: 1비트 = 868클럭 = 8680ns
    // =========================================================
    localparam BIT_PERIOD = 8680;  // ns

    // =========================================================
    // 수신 결과 저장
    // =========================================================
    reg [7:0] decoded [0:15];
    integer   decode_cnt;
    integer   pass_cnt;
    integer   fail_cnt;

    // =========================================================
    // Task: tx 핀 출력을 UART 프레임으로 디코딩
    // uart_rx_tb의 반대 방향 — TX 출력을 소프트웨어로 수신
    // =========================================================
    task uart_decode;
        output [7:0] data;
        integer j;
        begin
            // start bit 대기 (falling edge)
            @(negedge tx);

            // start bit 중앙으로 이동 후 LOW 확인
            #(BIT_PERIOD / 2);
            if (tx !== 1'b0)
                $display("  [WARN] start bit가 LOW가 아님");

            // 8 data bits 샘플링 (각 비트 중앙)
            for (j = 0; j < 8; j = j + 1) begin
                #(BIT_PERIOD);
                data[j] = tx;  // LSB first
            end

            // stop bit 중앙 확인
            #(BIT_PERIOD);
            if (tx !== 1'b1)
                $display("  [WARN] stop bit가 HIGH가 아님");
        end
    endtask

    // =========================================================
    // Task: PASS/FAIL 검사
    // =========================================================
    task check_byte;
        input [7:0] expected;
        input integer idx;
        begin
            if (decoded[idx] === expected) begin
                $display("  [PASS] decoded[%0d] = 0x%02X", idx, decoded[idx]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] decoded[%0d] = 0x%02X  (expected 0x%02X)",
                         idx, decoded[idx], expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // Task: 1바이트 전송 (tx_busy 확인 후 tx_start pulse)
    // =========================================================
    task send_byte;
        input [7:0] data;
        begin
            // tx_busy가 HIGH면 완료까지 대기
            wait(!tx_busy);
            @(posedge clk);
            tx_data  <= data;
            tx_start <= 1;
            @(posedge clk);
            tx_start <= 0;
        end
    endtask

    // =========================================================
    // 메인 테스트
    // =========================================================
    initial begin
        clk        = 0;
        rst        = 1;
        tx_start   = 0;
        tx_data    = 0;
        decode_cnt = 0;
        pass_cnt   = 0;
        fail_cnt   = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // -----------------------------------------------
        // Test 1: 0x55 (01010101)
        // -----------------------------------------------
        $display("=== Test 1: 0x55 ===");
        fork
            send_byte(8'h55);
            begin
                uart_decode(decoded[0]);
                decode_cnt = decode_cnt + 1;
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'h55, 0);

        // -----------------------------------------------
        // Test 2: 0xAA (10101010)
        // -----------------------------------------------
        $display("=== Test 2: 0xAA ===");
        fork
            send_byte(8'hAA);
            begin
                uart_decode(decoded[1]);
                decode_cnt = decode_cnt + 1;
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'hAA, 1);

        // -----------------------------------------------
        // Test 3: 0x00 (data bits 전부 LOW)
        // -----------------------------------------------
        $display("=== Test 3: 0x00 ===");
        fork
            send_byte(8'h00);
            begin
                uart_decode(decoded[2]);
                decode_cnt = decode_cnt + 1;
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'h00, 2);

        // -----------------------------------------------
        // Test 4: 0xFF (data bits 전부 HIGH)
        // -----------------------------------------------
        $display("=== Test 4: 0xFF ===");
        fork
            send_byte(8'hFF);
            begin
                uart_decode(decoded[3]);
                decode_cnt = decode_cnt + 1;
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'hFF, 3);

        // -----------------------------------------------
        // Test 5: tx_busy 동안 tx_start 무시 확인
        // 전송 중에 tx_start=1 넣어도 두 번 전송하면 안 됨
        // -----------------------------------------------
        $display("=== Test 5: tx_busy 중 tx_start 무시 ===");
        @(posedge clk);
        tx_data  <= 8'hA5;
        tx_start <= 1;        // 첫 번째 전송 시작
        @(posedge clk);
        tx_start <= 1;        // tx_busy=1 상태에서 두 번째 tx_start (무시돼야 함)
        @(posedge clk);
        tx_start <= 0;

        fork
            begin
                uart_decode(decoded[4]);
                decode_cnt = decode_cnt + 1;
            end
            begin
                // tx_done 1회만 나와야 함
                wait(tx_done);
                @(posedge clk);
                if (!tx_done) begin
                    $display("  [PASS] tx_done 1회 (두 번째 tx_start 무시됨)");
                    pass_cnt = pass_cnt + 1;
                end
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'hA5, 4);

        // -----------------------------------------------
        // Test 6: tx_done 타이밍 확인
        // -----------------------------------------------
        $display("=== Test 6: tx_done 펄스 확인 ===");
        fork
            send_byte(8'h3C);
            begin
                uart_decode(decoded[5]);
                decode_cnt = decode_cnt + 1;
            end
            begin
                wait(tx_done);
                $display("  [INFO] tx_done 발생, tx=%b (1이어야 함)", tx);
                if (tx === 1'b1) begin
                    $display("  [PASS] tx_done 시 tx=HIGH");
                    pass_cnt = pass_cnt + 1;
                end else begin
                    $display("  [FAIL] tx_done 시 tx!=HIGH");
                    fail_cnt = fail_cnt + 1;
                end
            end
        join
        repeat(5) @(posedge clk);
        check_byte(8'h3C, 5);

        // -----------------------------------------------
        // 결과
        // -----------------------------------------------
        $display("================================");
        $display("  PASS: %0d  /  FAIL: %0d", pass_cnt, fail_cnt);
        $display("================================");
        $finish;
    end

    // =========================================================
    // 타임아웃 (10ms)
    // 1바이트 ≈ 10 × 8680ns = 87us → 6바이트 ≈ 600us << 10ms
    // =========================================================
    initial begin
        #10000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
