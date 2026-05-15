`timescale 1ns / 1ps

// OV7670 RGB565 모드 (VGA 640x480)
// 바이트 순서: 상위바이트 {R[4:0],G[5:3]}, 하위바이트 {G[2:0],B[4:0]}
// 짝수 행 + 짝수 픽셀만 출력 → 320x240 다운스케일

module ov7670_capture(
    input  wire        pclk,
    input  wire        vsync,
    input  wire        href,
    input  wire  [7:0] d,

    output reg  [15:0] pixel_data,
    output reg         pixel_valid,
    output reg  [16:0] addr
);

    reg byte_sel = 1'b0;
    reg [7:0] high_byte = 8'd0;  // RGB565 상위 바이트

    reg [9:0] x = 10'd0;
    reg [8:0] y = 9'd0;
    reg vsync_d = 1'b0;

    always @(posedge pclk) begin
        pixel_valid <= 1'b0;
        vsync_d     <= vsync;

        if (vsync && !vsync_d) begin
            x        <= 10'd0;
            y        <= 9'd0;
            byte_sel <= 1'b0;
        end
        else if (!href) begin
            byte_sel <= 1'b0;
        end
        else begin
            if (!byte_sel) begin
                high_byte <= d;      // 첫 번째 바이트 캡처
                byte_sel  <= 1'b1;
            end else begin
                byte_sel <= 1'b0;   // 두 번째 바이트 → 픽셀 완성

                // 짝수 행 + 짝수 픽셀만 출력 (2x2 픽셀 스킵)
                if (x[0] == 1'b0 && y[0] == 1'b0) begin
                    pixel_data  <= {high_byte, d};   // RGB565 그대로 출력
                    pixel_valid <= 1'b1;
                    addr        <= ({1'b0, y[8:1], 8'b0}
                                 + {3'b0, y[8:1], 6'b0}
                                 + {8'b0, x[9:1]});
                end

                if (x == 10'd639) begin
                    x <= 10'd0;
                    if (y < 9'd479)
                        y <= y + 9'd1;
                end 
                else begin
                    x <= x + 10'd1;
                end
            end
        end
    end

endmodule
