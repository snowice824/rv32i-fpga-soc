// 2-input multiplexer, WIDTH bits wide.
module Mux_2to1 #(parameter WIDTH = 4) (
    input  wire             select,
    input  wire [WIDTH-1:0] input_0,
    input  wire [WIDTH-1:0] input_1,
    output wire [WIDTH-1:0] output_value
);
    assign output_value = select ? input_1 : input_0;
endmodule
