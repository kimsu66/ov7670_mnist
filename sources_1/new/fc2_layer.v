`timescale 1ns / 1ps

module fc2_layer (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [7:0]  act_data,
    input  wire        act_valid,
    output reg  signed [23:0] out_data,
    output reg         out_valid,
    output reg         done
);

    localparam IDLE       = 3'd0;
    localparam LOAD       = 3'd1;
    localparam ADDR_SETUP = 3'd2;  // 추가: BRAM addr 세팅 준비 사이클
    localparam COMPUTE    = 3'd3;
    localparam BIAS_WAIT  = 3'd4;
    localparam OUTPUT     = 3'd5;

    reg [2:0] state;

    reg [7:0] act_buf [0:63];
    reg [5:0] act_cnt;

    reg  [9:0] w_addr;
    wire [7:0] w_data;

    reg  [3:0] b_addr;
    wire [7:0] b_data;

    reg  [3:0]         neuron_idx;
    reg  [6:0]         act_idx;
    reg  signed [23:0] accumulator;

    wire signed [23:0] acc_with_bias;
    assign acc_with_bias = accumulator + $signed({{16{b_data[7]}}, b_data});

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
            out_data    <= 0;
            out_valid   <= 0;
            done        <= 0;
            w_addr      <= 0;
            b_addr      <= 0;
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

                LOAD: begin
                    if (act_valid) begin
                        act_buf[act_cnt] <= act_data;
                        act_cnt <= act_cnt + 1;
                        if (act_cnt == 63) begin
                            neuron_idx  <= 0;
                            accumulator <= 0;
                            state       <= ADDR_SETUP;  // COMPUTE 대신 ADDR_SETUP
                        end
                    end
                end

                // BRAM addr 첫 번째 세팅 사이클
                // act_idx=0 기준으로 addr 세팅, act_idx를 1로 올림
                // 다음 사이클(COMPUTE)에서 w_data[0]이 유효
                ADDR_SETUP: begin
                    w_addr  <= {6'd0, neuron_idx} * 10'd64;  // neuron*64 + 0
                    act_idx <= 1;
                    state   <= COMPUTE;
                end

                // MAC 연산
                // act_idx=1일 때: w_data = w[neuron][0] 유효
                //   → act_buf[0]과 곱 (act_idx-1=0)
                // act_idx=64일 때: w_data = w[neuron][63] 유효
                //   → act_buf[63]과 곱 후 BIAS_WAIT
                COMPUTE: begin
                    out_valid <= 0;

                    // 다음 주소 세팅 (64 이전까지만)
                    if (act_idx < 64) begin
                        w_addr <= ({6'd0, neuron_idx} * 10'd64) + {4'd0, act_idx};
                    end

                    // 현재 w_data (act_idx-1 기준) 누적
                    accumulator <= accumulator +
                        $signed(w_data) * $signed({1'b0, act_buf[act_idx - 1]});

                    if (act_idx == 64) begin
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        act_idx <= act_idx + 1;
                    end
                end

                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    out_data  <= acc_with_bias;
                    out_valid <= 1;

                    if (neuron_idx == 9) begin
                        done  <= 1;
                        state <= IDLE;
                    end else begin
                        neuron_idx  <= neuron_idx + 1;
                        accumulator <= 0;
                        state       <= ADDR_SETUP;  // COMPUTE 대신 ADDR_SETUP
                    end
                end

            endcase
        end
    end

endmodule