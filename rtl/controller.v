module Control_Unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire       funct7_5, 
    input  wire       Zero,
    input  wire       N,
    input  wire       OVF,
    input  wire       CO,
    output reg  [1:0] PCSrc,       // Expanded to 2 bits
    output reg  [1:0] ResultSrc,
    output reg        MemWrite,
    output reg  [3:0] ALUControl,
    output reg        ALUSrc,
    output reg  [2:0] ImmSrc,
    output reg        RegWrite
);

    reg [1:0] ALUOp;
    reg       Branch, Jump, TakeBranch;

    always @(*) begin
        RegWrite  = 1'b0; ImmSrc = 3'b000; ALUSrc = 1'b0; MemWrite = 1'b0;
        ResultSrc = 2'b00; Branch = 1'b0; Jump = 1'b0; ALUOp = 2'b00;

        case(opcode)
            7'b0110011: begin RegWrite = 1'b1; ALUOp = 2'b10; end
            7'b0010011: begin RegWrite = 1'b1; ALUSrc = 1'b1; ALUOp = 2'b10; end
            7'b0000011: begin RegWrite = 1'b1; ALUSrc = 1'b1; ResultSrc = 2'b01; ALUOp = 2'b00; end
            7'b0100011: begin ImmSrc = 3'b001; ALUSrc = 1'b1; MemWrite = 1'b1; ALUOp = 2'b00; end
            7'b1100011: begin ImmSrc = 3'b010; Branch = 1'b1; ALUOp = 2'b01; end
            7'b1101111: begin RegWrite = 1'b1; ImmSrc = 3'b011; Jump = 1'b1; ResultSrc = 2'b10; end
            7'b1100111: begin RegWrite = 1'b1; ALUSrc = 1'b1; Jump = 1'b1; ResultSrc = 2'b10; ALUOp = 2'b00; end
            7'b0110111: begin RegWrite = 1'b1; ImmSrc = 3'b100; ALUSrc = 1'b1; ALUOp = 2'b11; end
            7'b0010111: begin RegWrite = 1'b1; ImmSrc = 3'b100; ResultSrc = 2'b11; end
            default: ;
        endcase
    end

    always @(*) begin
        case(ALUOp)
            2'b00: ALUControl = 4'b0000; 
            2'b01: ALUControl = 4'b0001; 
            2'b10: begin 
                case(funct3)
                    3'b000: ALUControl = (opcode == 7'b0110011 && funct7_5) ? 4'b0001 : 4'b0000;
                    3'b001: ALUControl = 4'b0101; 
                    3'b010: ALUControl = 4'b1000; 
                    3'b011: ALUControl = 4'b1001; 
                    3'b100: ALUControl = 4'b0100; 
                    3'b101: ALUControl = funct7_5 ? 4'b0111 : 4'b0110; 
                    3'b110: ALUControl = 4'b0011; 
                    3'b111: ALUControl = 4'b0010; 
                    default: ALUControl = 4'b0000;
                endcase
            end
            2'b11: ALUControl = 4'b1010; 
            default: ALUControl = 4'b0000;
        endcase
    end

    always @(*) begin
        case(funct3)
            3'b000: TakeBranch = Zero;               
            3'b001: TakeBranch = ~Zero;              
            3'b100: TakeBranch = (N != OVF);         
            3'b101: TakeBranch = (N == OVF);         
            3'b110: TakeBranch = (~CO);              
            3'b111: TakeBranch = (CO);               
            default: TakeBranch = 1'b0;
        endcase
    end

    // Updated PC Source Multiplexer Logic
    always @(*) begin
        if (opcode == 7'b1100111) begin
            PCSrc = 2'b10; // JALR requires ALU target routing
        end else if (Jump | (Branch & TakeBranch)) begin
            PCSrc = 2'b01; // JAL or taken Branch
        end else begin
            PCSrc = 2'b00; // Standard PC + 4
        end
    end
endmodule