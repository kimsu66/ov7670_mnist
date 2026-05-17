module fc1_layer (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,        // 추론 시작 신호 (top에서 1클럭 pulse)
    input  wire [7:0]  pixel_data,   // x: 입력 픽셀 (0~255, 1개씩 순서대로)
    input  wire        pixel_valid,  // 픽셀 유효 신호 (1이면 pixel_data 읽기)
    output reg  [7:0]  out_data,     // activation: FC1 출력 (ReLU 적용된 값, 1개씩)
    output reg         out_valid,    // 출력 유효 신호 (1이면 out_data 읽기)
    output reg         done          // FC1 전체 완료 신호
);

    // =========================================================
    // 상태 머신 정의
    // IDLE    : 대기
    // LOAD    : 픽셀 784개를 pixel_buf에 저장
    // COMPUTE : MAC 연산 (weight * pixel 누적)
    // OUTPUT  : bias 더하기 + ReLU + 출력
    // =========================================================
    localparam IDLE      = 3'd0;
    localparam LOAD      = 3'd1;
    localparam COMPUTE   = 3'd2;
    localparam BIAS_WAIT = 3'd3;
    localparam OUTPUT    = 3'd4;

    reg [2:0] state;

    // =========================================================
    // 픽셀 버퍼
    // UART 등으로 들어오는 픽셀 784개를 일단 여기 저장
    // FC1은 뉴런 64개를 순서대로 계산하는데,
    // 각 뉴런마다 784개 픽셀을 전부 다시 읽어야 하므로
    // 버퍼에 저장해두고 재사용
    // =========================================================
    reg [7:0] pixel_buf [0:783];  // x[0] ~ x[783]
    reg [9:0] pixel_cnt;          // LOAD 상태에서 몇 개 받았는지 카운터 (0~783)

    // =========================================================
    // BRAM 인터페이스
    // fc1_weight BRAM: (64, 784) 행렬을 flatten해서 저장
    //   주소 계산: neuron_idx * 784 + pixel_idx
    //   → 뉴런 i번의 j번째 weight = w[i*784 + j]
    // fc1_bias BRAM: 64개 bias 저장
    //   주소 = neuron_idx
    // =========================================================
    reg  [15:0] w_addr;  // weight BRAM 주소 (0~50175, 16비트)
    wire [7:0]  w_data;  // weight BRAM 읽기값 (INT8, 부호 있음)

    reg  [5:0]  b_addr;  // bias BRAM 주소 (0~63, 6비트)
    wire [7:0]  b_data;  // bias BRAM 읽기값 (INT8, 부호 있음)

    // =========================================================
    // 연산용 레지스터
    // neuron_idx : 현재 계산 중인 뉴런 번호 (0~63)
    // pixel_idx  : 현재 처리 중인 픽셀 번호 (0~783)
    // accumulator: MAC 누적합
    //   INT8 * INT8 = 최대 127*127 = 16129
    //   784번 누적 → 최대 16129*784 ≈ 12.6M → 24비트 필요 (signed)
    // out_buf    : ReLU 적용된 FC1 출력 64개 저장
    // =========================================================
    reg  [5:0]        neuron_idx;
    reg  [9:0]        pixel_idx;
    reg  signed [23:0] accumulator;  // 수정: 20비트→24비트 (오버플로우 방지)
    wire signed [23:0] acc_with_bias;
    assign acc_with_bias = accumulator + $signed(b_data);

    // =========================================================
    // BRAM 인스턴스
    // Vivado IP에서 생성한 이름과 일치해야 함
    // =========================================================

    // fc1_weight: w[neuron][pixel] → flatten주소 = neuron*784 + pixel
    blk_mem_gen_0 fc1_weight_bram (
        .clka  (clk),
        .addra (w_addr),
        .douta (w_data)   // 1클럭 레이턴시
    );

    // fc1_bias: b[neuron]
    blk_mem_gen_1 fc1_bias_bram (
        .clka  (clk),
        .addra (b_addr),
        .douta (b_data)   // 1클럭 레이턴시
    );

    // =========================================================
    // 상태 머신 동작
    // =========================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            pixel_cnt   <= 0;
            neuron_idx  <= 0;
            pixel_idx   <= 0;
            accumulator <= 0;
            out_valid   <= 0;
            done        <= 0;
        end else begin
            case (state)

                // -----------------------------------------------
                // IDLE: start 신호 기다림
                // -----------------------------------------------
                IDLE: begin
                    out_valid <= 0;
                    done      <= 0;
                    if (start) begin
                        pixel_cnt <= 0;
                        state     <= LOAD;
                    end
                end

                // -----------------------------------------------
                // LOAD: pixel_valid가 1일 때마다 픽셀 1개씩 버퍼에 저장
                // 784개 다 받으면 COMPUTE로 전환
                // -----------------------------------------------
                LOAD: begin
                    if (pixel_valid) begin
                        pixel_buf[pixel_cnt] <= pixel_data;  // x[pixel_cnt] 저장
                        pixel_cnt <= pixel_cnt + 1;
                        if (pixel_cnt == 783) begin
                            // 784개 수신 완료 → MAC 연산 시작 준비
                            neuron_idx  <= 0;
                            pixel_idx   <= 0;
                            accumulator <= 0;
                            w_addr      <= 0;
                            b_addr      <= 0;
                            state       <= COMPUTE;
                        end
                    end
                end

                // -----------------------------------------------
                // COMPUTE: MAC 연산
                // y[neuron] += w[neuron][pixel] * x[pixel]
                //
                // BRAM 레이턴시 1클럭이라:
                //   클럭 N   : w_addr = neuron*784 + pixel_idx 세팅
                //   클럭 N+1 : w_data 유효 → pixel_idx-1 번 픽셀이랑 곱해서 누적
                // -----------------------------------------------
                COMPUTE: begin
                    out_valid <= 0;

                    // pixel_idx < 784 일 때만 주소 세팅
                    if (pixel_idx < 784) begin
                        w_addr <= ({10'd0, neuron_idx} * 16'd784) + {6'd0, pixel_idx};
                    end

                    if (pixel_idx > 0) begin
                        accumulator <= accumulator +
                            $signed(w_data) * $signed({1'b0, pixel_buf[pixel_idx - 1]});
                    end

                    if (pixel_idx == 784) begin
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        pixel_idx <= pixel_idx + 1;
                    end
                end

                // -----------------------------------------------
                // BIAS_WAIT: b_addr 세팅 후 1클럭 대기 (BRAM 레이턴시)
                // -----------------------------------------------
                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                // -----------------------------------------------
                // OUTPUT: bias 더하기 + ReLU + 출력
                //
                // y[neuron] = ReLU(accumulator + b[neuron])
                // ReLU: 음수면 0, 양수면 그대로
                // 출력은 8비트로 클리핑 (0~127)
                // -----------------------------------------------
                OUTPUT: begin
                    // acc_with_bias = accumulator + b_data (조합 회로, 이번 클럭 즉시 반영)
                    // ReLU + 8비트 클리핑 후 출력
                    if ($signed(acc_with_bias) > 0) begin
                        out_data <= (acc_with_bias > 24'sd127) ? 8'd127 : acc_with_bias[7:0];
                    end else begin
                        out_data <= 8'd0;
                    end
                    out_valid <= 1;

                    if (neuron_idx == 63) begin
                        // 64개 뉴런 전부 완료
                        done  <= 1;
                        state <= IDLE;
                    end else begin
                        // 다음 뉴런 계산으로
                        neuron_idx  <= neuron_idx + 1;
                        pixel_idx   <= 0;
                        accumulator <= 0;
                        state       <= COMPUTE;
                    end
                end

            endcase
        end
    end

endmodule