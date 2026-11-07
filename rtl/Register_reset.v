// Register with a synchronous, active-high reset. Loads DATA every clock
// otherwise. Starts at zero after configuration.
module Register_reset #(parameter WIDTH = 8) (
    input  wire             clk,
    input  wire             reset,
    input  wire [WIDTH-1:0] DATA,
    output reg  [WIDTH-1:0] OUT = {WIDTH{1'b0}}
);
    always @(posedge clk) begin
        OUT <= reset ? {WIDTH{1'b0}} : DATA;
    end
endmodule
