// Produces a single one-clock-wide pulse on each 0->1 transition of `signal`.
// Used to turn a debounced button press into one CPU step.
module OnePulse (
    input  wire clk,
    input  wire signal,
    output reg  pulse
);
    reg prev;
    initial begin
        prev  = 1'b0;
        pulse = 1'b0;
    end
    always @(posedge clk) begin
        pulse <= signal & ~prev;
        prev  <= signal;
    end
endmodule
