// Seven-segment decoder for one hex digit. Output is active-low,
// bit order {g,f,e,d,c,b,a}.
module SSD (
    input  wire [3:0] value,
    output reg  [6:0] display
);
    // Segments that are lit (1 = on), inverted below for the active-low display.
    reg [6:0] lit;

    always @(*) begin
        case (value)
            4'h0: lit = 7'b0111111;
            4'h1: lit = 7'b0000110;
            4'h2: lit = 7'b1011011;
            4'h3: lit = 7'b1001111;
            4'h4: lit = 7'b1100110;
            4'h5: lit = 7'b1101101;
            4'h6: lit = 7'b1111101;
            4'h7: lit = 7'b0000111;
            4'h8: lit = 7'b1111111;
            4'h9: lit = 7'b1101111;
            4'hA: lit = 7'b1110111;
            4'hB: lit = 7'b1111100;
            4'hC: lit = 7'b0111001;
            4'hD: lit = 7'b1011110;
            4'hE: lit = 7'b1111001;
            4'hF: lit = 7'b1110001;
        endcase
        display = ~lit;
    end
endmodule
