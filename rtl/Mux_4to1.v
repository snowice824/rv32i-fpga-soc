// 4-input multiplexer, WIDTH bits wide.
module Mux_4to1 #(parameter WIDTH = 4) (
    input  wire [1:0]       select,
    input  wire [WIDTH-1:0] input_0,
    input  wire [WIDTH-1:0] input_1,
    input  wire [WIDTH-1:0] input_2,
    input  wire [WIDTH-1:0] input_3,
    output reg  [WIDTH-1:0] output_value
);
    always @(*) begin
        case (select)
            2'd0:    output_value = input_0;
            2'd1:    output_value = input_1;
            2'd2:    output_value = input_2;
            default: output_value = input_3;
        endcase
    end
endmodule
