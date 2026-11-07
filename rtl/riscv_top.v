module RISCV_Top #(
    parameter CLK_HZ = 50_000_000   // system clock frequency, used to time the SPI clock
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        en,            // step/run enable (tie high for free-running, e.g. in the testbench)

    // Debug Interfaces
    input  wire [4:0]  debug_reg_select,
    output wire [31:0] debug_reg_out,
    output wire [31:0] PC,

    // External SPI interfaces to ADXL362
    output wire        ACL_MOSI,
    input  wire        ACL_MISO,
    output wire        ACL_SCLK,
    output wire        ACL_CSN
);

    wire [31:0] Instr;
    wire        Zero, N, OVF, CO;

    wire [1:0]  PCSrc;
    wire        ALUSrc, RegWrite, MemWrite;
    wire [1:0]  ResultSrc;
    wire [3:0]  ALUControl;
    wire [2:0]  ImmSrc;

    // Single-step gating: register-file and memory writes only commit on an
    // enabled cycle. The SPI peripheral itself still runs every clk so it can
    // complete a transaction at full speed after the X_Start store is issued.
    wire RegWrite_en = RegWrite & en;
    wire MemWrite_en = MemWrite & en;

    Control_Unit controller (
        .opcode     (Instr[6:0]),
        .funct3     (Instr[14:12]),
        .funct7_5   (Instr[30]),
        .Zero       (Zero),
        .N          (N),
        .OVF        (OVF),
        .CO         (CO),
        .PCSrc      (PCSrc),
        .ResultSrc  (ResultSrc),
        .MemWrite   (MemWrite),
        .ALUControl (ALUControl),
        .ALUSrc     (ALUSrc),
        .ImmSrc     (ImmSrc),
        .RegWrite   (RegWrite)
    );

    RISCV_Datapath #(.CLK_HZ(CLK_HZ)) datapath (
        .clk              (clk),
        .reset            (reset),
        .en               (en),

        .PCSrc            (PCSrc),
        .ResultSrc        (ResultSrc),
        .ALUControl       (ALUControl),
        .ALUSrc           (ALUSrc),
        .ImmSrc           (ImmSrc),
        .RegWrite         (RegWrite_en),
        .MemWrite_In      (MemWrite_en),

        .debug_reg_select (debug_reg_select),
        .debug_reg_out    (debug_reg_out),
        .PC               (PC),
        .Instr            (Instr),

        .Zero             (Zero),
        .N                (N),
        .OVF              (OVF),
        .CO               (CO),

        .ACL_MOSI         (ACL_MOSI),
        .ACL_MISO         (ACL_MISO),
        .ACL_SCLK         (ACL_SCLK),
        .ACL_CSN          (ACL_CSN)
    );

endmodule
