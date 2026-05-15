`timescale 1ns / 1ps

// OV7670 카메라 + 도형 인식 탑 모듈
//
// 파이프라인:
//   OV7670 → frame_buffer → box_sampler(56×56→28×28) → shape_classifier → LED
//
// LED 인코딩:
//   4'b0000 : 도형 없음
//   4'b0001 : ○ (원)
//   4'b0111 : △ (삼각형)
//   4'b1111 : □ (사각형)
//
// 4프레임 연속 동일 결과 시 LED 갱신 (흔들림 방지)

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
    wire        img_active = (vga_x < 10'd320) && (vga_y < 10'd240);
    wire [16:0] read_addr  = {1'b0, fb_y, 8'b0}
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
    // VGA 출력 (샘플링 영역 오버레이)
    // 빨간 박스: 전체 관심 영역 (140×140)
    // 파란 박스: 56×56 실제 샘플링 영역
    // ============================================================
    wire in_box_h    = (vga_x >= 10'd90)  && (vga_x <= 10'd229);
    wire in_box_v    = (vga_y >= 10'd50)  && (vga_y <= 10'd189);
    wire on_border   = (
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

    assign vgaRed   = (vga_active && img_active) ? (on_border ? 4'hF : (on_blue_border ? 4'h0 : gray4)) : 4'b0;
    assign vgaGreen = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'h0 : gray4)) : 4'b0;
    assign vgaBlue  = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'hF : gray4)) : 4'b0;

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
    // shape_classifier: 28×28 스트림 → ○ △ □ 분류
    // ============================================================
    wire [1:0] shape;
    wire       shape_valid;

    shape_classifier u_shape (
        .clk          (clk_25mhz),
        .rst          (1'b0),
        .sampled_pixel(sampled_pixel),
        .sampled_valid(sampled_valid),
        .frame_done   (frame_done),
        .shape        (shape),
        .shape_valid  (shape_valid)
    );

    // ============================================================
    // LED 출력 (4프레임 연속 동일 결과 시 갱신)
    //   4'b0000 : 없음
    //   4'b0001 : ○
    //   4'b0111 : △
    //   4'b1111 : □
    // ============================================================
    reg [3:0] led_reg    = 4'b0000;
    reg [1:0] last_shape = 2'b00;
    reg [2:0] stable_cnt = 3'd0;

    always @(posedge clk_25mhz) begin
        if (shape_valid) begin
            if (shape == 2'b00) begin
                led_reg    <= 4'b0000;
                stable_cnt <= 3'd0;
                last_shape <= 2'b00;
            end else if (shape == last_shape) begin
                if (stable_cnt < 3'd4)
                    stable_cnt <= stable_cnt + 3'd1;
                if (stable_cnt >= 3'd4) begin
                    case (shape)
                        2'b01:   led_reg <= 4'b0001;  // ○
                        2'b10:   led_reg <= 4'b0111;  // △
                        2'b11:   led_reg <= 4'b1111;  // □
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
