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
    localparam ADDR_SETUP = 3'd2;  // 추가: BRAM addr 세팅 준비 사이클
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
    wire signed [23:0] acc_with_bias;
    assign acc_with_bias = accumulator + $signed({{16{b_data[7]}}, b_data});

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
            pixel_cnt   <= 0;
            neuron_idx  <= 0;
            pixel_idx   <= 0;
            accumulator <= 0;
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
                        pixel_cnt <= 0;
                        state     <= LOAD;
                    end
                end

                LOAD: begin
                    if (pixel_valid) begin
                        pixel_buf[pixel_cnt] <= pixel_data;
                        pixel_cnt <= pixel_cnt + 1;
                        if (pixel_cnt == 783) begin
                            neuron_idx  <= 0;
                            accumulator <= 0;
                            state       <= ADDR_SETUP;  // COMPUTE 대신 ADDR_SETUP
                        end
                    end
                end

                // BRAM addr 첫 번째 세팅 사이클
                // pixel_idx=0 기준으로 addr 세팅, pixel_idx를 1로 올림
                // 다음 사이클(COMPUTE)에서 w_data[0]이 유효
                ADDR_SETUP: begin
                    w_addr    <= {10'd0, neuron_idx} * 16'd784;  // neuron*784 + 0
                    pixel_idx <= 1;
                    state     <= COMPUTE;
                end

                // MAC 연산
                // pixel_idx=1일 때: w_data = w[neuron][0] 유효
                //   → pixel_buf[0]과 곱 (pixel_idx-1=0)
                // pixel_idx=784일 때: w_data = w[neuron][783] 유효
                //   → pixel_buf[783]과 곱 후 BIAS_WAIT
                COMPUTE: begin
                    out_valid <= 0;

                    // 다음 주소 세팅 (784 이전까지만)
                    if (pixel_idx < 784) begin
                        w_addr <= ({10'd0, neuron_idx} * 16'd784) + {6'd0, pixel_idx};
                    end

                    // 현재 w_data (pixel_idx-1 기준) 누적
                    accumulator <= accumulator +
                        $signed(w_data) * $signed({1'b0, pixel_buf[pixel_idx - 1]});

                    if (pixel_idx == 784) begin
                        b_addr <= neuron_idx;
                        state  <= BIAS_WAIT;
                    end else begin
                        pixel_idx <= pixel_idx + 1;
                    end
                end

                BIAS_WAIT: begin
                    state <= OUTPUT;
                end

                OUTPUT: begin
                    if ($signed(acc_with_bias) > 0) begin
                        out_data <= (acc_with_bias > 24'sd127) ? 8'd127 : acc_with_bias[7:0];
                    end else begin
                        out_data <= 8'd0;
                    end
                    out_valid <= 1;

                    if (neuron_idx == 63) begin
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