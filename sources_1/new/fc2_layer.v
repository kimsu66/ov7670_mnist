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
    localparam ADDR_SETUP = 3'd2;
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

    wire signed [7:0]  w_data_s;
    wire signed [7:0]  b_data_s;
    wire signed [23:0] acc_with_bias;

    assign w_data_s      = w_data;
    assign b_data_s      = b_data;
    assign acc_with_bias = accumulator + {{16{b_data_s[7]}}, b_data_s};

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
            act_cnt     <= 6'd0;
            neuron_idx  <= 4'd0;
            act_idx     <= 7'd0;
            accumulator <= 24'sd0;
            out_data    <= 24'sd0;
            out_valid   <= 1'b0;
            done        <= 1'b0;
            w_addr      <= 10'd0;
            b_addr      <= 4'd0;
        end else begin
            // out_valid/done은 반드시 1-cycle pulse로만 발생시킨다.
            // 기존 코드에서는 OUTPUT 다음 ADDR_SETUP/COMPUTE에서 값이 유지되어
            // argmax가 동일 score를 중복 입력받는 문제가 있었다.
            out_valid <= 1'b0;
            done      <= 1'b0;

            case (state)

                IDLE: begin
                    if (start) begin
                        act_cnt <= 6'd0;
                        state   <= LOAD;
                    end
                end

                LOAD: begin
                    if (act_valid) begin
                        act_buf[act_cnt] <= act_data;
                        act_cnt <= act_cnt + 6'd1;

                        if (act_cnt == 6'd63) begin
                            neuron_idx  <= 4'd0;
                            accumulator <= 24'sd0;
                            state       <= ADDR_SETUP;
                        end
                    end
                end

                // BRAM read latency 1-cycle 가정: addr[class][0] 설정
                ADDR_SETUP: begin
                    w_addr  <= ({6'd0, neuron_idx} * 10'd64);
                    act_idx <= 7'd1;
                    state   <= COMPUTE;
                end

                // act_idx=1일 때 w_data는 w[class][0]에 대응
                // act_idx=64일 때 w_data는 w[class][63]에 대응
                COMPUTE: begin
                    if (act_idx < 7'd64) begin
                        w_addr <= ({6'd0, neuron_idx} * 10'd64) + {3'd0, act_idx};
                    end

                    accumulator <= accumulator
                                 + ($signed(w_data_s) * $signed({1'b0, act_buf[act_idx - 7'd1]}));

                    if (act_idx == 7'd64) begin
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        act_idx <= act_idx + 7'd1;
                    end
                end

                // bias BRAM read latency 1-cycle 가정
                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    // Python: z2 = w2 @ act1 + b2, clamp 없음
                    out_data  <= acc_with_bias;
                    out_valid <= 1'b1;

                    if (neuron_idx == 4'd9) begin
                        done  <= 1'b1;
                        state <= IDLE;
                    end else begin
                        neuron_idx  <= neuron_idx + 4'd1;
                        accumulator <= 24'sd0;
                        state       <= ADDR_SETUP;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule