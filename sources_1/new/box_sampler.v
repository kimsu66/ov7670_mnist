`timescale 1ns / 1ps

module box_sampler (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  pixel_in,   // frame_buffer pixel_out
    input  wire [9:0]  vga_x,
    input  wire [9:0]  vga_y,
    output reg  [7:0]  sampled_pixel,
    output reg         sampled_valid,
    output reg         frame_done
);

    // 56×56 픽셀 영역을 step=2로 28×28 다운샘플링
    // 중심: (160, 120), 영역: x[132,187], y[92,147]
    // 40×40 크기 숫자 → 28×28에서 약 20×20으로 매핑 (MNIST 분포와 유사)
    localparam [9:0] BOX_X0 = 10'd132;  // 160 - 28
    localparam [9:0] BOX_X1 = 10'd187;  // 132 + 56 - 1
    localparam [9:0] BOX_Y0 = 10'd92;   // 120 - 28
    localparam [9:0] BOX_Y1 = 10'd147;  // 92  + 56 - 1

    wire in_x = (vga_x >= BOX_X0) && (vga_x <= BOX_X1);
    wire in_y = (vga_y >= BOX_Y0) && (vga_y <= BOX_Y1);

    // step=2: BOX_X0=132, BOX_Y0=92 모두 짝수이므로
    // vga_x[0]==0 (짝수)인 위치에서만 샘플 → 132,134,...,186 (28개)
    // vga_y[0]==0 (짝수)인 라인에서만 샘플 → 92,94,...,146  (28개)
    wire is_sample = in_x && in_y && (vga_x[0] == 1'b0) && (vga_y[0] == 1'b0);

    reg [9:0] sample_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sampled_pixel <= 8'd0;
            sampled_valid <= 1'b0;
            frame_done    <= 1'b0;
            sample_cnt    <= 10'd0;
        end else begin
            sampled_valid <= 1'b0;
            frame_done    <= 1'b0;

            if (is_sample) begin
                // sampled_pixel <= {pixel_in[7:4], 4'b0};
                sampled_pixel <= {pixel_in[7:4], pixel_in[7:4]};  // 4비트 → 8비트 스케일링 (0→0, 15→255)
                sampled_valid <= 1'b1;
                if (sample_cnt == 10'd783) begin
                    frame_done <= 1'b1;
                    sample_cnt <= 10'd0;
                end else begin
                    sample_cnt <= sample_cnt + 10'd1;
                end
            end
        end
    end

endmodule
