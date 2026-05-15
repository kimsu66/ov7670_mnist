`timescale 1ns / 1ps

module top(
    input  wire       clk,

    input  wire [7:0] cam_d,
    input  wire       cam_vsync,
    input  wire       cam_pclk,
    input  wire       cam_href,

    output wire       cam_scl,
    inout  wire       cam_sda,
    output wire       cam_rst,
    output wire       cam_xclk,
    output wire       cam_pwdn,

    output wire [2:0] led,

    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync
);

    // =====================
    // Camera basic control
    // =====================
    assign cam_rst  = 1'b1;
    assign cam_pwdn = 1'b0;

    // =========================
    // 100MHz -> 25MHz (VGA pixel clock + cam XCLK)
    // =========================
    reg [1:0] div4_reg = 2'd0;
    always @(posedge clk) begin
        div4_reg <= div4_reg + 2'd1;
    end
    wire clk_25mhz;
    assign clk_25mhz = div4_reg[1];
    assign cam_xclk  = clk_25mhz;

    // =====================
    // OV7670 init
    // =====================
    wire init_done;

    ov7670_init u_init (
        .clk      (clk),
        .resetn   (1'b1),
        .scl      (cam_scl),
        .sda      (cam_sda),
        .done     (init_done)
    );

    // =========================
    // OV7670 capture (QVGA 320x240, grayscale)
    // =========================
    wire  [7:0] pixel_data;
    wire        pixel_valid;
    wire [16:0] write_addr;

    ov7670_capture capture(
        .pclk       (cam_pclk),
        .vsync      (cam_vsync),
        .href       (cam_href),
        .d          (cam_d),
        .pixel_data (pixel_data),
        .pixel_valid(pixel_valid),
        .addr       (write_addr)
    );

    // =========================
    // VGA timing generator
    // =========================
    wire [9:0] vga_x;
    wire [9:0] vga_y;
    wire       vga_active;

    vga_controller u_vga (
        .clk    (clk_25mhz),
        .x      (vga_x),
        .y      (vga_y),
        .Hsync  (Hsync),
        .Vsync  (Vsync),
        .active (vga_active)
    );

    // =========================
    // Frame buffer read address
    // 320x240 image -> 좌상단 1:1 출력
    // =========================
    wire [8:0]  fb_x      = vga_x[8:0];
    wire [7:0]  fb_y      = vga_y[7:0];
    wire        img_active = (vga_x < 10'd320) && (vga_y < 10'd240);
    // read_addr = fb_y*320 + fb_x = fb_y*256 + fb_y*64 + fb_x
    wire [16:0] read_addr = {1'b0, fb_y, 8'b0} + {3'b0, fb_y, 6'b0} + {8'b0, fb_x};

    // =========================
    // Frame buffer (dual-port BRAM, 320x240 x 8-bit grayscale Y)
    // =========================
    wire  [7:0] pixel_out;

    frame_buffer u_fb (
        .clk_write  (cam_pclk),
        .write_en   (pixel_valid),
        .write_addr (write_addr),
        .pixel_in   (pixel_data),

        .clk_read   (clk_25mhz),
        .read_addr  (read_addr),
        .pixel_out  (pixel_out)
    );

    // =========================
    // 박스 영역 정의 (중앙 140×140)
    // x: 90~229, y: 50~189
    // =========================
    wire in_box_h = (vga_x >= 10'd90)  && (vga_x <= 10'd229);
    wire in_box_v = (vga_y >= 10'd50)  && (vga_y <= 10'd189);

    // 빨간 박스 테두리 (2픽셀 두께)
    wire on_border = (
        ((vga_x == 10'd90  || vga_x == 10'd91  ||
        vga_x == 10'd228 || vga_x == 10'd229) && in_box_v) ||
        ((vga_y == 10'd50  || vga_y == 10'd51  ||
        vga_y == 10'd188 || vga_y == 10'd189) && in_box_h)
    );

    // 파란 박스: 56×56 샘플링 영역 표시 (center: 160, 120), 2픽셀 두께
    wire in_blue_h = (vga_x >= 10'd132) && (vga_x <= 10'd187);
    wire in_blue_v = (vga_y >= 10'd92)  && (vga_y <= 10'd147);
    wire on_blue_border = (
        ((vga_x == 10'd132 || vga_x == 10'd133 ||
          vga_x == 10'd186 || vga_x == 10'd187) && in_blue_v) ||
        ((vga_y == 10'd92  || vga_y == 10'd93  ||
          vga_y == 10'd146 || vga_y == 10'd147) && in_blue_h)
    );

    // =========================
    // VGA output
    // =========================
    wire [3:0] gray4 = pixel_out[7:4];

    assign vgaRed   = (vga_active && img_active) ? (on_border ? 4'hF : (on_blue_border ? 4'h0 : gray4)) : 4'b0000;
    assign vgaGreen = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'h0 : gray4)) : 4'b0000;
    assign vgaBlue  = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'hF : gray4)) : 4'b0000;

    // // =========================
    // // VGA output (YUV Y채널 흑백)
    // // =========================
    // wire [3:0] gray4 = pixel_out[7:4];

    // assign vgaRed   = (vga_active && img_active) ? gray4 : 4'b0000;
    // assign vgaGreen = (vga_active && img_active) ? gray4 : 4'b0000;
    // assign vgaBlue  = (vga_active && img_active) ? gray4 : 4'b0000;

    // // =========================
    // // LEDs
    // // =========================
    // assign led[0] = init_done;
    // assign led[1] = cam_vsync;
    // assign led[2] = cam_href;

endmodule
