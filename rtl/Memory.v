// Byte-addressable data memory built from four byte-wide banks, so that it
// maps onto distributed (LUT) RAM instead of thousands of flip-flops.
//
// Interface convention (unchanged from the datapath's point of view):
//   * Read:  RD holds the bytes starting at the exact byte address ADDR in its
//            LOW lanes. A load only needs funct3 to format it (LB/LH/LW), no
//            byte offset.
//   * Write: WD and WE are given unshifted, as if writing at the low lanes.
//            WE[k] enables byte k. SB -> 0001, SH -> 0011, SW -> 1111.
//
// Internally the storage is word-organised. A write is shifted up into the
// lanes selected by ADDR[1:0], and a read word is shifted back down. Accesses
// must therefore be naturally aligned (halfword on even addresses, word on
// multiples of four); bytes that would cross a word boundary are dropped on a
// write and read as zero.
//
// BYTE_SIZE is fixed at 4 by this implementation. DEPTH is in bytes.
module Memory #(
    parameter BYTE_SIZE  = 4,
    parameter ADDR_WIDTH = 32,
    parameter DEPTH      = 1024   // bytes: 0x000-0x3FF, up to the SPI window at 0x400
)(
    input  wire                     clk,
    input  wire [BYTE_SIZE-1:0]     WE,    // per-byte write enable (1 bit per byte lane)
    input  wire [ADDR_WIDTH-1:0]    ADDR,
    input  wire [(BYTE_SIZE*8)-1:0] WD,
    output wire [(BYTE_SIZE*8)-1:0] RD
);
    localparam WORDS = DEPTH / 4;
    localparam AW    = $clog2(WORDS);

    wire [1:0]    off  = ADDR[1:0];
    wire [AW-1:0] widx = ADDR[AW+1:2];

    // Move the write data and byte enables into the lanes chosen by the offset.
    wire [7:0]  we_wide = {4'b0000, WE[3:0]} << off;
    wire [3:0]  we_s    = we_wide[3:0];
    wire [31:0] wd_s    = WD << {off, 3'b000};

    // One 8-bit-wide bank per byte lane, asynchronous read, synchronous write.
    wire [31:0] word;

    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : lane
            reg [7:0] bank [0:WORDS-1];

            integer j;
            initial begin
                for (j = 0; j < WORDS; j = j + 1) bank[j] = 8'h00;
            end

            always @(posedge clk) begin
                if (we_s[k]) bank[widx] <= wd_s[8*k +: 8];
            end

            assign word[8*k +: 8] = bank[widx];
        end
    endgenerate

    // Bring the addressed byte(s) down to the low lanes.
    assign RD = word >> {off, 3'b000};
endmodule
