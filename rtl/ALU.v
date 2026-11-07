// Arithmetic/logic unit for the RV32I core.
//
// control  operation
//   0000   add (uses CI as carry in)
//   0001   subtract (A - B)
//   0010   AND
//   0011   OR
//   0100   XOR
//   0101   shift left logical
//   0110   shift right logical
//   0111   shift right arithmetic
//   1000   set if less than (signed)
//   1001   set if less than (unsigned)
//   1010   pass B (used for LUI)
//
// CO and OVF are only meaningful for add/subtract and are 0 otherwise.
// N and Z are derived from the result.
module ALU #(parameter WIDTH = 32) (
    input  wire [3:0]       control,
    input  wire             CI,
    input  wire [WIDTH-1:0] DATA_A,
    input  wire [WIDTH-1:0] DATA_B,
    output reg  [WIDTH-1:0] OUT,
    output reg              CO,
    output reg              OVF,
    output wire             N,
    output wire             Z
);
    localparam [3:0] ADD  = 4'b0000, SUB  = 4'b0001, AND_ = 4'b0010,
                     OR_  = 4'b0011, XOR_ = 4'b0100, SLL  = 4'b0101,
                     SRL  = 4'b0110, SRA  = 4'b0111, SLT  = 4'b1000,
                     SLTU = 4'b1001, PASSB = 4'b1010;

    localparam MSB = WIDTH - 1;

    // Adder and subtractor results, WIDTH+1 bits so the top bit is the carry.
    wire [WIDTH:0] sum  = {1'b0, DATA_A} + {1'b0, DATA_B} + CI;
    wire [WIDTH:0] diff = {1'b0, DATA_A} + {1'b0, ~DATA_B} + 1'b1;

    // Signed overflow: for an add the operand signs must match, for a subtract
    // they must differ, and in both cases the result sign must change.
    wire add_ovf = (DATA_A[MSB] == DATA_B[MSB]) && (sum[MSB]  != DATA_A[MSB]);
    wire sub_ovf = (DATA_A[MSB] != DATA_B[MSB]) && (diff[MSB] != DATA_A[MSB]);

    wire [4:0] shamt = DATA_B[4:0];

    always @(*) begin
        OUT = {WIDTH{1'b0}};
        CO  = 1'b0;
        OVF = 1'b0;

        case (control)
            ADD:   begin {CO, OUT} = sum;  OVF = add_ovf; end
            SUB:   begin {CO, OUT} = diff; OVF = sub_ovf; end
            AND_:  OUT = DATA_A & DATA_B;
            OR_:   OUT = DATA_A | DATA_B;
            XOR_:  OUT = DATA_A ^ DATA_B;
            SLL:   OUT = DATA_A << shamt;
            SRL:   OUT = DATA_A >> shamt;
            SRA:   OUT = $signed(DATA_A) >>> shamt;
            SLT:   OUT = {{(WIDTH-1){1'b0}}, $signed(DATA_A) < $signed(DATA_B)};
            SLTU:  OUT = {{(WIDTH-1){1'b0}}, DATA_A < DATA_B};
            PASSB: OUT = DATA_B;
            default: ;
        endcase
    end

    assign N = OUT[MSB];
    assign Z = (OUT == {WIDTH{1'b0}});
endmodule
