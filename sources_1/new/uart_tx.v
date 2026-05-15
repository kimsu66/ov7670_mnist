module uart_tx (
    input  wire       clk,       // 100MHz
    input  wire       rst,
    input  wire       tx_start,  // 1클럭 pulse: 전송 시작
    input  wire [7:0] tx_data,   // 전송할 데이터 (tx_start와 같은 클럭에 유효)
    output reg        tx,        // UART TX 핀 (idle = HIGH)
    output reg        tx_busy,   // 전송 중 HIGH (이 신호 확인 후 tx_start 보낼 것)
    output reg        tx_done    // 1클럭 pulse: 전송 완료
);

    // =========================================================
    // UART 설정
    // Baud rate: 115200
    // 100MHz / 115200 = 868 클럭 per bit
    // =========================================================
    localparam CLKS_PER_BIT = 868;

    localparam IDLE      = 2'd0;
    localparam START_BIT = 2'd1;
    localparam DATA_BITS = 2'd2;
    localparam STOP_BIT  = 2'd3;

    reg [1:0] state;
    reg [9:0] clk_cnt;   // 비트 내 클럭 카운터 (0~867)
    reg [2:0] bit_idx;   // 전송 비트 인덱스 (0~7)
    reg [7:0] tx_shift;  // 전송 시프트 레지스터 (tx_start 시 래치)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= IDLE;
            tx       <= 1;
            tx_busy  <= 0;
            tx_done  <= 0;
            clk_cnt  <= 0;
            bit_idx  <= 0;
            tx_shift <= 0;
        end else begin
            tx_done <= 0;  // 기본 0, 전송 완료 시만 1

            case (state)

                // -----------------------------------------------
                // IDLE: tx_start 대기
                // tx_busy=0일 때만 tx_start를 받음
                // -----------------------------------------------
                IDLE: begin
                    tx      <= 1;   // idle = HIGH
                    tx_busy <= 0;
                    if (tx_start) begin
                        tx_shift <= tx_data;  // 데이터 래치
                        tx_busy  <= 1;
                        clk_cnt  <= 0;
                        bit_idx  <= 0;
                        state    <= START_BIT;
                    end
                end

                // -----------------------------------------------
                // START_BIT: 1비트 동안 LOW 출력
                // -----------------------------------------------
                START_BIT: begin
                    tx <= 0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
                        state   <= DATA_BITS;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

                // -----------------------------------------------
                // DATA_BITS: 8비트 전송 (LSB first)
                // -----------------------------------------------
                DATA_BITS: begin
                    tx <= tx_shift[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 0;
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
                // STOP_BIT: 1비트 동안 HIGH 출력 후 완료
                // -----------------------------------------------
                STOP_BIT: begin
                    tx <= 1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        tx_done <= 1;   // 1클럭 pulse
                        tx_busy <= 0;
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 1;
                    end
                end

            endcase
        end
    end

endmodule
