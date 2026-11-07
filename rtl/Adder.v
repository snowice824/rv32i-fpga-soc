// Plain combinational adder (no carry in/out).
module Adder #(parameter WIDTH = 32) (
    input  wire [WIDTH-1:0] DATA_A,
    input  wire [WIDTH-1:0] DATA_B,
    output wire [WIDTH-1:0] OUT
);
    assign OUT = DATA_A + DATA_B;
endmodule
