`timescale 1ns / 1ps

// OV7670 카메라 + 도형 인식 탑 모듈
//
// 파이프라인:
//   OV7670 → frame_buffer → box_sampler(56×56→28×28) → shape_classifier → LED
//
// 화면 구성:
//   좌(0~319): 카메라 원본 + 빨간(140×140)/파란(56×56) 박스 오버레이
//   구분선(326~329): 흰색 세로선
//   우(340~619): 28×28 스냅샷 × 10배 (280×280) 업스케일 표시
//
// LED 인코딩:
//   4'b0000 : 흰 배경 (잉크 부족 → 아무것도 없는 화면)
//   4'b1111 : 검은 배경 (잉크 과다 → 카메라 가려짐)
//   4'b1010 : 미인식 (유효 잉크이나 도형 조건 미충족)
//   4'b0001 : ○ (원, 채워진)
//   4'b0111 : □ (사각형, 속 빈 윤곽선)
//   4'b1110 : +× (십자 또는 대각 십자)
//
// 4프레임 연속 동일 결과 시 LED 갱신 (흔들림 방지, NONE 제외)

module top_camera_shape (
    input  wire       clk,          // 100 MHz 시스템 클럭

    // OV7670 카메라
    input  wire [7:0] cam_d,
    input  wire       cam_vsync,
    input  wire       cam_pclk,
    input  wire       cam_href,
    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_rst,
    output wire       cam_xclk,
    output wire       cam_pwdn,

    // VGA
    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync,

    // LED: 인식된 도형
    output wire [3:0] led
);

    // ============================================================
    // 100MHz → 25MHz (VGA 픽셀 클럭 / 카메라 XCLK)
    // ============================================================
    reg [1:0] div4 = 2'd0;
    always @(posedge clk) div4 <= div4 + 2'd1;
    wire clk_25mhz = div4[1];

    assign cam_xclk = clk_25mhz;
    assign cam_rst  = 1'b1;
    assign cam_pwdn = 1'b0;

    // ============================================================
    // OV7670 I2C 초기화
    // ============================================================
    ov7670_init u_init (
        .clk    (clk),
        .resetn (1'b1),
        .scl    (cam_scl),
        .sda    (cam_sda),
        .done   ()
    );

    // ============================================================
    // OV7670 캡처 → 프레임 버퍼 쓰기
    // ============================================================
    wire [7:0]  pixel_data;
    wire        pixel_valid;
    wire [16:0] write_addr;

    ov7670_capture u_capture (
        .pclk        (cam_pclk),
        .vsync       (cam_vsync),
        .href        (cam_href),
        .d           (cam_d),
        .pixel_data  (pixel_data),
        .pixel_valid (pixel_valid),
        .addr        (write_addr)
    );

    // ============================================================
    // VGA 타이밍 컨트롤러 (25MHz)
    // ============================================================
    wire [9:0] vga_x, vga_y;
    wire       vga_active;

    vga_controller u_vga (
        .clk    (clk_25mhz),
        .x      (vga_x),
        .y      (vga_y),
        .Hsync  (Hsync),
        .Vsync  (Vsync),
        .active (vga_active)
    );

    // ============================================================
    // 프레임 버퍼 (320×240 그레이스케일)
    // ============================================================
    wire [8:0]  fb_x      = vga_x[8:0];
    wire [7:0]  fb_y      = vga_y[7:0];
    wire [16:0] read_addr = {1'b0, fb_y, 8'b0}
                          + {3'b0, fb_y, 6'b0}
                          + {8'b0, fb_x};
    wire [7:0] pixel_out;

    frame_buffer u_fb (
        .clk_write  (cam_pclk),
        .write_en   (pixel_valid),
        .write_addr (write_addr),
        .pixel_in   (pixel_data),
        .clk_read   (clk_25mhz),
        .read_addr  (read_addr),
        .pixel_out  (pixel_out)
    );

    // ============================================================
    // box_sampler: 56×56 영역 → 2×2 평균 풀링 → 28×28
    // ============================================================
    wire [7:0] sampled_pixel;
    wire       sampled_valid;
    wire       frame_done;

    box_sampler u_sampler (
        .clk          (clk_25mhz),
        .rst          (1'b0),
        .pixel_in     (pixel_out),
        .vga_x        (vga_x),
        .vga_y        (vga_y),
        .sampled_pixel(sampled_pixel),
        .sampled_valid(sampled_valid),
        .frame_done   (frame_done)
    );

    // ============================================================
    // shape_classifier: 28×28 스트림 → ○ □ + 분류
    // ============================================================
    wire [1:0] shape;
    wire       shape_valid;
    wire       is_dark;
    wire       is_unknown;

    shape_classifier u_shape (
        .clk          (clk_25mhz),
        .rst          (1'b0),
        .sampled_pixel(sampled_pixel),
        .sampled_valid(sampled_valid),
        .frame_done   (frame_done),
        .shape        (shape),
        .shape_valid  (shape_valid),
        .is_dark      (is_dark),
        .is_unknown   (is_unknown)
    );

    // ============================================================
    // 28×28 픽셀 버퍼 (sampled_valid 순서대로 순차 저장)
    // shape_classifier에 들어가는 바로 그 픽셀을 동일하게 저장
    // ============================================================
    reg [7:0] pixel_buf [0:783];
    reg [9:0] buf_wr_cnt = 10'd0;

    always @(posedge clk_25mhz) begin
        if (sampled_valid) begin
            pixel_buf[buf_wr_cnt] <= sampled_pixel;
            buf_wr_cnt <= frame_done ? 10'd0 : buf_wr_cnt + 10'd1;
        end else if (frame_done) begin
            buf_wr_cnt <= 10'd0;
        end
    end

    // ============================================================
    // 스냅샷 버퍼: frame_done 후 pixel_buf 전체 복사
    // (VGA 렌더링 중 pixel_buf가 덮어쓰이는 것을 방지)
    // ============================================================
    reg [7:0] snapshot_buf [0:783];
    reg [9:0] copy_cnt = 10'd0;
    reg       copying  = 1'b0;

    reg frame_done_d = 1'b0;
    always @(posedge clk_25mhz) frame_done_d <= frame_done;

    always @(posedge clk_25mhz) begin
        if (frame_done_d && !copying) begin
            copying  <= 1'b1;
            copy_cnt <= 10'd0;
        end
        if (copying) begin
            snapshot_buf[copy_cnt] <= pixel_buf[copy_cnt];
            if (copy_cnt == 10'd783)
                copying <= 1'b0;
            else
                copy_cnt <= copy_cnt + 10'd1;
        end
    end

    // ============================================================
    // VGA 좌측: 카메라 원본 + 오버레이 박스
    //   빨간 박스: 140×140 관심 영역 (x:90~229, y:50~189)
    //   파란 박스: 56×56 실제 샘플링 영역 (x:132~187, y:92~147)
    // ============================================================
    wire in_cam    = (vga_x < 10'd320) && (vga_y < 10'd240);
    wire in_box_h  = (vga_x >= 10'd90)  && (vga_x <= 10'd229);
    wire in_box_v  = (vga_y >= 10'd50)  && (vga_y <= 10'd189);
    wire on_border = (
        ((vga_x == 10'd90  || vga_x == 10'd91  ||
          vga_x == 10'd228 || vga_x == 10'd229) && in_box_v) ||
        ((vga_y == 10'd50  || vga_y == 10'd51  ||
          vga_y == 10'd188 || vga_y == 10'd189) && in_box_h)
    );
    wire in_blue_h      = (vga_x >= 10'd132) && (vga_x <= 10'd187);
    wire in_blue_v      = (vga_y >= 10'd92)  && (vga_y <= 10'd147);
    wire on_blue_border = (
        ((vga_x == 10'd132 || vga_x == 10'd133 ||
          vga_x == 10'd186 || vga_x == 10'd187) && in_blue_v) ||
        ((vga_y == 10'd92  || vga_y == 10'd93  ||
          vga_y == 10'd146 || vga_y == 10'd147) && in_blue_h)
    );
    wire [3:0] gray4 = pixel_out[7:4];

    // ============================================================
    // 가운데 구분선 (x: 326~329, 흰색 4픽셀)
    // ============================================================
    wire on_divider = (vga_x >= 10'd326) && (vga_x <= 10'd329);

    // ============================================================
    // VGA 우측: 280×280 업스케일 표시
    //   가로 중앙: 320 + (320-280)/2 = 340  →  x: 340~619
    //   세로 중앙: (480-280)/2 = 100         →  y: 100~379
    //
    // /10 근사: floor(n * 205 / 2048)  (n=0..279, 오차 없음)
    // ============================================================
    localparam [9:0] UP_X0 = 10'd340;
    localparam [9:0] UP_Y0 = 10'd100;

    wire in_up_h = (vga_x >= UP_X0) && (vga_x < UP_X0 + 10'd280);
    wire in_up_v = (vga_y >= UP_Y0) && (vga_y < UP_Y0 + 10'd280);
    wire in_up   = in_up_h && in_up_v;

    wire [8:0]  vx_loc  = vga_x - UP_X0;
    wire [8:0]  vy_loc  = vga_y - UP_Y0;
    wire [17:0] vx_prod = {9'b0, vx_loc} * 18'd205;
    wire [17:0] vy_prod = {9'b0, vy_loc} * 18'd205;
    wire [4:0]  col_28  = vx_prod[15:11];   // 0..27
    wire [4:0]  row_28  = vy_prod[15:11];   // 0..27

    // buf_addr = row_28 * 28 + col_28
    wire [9:0] buf_addr = ({5'b0, row_28} << 5)
                        - ({5'b0, row_28} << 2)
                        + {5'b0, col_28};

    wire [3:0] up_gray     = snapshot_buf[buf_addr][7:4];
    wire       on_up_border = in_up && (
        vga_x == UP_X0           || vga_x == UP_X0 + 10'd279 ||
        vga_y == UP_Y0           || vga_y == UP_Y0 + 10'd279
    );

    // ============================================================
    // 3×3 grid 오버레이 (우측 패널)
    //
    // 28픽셀을 9/10/9로 분할 → ×10배 → 90/100/90 픽셀
    // 경계: x or y 방향 offset 90, 190 (= 90+100) 위치에 2픽셀 빨간 선
    // ============================================================
    wire on_grid = in_up && (
        (vga_x == UP_X0 + 10'd90)  || (vga_x == UP_X0 + 10'd91)  ||
        (vga_x == UP_X0 + 10'd190) || (vga_x == UP_X0 + 10'd191) ||
        (vga_y == UP_Y0 + 10'd90)  || (vga_y == UP_Y0 + 10'd91)  ||
        (vga_y == UP_Y0 + 10'd190) || (vga_y == UP_Y0 + 10'd191)
    );

    // ============================================================
    // VGA 출력 합성 (좌: 카메라 원본 / 우: 28×28 × 10배 업스케일)
    // ============================================================
    wire [3:0] out_r =
        on_divider    ? 4'hF :
        in_cam        ? (on_border ? 4'hF : (on_blue_border ? 4'h0 : gray4)) :
        on_grid       ? 4'hF :
        in_up         ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    wire [3:0] out_g =
        on_divider    ? 4'hF :
        in_cam        ? (on_border ? 4'h0 : (on_blue_border ? 4'h0 : gray4)) :
        on_grid       ? 4'h0 :
        in_up         ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    wire [3:0] out_b =
        on_divider    ? 4'hF :
        in_cam        ? (on_border ? 4'h0 : (on_blue_border ? 4'hF : gray4)) :
        on_grid       ? 4'h0 :
        in_up         ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    assign vgaRed   = vga_active ? out_r : 4'b0;
    assign vgaGreen = vga_active ? out_g : 4'b0;
    assign vgaBlue  = vga_active ? out_b : 4'b0;

    // ============================================================
    // LED 출력 (4프레임 연속 동일 결과 시 갱신, NONE/UNKNOWN은 즉시 반영)
    //   4'b0000 : 흰 배경 (NONE + 잉크 부족)
    //   4'b1111 : 검은 배경 (NONE + 잉크 과다 / 카메라 가려짐)
    //   4'b1010 : 미인식 (유효 잉크이나 도형 조건 미충족)
    //   4'b0001 : ○ (원, 채워진)
    //   4'b0111 : □ (사각형, 속 빈 윤곽선)
    //   4'b1110 : +× (십자 또는 대각 십자)
    // ============================================================
    reg [3:0] led_reg    = 4'b0000;
    reg [1:0] last_shape = 2'b00;
    reg [2:0] stable_cnt = 3'd0;

    always @(posedge clk_25mhz) begin
        if (shape_valid) begin
            if (shape == 2'b00) begin
                // NONE / UNKNOWN: 즉시 반영
                if (is_dark)
                    led_reg <= 4'b1111;
                else if (is_unknown)
                    led_reg <= 4'b1010;
                else
                    led_reg <= 4'b0000;
                stable_cnt <= 3'd0;
                last_shape <= 2'b00;
            end else if (shape == last_shape) begin
                if (stable_cnt < 3'd4)
                    stable_cnt <= stable_cnt + 3'd1;
                if (stable_cnt >= 3'd4) begin
                    case (shape)
                        2'b01:   led_reg <= 4'b0001;  // ○
                        2'b10:   led_reg <= 4'b0111;  // □
                        2'b11:   led_reg <= 4'b1110;  // +×
                        default: led_reg <= 4'b0000;
                    endcase
                end
            end else begin
                last_shape <= shape;
                stable_cnt <= 3'd0;
            end
        end
    end

    assign led = led_reg;

endmodule
