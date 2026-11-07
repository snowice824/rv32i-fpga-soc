// Clears the least-significant bit, used to form the JALR target:
//   (rs1 + imm) & ~1
// Kept as a submodule so the datapath stays free of inline/direct logic.
module LSB_Clear #(parameter WIDTH = 32) (
    input  wire [WIDTH-1:0] in,
    output wire [WIDTH-1:0] out
);
    assign out = {in[WIDTH-1:1], 1'b0};
endmodule
