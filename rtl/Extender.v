module Extender (
    input  wire [31:0] DATA,   
    input  wire [2:0]  select, 
    output reg  [31:0] Extended_data
);

    always @(*) begin
        case(select)
            3'b000: Extended_data = {{20{DATA[31]}}, DATA[31:20]};
            3'b001: Extended_data = {{20{DATA[31]}}, DATA[31:25], DATA[11:7]};
            3'b010: Extended_data = {{20{DATA[31]}}, DATA[7], DATA[30:25], DATA[11:8], 1'b0};
            3'b011: Extended_data = {{12{DATA[31]}}, DATA[19:12], DATA[20], DATA[30:21], 1'b0};
            3'b100: Extended_data = {DATA[31:12], 12'b0};
            default: Extended_data = 32'd0;
        endcase
    end
endmodule