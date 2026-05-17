`timescale 1ns / 1ps

// 도형 분류기: 28×28 pixel stream → ○ / □ / +×
//
// 입력 도형 형태:
//   ○ : 가운데가 꽉 찬 원. 주변(surrounding 8셀)보다 g11(중앙)이 많아야 함.
//       → 작게 그릴수록 잘 됨. 너무 크게 그리면 주변에도 잉크가 넘쳐 십자로 오인 가능.
//   □ : 속이 빈 윤곽선 사각형. g11(중앙)은 거의 비어있어야 함.
//       회전해도 g11이 비어있으면 검출 유지됨.
//   +×: 가운데(g11)가 차있고, 팔 방향이 편중.
//       + : plus_arms(위아래좌우 4셀) >> corner(대각 4셀)
//       × : corner(대각 4셀) >> plus_arms(위아래좌우 4셀)
//       둘 다 같은 출력(11).
//
// 3×3 grid (9/10/9 분할):
//   [g00][g01][g02]
//   [g10][g11][g12]    g11 = 중앙 셀 (10×10 = 최대 100px)
//   [g20][g21][g22]
//
//   plus_arms  = g01+g10+g12+g21  (축 방향 4셀, max ~400)
//   corner_ink = g00+g02+g20+g22  (대각 방향 4셀, max ~400)
//   surround   = plus_arms + corner_ink  (g11 제외 전체)
//
// 판정 (우선순위 순):
//   NONE    : total < MIN_INK        → 흰 배경
//             total > MAX_INK        → 검은 배경 (is_dark=1)
//   ○       : g11 >= MIN_CIRCLE_G11  AND  g11 > surround  (중앙 > 주변 합)
//   □       : g11 <= MAX_HOLLOW      AND  corner >= MIN_SQUARE_CORNER
//   +×      : g11 >= MIN_CENTER_INK  AND  (plus >> corner 또는 corner >> plus)
//   UNKNOWN : 유효 잉크이나 조건 미충족 (is_unknown=1)
//
// LED 인코딩 (top_camera_shape 기준):
//   4'b0000 : 흰 배경
//   4'b1111 : 검은 배경
//   4'b1010 : 미인식 (UNKNOWN)
//   4'b0001 : ○
//   4'b0111 : □
//   4'b1110 : +×

module shape_classifier (
    input  wire        clk,
    input  wire        rst,
    input  wire [7:0]  sampled_pixel,
    input  wire        sampled_valid,
    input  wire        frame_done,
    output reg  [1:0]  shape,       // 00=없음/미인식  01=○  10=□  11=+×
    output reg         shape_valid, // frame_done 시점 1클럭 펄스
    output reg         is_dark,     // 1=검은 배경
    output reg         is_unknown   // 1=유효 잉크이나 미인식 → LED 1010
);

    // ── 파라미터 ──────────────────────────────────────────────────────────
    localparam [7:0]  INK_THR          = 8'd80;
    localparam [9:0]  MIN_INK          = 10'd30;
    localparam [9:0]  MAX_INK          = 10'd280;

    localparam [9:0]  MIN_CIRCLE_G11   = 10'd40;   // 원: g11 최소 잉크
    // 원의 핵심 조건: g11 > surround (중앙이 주변 합보다 많음)

    localparam [9:0]  MAX_HOLLOW       = 10'd20;   // 사각형: g11 최대 (속 빔)
    localparam [9:0]  MIN_SQUARE_CORNER= 10'd40;   // 사각형: corner_ink 최소

    localparam [9:0]  MIN_CENTER_INK   = 10'd10;   // 십자: g11 최소
    localparam [9:0]  MAX_CROSS_MINOR  = 10'd60;   // 십자: 비주(非主) 방향 상한

    localparam [1:0] NONE   = 2'b00;
    localparam [1:0] CIRCLE = 2'b01;
    localparam [1:0] SQUARE = 2'b10;
    localparam [1:0] CROSS  = 2'b11;

    // ── 픽셀 좌표 ─────────────────────────────────────────────────────────
    reg [4:0] row_cnt;
    reg [4:0] col_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            row_cnt <= 5'd0; col_cnt <= 5'd0;
        end else if (frame_done) begin
            row_cnt <= 5'd0; col_cnt <= 5'd0;
        end else if (sampled_valid) begin
            if (col_cnt == 5'd27) begin
                col_cnt <= 5'd0;
                row_cnt <= (row_cnt == 5'd27) ? 5'd0 : row_cnt + 5'd1;
            end else begin
                col_cnt <= col_cnt + 5'd1;
            end
        end
    end

    // ── grid 영역 (9/10/9 분할) ──────────────────────────────────────────
    wire is_ink    = sampled_valid && (sampled_pixel < INK_THR);
    wire row_top   = (row_cnt <= 5'd8);
    wire row_mid   = (row_cnt >= 5'd9)  && (row_cnt <= 5'd18);
    wire row_bot   = (row_cnt >= 5'd19);
    wire col_left  = (col_cnt <= 5'd8);
    wire col_mid   = (col_cnt >= 5'd9)  && (col_cnt <= 5'd18);
    wire col_right = (col_cnt >= 5'd19);

    // ── 누산기 ────────────────────────────────────────────────────────────
    reg [9:0] total_ink;
    reg [9:0] g00, g01, g02, g10, g11, g12, g20, g21, g22;

    wire [9:0] c_total = total_ink + (is_ink                              ? 10'd1 : 10'd0);
    wire [9:0] c_g00   = g00 + (is_ink && row_top && col_left            ? 10'd1 : 10'd0);
    wire [9:0] c_g01   = g01 + (is_ink && row_top && col_mid             ? 10'd1 : 10'd0);
    wire [9:0] c_g02   = g02 + (is_ink && row_top && col_right           ? 10'd1 : 10'd0);
    wire [9:0] c_g10   = g10 + (is_ink && row_mid && col_left            ? 10'd1 : 10'd0);
    wire [9:0] c_g11   = g11 + (is_ink && row_mid && col_mid             ? 10'd1 : 10'd0);
    wire [9:0] c_g12   = g12 + (is_ink && row_mid && col_right           ? 10'd1 : 10'd0);
    wire [9:0] c_g20   = g20 + (is_ink && row_bot && col_left            ? 10'd1 : 10'd0);
    wire [9:0] c_g21   = g21 + (is_ink && row_bot && col_mid             ? 10'd1 : 10'd0);
    wire [9:0] c_g22   = g22 + (is_ink && row_bot && col_right           ? 10'd1 : 10'd0);

    // ── 특징량 ────────────────────────────────────────────────────────────
    wire [11:0] corner_ink  = {2'b0,c_g00}+{2'b0,c_g02}+{2'b0,c_g20}+{2'b0,c_g22};
    wire [11:0] plus_arms   = {2'b0,c_g01}+{2'b0,c_g10}+{2'b0,c_g12}+{2'b0,c_g21};
    wire [12:0] surround    = {1'b0,corner_ink} + {1'b0,plus_arms};  // g11 제외 전체 합

    wire [12:0] twice_corner = {1'b0,corner_ink} + {1'b0,corner_ink};
    wire [12:0] twice_plus   = {1'b0,plus_arms}  + {1'b0,plus_arms};

    // ── 분류 조건 ─────────────────────────────────────────────────────────
    wire valid_ink = (c_total >= MIN_INK) && (c_total <= MAX_INK);

    // ○ 원: 중앙(g11)이 주변 8셀 합보다 큼 → 가운데 집중형
    wire circle_cond = valid_ink &&
                       (c_g11 >= MIN_CIRCLE_G11) &&
                       ({3'b0, c_g11} > surround);

    // □ 사각형: 중앙이 거의 비어있고 꼭짓점 존재
    wire square_cond = valid_ink && !circle_cond &&
                       (c_g11 <= MAX_HOLLOW) &&
                       (corner_ink >= {2'b0, MIN_SQUARE_CORNER});

    // +× 십자: 중앙 크고, plus_arms 또는 corner 중 하나가 반대편의 2배 이상
    wire cond_plus = ({1'b0,plus_arms}  > twice_corner) && (corner_ink < {2'b0,MAX_CROSS_MINOR});
    wire cond_diag = ({1'b0,corner_ink} > twice_plus)   && (plus_arms  < {2'b0,MAX_CROSS_MINOR});
    wire cross_cond = valid_ink && !circle_cond && !square_cond &&
                      (c_g11 >= MIN_CENTER_INK) && (cond_plus || cond_diag);

    // ── 순차 논리 ─────────────────────────────────────────────────────────
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            total_ink <= 10'd0;
            g00<=10'd0; g01<=10'd0; g02<=10'd0;
            g10<=10'd0; g11<=10'd0; g12<=10'd0;
            g20<=10'd0; g21<=10'd0; g22<=10'd0;
            shape <= NONE; shape_valid <= 1'b0;
            is_dark <= 1'b0; is_unknown <= 1'b0;
        end else begin
            shape_valid <= 1'b0;

            if (frame_done) begin
                if (!valid_ink) begin
                    shape <= NONE; is_dark <= (c_total > MAX_INK); is_unknown <= 1'b0;
                end else if (circle_cond) begin
                    shape <= CIRCLE; is_dark <= 1'b0; is_unknown <= 1'b0;
                end else if (square_cond) begin
                    shape <= SQUARE; is_dark <= 1'b0; is_unknown <= 1'b0;
                end else if (cross_cond) begin
                    shape <= CROSS;  is_dark <= 1'b0; is_unknown <= 1'b0;
                end else begin
                    shape <= NONE;   is_dark <= 1'b0; is_unknown <= 1'b1;
                end
                shape_valid <= 1'b1;
                total_ink <= 10'd0;
                g00<=10'd0; g01<=10'd0; g02<=10'd0;
                g10<=10'd0; g11<=10'd0; g12<=10'd0;
                g20<=10'd0; g21<=10'd0; g22<=10'd0;

            end else if (sampled_valid) begin
                total_ink <= c_total;
                g00<=c_g00; g01<=c_g01; g02<=c_g02;
                g10<=c_g10; g11<=c_g11; g12<=c_g12;
                g20<=c_g20; g21<=c_g21; g22<=c_g22;
            end
        end
    end

endmodule
