// Multiplexed 8-digit seven-segment driver. Cycles through the eight hex
// digits of `value`, enabling one anode at a time (active-low) and showing its
// decimal point from `dpValue` (a 1 bit lights the point). The digit advances
// every TICKS+1 clocks; set TICKS to (clock Hz / 1000) - 1 for about 1 ms per
// digit, which is a refresh rate of roughly 125 Hz for all eight digits.
module MSSD #(
    parameter TICKS = 100000
) (
    input  wire        clk,
    input  wire [31:0] value,
    input  wire [7:0]  dpValue,
    output wire [6:0]  display,
    output wire        DP,
    output wire [7:0]  AN
);
    reg [2:0]  digit = 3'd0;
    reg [31:0] tick  = 32'd0;

    always @(posedge clk) begin
        if (tick == TICKS) begin
            tick  <= 32'd0;
            digit <= digit + 3'd1;
        end else begin
            tick <= tick + 32'd1;
        end
    end

    assign AN = ~(8'b0000_0001 << digit);
    assign DP = ~dpValue[digit];

    SSD digit_decoder (
        .value   (value[digit*4 +: 4]),
        .display (display)
    );
endmodule
