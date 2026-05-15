`timescale 1ns / 1ps

// 도형 분류기: 28×28 픽셀 스트림 → ○ △ □ 판별
//
// 입력 극성: INK_THR 미만 픽셀 = 잉크 (밝은 배경 + 어두운 마커 기준)
//
// 분류 순서:
//   1. 총 잉크 픽셀 < MIN_INK                        → NONE
//   2. 상하 비대칭 > ASYM_THR                        → TRIANGLE
//   3. 상단 코너 AND 하단 코너 모두 잉크 > CORNER_THR → SQUARE
//   4. 나머지                                        → CIRCLE
//
// 코너 영역: 각 귀퉁이 7×7 픽셀 (rows/cols 0‑6 및 21‑27)
//
// ── 조정 파라미터 ────────────────────────────────────────────────────────
//  INK_THR    : 잉크 판별 밝기 경계 (낮출수록 더 어두운 픽셀만 잉크로 처리)
//  MIN_INK    : 도형으로 인정할 최소 잉크 픽셀 수
//  ASYM_THR   : 삼각형 판별 상하 비대칭 임계값 (픽셀 수 차이)
//  CORNER_THR : 사각형 판별 코너 잉크 임계값 (상단/하단 각각)
// ─────────────────────────────────────────────────────────────────────────

module shape_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg  [1:0]  shape,       // 00=없음  01=○  10=△  11=□
    output reg         shape_valid  // frame_done 시점 1클럭 펄스
);

    localparam [7:0] INK_THR    = 8'd128;
    localparam [9:0] MIN_INK    = 10'd30;
    localparam [8:0] ASYM_THR   = 9'd20;
    localparam [7:0] CORNER_THR = 8'd3;

    localparam [1:0] NONE     = 2'b00;
    localparam [1:0] CIRCLE   = 2'b01;
    localparam [1:0] TRIANGLE = 2'b10;
    localparam [1:0] SQUARE   = 2'b11;

    // ── 픽셀 좌표 추적 ────────────────────────────────────────────────
    // sampled_valid 마다 col→row 순으로 증가
    // frame_done (마지막 sampled_valid와 동시)에서 리셋
    reg [4:0] row_cnt;  // 0..27
    reg [4:0] col_cnt;  // 0..27

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_cnt <= 5'd0;
            col_cnt <= 5'd0;
        end else if (frame_done) begin
            // frame_done 사이클: 아직 row=27, col=27 → 분류에 사용 후 리셋
            row_cnt <= 5'd0;
            col_cnt <= 5'd0;
        end else if (sampled_valid) begin
            if (col_cnt == 5'd27) begin
                col_cnt <= 5'd0;
                row_cnt <= row_cnt + 5'd1;
            end else
                col_cnt <= col_cnt + 5'd1;
        end
    end

    // ── 픽셀 속성 (조합 논리) ─────────────────────────────────────────
    wire is_ink        = sampled_valid && (sampled_pixel < INK_THR);
    wire is_top        = (row_cnt < 5'd14);           // 상반부 행 0~13
    wire is_bot        = (row_cnt >= 5'd14);          // 하반부 행 14~27
    wire is_top_row    = (row_cnt <= 5'd6);           // 상단 코너 행
    wire is_bot_row    = (row_cnt >= 5'd21);          // 하단 코너 행
    wire is_lft_col    = (col_cnt <= 5'd6);           // 좌측 코너 열
    wire is_rgt_col    = (col_cnt >= 5'd21);          // 우측 코너 열
    wire is_top_corner = is_top_row && (is_lft_col || is_rgt_col);  // 상단 좌·우 코너
    wire is_bot_corner = is_bot_row && (is_lft_col || is_rgt_col);  // 하단 좌·우 코너

    // ── 누산기 ────────────────────────────────────────────────────────
    reg [9:0] total_ink;
    reg [8:0] top_ink;
    reg [8:0] bot_ink;
    reg [7:0] top_corner_ink;  // 상단 좌+우 코너 잉크 합 (최대 98)
    reg [7:0] bot_corner_ink;  // 하단 좌+우 코너 잉크 합 (최대 98)

    // frame_done과 sampled_valid가 동시인 마지막 픽셀도 분류에 포함하기 위해
    // 현재 픽셀 기여분을 조합으로 더한 cur_ 와이어를 분류에 사용한다
    wire [9:0] cur_total      = total_ink      + (is_ink                  ? 10'd1 : 10'd0);
    wire [8:0] cur_top        = top_ink        + (is_ink && is_top        ?  9'd1 :  9'd0);
    wire [8:0] cur_bot        = bot_ink        + (is_ink && is_bot        ?  9'd1 :  9'd0);
    wire [7:0] cur_top_corner = top_corner_ink + (is_ink && is_top_corner ?  8'd1 :  8'd0);
    wire [7:0] cur_bot_corner = bot_corner_ink + (is_ink && is_bot_corner ?  8'd1 :  8'd0);

    wire [8:0] asym = (cur_bot >= cur_top) ? (cur_bot - cur_top) :
                                              (cur_top - cur_bot);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            total_ink      <= 10'd0;
            top_ink        <=  9'd0;
            bot_ink        <=  9'd0;
            top_corner_ink <=  8'd0;
            bot_corner_ink <=  8'd0;
            shape          <= NONE;
            shape_valid    <= 1'b0;
        end else begin
            shape_valid <= 1'b0;

            if (frame_done) begin
                // ── 분류 (cur_ = 마지막 픽셀까지 포함한 값) ──────────
                if (cur_total < MIN_INK)
                    shape <= NONE;
                else if (asym > ASYM_THR)
                    shape <= TRIANGLE;
                else if (cur_top_corner > CORNER_THR && cur_bot_corner > CORNER_THR)
                    shape <= SQUARE;
                else
                    shape <= CIRCLE;

                shape_valid <= 1'b1;

                // ── 누산기 리셋 ───────────────────────────────────────
                total_ink      <= 10'd0;
                top_ink        <=  9'd0;
                bot_ink        <=  9'd0;
                top_corner_ink <=  8'd0;
                bot_corner_ink <=  8'd0;

            end else if (sampled_valid) begin
                total_ink      <= cur_total;
                top_ink        <= cur_top;
                bot_ink        <= cur_bot;
                top_corner_ink <= cur_top_corner;
                bot_corner_ink <= cur_bot_corner;
            end
        end
    end

endmodule
