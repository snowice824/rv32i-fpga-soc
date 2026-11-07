module Register_file #(parameter WIDTH = 32)
(
    input  wire             clk,
    input  wire             write_enable,
    input  wire             reset,
    input  wire [4:0]       Source_select_0,    
    input  wire [4:0]       Source_select_1,    
    input  wire [4:0]       Destination_select, 
    input  wire [WIDTH-1:0] DATA,
    input  wire [4:0]       Debug_Source_select,
    output wire [WIDTH-1:0] out_0,
    output wire [WIDTH-1:0] out_1,
    output wire [WIDTH-1:0] Debug_out
);

    reg [WIDTH-1:0] registers [31:1];
    integer i;

    always @(posedge clk) begin
        if (reset == 1'b1) begin
            for (i = 1; i < 32; i = i + 1) begin
                registers[i] <= {WIDTH{1'b0}};
            end
        end else if (write_enable == 1'b1 && Destination_select != 5'd0) begin
            registers[Destination_select] <= DATA;
        end
    end

    assign out_0 = (Source_select_0 == 5'd0) ? {WIDTH{1'b0}} : registers[Source_select_0];
    assign out_1 = (Source_select_1 == 5'd0) ? {WIDTH{1'b0}} : registers[Source_select_1];
    assign Debug_out = (Debug_Source_select == 5'd0) ? {WIDTH{1'b0}} : registers[Debug_Source_select];
endmodule