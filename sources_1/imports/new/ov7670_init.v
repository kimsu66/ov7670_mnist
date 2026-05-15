`timescale 1ns / 1ps

module ov7670_init(
    input  wire clk,      // 100MHz
    input  wire resetn,
    inout  wire sda,
    
    output reg  scl,
    output reg  done
);

    reg sda_oe  = 1'b1;
    reg sda_out = 1'b1;
    assign sda = sda_oe ? sda_out : 1'bz;

    // tick: 100MHz / 500 = 200kHz
    reg [8:0] clk_div = 9'd0;
    reg tick = 1'b0;
    always @(posedge clk) begin
        if (clk_div == 9'd499) begin
            clk_div <= 9'd0;
            tick    <= 1'b1;
        end else begin
            clk_div <= clk_div + 9'd1;
            tick    <= 1'b0;
        end
    end

    // -----------------------------------------
    // init ROM - VGA RGB565 + AGC/AEC + Gamma
    // -----------------------------------------
    reg [7:0] rom_addr [0:30];
    reg [7:0] rom_data [0:30];

    initial begin
        // 기본 설정
        rom_addr[0]  = 8'h12; rom_data[0]  = 8'b1000_0000; // COM7: software reset
        rom_addr[1]  = 8'h11; rom_data[1]  = 8'b0000_0000; // CLKRC: no prescale
        rom_addr[2]  = 8'h12; rom_data[2]  = 8'b0000_0100; // COM7: RGB 모드 (bit[2]=1)
        rom_addr[3]  = 8'h40; rom_data[3]  = 8'b1101_0000; // COM15: full range + RGB565
        rom_addr[4]  = 8'h3A; rom_data[4]  = 8'b0000_0100; // TSLB: YUYV 유지
        rom_addr[5]  = 8'h3D; rom_data[5]  = 8'b1100_0000; // COM13: gamma + UV auto, bit0=0 유지
        rom_addr[6]  = 8'h0C; rom_data[6]  = 8'b0000_0000; // COM3: no scaling
        rom_addr[7]  = 8'h3E; rom_data[7]  = 8'b0000_0000; // COM14: normal PCLK
        rom_addr[8]  = 8'h70; rom_data[8]  = 8'b0011_1010; // SCALING_XSC
        rom_addr[9]  = 8'h71; rom_data[9]  = 8'b0011_0101; // SCALING_YSC
        rom_addr[10] = 8'h15; rom_data[10] = 8'b0000_0000; // COM10: normal polarity
        // AGC / AEC (자동 노출 및 게인)
        rom_addr[11] = 8'h13; rom_data[11] = 8'b1110_0000; // COM8: AGC/AEC 일시 비활성
        rom_addr[12] = 8'h00; rom_data[12] = 8'b0000_0000; // GAIN: 0
        rom_addr[13] = 8'h10; rom_data[13] = 8'b0000_0000; // AECH: exposure = 0
        rom_addr[14] = 8'h14; rom_data[14] = 8'b0001_1000; // COM9: max AGC 4x
        rom_addr[15] = 8'h13; rom_data[15] = 8'b1110_0101; // COM8: AGC+AEC+AWB 활성화
        // 감마 커브 (밝은 영역 계조 개선)
        rom_addr[16] = 8'h7a; rom_data[16] = 8'b0010_0000;
        rom_addr[17] = 8'h7b; rom_data[17] = 8'b0001_0000;
        rom_addr[18] = 8'h7c; rom_data[18] = 8'b0001_1110;
        rom_addr[19] = 8'h7d; rom_data[19] = 8'b0011_0101;
        rom_addr[20] = 8'h7e; rom_data[20] = 8'b0101_1010;
        rom_addr[21] = 8'h7f; rom_data[21] = 8'b0110_1001;
        rom_addr[22] = 8'h80; rom_data[22] = 8'b0111_0110;
        rom_addr[23] = 8'h81; rom_data[23] = 8'b1000_0000;
        rom_addr[24] = 8'h82; rom_data[24] = 8'b1000_1000;
        rom_addr[25] = 8'h83; rom_data[25] = 8'b1000_1111;
        rom_addr[26] = 8'h84; rom_data[26] = 8'b1001_0110;
        rom_addr[27] = 8'h85; rom_data[27] = 8'b1010_0011;
        rom_addr[28] = 8'h86; rom_data[28] = 8'b1010_1111;
        rom_addr[29] = 8'h87; rom_data[29] = 8'b1100_0100;
        rom_addr[30] = 8'h88; rom_data[30] = 8'b1101_0111;
    end

    localparam DEV_WR = 8'h42;

    reg [4:0]  state    = 0;
    reg [4:0]  ack_next = 0;   // ACK 후 이동할 상태
    reg [3:0]  bit_cnt  = 0;
    reg [7:0]  shreg = 8'd0;
    reg [5:0]  reg_index = 0;  // 6-bit: 0~63
    reg [23:0] wait_cnt = 0;

    localparam S_IDLE      = 0,
               S_START1    = 1,
               S_START2    = 2,
               S_LOAD_DEV  = 3,
               S_SEND_DEV0 = 4,
               S_SEND_DEV1 = 5,
               S_LOAD_REG  = 6,
               S_SEND_REG0 = 7,
               S_SEND_REG1 = 8,
               S_LOAD_DAT  = 9,
               S_SEND_DAT0 = 10,
               S_SEND_DAT1 = 11,
               S_STOP1     = 12,
               S_STOP2     = 13,
               S_WAIT1MS   = 14,
               S_DONE      = 15,
               S_ACK_H     = 16,  // 9번째 클럭 High (SCCB DC don't-care bit)
               S_ACK_L     = 17;  // 9번째 클럭 Low → ack_next로 이동

    initial begin
        scl     = 1'b1;
        sda_oe  = 1'b1;
        sda_out = 1'b1;
        done    = 1'b0;
    end

    always @(posedge clk) begin
        if (!resetn) begin
            state     <= S_IDLE;
            scl       <= 1'b1;
            sda_oe    <= 1'b1;
            sda_out   <= 1'b1;
            done      <= 1'b0;
            reg_index <= 0;
            wait_cnt  <= 0;
        end else if (tick) begin
            case (state)
                S_IDLE: begin
                    done    <= 1'b0;
                    scl     <= 1'b1;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;
                    state   <= S_START1;
                end

                S_START1: begin
                    scl     <= 1'b1;
                    sda_out <= 1'b0;
                    state   <= S_START2;
                end

                S_START2: begin
                    scl   <= 1'b0;
                    state <= S_LOAD_DEV;
                end

                S_LOAD_DEV: begin
                    shreg   <= DEV_WR;
                    bit_cnt <= 4'd7;
                    state   <= S_SEND_DEV0;
                end

                S_SEND_DEV0: begin
                    sda_oe  <= 1'b1;
                    sda_out <= shreg[bit_cnt];
                    scl     <= 1'b0;
                    state   <= S_SEND_DEV1;
                end

                S_SEND_DEV1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl      <= 1'b0;
                        sda_oe   <= 1'b0;   // SDA 해제 (9번째 클럭 준비)
                        ack_next <= S_LOAD_REG;
                        state    <= S_ACK_H;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state   <= S_SEND_DEV0;
                    end
                end

                S_LOAD_REG: begin
                    sda_oe  <= 1'b1;
                    shreg   <= rom_addr[reg_index];
                    bit_cnt <= 4'd7;
                    state   <= S_SEND_REG0;
                end

                S_SEND_REG0: begin
                    sda_out <= shreg[bit_cnt];
                    scl     <= 1'b0;
                    state   <= S_SEND_REG1;
                end

                S_SEND_REG1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl      <= 1'b0;
                        sda_oe   <= 1'b0;
                        ack_next <= S_LOAD_DAT;
                        state    <= S_ACK_H;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state   <= S_SEND_REG0;
                    end
                end

                S_LOAD_DAT: begin
                    sda_oe  <= 1'b1;
                    shreg   <= rom_data[reg_index];
                    bit_cnt <= 4'd7;
                    state   <= S_SEND_DAT0;
                end

                S_SEND_DAT0: begin
                    sda_out <= shreg[bit_cnt];
                    scl     <= 1'b0;
                    state   <= S_SEND_DAT1;
                end

                S_SEND_DAT1: begin
                    scl <= 1'b1;
                    if (bit_cnt == 0) begin
                        scl      <= 1'b0;
                        sda_oe   <= 1'b0;
                        ack_next <= S_STOP1;
                        state    <= S_ACK_H;
                    end else begin
                        bit_cnt <= bit_cnt - 1'b1;
                        state   <= S_SEND_DAT0;
                    end
                end

                S_STOP1: begin
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b0;
                    scl     <= 1'b1;
                    state   <= S_STOP2;
                end

                S_STOP2: begin
                    sda_out <= 1'b1;
                    if (reg_index == 0) begin
                        wait_cnt <= 24'd2000; // 10ms @ 200kHz tick
                        state    <= S_WAIT1MS;
                    end else if (reg_index == 30) begin
                        state <= S_DONE;
                    end else begin
                        reg_index <= reg_index + 1'b1;
                        state     <= S_START1;
                    end
                end

                S_WAIT1MS: begin
                    if (wait_cnt == 0) begin
                        reg_index <= reg_index + 1'b1;
                        state     <= S_START1;
                    end else begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end
                end

                S_DONE: begin
                    done    <= 1'b1;
                    scl     <= 1'b1;
                    sda_oe  <= 1'b1;
                    sda_out <= 1'b1;
                    state   <= S_DONE;
                end

                S_ACK_H: begin
                    scl   <= 1'b1;   // 9번째 클럭 High
                    state <= S_ACK_L;
                end

                S_ACK_L: begin
                    scl    <= 1'b0;   // 9번째 클럭 Low
                    sda_oe <= 1'b1;   // SDA 다시 제어
                    state  <= ack_next;
                end
            endcase
        end
    end

endmodule
