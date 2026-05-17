`timescale 1ns / 1ps

// 도형 분류기: 28×28 픽셀 스트림 → ○ △ + 판별
//
// 입력 극성: INK_THR 미만 픽셀 = 잉크 (밝은 배경 + 어두운 마커 기준)
//
// 행 밴드 기반 알고리즘:
//   outer_top = row  0~ 6 잉크 수 (상단 외곽 7행)
//   outer_bot = row 21~27 잉크 수 (하단 외곽 7행)
//   mid       = row  7~20 잉크 수 (암묵, total - outer_top - outer_bot)
//
//   분류 순서:
//     1. total < MIN_INK 또는 > MAX_INK          → NONE
//     2. (outer_top + outer_bot) × 3 < total     → CROSS  (+) 중앙 집중
//     3. outer_bot > outer_top + ASYM_THR        → TRIANGLE △ 하단 집중
//     4. 나머지                                  → CIRCLE ○
//
// ── 핵심 원리 ──────────────────────────────────────────────────────────────
//
//  십자(+): 가로/세로 막대가 중앙(row 7~20)에 집중
//           → outer 합의 3배가 total보다 작음
//           (획 굵기와 무관하게 동작 — 구 코너 방식의 굵은 획 오인 문제 해소)
//
//  삼각형△: 꼭짓점이 위(outer_top 소), 밑변이 아래(outer_bot 대)
//           → outer_bot - outer_top이 임계값 초과
//
//  원    ○: 위아래 외곽 모두 상당하고 대칭 → 나머지 fallback
//
// ── 조정 파라미터 ─────────────────────────────────────────────────────────
//  INK_THR  : 잉크 판별 밝기 경계 (이 미만 = 잉크)
//  MIN_INK  : 도형 인정 최소 잉크 픽셀 (흰 화면 거부)
//  MAX_INK  : 도형 인정 최대 잉크 픽셀 (검은 화면 거부)
//  ASYM_THR : 삼각형 판별 하단-상단 차이 임계값
// ──────────────────────────────────────────────────────────────────────────

module shape_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg  [1:0]  shape,       // 00=없음  01=○  10=△  11=+
    output reg         shape_valid, // frame_done 시점 1클럭 펄스
    output reg         is_dark      // 1=NONE이 검은 화면, 0=흰 화면
);

    localparam [7:0] INK_THR  = 8'd96;
    localparam [9:0] MIN_INK  = 10'd30;
    localparam [9:0] MAX_INK  = 10'd700;
    localparam [7:0] ASYM_THR = 8'd20;

    localparam [1:0] NONE     = 2'b00;
    localparam [1:0] CIRCLE   = 2'b01;
    localparam [1:0] TRIANGLE = 2'b10;
    localparam [1:0] CROSS    = 2'b11;

    // ── 픽셀 좌표 추적 ────────────────────────────────────────────────────
    reg [4:0] row_cnt;  // 0..27
    reg [4:0] col_cnt;  // 0..27

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_cnt <= 5'd0;
            col_cnt <= 5'd0;
        end else if (frame_done) begin
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

    // ── 픽셀 속성 (조합 논리) ─────────────────────────────────────────────
    wire is_ink     = sampled_valid && (sampled_pixel < INK_THR);
    wire is_out_top = (row_cnt <= 5'd6);   // row 0~6
    wire is_out_bot = (row_cnt >= 5'd21);  // row 21~27

    // ── 누산기 ────────────────────────────────────────────────────────────
    // outer_top / outer_bot 최대: 7행 × 28열 = 196 → 8비트
    reg  [9:0] total_ink;
    reg  [7:0] outer_top;
    reg  [7:0] outer_bot;

    wire [9:0] cur_total   = total_ink + (is_ink                    ? 10'd1 : 10'd0);
    wire [7:0] cur_out_top = outer_top + (is_ink && is_out_top      ?  8'd1 :  8'd0);
    wire [7:0] cur_out_bot = outer_bot + (is_ink && is_out_bot      ?  8'd1 :  8'd0);

    // ── 분류 조건 (조합 논리) ─────────────────────────────────────────────
    wire  [8:0] outer_sum  = {1'b0, cur_out_top} + {1'b0, cur_out_bot};
    // 십자: outer_sum × 3 < total  (최대 196×2×3=1176 < 2^11)
    wire [10:0] outer_sum3 = {2'b0, outer_sum} + {2'b0, outer_sum} + {2'b0, outer_sum};
    wire cross_cond = (outer_sum3 < {1'b0, cur_total});
    // 삼각형: outer_bot - outer_top > ASYM_THR
    wire asym_cond  = (cur_out_bot > cur_out_top + ASYM_THR);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            total_ink   <= 10'd0;
            outer_top   <=  8'd0;
            outer_bot   <=  8'd0;
            shape       <= NONE;
            shape_valid <= 1'b0;
            is_dark     <= 1'b0;
        end else begin
            shape_valid <= 1'b0;

            if (frame_done) begin
                // ── 분류 ──────────────────────────────────────────────────
                if (cur_total < MIN_INK || cur_total > MAX_INK) begin
                    shape   <= NONE;
                    is_dark <= (cur_total > MAX_INK);
                end else if (cross_cond) begin
                    shape   <= CROSS;
                    is_dark <= 1'b0;
                end else if (asym_cond) begin
                    shape   <= TRIANGLE;
                    is_dark <= 1'b0;
                end else begin
                    shape   <= CIRCLE;
                    is_dark <= 1'b0;
                end

                shape_valid <= 1'b1;

                // ── 리셋 ──────────────────────────────────────────────────
                total_ink <= 10'd0;
                outer_top <=  8'd0;
                outer_bot <=  8'd0;

            end else if (sampled_valid) begin
                // ── 픽셀 누산 ─────────────────────────────────────────────
                total_ink <= cur_total;
                outer_top <= cur_out_top;
                outer_bot <= cur_out_bot;
            end
        end
    end

endmodule
