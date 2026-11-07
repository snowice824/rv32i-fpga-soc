module Instruction_memory #(
    parameter BYTE_SIZE  = 4, 
    parameter ADDR_WIDTH = 32
)(
    input  wire [ADDR_WIDTH-1:0] ADDR,
    output wire [(BYTE_SIZE*8)-1:0] RD 
);

    // Instantiate memory as an array of 256 32-bit words
    reg [(BYTE_SIZE*8)-1:0] mem [255:0];
    
    integer i;

    initial begin
        // Initialize memory to zero to prevent X state propagation
        for (i = 0; i < 256; i = i + 1) begin
            mem[i] = 0;
        end
        
        // Read 32-bit machine code lines directly into the word-sized array
        $readmemh("Instructions.hex", mem);
    end

    // The RISC-V Program Counter is byte-addressed. 
    // Divide the address by 4 (shift right by 2) to access the word-aligned array.
    assign RD = mem[ADDR[31:2]];

endmodule