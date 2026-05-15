module uart_rx (
    input  wire       clk,        // 100MHz
    input  wire       rst,
    input  wire       rx,         // UART RX 핀 (Basys3 USB-UART)
    output reg  [7:0] rx_data,    // 수신된 1바이트
    output reg        rx_valid    // 1클럭 pulse: rx_data 유효
);

    // =========================================================
    // UART 설정
    // Baud rate: 115200
    // 100MHz / 115200 = 868 클럭 per bit
    // =========================================================
    localparam CLKS_PER_BIT = 868;
    localparam HALF_BIT     = 434;  // 중앙 샘플링용

    // 상태 머신
    localparam IDLE      = 2'd0;
    localparam START_BIT = 2'd1;
    localparam DATA_BITS = 2'd2;
    localparam STOP_BIT  = 2'd3;

    reg [1:0]  state;
    reg [9:0]  clk_cnt;   // 클럭 카운터 (0~868)
    reg [2:0]  bit_idx;   // 수신 비트 인덱스 (0~7)
    reg [7:0]  rx_shift;  // 수신 시프트 레지스터

    // RX 메타스태빌리티 방지용 2단 FF
    reg rx_sync1, rx_sync2;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rx_sync1 <= 1;
            rx_sync2 <= 1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            rx_shift <= 0;
            rx_data  <= 0;
            rx_valid <= 0;
        end else begin
            rx_valid <= 0;  // 기본 0, 수신 완료시만 1

            case (state)

                // -----------------------------------------------
                // IDLE: RX 라인이 LOW로 떨어지면 start bit 감지
                // UART idle 상태는 HIGH
                // -----------------------------------------------
                IDLE: begin
                    if (rx_sync2 == 0) begin
                        // start bit 감지
                        clk_cnt <= 0;
                        state   <= START_BIT;
                    end
                end

                // -----------------------------------------------
                // START_BIT: 중앙(HALF_BIT)에서 샘플링
                // 여전히 LOW면 유효한 start bit
                // -----------------------------------------------
                START_BIT: begin
                    if (clk_cnt == HALF_BIT) begin
                        if (rx_sync2 == 0) begin
                            // 유효한 start bit
                            clk_cnt <= 0;
                            bit_idx <= 0;
                            state   <= DATA_BITS;
                        end else begin
                            // 노이즈 → IDLE로
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // -----------------------------------------------
                // DATA_BITS: 8비트 수신
                // 각 비트 중앙(CLKS_PER_BIT)에서 샘플링
                // LSB first (UART 표준)
                // -----------------------------------------------
                DATA_BITS: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt             <= 0;
                        rx_shift[bit_idx]   <= rx_sync2;  // LSB first
                        if (bit_idx == 7) begin
                            state <= STOP_BIT;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // -----------------------------------------------
                // STOP_BIT: stop bit 확인 후 데이터 출력
                // stop bit는 HIGH여야 함
                // -----------------------------------------------
                STOP_BIT: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        if (rx_sync2 == 1) begin
                            // 정상 수신
                            rx_data  <= rx_shift;
                            rx_valid <= 1;  // 1클럭 pulse
                        end
                        // stop bit 오류여도 IDLE로 복귀
                        state <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule