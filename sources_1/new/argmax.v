module argmax (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire signed [23:0] score_data,  // FC2 출력 score (1개씩)
    input  wire        score_valid,
    output reg  [3:0]  result,             // 최댓값 인덱스 (0~9)
    output reg         done
);

    // =========================================================
    // 동작:
    // score 10개를 순서대로 받아서
    // 가장 큰 값의 인덱스를 result에 저장
    // =========================================================

    reg signed [23:0] max_val;   // 현재까지 최댓값
    reg [3:0]         score_cnt; // 몇 개 받았는지 (0~9)

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            result    <= 0;
            done      <= 0;
            max_val   <= 24'sh800000;  // 최솟값 (signed 16비트 최솟값)
            score_cnt <= 0;
        end else begin
            done <= 0;

            if (start) begin
                max_val   <= 24'sh800000;
                score_cnt <= 0;
                result    <= 0;
                done      <= 0;
            end

            if (score_valid) begin
                if ($signed(score_data) > $signed(max_val)) begin
                    max_val <= score_data;
                    result  <= score_cnt;
                end
                score_cnt <= score_cnt + 1;

                if (score_cnt == 9) begin
                    done <= 1;
                end
            end
        end
    end

endmodule