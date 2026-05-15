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

    // 56×56 픽셀 영역을 2×2 평균 풀링으로 28×28 다운샘플링
    // 중심: (160, 120), 영역: x[132,187], y[92,147]
    localparam [9:0] BOX_X0 = 10'd132;
    localparam [9:0] BOX_X1 = 10'd187;
    localparam [9:0] BOX_Y0 = 10'd92;
    localparam [9:0] BOX_Y1 = 10'd147;

    wire in_box = (vga_x >= BOX_X0) && (vga_x <= BOX_X1) &&
                  (vga_y >= BOX_Y0) && (vga_y <= BOX_Y1);

    wire [9:0] local_x = vga_x - BOX_X0;  // 0..55
    wire [9:0] local_y = vga_y - BOX_Y0;  // 0..55
    wire       x_pair  = local_x[0];      // 0=좌, 1=우 (2×2 블록 내)
    wire       y_pair  = local_y[0];      // 0=상, 1=하 (2×2 블록 내)
    wire [4:0] ox      = local_x[5:1];    // 출력 열 인덱스 0..27

    // 상단 행의 좌+우 픽셀 합(최대 510)을 28열분 저장
    reg [9:0] line_buf [0:27];
    reg [9:0] acc;        // 부분 누산기
    reg [9:0] sample_cnt;

    // 출력 사이클에서 사용할 조합 합산 (acc = 상단합+하단좌, pixel_in = 하단우)
    wire [9:0] pool_sum = acc + {2'b0, pixel_in};
    // pool_sum[9:6]: 4픽셀 합을 >>6하면 4비트 평균, {avg4, avg4}로 8비트 스케일링
    //   pixel_in = {gray4, 4'b0} 형태이므로 sum = Σgray_i * 16
    //   pool_sum[9:6] = Σgray_i >> 2 = 4비트 평균 (0..15)

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sampled_pixel <= 8'd0;
            sampled_valid <= 1'b0;
            frame_done    <= 1'b0;
            sample_cnt    <= 10'd0;
            acc           <= 10'd0;
            for (i = 0; i < 28; i = i + 1)
                line_buf[i] <= 10'd0;
        end else begin
            sampled_valid <= 1'b0;
            frame_done    <= 1'b0;

            if (in_box) begin
                if (y_pair == 1'b0) begin
                    // 상단 행: 좌→acc 저장, 우→line_buf에 좌+우 합 저장
                    if (x_pair == 1'b0)
                        acc <= {2'b0, pixel_in};
                    else
                        line_buf[ox] <= acc + {2'b0, pixel_in};
                end else begin
                    // 하단 행: 좌→(상단합+하단좌)를 acc에, 우→4픽셀 평균 출력
                    if (x_pair == 1'b0) begin
                        acc <= line_buf[ox] + {2'b0, pixel_in};
                    end else begin
                        sampled_pixel <= {pool_sum[9:6], pool_sum[9:6]};
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
        end
    end

endmodule
