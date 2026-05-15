`timescale 1ns / 1ps

// 도형 분류기: 28×28 픽셀 스트림 → ○ △ □ 판별
//
// 입력 극성: INK_THR 미만 픽셀 = 잉크 (밝은 배경 + 어두운 마커 기준)
//
// 분류 순서 (순서가 핵심):
//   1. 잉크 범위 밖                                → NONE  (흰/검은 화면)
//   2. 2 × min행픽셀 > max행픽셀                   → SQUARE (행 균일 → 크기·위치 무관)
//   3. 상하 비대칭 > ASYM_THR                      → TRIANGLE
//   4. 나머지                                      → CIRCLE
//
// ── 핵심 원리 ─────────────────────────────────────────────────────────────
//
//  사각형: 도형 내 모든 행의 폭이 같음  → row_min ≈ row_max → 2*min > max
//  원    : 중간 행이 넓고 위아래가 좁음 → row_min << row_max → 2*min ≤ max
//  삼각형: 한쪽 끝이 좁고 다른 쪽이 넓음 → 2*min ≤ max + 상하 비대칭 큼
//
//  → 사각형을 먼저 체크해야 함. 치우친 사각형도 삼각형 조건(ASYM)에 걸리지 않도록
//    사각형 체크가 우선권을 가져야 올바르게 분류됨.
//
// ── 조정 파라미터 ─────────────────────────────────────────────────────────
//  INK_THR   : 잉크 판별 밝기 경계
//  MIN_INK   : 도형 인정 최소 잉크 픽셀 수 (흰 화면 거부)
//  MAX_INK   : 도형 인정 최대 잉크 픽셀 수 (검은 화면 거부)
//  ASYM_THR  : 삼각형 판별 상하 비대칭 임계값 (픽셀 수 차이)
//              너무 낮으면 치우친 사각형이 삼각형으로 오인됨 → 50 이상 권장
// ──────────────────────────────────────────────────────────────────────────

module shape_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg  [1:0]  shape,       // 00=없음  01=○  10=△  11=□
    output reg         shape_valid  // frame_done 시점 1클럭 펄스
);

    localparam [7:0] INK_THR  = 8'd128;
    localparam [9:0] MIN_INK  = 10'd30;   // 이 미만 → 흰 화면 → NONE
    localparam [9:0] MAX_INK  = 10'd700;  // 이 초과 → 검은 화면 → NONE
    localparam [8:0] ASYM_THR = 9'd50;   // 삼각형 상하 비대칭 임계값

    localparam [1:0] NONE     = 2'b00;
    localparam [1:0] CIRCLE   = 2'b01;
    localparam [1:0] TRIANGLE = 2'b10;
    localparam [1:0] SQUARE   = 2'b11;

    // ── 픽셀 좌표 추적 ────────────────────────────────────────────────
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

    // ── 픽셀 속성 (조합 논리) ─────────────────────────────────────────
    wire is_ink     = sampled_valid && (sampled_pixel < INK_THR);
    wire is_top     = (row_cnt < 5'd14);
    wire is_bot     = (row_cnt >= 5'd14);
    wire is_row_end = sampled_valid && (col_cnt == 5'd27);

    // ── 누산기 ────────────────────────────────────────────────────────
    reg [9:0] total_ink;
    reg [8:0] top_ink;
    reg [8:0] bot_ink;
    reg [5:0] row_ink;    // 현재 행 잉크 픽셀 수 (max 28)
    reg [5:0] row_max_r;  // 지금까지 비어있지 않은 행의 최대 픽셀 수
    reg [5:0] row_min_r;  // 지금까지 비어있지 않은 행의 최소 픽셀 수 (초기 sentinel=28)

    wire [9:0] cur_total   = total_ink + (is_ink          ? 10'd1 : 10'd0);
    wire [8:0] cur_top     = top_ink   + (is_ink && is_top ?  9'd1 :  9'd0);
    wire [8:0] cur_bot     = bot_ink   + (is_ink && is_bot ?  9'd1 :  9'd0);
    wire [5:0] cur_row_ink = row_ink   + (is_ink           ?  6'd1 :  6'd0);

    // frame_done 시 마지막 행(row 27)까지 포함한 최종 max/min
    wire [5:0] final_row_max = (cur_row_ink > row_max_r) ? cur_row_ink : row_max_r;
    wire [5:0] final_row_min = (cur_row_ink > 6'd0 && cur_row_ink < row_min_r)
                               ? cur_row_ink : row_min_r;

    // ── 분류 조건 (조합 논리) ─────────────────────────────────────────
    wire [8:0] asym = (cur_bot >= cur_top) ? (cur_bot - cur_top) :
                                              (cur_top - cur_bot);

    // 사각형 조건: 2 × min > max  (모든 행 폭이 균일 → 크기·위치 무관)
    // 원:  min이 max보다 훨씬 작음 (위아래 행이 좁음) → 조건 불성립
    // 삼각형: min ≈ 0 (꼭짓점 행) → 조건 불성립
    wire is_sq = (final_row_min != 6'd0) &&
                 ({final_row_min, 1'b0} > {1'b0, final_row_max});
    //           ↑ 7비트: 2*min         ↑ 7비트: max (MSB=0)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            total_ink  <= 10'd0;
            top_ink    <=  9'd0;
            bot_ink    <=  9'd0;
            row_ink    <=  6'd0;
            row_max_r  <=  6'd0;
            row_min_r  <=  6'd28;
            shape      <= NONE;
            shape_valid <= 1'b0;
        end else begin
            shape_valid <= 1'b0;

            if (frame_done) begin
                // ── 분류 ──────────────────────────────────────────────
                if (cur_total < MIN_INK || cur_total > MAX_INK)
                    shape <= NONE;      // 흰 화면 or 검은 화면
                else if (is_sq)
                    shape <= SQUARE;    // 행 균일 → 치우쳐 있어도 정상 검출
                else if (asym > ASYM_THR)
                    shape <= TRIANGLE;  // 상하 비대칭
                else
                    shape <= CIRCLE;    // 대칭 + 행 불균일

                shape_valid <= 1'b1;

                // ── 리셋 ──────────────────────────────────────────────
                total_ink  <= 10'd0;
                top_ink    <=  9'd0;
                bot_ink    <=  9'd0;
                row_ink    <=  6'd0;
                row_max_r  <=  6'd0;
                row_min_r  <=  6'd28;

            end else if (is_row_end) begin
                // ── 행 끝: max/min 갱신 후 row_ink 리셋 ─────────────
                if (cur_row_ink > 6'd0) begin
                    if (cur_row_ink > row_max_r) row_max_r <= cur_row_ink;
                    if (cur_row_ink < row_min_r) row_min_r <= cur_row_ink;
                end
                row_ink   <= 6'd0;
                total_ink <= cur_total;
                top_ink   <= cur_top;
                bot_ink   <= cur_bot;

            end else if (sampled_valid) begin
                // ── 픽셀 누산 ─────────────────────────────────────────
                row_ink   <= cur_row_ink;
                total_ink <= cur_total;
                top_ink   <= cur_top;
                bot_ink   <= cur_bot;
            end
        end
    end

endmodule
