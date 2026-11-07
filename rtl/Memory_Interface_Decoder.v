// Routes a memory access to either the data memory or the SPI peripheral,
// and produces the data-memory per-byte write-enable mask.
//
// SPI window: 0x00000400 .. 0x0000040F  (covers TX/RX/length/start registers)
//   - The SPI peripheral handles its own register/byte semantics, so it gets
//     a single write-enable and the raw write data (WD) elsewhere.
//   - The data memory gets the per-byte mask (store_be) so SB/SH/SW behave.
module Memory_Interface_Decoder (
    input  wire [31:0] ADDR,
    input  wire        MemWrite_In,
    input  wire [3:0]  store_be,       // per-byte mask from Store_Decoder
    input  wire [31:0] SPI_ReadData,
    input  wire [31:0] Ext_ReadData,
    output wire        SPI_WE,
    output wire [3:0]  Ext_WE,
    output wire [31:0] ReadData_Out
);
    wire is_spi_addr = (ADDR[31:12] == 20'h00000) && (ADDR[11:4] == 8'h40);

    assign SPI_WE       = MemWrite_In & is_spi_addr;
    assign Ext_WE       = (MemWrite_In & ~is_spi_addr) ? store_be : 4'b0000;
    assign ReadData_Out = is_spi_addr ? SPI_ReadData : Ext_ReadData;
endmodule
