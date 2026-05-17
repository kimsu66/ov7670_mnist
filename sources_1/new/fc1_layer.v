`timescale 1ns / 1ps

module fc1_layer (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire [7:0]  pixel_data,
    input  wire        pixel_valid,
    output reg  [7:0]  out_data,
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

    reg [7:0] pixel_buf [0:783];
    reg [9:0] pixel_cnt;

    reg  [15:0] w_addr;
    wire [7:0]  w_data;

    reg  [5:0]  b_addr;
    wire [7:0]  b_data;

    reg  [5:0]         neuron_idx;
    reg  [9:0]         pixel_idx;
    reg  signed [23:0] accumulator;

    wire signed [7:0]  w_data_s;
    wire signed [7:0]  b_data_s;
    wire signed [23:0] acc_with_bias;

    assign w_data_s      = w_data;
    assign b_data_s      = b_data;
    assign acc_with_bias = accumulator + {{16{b_data_s[7]}}, b_data_s};

    blk_mem_gen_0 fc1_weight_bram (
        .clka  (clk),
        .addra (w_addr),
        .douta (w_data)
    );

    blk_mem_gen_1 fc1_bias_bram (
        .clka  (clk),
        .addra (b_addr),
        .douta (b_data)
    );

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state       <= IDLE;
            pixel_cnt   <= 10'd0;
            neuron_idx  <= 6'd0;
            pixel_idx   <= 10'd0;
            accumulator <= 24'sd0;
            out_data    <= 8'd0;
            out_valid   <= 1'b0;
            done        <= 1'b0;
            w_addr      <= 16'd0;
            b_addr      <= 6'd0;
        end else begin
            // out_valid/done은 반드시 1-cycle pulse로만 발생시킨다.
            // 기존 코드에서는 OUTPUT 다음 ADDR_SETUP/COMPUTE에서 값이 유지되어
            // 상위 mnist_core가 동일한 activation/score를 중복 캡처하는 문제가 있었다.
            out_valid <= 1'b0;
            done      <= 1'b0;

            case (state)

                IDLE: begin
                    if (start) begin
                        pixel_cnt <= 10'd0;
                        state     <= LOAD;
                    end
                end

                LOAD: begin
                    if (pixel_valid) begin
                        // Python reference는 4-bit grayscale 0~15 입력 기준.
                        pixel_buf[pixel_cnt] <= {4'b0000, pixel_data[3:0]};
                        pixel_cnt <= pixel_cnt + 10'd1;

                        if (pixel_cnt == 10'd783) begin
                            neuron_idx  <= 6'd0;
                            accumulator <= 24'sd0;
                            state       <= ADDR_SETUP;
                        end
                    end
                end

                // BRAM read latency 1-cycle 가정: addr[neuron][0] 설정
                ADDR_SETUP: begin
                    w_addr    <= ({10'd0, neuron_idx} * 16'd784);
                    pixel_idx <= 10'd1;
                    state     <= COMPUTE;
                end

                // pixel_idx=1일 때 w_data는 w[neuron][0]에 대응
                // pixel_idx=784일 때 w_data는 w[neuron][783]에 대응
                COMPUTE: begin
                    if (pixel_idx < 10'd784) begin
                        w_addr <= ({10'd0, neuron_idx} * 16'd784) + {6'd0, pixel_idx};
                    end

                    accumulator <= accumulator
                                 + ($signed(w_data_s) * $signed({1'b0, pixel_buf[pixel_idx - 10'd1]}));

                    if (pixel_idx == 10'd784) begin
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        pixel_idx <= pixel_idx + 10'd1;
                    end
                end

                // bias BRAM read latency 1-cycle 가정
                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    // Python: act1 = clip(max(z1, 0), 0, 127)
                    if (acc_with_bias <= 24'sd0) begin
                        out_data <= 8'd0;
                    end else if (acc_with_bias >= 24'sd127) begin
                        out_data <= 8'd127;
                    end else begin
                        out_data <= acc_with_bias[7:0];
                    end

                    out_valid <= 1'b1;

                    if (neuron_idx == 6'd63) begin
                        done  <= 1'b1;
                        state <= IDLE;
                    end else begin
                        neuron_idx  <= neuron_idx + 6'd1;
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