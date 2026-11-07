// Formats a loaded word into the value written back to the register file.
// The data memory returns its bytes already positioned at the target byte
// address (low lanes), so only funct3 is needed - no byte offset.
//   LB  (000): sign-extend  byte
//   LH  (001): sign-extend  half
//   LW  (010): pass through word
//   LBU (100): zero-extend  byte
//   LHU (101): zero-extend  half
module Load_Extend (
    input  wire [2:0]  funct3,
    input  wire [31:0] raw,
    output reg  [31:0] extended
);
    always @(*) begin
        case (funct3)
            3'b000:  extended = {{24{raw[7]}},  raw[7:0]};   // LB
            3'b001:  extended = {{16{raw[15]}}, raw[15:0]};  // LH
            3'b010:  extended = raw;                         // LW
            3'b100:  extended = {24'b0, raw[7:0]};           // LBU
            3'b101:  extended = {16'b0, raw[15:0]};          // LHU
            default: extended = raw;
        endcase
    end
endmodule
