module mnist_core (
    input  wire       clk,
    input  wire       rst,

    // UART RX (uart_rx 모듈의 출력을 그대로 연결)
    input  wire [7:0] rx_data,
    input  wire       rx_valid,

    // UART TX (uart_tx 모듈의 입력에 연결)
    output reg  [7:0] tx_data,
    output reg        tx_start,
    input  wire       tx_busy
);

    // =========================================================
    // 상태 정의
    // =========================================================
    localparam IDLE       = 4'd0;  // UART로 784바이트 수신 대기
    localparam RECV       = 4'd1;  // 픽셀 수신 중
    localparam FC1_START  = 4'd2;  // FC1 start 펄스 발생
    localparam FC1_STREAM = 4'd3;  // FC1에 784픽셀 스트리밍
    localparam FC1_WAIT   = 4'd4;  // FC1 완료 대기 + 출력 64개 버퍼링
    localparam FC2_START  = 4'd5;  // FC2 + argmax start 펄스 발생
    localparam FC2_STREAM = 4'd6;  // FC2에 64 activation 스트리밍
    localparam FC2_WAIT   = 4'd7;  // argmax 완료 대기
    localparam TX_SEND    = 4'd8;  // 결과 1바이트 UART TX 전송

    reg [3:0] state;

    // =========================================================
    // 픽셀 입력 버퍼 (UART로 받은 784바이트)
    // =========================================================
    reg [7:0]  pixel_buf [0:783];
    reg [9:0]  recv_cnt;         // 수신한 바이트 수

    // =========================================================
    // FC1 출력 버퍼 (ReLU 적용된 activation 64개)
    // =========================================================
    reg [7:0]  fc1_act_buf [0:63];
    reg [5:0]  fc1_act_cnt;

    // =========================================================
    // 스트리밍 카운터
    // =========================================================
    reg [9:0]  fc1_stream_cnt;   // 0~783
    reg [5:0]  fc2_stream_cnt;   // 0~63

    // =========================================================
    // FC1 인터페이스
    // =========================================================
    reg        fc1_start;
    reg  [7:0] fc1_pixel_data;
    reg        fc1_pixel_valid;
    wire [7:0] fc1_out_data;
    wire       fc1_out_valid;
    wire       fc1_done;

    fc1_layer fc1 (
        .clk         (clk),
        .rst         (rst),
        .start       (fc1_start),
        .pixel_data  (fc1_pixel_data),
        .pixel_valid (fc1_pixel_valid),
        .out_data    (fc1_out_data),
        .out_valid   (fc1_out_valid),
        .done        (fc1_done)
    );

    // =========================================================
    // FC2 인터페이스
    // =========================================================
    reg        fc2_start;
    reg  [7:0] fc2_act_data;
    reg        fc2_act_valid;
    wire signed [23:0] fc2_out_data;
    wire       fc2_out_valid;
    wire       fc2_done;

    fc2_layer fc2 (
        .clk       (clk),
        .rst       (rst),
        .start     (fc2_start),
        .act_data  (fc2_act_data),
        .act_valid (fc2_act_valid),
        .out_data  (fc2_out_data),
        .out_valid (fc2_out_valid),
        .done      (fc2_done)
    );

    // =========================================================
    // Argmax 인터페이스
    // FC2 out_valid/out_data를 argmax에 직접 연결
    // FC2_START와 같은 사이클에 argmax_start를 보내므로
    // FC2가 결과를 출력하기 훨씬 전에 argmax가 준비 완료
    // =========================================================
    reg       argmax_start;
    wire [3:0] argmax_result;
    wire       argmax_done;

    argmax argmax_inst (
        .clk         (clk),
        .rst         (rst),
        .start       (argmax_start),
        .score_data  (fc2_out_data),
        .score_valid (fc2_out_valid),
        .result      (argmax_result),
        .done        (argmax_done)
    );

    // =========================================================
    // 메인 상태 머신
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state          <= IDLE;
            recv_cnt       <= 0;
            fc1_act_cnt    <= 0;
            fc1_stream_cnt <= 0;
            fc2_stream_cnt <= 0;
            fc1_start      <= 0;
            fc1_pixel_data <= 0;
            fc1_pixel_valid <= 0;
            fc2_start      <= 0;
            fc2_act_data   <= 0;
            fc2_act_valid  <= 0;
            argmax_start   <= 0;
            tx_data        <= 0;
            tx_start       <= 0;
        end else begin
            // 기본 deassert
            fc1_start       <= 0;
            fc1_pixel_valid <= 0;
            fc2_start       <= 0;
            fc2_act_valid   <= 0;
            argmax_start    <= 0;
            tx_start        <= 0;

            case (state)

                // -----------------------------------------------
                // IDLE: 첫 번째 rx_valid 대기
                // 첫 바이트를 pixel_buf[0]에 저장하고 RECV로 전환
                // -----------------------------------------------
                IDLE: begin
                    if (rx_valid) begin
                        pixel_buf[0] <= rx_data;
                        recv_cnt     <= 10'd1;
                        state        <= RECV;
                    end
                end

                // -----------------------------------------------
                // RECV: 나머지 783바이트 수신
                // recv_cnt = 1 ~ 783
                // -----------------------------------------------
                RECV: begin
                    if (rx_valid) begin
                        pixel_buf[recv_cnt] <= rx_data;
                        recv_cnt            <= recv_cnt + 1;
                        if (recv_cnt == 783) begin
                            state <= FC1_START;
                        end
                    end
                end

                // -----------------------------------------------
                // FC1_START: fc1_start 1클럭 펄스 발생
                // 다음 사이클부터 FC1이 LOAD 상태에서 pixel_valid 수신 가능
                // -----------------------------------------------
                FC1_START: begin
                    fc1_start      <= 1;
                    fc1_stream_cnt <= 0;
                    fc1_act_cnt    <= 0;
                    state          <= FC1_STREAM;
                end

                // -----------------------------------------------
                // FC1_STREAM: pixel_buf[0..783]을 FC1에 스트리밍
                // 784사이클 연속 pixel_valid=1
                // -----------------------------------------------
                FC1_STREAM: begin
                    fc1_pixel_data  <= pixel_buf[fc1_stream_cnt];
                    fc1_pixel_valid <= 1;
                    fc1_stream_cnt  <= fc1_stream_cnt + 1;
                    if (fc1_stream_cnt == 783) begin
                        state <= FC1_WAIT;
                    end
                end

                // -----------------------------------------------
                // FC1_WAIT: FC1 MAC 연산 완료 대기
                // FC1 out_valid가 뜰 때마다 fc1_act_buf에 저장 (64회)
                // fc1_done과 마지막 out_valid는 같은 사이클에 발생
                // -----------------------------------------------
                FC1_WAIT: begin
                    if (fc1_out_valid) begin
                        fc1_act_buf[fc1_act_cnt] <= fc1_out_data;
                        fc1_act_cnt              <= fc1_act_cnt + 1;
                    end
                    if (fc1_done) begin
                        state <= FC2_START;
                    end
                end

                // -----------------------------------------------
                // FC2_START: fc2_start + argmax_start 동시 발생
                // fc2_start: FC2를 LOAD 상태로 전환
                // argmax_start: argmax 내부 상태 초기화
                //   → FC2 결과가 나오기까지 수백 사이클 여유 있음
                // -----------------------------------------------
                FC2_START: begin
                    fc2_start      <= 1;
                    argmax_start   <= 1;
                    fc2_stream_cnt <= 0;
                    state          <= FC2_STREAM;
                end

                // -----------------------------------------------
                // FC2_STREAM: fc1_act_buf[0..63]을 FC2에 스트리밍
                // 64사이클 연속 act_valid=1
                // -----------------------------------------------
                FC2_STREAM: begin
                    fc2_act_data   <= fc1_act_buf[fc2_stream_cnt];
                    fc2_act_valid  <= 1;
                    fc2_stream_cnt <= fc2_stream_cnt + 1;
                    if (fc2_stream_cnt == 63) begin
                        state <= FC2_WAIT;
                    end
                end

                // -----------------------------------------------
                // FC2_WAIT: argmax 완료 대기
                // FC2 out_valid는 argmax에 직결되어 있으므로
                // argmax가 score 10개를 받으면 done=1
                // -----------------------------------------------
                FC2_WAIT: begin
                    if (argmax_done) begin
                        state <= TX_SEND;
                    end
                end

                // -----------------------------------------------
                // TX_SEND: 인식 결과 1바이트 전송
                // tx_busy=0이 될 때까지 대기 후 전송
                // tx_data = 0x00~0x09 (인식된 숫자)
                // -----------------------------------------------
                TX_SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= {4'b0000, argmax_result};
                        tx_start <= 1;
                        state    <= IDLE;
                    end
                end

            endcase
        end
    end

endmodule
