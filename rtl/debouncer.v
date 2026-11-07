// Debounces five push buttons, one independent filter per button.
//
// Each filter is a hold-off timer. While the output is low the counter fills
// to HOLD_CYCLES; only then is a high input accepted. While the output is
// high the counter drains to zero; only then is a low input accepted. The
// output therefore cannot change again for at least HOLD_CYCLES clocks after
// any change (10M clocks = 100 ms at 100 MHz).
module debouncer #(parameter HOLD_CYCLES = 10000000) (
    input  wire       clk,
    input  wire [4:0] buttons,
    output reg  [4:0] out = 5'b00000
);
    reg [31:0] timer [0:4];

    integer k;
    initial begin
        for (k = 0; k < 5; k = k + 1) timer[k] = 32'd0;
    end

    genvar i;
    generate
        for (i = 0; i < 5; i = i + 1) begin : filter
            always @(posedge clk) begin
                if (!out[i]) begin
                    if (timer[i] != HOLD_CYCLES)
                        timer[i] <= timer[i] + 32'd1;
                    else if (buttons[i])
                        out[i] <= 1'b1;
                end else begin
                    if (timer[i] != 32'd0)
                        timer[i] <= timer[i] - 32'd1;
                    else if (!buttons[i])
                        out[i] <= 1'b0;
                end
            end
        end
    endgenerate
endmodule
