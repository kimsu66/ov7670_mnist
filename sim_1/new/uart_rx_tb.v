`timescale 1ns / 1ps

module uart_rx_tb;

    reg clk;
    reg rst;
    reg rx;

    wire [7:0] rx_data;
    wire       rx_valid;

    always #5 clk = ~clk;  // 100MHz

    uart_rx dut (
        .clk     (clk),
        .rst     (rst),
        .rx      (rx),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    // =========================================================
    // 수신 캡처
    // rx_valid는 1클럭 펄스 → received[] 배열에 순서대로 저장
    // =========================================================
    reg [7:0] received [0:15];
    integer   recv_cnt;
    integer   pass_cnt;
    integer   fail_cnt;

    always @(posedge clk) begin
        if (rx_valid) begin
            received[recv_cnt] <= rx_data;
            recv_cnt           <= recv_cnt + 1;
        end
    end

    // =========================================================
    // 115200 baud: 1비트 = 868클럭 = 8680ns
    // =========================================================
    localparam BIT_PERIOD = 8680;  // ns

    // =========================================================
    // Task: UART 1바이트 전송 (시간 기반, 클럭 비동기)
    // =========================================================
    task uart_send_byte;
        input [7:0] data;
        integer j;
        begin
            rx = 0;            // start bit
            #(BIT_PERIOD);
            for (j = 0; j < 8; j = j + 1) begin
                rx = data[j]; // data bits (LSB first)
                #(BIT_PERIOD);
            end
            rx = 1;            // stop bit
            #(BIT_PERIOD);
        end
    endtask

    // =========================================================
    // Task: PASS/FAIL 검사
    // =========================================================
    task check_byte;
        input [7:0] expected;
        input integer idx;
        begin
            if (received[idx] === expected) begin
                $display("  [PASS] received[%0d] = 0x%02X", idx, received[idx]);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  [FAIL] received[%0d] = 0x%02X  (expected 0x%02X)",
                         idx, received[idx], expected);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    // =========================================================
    // 메인 테스트
    // =========================================================
    initial begin
        clk      = 0;
        rst      = 1;
        rx       = 1;   // UART idle = HIGH
        recv_cnt = 0;
        pass_cnt = 0;
        fail_cnt = 0;

        repeat(5) @(posedge clk);
        rst = 0;
        repeat(2) @(posedge clk);

        // -----------------------------------------------
        // Test 1: 0x55 (01010101) — alternating bits
        // -----------------------------------------------
        $display("=== Test 1: 0x55 ===");
        uart_send_byte(8'h55);
        // rx_valid는 stop bit 카운트 중 1클럭 펄스 → task 종료 전에 이미 발생
        // task 이후 몇 클럭 대기하면 recv_cnt/received[] NBA가 반영됨
        repeat(5) @(posedge clk);
        check_byte(8'h55, 0);
        #(BIT_PERIOD);

        // -----------------------------------------------
        // Test 2: 0xAA (10101010)
        // -----------------------------------------------
        $display("=== Test 2: 0xAA ===");
        uart_send_byte(8'hAA);
        repeat(5) @(posedge clk);
        check_byte(8'hAA, 1);
        #(BIT_PERIOD);

        // -----------------------------------------------
        // Test 3: 0x00 (data bits 전부 LOW)
        // start bit 이후 data bits도 LOW → stop bit에서만 HIGH
        // -----------------------------------------------
        $display("=== Test 3: 0x00 ===");
        uart_send_byte(8'h00);
        repeat(5) @(posedge clk);
        check_byte(8'h00, 2);
        #(BIT_PERIOD);

        // -----------------------------------------------
        // Test 4: 0xFF (data bits 전부 HIGH)
        // -----------------------------------------------
        $display("=== Test 4: 0xFF ===");
        uart_send_byte(8'hFF);
        repeat(5) @(posedge clk);
        check_byte(8'hFF, 3);
        #(BIT_PERIOD);

        // -----------------------------------------------
        // Test 5: 노이즈 필터링
        // HALF_BIT(434클럭 = 4340ns)보다 짧은 LOW 글리치
        // START_BIT 상태에서 중앙 샘플링 시 HIGH이므로 → IDLE 복귀
        // -----------------------------------------------
        $display("=== Test 5: 노이즈 (200ns 글리치, 무시해야 함) ===");
        rx = 0;
        #200;   // 200ns = 20클럭 << HALF_BIT(4340ns)
        rx = 1;
        #(BIT_PERIOD * 3);
        if (recv_cnt == 4) begin
            $display("  [PASS] 노이즈 무시됨 (recv_cnt=%0d)", recv_cnt);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] 노이즈 오인식 (recv_cnt=%0d, 기대=4)", recv_cnt);
            fail_cnt = fail_cnt + 1;
        end

        // -----------------------------------------------
        // Test 6: 연속 전송 (inter-byte gap = 0)
        // stop bit 직후 바로 다음 start bit 시작
        // -----------------------------------------------
        $display("=== Test 6: 연속 전송 0x12, 0x34, 0x56 ===");
        uart_send_byte(8'h12);
        uart_send_byte(8'h34);
        uart_send_byte(8'h56);
        repeat(5) @(posedge clk);
        check_byte(8'h12, 4);
        check_byte(8'h34, 5);
        check_byte(8'h56, 6);

        // -----------------------------------------------
        // 결과 요약
        // -----------------------------------------------
        $display("================================");
        $display("  PASS: %0d  /  FAIL: %0d", pass_cnt, fail_cnt);
        $display("================================");
        $finish;
    end

    // =========================================================
    // 타임아웃 (10ms)
    // 1바이트 ≈ 10 × 8680ns = 87us → 7바이트 ≈ 700us << 10ms
    // =========================================================
    initial begin
        #10000000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
