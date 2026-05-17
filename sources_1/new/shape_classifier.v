`timescale 1ns / 1ps

// 도형 분류기: 28×28 pixel stream → ○ / □ / +×
//
// 입력 도형 형태:
//   ○ : 내부가 꽉 채워진 검은 원
//   □ : 검은 윤곽선 + 흰 내부 (속 빈 사각형)
//   +×: 정축(+) 또는 45° 대각(×) 십자, 둘 다 같은 출력
//
// 3×3 grid (9/10/9 분할):  g00 g01 g02 / g10 g11 g12 / g20 g21 g22
//   plus_arms  = g01+g10+g12+g21  (축 방향 엣지 4셀)
//   corner_ink = g00+g02+g20+g22  (모서리 4셀)
//
// 판정 (우선순위 순):
//   NONE    : total < MIN_INK        → 흰 배경
//             total > MAX_INK        → 검은 배경 (is_dark=1)
//   +×      : g11 크고 (중앙 막대 교차)
//             + : plus_arms > 2×corner  AND  corner  < MAX_CROSS_MINOR
//             × : corner  > 2×plus_arms AND  plus_arms < MAX_CROSS_MINOR
//             ※ corner와 plus_arms가 둘 다 크면(=원) 오인 방지용 상한 적용
//   □       : g11 <= MAX_HOLLOW (속 빔)  AND  corner >= MIN_SQUARE_CORNER
//   ○       : corner >= MIN_CIRCLE_CORNER  AND  plus_arms >= MIN_CIRCLE_PLUS
//             AND  mid > top  AND  mid > bot  (행별 bell-curve)
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
    localparam [7:0]  INK_THR          = 8'd80;   // 80 미만(진한 검정)만 잉크로 인정
    localparam [9:0]  MIN_INK          = 10'd30;
    localparam [9:0]  MAX_INK          = 10'd280;  // 784px 중 ~36% 이상 → 검은 배경

    localparam [9:0]  MIN_CENTER_INK   = 10'd10;   // g11 최소 (십자 중앙)
    localparam [9:0]  MAX_CROSS_MINOR  = 10'd80;   // 십자 판정 시 비주(非主) 셀 상한
                                                    // (원: corner≈220, plus≈300 → 둘 다 80 초과 → 오인 차단)
    localparam [9:0]  MAX_HOLLOW       = 10'd20;   // g11 최대 (사각형 속 빔)
    localparam [9:0]  MIN_SQUARE_CORNER= 10'd40;   // corner_ink 최소 (사각형 꼭짓점)
    localparam [9:0]  MIN_CIRCLE_CORNER= 10'd60;   // corner_ink 최소 (원)
    localparam [9:0]  MIN_CIRCLE_PLUS  = 10'd80;   // plus_arms 최소 (원)

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
    wire [11:0] top_ink    = {2'b0,c_g00}+{2'b0,c_g01}+{2'b0,c_g02};
    wire [11:0] mid_ink    = {2'b0,c_g10}+{2'b0,c_g11}+{2'b0,c_g12};
    wire [11:0] bot_ink    = {2'b0,c_g20}+{2'b0,c_g21}+{2'b0,c_g22};
    wire [11:0] corner_ink = {2'b0,c_g00}+{2'b0,c_g02}+{2'b0,c_g20}+{2'b0,c_g22};
    wire [11:0] plus_arms  = {2'b0,c_g01}+{2'b0,c_g10}+{2'b0,c_g12}+{2'b0,c_g21};
    wire [12:0] twice_corner = {1'b0,corner_ink}+{1'b0,corner_ink};
    wire [12:0] twice_plus   = {1'b0,plus_arms} +{1'b0,plus_arms};

    // ── 분류 조건 ─────────────────────────────────────────────────────────
    wire valid_ink = (c_total >= MIN_INK) && (c_total <= MAX_INK);

    // +× : 중앙 크고, 주(主) 방향이 부(副) 방향의 2배 이상, 부 방향은 상한 이하
    //      (원은 corner≈220, plus≈300으로 둘 다 MAX_CROSS_MINOR 초과 → 오인 차단)
    wire cond_plus = ({1'b0,plus_arms}  > twice_corner) && (corner_ink < {2'b0,MAX_CROSS_MINOR});
    wire cond_diag = ({1'b0,corner_ink} > twice_plus)   && (plus_arms  < {2'b0,MAX_CROSS_MINOR});
    wire cross_cond = valid_ink && (c_g11 >= MIN_CENTER_INK) && (cond_plus || cond_diag);

    // □ : 속 빔(g11 작음) + 꼭짓점 존재
    wire square_cond = valid_ink && !cross_cond &&
                       (c_g11 <= MAX_HOLLOW) &&
                       (corner_ink >= {2'b0,MIN_SQUARE_CORNER});

    // ○ : 모든 방향 채워짐 + 행별 bell-curve
    wire circle_cond = valid_ink && !cross_cond && !square_cond &&
                       (corner_ink >= {2'b0,MIN_CIRCLE_CORNER}) &&
                       (plus_arms  >= {2'b0,MIN_CIRCLE_PLUS})   &&
                       (mid_ink > top_ink) && (mid_ink > bot_ink);

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
                end else if (cross_cond) begin
                    shape <= CROSS;  is_dark <= 1'b0; is_unknown <= 1'b0;
                end else if (square_cond) begin
                    shape <= SQUARE; is_dark <= 1'b0; is_unknown <= 1'b0;
                end else if (circle_cond) begin
                    shape <= CIRCLE; is_dark <= 1'b0; is_unknown <= 1'b0;
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
