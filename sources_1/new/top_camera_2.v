`timescale 1ns / 1ps

module top_camera_mnist_2 (
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

    output wire [3:0] vgaRed,
    output wire [3:0] vgaGreen,
    output wire [3:0] vgaBlue,
    output wire       Hsync,
    output wire       Vsync,

    output wire [3:0] led
);

    reg [1:0] div4 = 2'd0;
    always @(posedge clk) div4 <= div4 + 2'd1;
    wire clk_25mhz = div4[1];

    assign cam_xclk = clk_25mhz;
    assign cam_rst  = 1'b1;
    assign cam_pwdn = 1'b0;

    ov7670_init u_init (
        .clk    (clk),
        .resetn (1'b1),
        .scl    (cam_scl),
        .sda    (cam_sda),
        .done   ()
    );

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

    wire [8:0]  fb_x      = vga_x[8:0];
    wire [7:0]  fb_y      = vga_y[7:0];
    wire        img_active = (vga_x < 10'd320) && (vga_y < 10'd240);
    wire [16:0] read_addr  = {1'b0, fb_y, 8'b0}
                           + {3'b0, fb_y, 6'b0}
                           + {8'b0, fb_x};
    wire [7:0]  pixel_out;

    frame_buffer u_fb (
        .clk_write  (cam_pclk),
        .write_en   (pixel_valid),
        .write_addr (write_addr),
        .pixel_in   (pixel_data),
        .clk_read   (clk_25mhz),
        .read_addr  (read_addr),
        .pixel_out  (pixel_out)
    );

    // 빨간 박스
    wire in_box_h  = (vga_x >= 10'd90)  && (vga_x <= 10'd229);
    wire in_box_v  = (vga_y >= 10'd50)  && (vga_y <= 10'd189);
    wire on_border = (
        ((vga_x == 10'd90  || vga_x == 10'd91  ||
          vga_x == 10'd228 || vga_x == 10'd229) && in_box_v) ||
        ((vga_y == 10'd50  || vga_y == 10'd51  ||
          vga_y == 10'd188 || vga_y == 10'd189) && in_box_h)
    );

    // 파란 박스
    wire in_blue_h      = (vga_x >= 10'd132) && (vga_x <= 10'd187);
    wire in_blue_v      = (vga_y >= 10'd92)  && (vga_y <= 10'd147);
    wire on_blue_border = (
        ((vga_x == 10'd132 || vga_x == 10'd133 ||
          vga_x == 10'd186 || vga_x == 10'd187) && in_blue_v) ||
        ((vga_y == 10'd92  || vga_y == 10'd93  ||
          vga_y == 10'd146 || vga_y == 10'd147) && in_blue_h)
    );
    wire [3:0] gray4  = pixel_out[7:4];
    wire       in_cam = img_active;

    // 구분선
    wire on_divider = (vga_x >= 10'd326) && (vga_x <= 10'd329);

    // 280×280 업스케일
    localparam [9:0] UP_X0 = 10'd340;
    localparam [9:0] UP_Y0 = 10'd100;

    wire in_up_h = (vga_x >= UP_X0) && (vga_x < UP_X0 + 10'd280);
    wire in_up_v = (vga_y >= UP_Y0) && (vga_y < UP_Y0 + 10'd280);
    wire in_up   = in_up_h && in_up_v;

    wire [8:0]  vx_loc  = vga_x - UP_X0;
    wire [8:0]  vy_loc  = vga_y - UP_Y0;
    wire [17:0] vx_prod = {9'b0, vx_loc} * 18'd205;
    wire [17:0] vy_prod = {9'b0, vy_loc} * 18'd205;
    wire [4:0]  col_28  = vx_prod[15:11];
    wire [4:0]  row_28  = vy_prod[15:11];

    reg [7:0] snapshot_buf [0:783];
    reg [9:0] snap_wr_cnt = 10'd0;

    wire [9:0] buf_addr    = ({5'b0, row_28} << 5)
                           - ({5'b0, row_28} << 2)
                           + {5'b0, col_28};
    wire [7:0] up_pixel    = snapshot_buf[buf_addr];
    wire [3:0] up_gray     = up_pixel[3:0];
    wire       on_up_border = in_up && (
        vga_x == UP_X0            || vga_x == UP_X0 + 10'd279 ||
        vga_y == UP_Y0            || vga_y == UP_Y0 + 10'd279
    );

    // VGA 출력
    wire [3:0] out_r =
        on_divider  ? 4'hF :
        in_cam      ? (on_border ? 4'hF : (on_blue_border ? 4'h0 : gray4)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;
    wire [3:0] out_g =
        on_divider  ? 4'hF :
        in_cam      ? (on_border ? 4'h0 : (on_blue_border ? 4'h0 : gray4)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;
    wire [3:0] out_b =
        on_divider  ? 4'hF :
        in_cam      ? (on_border ? 4'h0 : (on_blue_border ? 4'hF : gray4)) :
        in_up       ? (on_up_border ? 4'hF : up_gray) :
        4'b0;

    assign vgaRed   = vga_active ? out_r : 4'b0;
    assign vgaGreen = vga_active ? out_g : 4'b0;
    assign vgaBlue  = vga_active ? out_b : 4'b0;

    // box_sampler
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

    // snapshot_buf 쓰기 (VGA 표시용)
    localparam [3:0] PIXEL_THR = 4'd4;
    wire [3:0] avg4_raw = sampled_pixel[7:4];
    wire [3:0] avg4_thr = (avg4_raw >= PIXEL_THR) ? avg4_raw : 4'b0;

    always @(posedge clk_25mhz) begin
        if (sampled_valid) begin
            snapshot_buf[snap_wr_cnt] <= {4'b0, avg4_thr};
            snap_wr_cnt <= frame_done ? 10'd0 : snap_wr_cnt + 10'd1;
        end else if (frame_done)
            snap_wr_cnt <= 10'd0;
    end

    // digit_detector
    wire digit_detected;

    digit_detector u_detector (
        .clk           (clk_25mhz),
        .rst           (1'b0),
        .sampled_pixel (sampled_pixel),
        .sampled_valid (sampled_valid),
        .frame_done    (frame_done),
        .digit_detected(digit_detected)
    );

    // ============================================================
    // mnist_top
    // [핵심 수정] sampled_valid 그대로 전달 (digit_detected AND 제거)
    // → fc1이 매 프레임 784픽셀을 빠짐없이 수신해야 추론 시작 가능
    // digit_detected는 LED 표시 제어에만 사용
    // ============================================================
    wire [3:0] mnist_result;
    wire       mnist_result_valid;

    mnist_top u_mnist (
        .clk           (clk_25mhz),
        .rst           (1'b0),
        .sampled_pixel (sampled_pixel),
        .sampled_valid (sampled_valid),   // digit_detected 조건 제거
        .result        (mnist_result),
        .result_valid  (mnist_result_valid)
    );

    // ============================================================
    // LED 표시
    // - digit_detected 프레임에서 결과 나오면 → 안정화 후 표시
    // - digit 없는 프레임 → 4'hF (LED 전체 점등)
    // ============================================================
    reg frame_done_d = 1'b0;
    always @(posedge clk_25mhz)
        frame_done_d <= frame_done;

    reg        result_from_digit = 1'b0;  // 마지막 추론이 digit 프레임이었는지
    reg [3:0]  last_result = 4'hF;
    reg [3:0]  stable_cnt  = 4'd0;
    reg [3:0]  result_reg  = 4'hF;

    always @(posedge clk_25mhz) begin
        // digit_detected 래치: frame_done 시점에 해당 프레임 여부 저장
        if (frame_done_d)
            result_from_digit <= digit_detected;

        if (mnist_result_valid && result_from_digit) begin
            // 숫자 감지 프레임의 추론 결과만 반영
            if (mnist_result == last_result) begin
                if (stable_cnt < 4'd15)
                    stable_cnt <= stable_cnt + 4'd1;
                if (stable_cnt >= 4'd5)       // 안정화 임계값
                    result_reg <= mnist_result;
            end else begin
                last_result <= mnist_result;
                stable_cnt  <= 4'd0;
            end
        end else if (frame_done_d && !digit_detected) begin
            // 숫자 없는 프레임 → idle
            result_reg  <= 4'hF;
            stable_cnt  <= 4'd0;
            last_result <= 4'hF;
        end
    end

    assign led = result_reg;

endmodule