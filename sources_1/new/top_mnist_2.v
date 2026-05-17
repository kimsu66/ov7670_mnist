`timescale 1ns / 1ps

// ============================================================
//  top_mnist_2.v  — 버그 수정 완전판
//
//  수정사항:
//  1. digit_detected 조건 제거 → fc1이 매 프레임 784픽셀 항상 수신
//     (digit_detected는 LED 표시 제어에만 사용)
//  2. FC1 바이어스 타이밍 수정:
//     ST_WR에서 b_addr 세팅 → ST_BWAIT(1사이클 대기) → 확정된 b_data 사용
//     (기존과 동일 구조이나 n=0 초기 b_addr 세팅 위치 명확화)
//  3. FC2 act1_k: k 래치 후 다음 사이클에 MAC → 타이밍 명확화
//  4. argmax: n=9 비교 후 result 확정 타이밍 1사이클 수정
// ============================================================


// ============================================================
//  fc1_layer
// ============================================================
module fc1_layer (
    input  wire        clk,
    input  wire        rst,

    input  wire [3:0]  px_in,
    input  wire        px_valid,

    output reg  [447:0] act1_flat,
    output reg          done
);
    localparam [2:0]
        ST_RECV  = 3'd0,
        ST_BWAIT = 3'd1,   // b_addr 세팅 완료, b_data 대기 1사이클
        ST_MWAIT = 3'd2,   // w_addr 세팅 완료, w_data 대기 1사이클
        ST_MAC   = 3'd3,
        ST_WR    = 3'd4;

    reg [2:0] state = ST_RECV;

    reg [3:0]  px [0:783];
    reg [9:0]  rx_cnt = 10'd0;

    reg  [15:0] w_addr;
    reg  [5:0]  b_addr;
    wire [7:0]  w_data;
    wire [7:0]  b_data;

    blk_mem_gen_0 u_w1 (
        .clka  (clk),
        .addra (w_addr),
        .douta (w_data)
    );
    blk_mem_gen_1 u_b1 (
        .clka  (clk),
        .addra (b_addr),
        .douta (b_data)
    );

    reg [5:0]         n;
    reg [9:0]         k;
    reg signed [31:0] acc;

    function [6:0] relu7;
        input signed [31:0] v;
        begin
            if (v[31])            relu7 = 7'd0;
            else if (v > 32'd127) relu7 = 7'd127;
            else                  relu7 = v[6:0];
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_RECV;
            rx_cnt    <= 10'd0;
            done      <= 1'b0;
            act1_flat <= 448'd0;
            b_addr    <= 6'd0;
            w_addr    <= 16'd0;
        end else begin
            done <= 1'b0;

            case (state)

                // ── 784픽셀 수신 ──────────────────────────────
                ST_RECV: begin
                    if (px_valid) begin
                        px[rx_cnt] <= px_in;
                        if (rx_cnt == 10'd783) begin
                            rx_cnt <= 10'd0;
                            n      <= 6'd0;
                            b_addr <= 6'd0;   // B1[0] 주소 세팅
                            state  <= ST_BWAIT;
                        end else
                            rx_cnt <= rx_cnt + 10'd1;
                    end
                end

                // ── B1[n] 대기: 이 사이클 끝에 b_data=B1[n] 확정 ──
                ST_BWAIT: begin
                    acc <= {{24{b_data[7]}}, b_data};  // 확정된 b_data 사용
                    k   <= 10'd0;
                    // W1[n*784+0] 주소 세팅 (784 = 512+256+16)
                    w_addr <= ({10'b0, n} << 9)
                            + ({10'b0, n} << 8)
                            + ({10'b0, n} << 4);
                    state <= ST_MWAIT;
                end

                // ── W1[n*784+0] 대기: 이 사이클 끝에 w_data 확정 ──
                ST_MWAIT: begin
                    state <= ST_MAC;
                end

                // ── MAC: acc += w_data * px[k] ────────────────
                // 진입 시 w_data = W1[n*784+k] 유효
                ST_MAC: begin
                    acc <= acc + $signed(w_data)
                               * $signed({1'b0, px[k]});

                    if (k == 10'd783) begin
                        state <= ST_WR;
                    end else begin
                        k      <= k + 10'd1;
                        w_addr <= ({10'b0, n} << 9)
                                + ({10'b0, n} << 8)
                                + ({10'b0, n} << 4)
                                + {6'b0, k + 10'd1};
                        // 다음 사이클 ST_MAC 진입 시 w_data 확정 (레이턴시 1사이클 OK)
                    end
                end

                // ── ReLU + act1 저장 ──────────────────────────
                // 비블로킹으로 k=783 MAC가 acc에 반영된 후 진입
                ST_WR: begin
                    act1_flat[n*7 +: 7] <= relu7(acc);

                    if (n == 6'd63) begin
                        done  <= 1'b1;
                        state <= ST_RECV;
                    end else begin
                        // 다음 뉴런 바이어스 주소 세팅 → ST_BWAIT에서 1사이클 대기 후 사용
                        b_addr <= n + 6'd1;
                        n      <= n + 6'd1;
                        state  <= ST_BWAIT;
                    end
                end

                default: state <= ST_RECV;
            endcase
        end
    end
endmodule


// ============================================================
//  fc2_layer
// ============================================================
module fc2_layer (
    input  wire         clk,
    input  wire         rst,

    input  wire [447:0] act1_flat,
    input  wire         start,

    output reg  [319:0] logit_flat,
    output reg          done
);
    localparam [2:0]
        ST_IDLE  = 3'd0,
        ST_BWAIT = 3'd1,
        ST_MWAIT = 3'd2,
        ST_MAC   = 3'd3,
        ST_WR    = 3'd4;

    reg [2:0] state = ST_IDLE;

    reg  [9:0] w_addr;
    reg  [3:0] b_addr;
    wire [7:0] w_data;
    wire [7:0] b_data;

    fc2_weight u_w2 (
        .clka  (clk),
        .addra (w_addr),
        .douta (w_data)
    );
    fc2_bias u_b2 (
        .clka  (clk),
        .addra (b_addr),
        .douta (b_data)
    );

    reg [3:0]         n;
    reg [5:0]         k;
    reg signed [31:0] acc;

    // act1[k] 래치: k가 확정된 다음 사이클에 읽도록
    // → ST_MAC 진입 시 k는 이미 확정된 값 → act1_flat[k*7+:7] 직접 사용
    wire [6:0] act1_k = act1_flat[k*7 +: 7];

    always @(posedge clk) begin
        if (rst) begin
            state      <= ST_IDLE;
            done       <= 1'b0;
            logit_flat <= 320'd0;
            b_addr     <= 4'd0;
            w_addr     <= 10'd0;
        end else begin
            done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (start) begin
                        n      <= 4'd0;
                        b_addr <= 4'd0;   // B2[0] 주소 세팅
                        state  <= ST_BWAIT;
                    end
                end

                // B2[n] 대기
                ST_BWAIT: begin
                    acc    <= {{24{b_data[7]}}, b_data};
                    k      <= 6'd0;
                    w_addr <= {n, 6'b0};   // W2[n*64+0] 주소
                    state  <= ST_MWAIT;
                end

                // W2[n*64+0] 대기
                ST_MWAIT: begin
                    state <= ST_MAC;
                end

                // MAC: acc += w_data * act1[k]
                ST_MAC: begin
                    acc <= acc + $signed(w_data)
                               * $signed({1'b0, act1_k});

                    if (k == 6'd63) begin
                        state <= ST_WR;
                    end else begin
                        k      <= k + 6'd1;
                        w_addr <= {n, 6'b0} + {4'b0, k + 6'd1};
                    end
                end

                // logit 저장
                ST_WR: begin
                    logit_flat[n*32 +: 32] <= acc;

                    if (n == 4'd9) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        b_addr <= n + 4'd1;
                        n      <= n + 4'd1;
                        state  <= ST_BWAIT;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule


// ============================================================
//  argmax10
// ============================================================
module argmax10 (
    input  wire         clk,
    input  wire         rst,

    input  wire [319:0] logit_flat,
    input  wire         start,

    output reg  [3:0]   result,
    output reg          done
);
    reg [3:0]         n;
    reg signed [31:0] mx;
    reg [3:0]         mx_idx;
    reg               running = 1'b0;

    wire signed [31:0] logit_n = logit_flat[n*32 +: 32];

    always @(posedge clk) begin
        if (rst) begin
            running <= 1'b0;
            done    <= 1'b0;
            result  <= 4'd0;
        end else begin
            done <= 1'b0;

            if (start && !running) begin
                mx      <= $signed(logit_flat[31:0]);  // logit[0] 초기값
                mx_idx  <= 4'd0;
                n       <= 4'd1;                        // n=1부터 비교
                running <= 1'b1;
            end else if (running) begin
                if ($signed(logit_n) > $signed(mx)) begin
                    mx     <= logit_n;
                    mx_idx <= n;
                end

                if (n == 4'd9) begin
                    // n=9 비교 완료 → 다음 사이클에 result 확정
                    result  <= ($signed(logit_n) > $signed(mx)) ? n : mx_idx;
                    done    <= 1'b1;
                    running <= 1'b0;
                end else begin
                    n <= n + 4'd1;
                end
            end
        end
    end
endmodule


// ============================================================
//  mnist_top
// ============================================================
module mnist_top (
    input  wire       clk,
    input  wire       rst,

    input  wire [7:0] sampled_pixel,
    input  wire       sampled_valid,   // digit_detected 필터 없이 항상 전달

    output reg  [3:0] result,
    output reg        result_valid
);
    wire [3:0]   px4       = sampled_pixel[7:4];
    wire [447:0] act1_flat;
    wire         fc1_done;

    fc1_layer u_fc1 (
        .clk      (clk),
        .rst      (rst),
        .px_in    (px4),
        .px_valid (sampled_valid),
        .act1_flat(act1_flat),
        .done     (fc1_done)
    );

    wire [319:0] logit_flat;
    wire         fc2_done;

    fc2_layer u_fc2 (
        .clk       (clk),
        .rst       (rst),
        .act1_flat (act1_flat),
        .start     (fc1_done),
        .logit_flat(logit_flat),
        .done      (fc2_done)
    );

    wire [3:0] argmax_result;
    wire       argmax_done;

    argmax10 u_argmax (
        .clk        (clk),
        .rst        (rst),
        .logit_flat (logit_flat),
        .start      (fc2_done),
        .result     (argmax_result),
        .done       (argmax_done)
    );

    always @(posedge clk) begin
        if (rst) begin
            result       <= 4'hF;
            result_valid <= 1'b0;
        end else begin
            result_valid <= 1'b0;
            if (argmax_done) begin
                result       <= argmax_result;
                result_valid <= 1'b1;
            end
        end
    end
endmodule