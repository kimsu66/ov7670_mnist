`timescale 1ns / 1ps

module frame_buffer(
    input wire          clk_write,
    input wire          write_en,
    input wire  [16:0]  write_addr,
    input wire   [7:0]  pixel_in,

    input wire          clk_read,
    input wire  [16:0]  read_addr,
    output reg   [7:0]  pixel_out
);

reg [7:0] mem [0:76799];

always @(posedge clk_write) begin
    if(write_en)
        mem[write_addr] <= pixel_in;
end

always @(posedge clk_read) begin
    pixel_out <= mem[read_addr];
end

endmodule
