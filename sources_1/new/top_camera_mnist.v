`timescale 1ns / 1ps

module top_camera_mnist (
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

    // LED: 인식된 숫자 (0~9)
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
    wire [8:0]  fb_x       = vga_x[8:0];
    wire [7:0]  fb_y       = vga_y[7:0];
    wire        img_active = (vga_x < 10'd320) && (vga_y < 10'd240);
    // read_addr = fb_y * 320 = fb_y*256 + fb_y*64
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
    // VGA 출력 (빨간 박스 오버레이)
    // ============================================================
    wire in_box_h = (vga_x >= 10'd90) && (vga_x <= 10'd229);
    wire in_box_v = (vga_y >= 10'd50) && (vga_y <= 10'd189);
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
    wire [3:0] gray4 = pixel_out[7:4];

    assign vgaRed   = (vga_active && img_active) ? (on_border ? 4'hF : (on_blue_border ? 4'h0 : gray4)) : 4'b0;
    assign vgaGreen = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'h0 : gray4)) : 4'b0;
    assign vgaBlue  = (vga_active && img_active) ? (on_border ? 4'h0 : (on_blue_border ? 4'hF : gray4)) : 4'b0;

    // ============================================================
    // box_sampler: 박스 안에서 5픽셀마다 샘플링 → 28×28
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
    // digit_detector: 어두운 픽셀 비율로 숫자 존재 판단
    // ============================================================
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
    // 픽셀 버퍼: box_sampler가 출력하는 784픽셀을 순서대로 저장 (라이브 쓰기 버퍼)
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
    // 스냅샷 버퍼: frame_done 후 pixel_buf 전체를 복사 → MNIST 전용 읽기 버퍼
    //
    // 문제: box_sampler가 vga_y=92~147을 스캔하는 수십 μs 동안
    //       카메라가 frame_buffer를 계속 갱신하므로 pixel_buf 안에
    //       서로 다른 시간대의 픽셀이 섞인다.
    // 해결: frame_done(마지막 픽셀 확정) 이후 784사이클에 걸쳐
    //       pixel_buf → snapshot_buf로 복사하고, 복사 완료 시점에만
    //       MNIST가 읽도록 함 → 한 프레임 내 일관성 확보.
    // ============================================================
    reg [7:0] snapshot_buf [0:783];
    reg [9:0] copy_cnt       = 10'd0;
    reg       copying        = 1'b0;
    reg       snapshot_ready = 1'b0;  // 1클럭 펄스: 복사 완료 & MNIST 기동 가능
    reg       snapshot_digit = 1'b0;  // 해당 프레임의 digit_detected 래치

    always @(posedge clk_25mhz) begin
        snapshot_ready <= 1'b0;

        // frame_done 1사이클 후(frame_done_d) 복사 시작
        // - pixel_buf[783]의 non-blocking 쓰기가 이미 완료된 시점
        // - digit_detected도 digit_detector에서 1사이클 지연 후 확정된 값
        if (frame_done_d && !copying) begin
            copying        <= 1'b1;
            copy_cnt       <= 10'd0;
            snapshot_digit <= digit_detected;
        end

        if (copying) begin
            snapshot_buf[copy_cnt] <= pixel_buf[copy_cnt];
            if (copy_cnt == 10'd783) begin
                copying        <= 1'b0;
                snapshot_ready <= 1'b1;
            end else begin
                copy_cnt <= copy_cnt + 10'd1;
            end
        end
    end

    // ============================================================
    // MNIST 스트리밍 FSM
    // digit_detected → pixel_buf[0..783]을 mnist_core에 순차 전송
    // ============================================================
    localparam ST_IDLE   = 2'd0;
    localparam ST_STREAM = 2'd1;
    localparam ST_WAIT   = 2'd2;

    reg [1:0] stream_st  = ST_IDLE;
    reg [9:0] rd_cnt     = 10'd0;
    reg [7:0] mx_rx_data = 8'd0;
    reg       mx_rx_valid = 1'b0;

    always @(posedge clk_25mhz) begin
        mx_rx_valid <= 1'b0;
        case (stream_st)
            ST_IDLE: begin
                // snapshot_ready: 복사 완료 1클럭 펄스
                // snapshot_digit: 해당 프레임에서 숫자가 감지됐는지 여부
                if (snapshot_ready && snapshot_digit) begin
                    rd_cnt    <= 10'd0;
                    stream_st <= ST_STREAM;
                end
            end
            ST_STREAM: begin
                mx_rx_data  <= snapshot_buf[rd_cnt];  // pixel_buf 대신 snapshot_buf 사용
                mx_rx_valid <= 1'b1;
                if (rd_cnt == 10'd783) begin
                    rd_cnt    <= 10'd0;
                    stream_st <= ST_WAIT;
                end else begin
                    rd_cnt <= rd_cnt + 10'd1;
                end
            end
            ST_WAIT: begin
                // mnist_core가 tx_start를 올릴 때까지 대기
                if (mnist_tx_start)
                    stream_st <= ST_IDLE;
            end
            default: stream_st <= ST_IDLE;
        endcase
    end

    // ============================================================
    // mnist_core: FC1 → FC2 → argmax → 결과 숫자 출력
    // ============================================================
    wire [7:0] mnist_tx_data;
    wire       mnist_tx_start;

    mnist_core u_mnist (
        .clk      (clk_25mhz),
        .rst      (1'b0),
        .rx_data  (mx_rx_data),
        .rx_valid (mx_rx_valid),
        .tx_data  (mnist_tx_data),
        .tx_start (mnist_tx_start),
        .tx_busy  (1'b0)
    );
    


    // ============================================================
    // LED: 인식 결과 표시
    // - 숫자 감지 프레임 → MNIST 결과 표시 (0~9)
    // - 숫자 없는 프레임 → LED 전체 점등 (15, idle)
    // frame_done 1클럭 뒤에 digit_detected가 확정되므로 딜레이 사용
    // ============================================================
//    reg frame_done_d = 1'b0;
//    always @(posedge clk_25mhz)
//        frame_done_d <= frame_done;

//    reg [3:0] result_reg = 4'hF;
//    always @(posedge clk_25mhz) begin
//        if (mnist_tx_start)
//            result_reg <= mnist_tx_data[3:0];       // 인식 결과 래치
//        else if (frame_done_d && !digit_detected)
//            result_reg <= 4'hF;                      // 숫자 없으면 idle로 복귀
//    end
//    assign led = result_reg;
    // ============================================================
    // LED: 인식 결과 표시 (신호 안정화 포함)
    // ============================================================
    reg frame_done_d = 1'b0;
    always @(posedge clk_25mhz)
        frame_done_d <= frame_done;

    reg [3:0] last_result = 4'hF;
    reg [3:0] stable_cnt  = 4'd0;
    reg [3:0] result_reg  = 4'hF;

    always @(posedge clk_25mhz) begin
        if (mnist_tx_start) begin
            if (mnist_tx_data[3:0] == last_result) begin
                stable_cnt <= stable_cnt + 1;
                if (stable_cnt >= 4'd5) begin
                    result_reg <= mnist_tx_data[3:0];
                end
            end else begin
                last_result <= mnist_tx_data[3:0];
                stable_cnt  <= 4'd0;
            end
        end else if (frame_done_d && !digit_detected) begin
            result_reg  <= 4'hF;
            stable_cnt  <= 4'd0;
            last_result <= 4'hF;
        end
    end

    assign led = result_reg;

endmodule
