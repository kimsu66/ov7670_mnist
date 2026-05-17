`timescale 1ns / 1ps

// 도형 분류기: 28×28 픽셀 스트림 → ○ △ + 판별
//
// 입력 극성: INK_THR 미만 픽셀 = 잉크 (밝은 배경 + 어두운 마커 기준)
//
// 분류 순서:
//   1. 잉크 범위 밖                          → NONE
//   2. corner_ink < CORNER_THR               → CROSS (+)
//   3. 상하 비대칭 > ASYM_THR                → TRIANGLE (△)
//   4. 나머지                                → CIRCLE (○)
//
// ── 핵심 원리 ──────────────────────────────────────────────────────────────
//
//  십자(+): 4개 코너 구역(8×8)에 잉크가 없음  → corner_ink 매우 낮음
//  원  (○): 호(arc)가 대각선 코너 구역을 통과 → corner_ink 높음
//  삼각형(△): 밑변 양쪽 코너에 잉크 있음      → corner_ink 높음 + 상하 비대칭
//
//  코너 구역 정의: row 0~7 또는 20~27, col 0~7 또는 20~27 (각 8×8 = 64px, 4개)
//
// ── 조정 파라미터 ─────────────────────────────────────────────────────────
//  INK_THR    : 잉크 판별 밝기 경계
//  MIN_INK    : 도형 인정 최소 잉크 픽셀 수 (흰 화면 거부)
//  MAX_INK    : 도형 인정 최대 잉크 픽셀 수 (검은 화면 거부)
//  CORNER_THR : 십자 판별 코너 잉크 임계값 (이 미만 → 십자)
//               너무 높으면 작은 원도 십자로 오인, 너무 낮으면 굵은 십자 오인
//  ASYM_THR   : 삼각형 판별 상하 비대칭 임계값
// ──────────────────────────────────────────────────────────────────────────

module shape_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg  [1:0]  shape,       // 00=없음  01=○  10=△  11=+
    output reg         shape_valid, // frame_done 시점 1클럭 펄스
    output reg         is_dark      // 1=NONE이 검은 화면(잉크 과다), 0=흰 화면(잉크 부족)
);

    localparam [7:0] INK_THR    = 8'd128;
    localparam [9:0] MIN_INK    = 10'd30;
    localparam [9:0] MAX_INK    = 10'd700;
    localparam [8:0] CORNER_THR = 9'd15;  // 십자: 코너 잉크 이 미만
    localparam [8:0] ASYM_THR   = 9'd50;  // 삼각형 상하 비대칭 임계값

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
    wire is_ink    = sampled_valid && (sampled_pixel < INK_THR);
    wire is_top    = (row_cnt < 5'd14);
    wire is_bot    = (row_cnt >= 5'd14);
    // 코너 구역: (row 0~7 또는 20~27) AND (col 0~7 또는 20~27)
    wire is_corner = is_ink &&
                     ((row_cnt <= 5'd7) || (row_cnt >= 5'd20)) &&
                     ((col_cnt <= 5'd7) || (col_cnt >= 5'd20));

    // ── 누산기 ────────────────────────────────────────────────────────────
    reg  [9:0] total_ink;
    reg  [8:0] top_ink;
    reg  [8:0] bot_ink;
    reg  [8:0] corner_ink;  // 최대 4×8×8=256 → 9비트

    wire [9:0] cur_total  = total_ink  + (is_ink    ? 10'd1 : 10'd0);
    wire [8:0] cur_top    = top_ink    + (is_ink && is_top ? 9'd1 : 9'd0);
    wire [8:0] cur_bot    = bot_ink    + (is_ink && is_bot ? 9'd1 : 9'd0);
    wire [8:0] cur_corner = corner_ink + (is_corner ? 9'd1 : 9'd0);

    // ── 분류 조건 (조합 논리) ─────────────────────────────────────────────
    wire [8:0] asym = (cur_bot >= cur_top) ? (cur_bot - cur_top) :
                                              (cur_top - cur_bot);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            total_ink  <= 10'd0;
            top_ink    <=  9'd0;
            bot_ink    <=  9'd0;
            corner_ink <=  9'd0;
            shape      <= NONE;
            shape_valid <= 1'b0;
            is_dark    <= 1'b0;
        end else begin
            shape_valid <= 1'b0;

            if (frame_done) begin
                // ── 분류 ──────────────────────────────────────────────────
                if (cur_total < MIN_INK || cur_total > MAX_INK) begin
                    shape   <= NONE;
                    is_dark <= (cur_total > MAX_INK);  // 과다=검정, 부족=흰색
                end else if (cur_corner < CORNER_THR) begin
                    shape   <= CROSS;     // 코너에 잉크 없음 → 십자
                    is_dark <= 1'b0;
                end else if (asym > ASYM_THR) begin
                    shape   <= TRIANGLE;  // 상하 비대칭 → 삼각형
                    is_dark <= 1'b0;
                end else begin
                    shape   <= CIRCLE;    // 대칭 + 코너에 잉크 있음 → 원
                    is_dark <= 1'b0;
                end

                shape_valid <= 1'b1;

                // ── 리셋 ──────────────────────────────────────────────────
                total_ink  <= 10'd0;
                top_ink    <=  9'd0;
                bot_ink    <=  9'd0;
                corner_ink <=  9'd0;

            end else if (sampled_valid) begin
                // ── 픽셀 누산 ─────────────────────────────────────────────
                total_ink  <= cur_total;
                top_ink    <= cur_top;
                bot_ink    <= cur_bot;
                corner_ink <= cur_corner;
            end
        end
    end

endmodule
