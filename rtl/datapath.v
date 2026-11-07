module RISCV_Datapath #(
    parameter CLK_HZ = 50_000_000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire        en,           // step/run enable: architectural state advances only when high

    // Control Inputs
    input  wire [1:0]  PCSrc,
    input  wire [1:0]  ResultSrc,
    input  wire [3:0]  ALUControl,
    input  wire        ALUSrc,
    input  wire [2:0]  ImmSrc,
    input  wire        RegWrite,      // already gated by en in the top module
    input  wire        MemWrite_In,   // already gated by en in the top module

    // Debug & Memory Ports
    input  wire [4:0]  debug_reg_select,
    output wire [31:0] debug_reg_out,
    output wire [31:0] PC,
    output wire [31:0] Instr,

    // ALU Flags
    output wire        Zero,
    output wire        N,
    output wire        OVF,
    output wire        CO,

    // SPI I/O
    output wire        ACL_MOSI,
    input  wire        ACL_MISO,
    output wire        ACL_SCLK,
    output wire        ACL_CSN
);

    wire [31:0] PCNext, PCNext_computed, PCPlus4, PCTarget;
    wire [31:0] ImmExt, SrcA, SrcB, RD2, Result;
    wire [31:0] ALUResult_internal;
    wire [31:0] jalr_target;

    wire [31:0] spi_rd, dmem_rd, Muxed_ReadData, Load_Result;
    wire        spi_we;
    wire [3:0]  dmem_we;
    wire [3:0]  store_be;

    // JALR target = (rs1 + imm) with LSB forced to 0 (kept in a submodule)
    LSB_Clear #(32) jalr_mask (.in(ALUResult_internal), .out(jalr_target));

    // Next-PC source select
    Mux_4to1 #(32) mux_pc_next (
        .select(PCSrc),
        .input_0(PCPlus4),
        .input_1(PCTarget),
        .input_2(jalr_target),
        .input_3(32'd0),
        .output_value(PCNext_computed)
    );

    // Single-step hold: when en=0 the PC reloads itself (frozen);
    // when en=1 it takes the freshly computed next-PC.
    Mux_2to1 #(32) mux_pc_hold (
        .select(en), .input_0(PC), .input_1(PCNext_computed), .output_value(PCNext)
    );

    Register_reset #(32) pc_reg (.clk(clk), .reset(reset), .DATA(PCNext), .OUT(PC));
    Adder #(32) adder_pc_plus_4 (.DATA_A(PC), .DATA_B(32'd4),  .OUT(PCPlus4));
    Adder #(32) adder_pc_target (.DATA_A(PC), .DATA_B(ImmExt), .OUT(PCTarget));

    Instruction_memory #(4, 32) i_mem (.ADDR(PC), .RD(Instr));

    Register_file #(32) reg_file (
        .clk(clk), .reset(reset), .write_enable(RegWrite),
        .Source_select_0(Instr[19:15]), .Source_select_1(Instr[24:20]),
        .Destination_select(Instr[11:7]), .DATA(Result), .out_0(SrcA), .out_1(RD2),
        .Debug_Source_select(debug_reg_select), .Debug_out(debug_reg_out)
    );

    Extender imm_ext (.DATA(Instr), .select(ImmSrc), .Extended_data(ImmExt));
    Mux_2to1 #(32) mux_alu_srcb (.select(ALUSrc), .input_0(RD2), .input_1(ImmExt), .output_value(SrcB));

    ALU #(32) alu (
        .control(ALUControl), .CI(1'b0), .DATA_A(SrcA), .DATA_B(SrcB),
        .OUT(ALUResult_internal), .CO(CO), .OVF(OVF), .N(N), .Z(Zero)
    );

    // Per-byte write mask for SB/SH/SW (funct3 = Instr[14:12])
    Store_Decoder store_dec (.funct3(Instr[14:12]), .byte_enable(store_be));

    Memory_Interface_Decoder mem_decoder (
        .ADDR(ALUResult_internal), .MemWrite_In(MemWrite_In), .store_be(store_be),
        .SPI_ReadData(spi_rd), .Ext_ReadData(dmem_rd),
        .SPI_WE(spi_we), .Ext_WE(dmem_we), .ReadData_Out(Muxed_ReadData)
    );

    Memory #(4, 32) d_mem (
        .clk(clk), .WE(dmem_we), .ADDR(ALUResult_internal), .WD(RD2), .RD(dmem_rd)
    );

    SPI_Peripheral #(.CLK_HZ(CLK_HZ)) spi_module (
        .clk(clk), .reset(reset), .ADDR(ALUResult_internal), .WD(RD2), .WE(spi_we), .RD(spi_rd),
        .MOSI(ACL_MOSI), .MISO(ACL_MISO), .SCLK(ACL_SCLK), .CS_N(ACL_CSN)
    );

    // Format the loaded value (sign/zero extend for byte/half, pass through for word)
    Load_Extend load_ext (.funct3(Instr[14:12]), .raw(Muxed_ReadData), .extended(Load_Result));

    Mux_4to1 #(32) mux_result (
        .select(ResultSrc),
        .input_0(ALUResult_internal),
        .input_1(Load_Result),
        .input_2(PCPlus4),
        .input_3(PCTarget),
        .output_value(Result)
    );

endmodule
