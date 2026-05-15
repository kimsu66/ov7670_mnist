`timescale 1ns / 1ps

// 좌: 카메라 원본 (320×240, 빨강/파랑 오버레이)
// 우: 28×28 스냅샷 × 10배 업스케일 → 280×280 (오른쪽 반 중앙)
module top_2828 (
    input  wire       clk,        // 100 MHz

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
    output wire       Vsync
);

    // ============================================================
    // 100MHz → 25MHz
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
    // VGA 타이밍 컨트롤러 (25MHz, 640×480)
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
    // read_addr은 vga_x/y 기반 → box_sampler가 올바른 픽셀을 읽도록 유지
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
    // box_sampler: 56×56 → 2×2 풀링 → 28×28
    // 샘플 영역: vga_x[132,187], vga_y[92,147] — read_addr이 이 범위에서는 유효
    // ============================================================
    wire [7:0] sampled_pixel;
    wire       sampled_valid;
    wire       frame_done;

    box_sampler u_sampler (
        .clk           (clk_25mhz),
        .rst           (1'b0),
        .pixel_in      (pixel_out),
        .vga_x         (vga_x),
        .vga_y         (vga_y),
        .sampled_pixel (sampled_pixel),
        .sampled_valid (sampled_valid),
        .frame_done    (frame_done)
    );

    // ============================================================
    // 28×28 라이브 쓰기 버퍼
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
    // 28×28 스냅샷 버퍼 (frame_done 후 784사이클 복사)
    // ============================================================
    reg [7:0] snapshot_buf [0:783];
    reg [9:0] copy_cnt  = 10'd0;
    reg       copying   = 1'b0;

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
    // 왼쪽: 카메라 원본 (x: 0..319, y: 0..239)
    //   빨간 박스: 샘플링 외부 참조 영역 (90..229 × 50..189)
    //   파란 박스: box_sampler 실제 샘플링 영역 (132..187 × 92..147)
    // ============================================================
    wire in_cam = (vga_x < 10'd320) && (vga_y < 10'd240);

    wire in_red_h = (vga_x >= 10'd90)  && (vga_x <= 10'd229);
    wire in_red_v = (vga_y >= 10'd50)  && (vga_y <= 10'd189);
    wire on_red   = (
        ((vga_x == 10'd90  || vga_x == 10'd91  ||
          vga_x == 10'd228 || vga_x == 10'd229) && in_red_v) ||
        ((vga_y == 10'd50  || vga_y == 10'd51  ||
          vga_y == 10'd188 || vga_y == 10'd189) && in_red_h)
    );

    wire in_blue_h = (vga_x >= 10'd132) && (vga_x <= 10'd187);
    wire in_blue_v = (vga_y >= 10'd92)  && (vga_y <= 10'd147);
    wire on_blue   = (
        ((vga_x == 10'd132 || vga_x == 10'd133 ||
          vga_x == 10'd186 || vga_x == 10'd187) && in_blue_v) ||
        ((vga_y == 10'd92  || vga_y == 10'd93  ||
          vga_y == 10'd146 || vga_y == 10'd147) && in_blue_h)
    );

    wire [3:0] cam_gray = pixel_out[7:4];

    // ============================================================
    // 가운데 구분선 (x: 326..329, 흰색 4픽셀)
    // ============================================================
    wire on_divider = (vga_x >= 10'd326) && (vga_x <= 10'd329);

    // ============================================================
    // 오른쪽: 280×280 업스케일 (오른쪽 반 중앙)
    //   오른쪽 반: x 320..639 (폭 320)
    //   가로 중앙: 320 + (320-280)/2 = 340
    //   세로 중앙: (480-280)/2 = 100
    //   → x: 340..619,  y: 100..379
    //
    // 10 나누기 근사: floor(n × 205 / 2048), n ∈ [0,279] 오차 없음
    // ============================================================
    localparam [9:0] UP_X0 = 10'd340;
    localparam [9:0] UP_Y0 = 10'd100;

    wire in_up_h = (vga_x >= UP_X0) && (vga_x < UP_X0 + 10'd280);
    wire in_up_v = (vga_y >= UP_Y0) && (vga_y < UP_Y0 + 10'd280);
    wire in_up   = in_up_h && in_up_v;

    wire [8:0] vx_loc = vga_x - UP_X0;   // 0..279
    wire [8:0] vy_loc = vga_y - UP_Y0;   // 0..279

    // 10 나누기: floor(n * 205 / 2048), n=0..279 오차 없음
    // 18비트 중간값으로 명시 — 9비트 컨텍스트면 곱셈이 0으로 잘림
    wire [17:0] vx_prod = {9'b0, vx_loc} * 18'd205;
    wire [17:0] vy_prod = {9'b0, vy_loc} * 18'd205;
    wire [4:0]  col_28  = vx_prod[15:11];   // 0..27
    wire [4:0]  row_28  = vy_prod[15:11];   // 0..27

    // buf_addr = row_28 * 28 + col_28  (0..783)
    wire [9:0] buf_addr = ({5'b0, row_28} << 5)
                        - ({5'b0, row_28} << 2)
                        + {5'b0, col_28};

    wire [7:0] up_pixel = snapshot_buf[buf_addr];
    wire [3:0] up_gray  = up_pixel[7:4];

    wire on_up_border = in_up && (
        vga_x == UP_X0           || vga_x == UP_X0 + 10'd279 ||
        vga_y == UP_Y0           || vga_y == UP_Y0 + 10'd279
    );

    // ============================================================
    // VGA 출력 합성
    // ============================================================
    wire [3:0] out_r =
        on_divider  ? 4'hF :
        in_cam      ? (on_red  ? 4'hF : (on_blue ? 4'h0 : cam_gray)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    wire [3:0] out_g =
        on_divider  ? 4'hF :
        in_cam      ? (on_red  ? 4'h0 : (on_blue ? 4'h0 : cam_gray)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    wire [3:0] out_b =
        on_divider  ? 4'hF :
        in_cam      ? (on_red  ? 4'h0 : (on_blue ? 4'hF : cam_gray)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    assign vgaRed   = vga_active ? out_r : 4'b0;
    assign vgaGreen = vga_active ? out_g : 4'b0;
    assign vgaBlue  = vga_active ? out_b : 4'b0;

endmodule
