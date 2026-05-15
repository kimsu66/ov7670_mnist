`timescale 1ns / 1ps

module digit_detector (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg         digit_detected  // 1클럭 펄스
);

    // 검정 배경 + 흰 숫자 기준 (흰 획이 bright, 검정 배경이 dark)
    //
    // 숫자 없을 때 (검정 배경만):
    //   dark_cnt≈700, bright_cnt≈0~10  → bright_cnt < MIN_BRIGHT → 미감지 → LED=15
    //
    // 숫자 있을 때 (흰 획 + 검정 배경):
    //   dark_cnt≈450~650, bright_cnt≈40~180 → 두 조건 충족 → 감지
    //
    // 흰 배경만:
    //   dark_cnt≈0, bright_cnt≈784 → dark_cnt < MIN_DARK → 미감지 → LED=15

    localparam [7:0] LOW_THR    = 8'd80;   // 이하 → 어두운 픽셀 (검정 배경)
    localparam [7:0] HIGH_THR   = 8'd170;  // 이상 → 밝은 픽셀 (흰 획)
    localparam [9:0] MIN_DARK   = 10'd150; // 배경이 충분히 어두워야 함 (~19%)
    localparam [9:0] MIN_BRIGHT = 10'd25;  // 흰 획이 최소한 있어야 함 (~3%)

    reg [9:0] dark_cnt;
    reg [9:0] bright_cnt;

    // frame_done과 sampled_valid 동시 도달 시 마지막 픽셀도 포함
    wire is_dark   = sampled_valid && (sampled_pixel <  LOW_THR);
    wire is_bright = sampled_valid && (sampled_pixel >= HIGH_THR);

    wire [9:0] cur_dark   = dark_cnt   + (is_dark   ? 10'd1 : 10'd0);
    wire [9:0] cur_bright = bright_cnt + (is_bright ? 10'd1 : 10'd0);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dark_cnt       <= 10'd0;
            bright_cnt     <= 10'd0;
            digit_detected <= 1'b0;
        end else begin
            digit_detected <= 1'b0;

            if (frame_done) begin
                digit_detected <= (cur_dark >= MIN_DARK) && (cur_bright >= MIN_BRIGHT);
                dark_cnt       <= 10'd0;
                bright_cnt     <= 10'd0;
            end else if (sampled_valid) begin
                if (is_dark)   dark_cnt   <= dark_cnt   + 10'd1;
                if (is_bright) bright_cnt <= bright_cnt + 10'd1;
            end
        end
    end

endmodule
