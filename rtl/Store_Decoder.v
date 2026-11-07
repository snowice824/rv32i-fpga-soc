// Generates the per-byte write-enable mask for a store, from funct3.
// SB (000) -> 0001 , SH (001) -> 0011 , SW (010) -> 1111
// Combined elsewhere with MemWrite and the address decode.
module Store_Decoder (
    input  wire [2:0] funct3,
    output reg  [3:0] byte_enable
);
    always @(*) begin
        case (funct3)
            3'b000:  byte_enable = 4'b0001; // SB
            3'b001:  byte_enable = 4'b0011; // SH
            3'b010:  byte_enable = 4'b1111; // SW
            default: byte_enable = 4'b1111;
        endcase
    end
endmodule
