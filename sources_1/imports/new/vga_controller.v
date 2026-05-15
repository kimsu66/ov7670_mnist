`timescale 1ns / 1ps

module vga_controller(
    input  wire        clk,       // 25MHz VGA pixel clock
    
    output reg [9:0]   x = 10'd0,
    output reg [9:0]   y = 10'd0,
    output wire        Hsync,
    output wire        Vsync,
    output wire        active
);

    // 640x480 @60Hz
    // horizontal: visible 640, front 16, sync 96, back 48 => total 800
    // vertical  : visible 480, front 10, sync 2,  back 33 => total 525

    reg [9:0] h_cnt = 10'd0;
    reg [9:0] v_cnt = 10'd0;

    always @(posedge clk) begin
        if (h_cnt == 10'd799) begin
            h_cnt <= 10'd0;
            if (v_cnt == 10'd524)
                v_cnt <= 10'd0;
            else
                v_cnt <= v_cnt + 10'd1;
        end else begin
            h_cnt <= h_cnt + 10'd1;
        end
    end

    always @(posedge clk) begin
        x <= h_cnt;
        y <= v_cnt;
    end

    assign active = (h_cnt < 10'd640) && (v_cnt < 10'd480);

    assign Hsync = ~((h_cnt >= 10'd656) && (h_cnt < 10'd752));
    assign Vsync = ~((v_cnt >= 10'd490) && (v_cnt < 10'd492));

endmodule