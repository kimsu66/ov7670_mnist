`timescale 1ns / 1ps

module argmax (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire signed [23:0] score_data,  // FC2 출력 score (1개씩)
    input  wire        score_valid,
    output reg  [3:0]  result,             // 최댓값 인덱스 (0~9)
    output reg         done
);

    // score 10개를 순서대로 받아 가장 큰 값의 인덱스를 result에 저장한다.
    // start와 score_valid가 같은 cycle에 겹칠 경우 start를 우선하여 새 비교를 초기화한다.
    // 10개 이후의 score_valid는 방어적으로 무시한다.

    reg signed [23:0] max_val;
    reg [3:0]         score_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result    <= 4'd0;
            done      <= 1'b0;
            max_val   <= 24'sh800000;
            score_cnt <= 4'd0;
        end else begin
            done <= 1'b0;

            if (start) begin
                max_val   <= 24'sh800000;
                score_cnt <= 4'd0;
                result    <= 4'd0;
            end else if (score_valid && (score_cnt < 4'd10)) begin
                if ($signed(score_data) > $signed(max_val)) begin
                    max_val <= score_data;
                    result  <= score_cnt;
                end

                if (score_cnt == 4'd9) begin
                    done <= 1'b1;
                end

                score_cnt <= score_cnt + 4'd1;
            end
        end
    end

endmodule