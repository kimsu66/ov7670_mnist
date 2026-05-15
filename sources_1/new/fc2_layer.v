module fc2_layer (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [7:0]  act_data,    // FC1 출력 activation (1개씩)
    input  wire        act_valid,
    output reg  signed [15:0]  out_data,    // FC2 출력 (0~9 점수, 1개씩)
    output reg         out_valid,
    output reg         done
);

    localparam IDLE      = 3'd0;
    localparam LOAD      = 3'd1;
    localparam COMPUTE   = 3'd2;
    localparam BIAS_WAIT = 3'd3;
    localparam OUTPUT    = 3'd4;

    reg [2:0] state;

    // 입력 버퍼 (FC1 출력 64개)
    reg [7:0] act_buf [0:63];
    reg [5:0] act_cnt;   // 0~63

    // BRAM 인터페이스 - fc2_weight (10*64=640)
    reg  [9:0] w_addr;   // 0~639
    wire [7:0] w_data;

    // BRAM 인터페이스 - fc2_bias (10개)
    reg  [3:0] b_addr;   // 0~9
    wire [7:0] b_data;

    // 연산용
    reg  [3:0]         neuron_idx;  // 0~9
    reg  [6:0]         act_idx;     // 0~64 (64 도달 확인용으로 7비트 필요)
    reg  signed [19:0] accumulator;
    // INT8*INT8*64 = 127*127*64 ≈ 1M → 20비트로 충분

    wire signed [19:0] acc_with_bias;
    assign acc_with_bias = accumulator + $signed(b_data);

    // BRAM 인스턴스
    fc2_weight fc2_weight_bram (
        .clka  (clk),
        .addra (w_addr),
        .douta (w_data)
    );

    fc2_bias fc2_bias_bram (
        .clka  (clk),
        .addra (b_addr),
        .douta (b_data)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            act_cnt     <= 0;
            neuron_idx  <= 0;
            act_idx     <= 0;
            accumulator <= 0;
            out_valid   <= 0;
            done        <= 0;
        end else begin
            case (state)

                IDLE: begin
                    out_valid <= 0;
                    done      <= 0;
                    if (start) begin
                        act_cnt <= 0;
                        state   <= LOAD;
                    end
                end

                // FC1 출력 64개 버퍼에 저장
                LOAD: begin
                    if (act_valid) begin
                        act_buf[act_cnt] <= act_data;
                        act_cnt <= act_cnt + 1;
                        if (act_cnt == 63) begin
                            neuron_idx  <= 0;
                            act_idx     <= 0;
                            accumulator <= 0;
                            w_addr      <= 0;
                            b_addr      <= 0;
                            state       <= COMPUTE;
                        end
                    end
                end

                // MAC: y[neuron] += w[neuron][act] * act[act]
                COMPUTE: begin
                    out_valid <= 0;
                    w_addr <= ({6'd0, neuron_idx} * 10'd64) + {4'd0, act_idx};

                    if (act_idx > 0) begin
                        accumulator <= accumulator +
                            $signed(w_data) * $signed({1'b0, act_buf[act_idx - 1]});
                    end

                    if (act_idx == 64) begin
                        // 마지막 act_buf[63]도 누적됨 (act_idx>0 블록)
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        act_idx <= act_idx + 1;
                    end
                end

                // bias BRAM 레이턴시 1클럭 대기
                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                // bias 더하기, ReLU 없음, 출력
                OUTPUT: begin
                    // FC2는 ReLU 없음 → 음수도 그대로 출력 (signed)
                    out_data  <= acc_with_bias[15:0];
                    out_valid <= 1;

                    if (neuron_idx == 9) begin
                        done  <= 1;
                        state <= IDLE;
                    end else begin
                        neuron_idx  <= neuron_idx + 1;
                        act_idx     <= 0;
                        accumulator <= 0;
                        state       <= COMPUTE;
                    end
                end

            endcase
        end
    end

endmodule