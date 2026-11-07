// SPI master peripheral for the ADXL362 (Mode 0: CPOL=0, CPHA=0).
// SCLK is 1 MHz (1 Mbps), divided down from the system clock whose frequency
// in Hz is given by CLK_HZ (an even multiple of 2 MHz, e.g. 50 or 100 MHz).
//
// Memory-mapped registers:
//   0x400  TX_Data   (SW)  32-bit, little endian: byte0 = bits[7:0] sent first
//   0x404  TX_Length (SB)  number of bytes to transmit (<=4)
//   0x405  RX_Length (SB)  number of bytes to receive  (<=4)
//   0x406  X_Start   (SB)  write -> start one transaction
//   0x408  RX_Data   (LW)  32-bit, little endian: byte0 = first byte received
//
// Each transaction: assert CS, send TX_Length bytes (MSB-first within a byte,
// byte0 first), then receive RX_Length bytes into RX_Data, then de-assert CS.
module SPI_Peripheral #(
    parameter CLK_HZ = 50_000_000
) (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] ADDR,
    input  wire [31:0] WD,
    input  wire        WE,
    output reg  [31:0] RD,
    output reg         MOSI,
    input  wire        MISO,
    output reg         SCLK,
    output reg         CS_N
);

    // ---------------- Memory-mapped registers ----------------
    reg [31:0] tx_data;
    reg [7:0]  tx_length, rx_length;
    reg [31:0] rx_data;
    reg        x_start;

    // ---------------- FSM ----------------
    localparam IDLE = 2'd0, TRANSFER = 2'd1, DONE = 2'd2;
    reg [1:0]  state;

    // Baud generator: toggle SCLK every CLK_HZ/2e6 clocks -> SCLK = 1 MHz
    // (50 clocks per half period at 100 MHz, 25 at 50 MHz).
    localparam [6:0] HALF = (CLK_HZ / 2_000_000) - 1;
    reg [6:0]  clk_cnt;
    wire       tick = (clk_cnt == HALF);

    reg [31:0] tx_sh;             // TX shift register, MSB sent first
    reg [6:0]  tx_bits, rx_bits;  // bit counts for each phase (<=32 each)
    reg [6:0]  bit_cnt;           // bits clocked so far

    reg [7:0]  cur_byte;          // RX byte under assembly (MSB first)
    reg [2:0]  rx_bit_in_byte;
    reg [2:0]  rx_byte_idx;

    // ---------------- Register write interface ----------------
    always @(posedge clk) begin
        if (reset) begin
            tx_data   <= 32'd0;
            tx_length <= 8'd0;
            rx_length <= 8'd0;
            x_start   <= 1'b0;
        end else if (WE) begin
            case (ADDR[11:0])
                12'h400: tx_data   <= WD;
                12'h404: tx_length <= WD[7:0];
                12'h405: rx_length <= WD[7:0];
                12'h406: x_start   <= WD[0];
                default: ;
            endcase
        end else if (state != IDLE) begin
            x_start <= 1'b0;       // request consumed once a transaction is running
        end
    end

    // ---------------- Register read interface ----------------
    always @(*) begin
        case (ADDR[11:0])
            12'h400: RD = tx_data;
            12'h404: RD = {24'd0, tx_length};
            12'h405: RD = {24'd0, rx_length};
            12'h406: RD = {31'd0, x_start};
            12'h408: RD = rx_data;
            default: RD = 32'd0;
        endcase
    end

    // ---------------- SPI master FSM ----------------
    always @(posedge clk) begin
        if (reset) begin
            state          <= IDLE;
            CS_N           <= 1'b1;
            SCLK           <= 1'b0;
            MOSI           <= 1'b0;
            clk_cnt        <= 7'd0;
            bit_cnt        <= 7'd0;
            rx_data        <= 32'd0;
            rx_bit_in_byte <= 3'd0;
            rx_byte_idx    <= 3'd0;
        end else begin
            case (state)

                IDLE: begin
                    CS_N           <= 1'b1;
                    SCLK           <= 1'b0;
                    clk_cnt        <= 7'd0;
                    bit_cnt        <= 7'd0;
                    rx_bit_in_byte <= 3'd0;
                    rx_byte_idx    <= 3'd0;
                    if (x_start && ((tx_length != 8'd0) || (rx_length != 8'd0))) begin
                        // Byte-reverse so the little-endian byte0 (bits[7:0]) is
                        // shifted out first, MSB-first within each byte.
                        tx_sh   <= {tx_data[7:0], tx_data[15:8], tx_data[23:16], tx_data[31:24]};
                        tx_bits <= {tx_length, 3'b000};   // *8
                        rx_bits <= {rx_length, 3'b000};   // *8
                        rx_data <= 32'd0;
                        CS_N    <= 1'b0;
                        SCLK    <= 1'b0;
                        // First MOSI bit must be valid before the first rising edge.
                        MOSI    <= (tx_length != 8'd0) ? tx_data[7] : 1'b0;
                        state   <= TRANSFER;
                    end
                end

                TRANSFER: begin
                    if (tick) begin
                        clk_cnt <= 7'd0;
                        if (SCLK == 1'b0) begin
                            // ---- Leading (rising) edge: master samples ----
                            SCLK <= 1'b1;
                            if (bit_cnt >= tx_bits) begin
                                // RX bit -> assemble bytes in little-endian order
                                cur_byte <= {cur_byte[6:0], MISO};
                                if (rx_bit_in_byte == 3'd7) begin
                                    rx_data[rx_byte_idx*8 +: 8] <= {cur_byte[6:0], MISO};
                                    rx_byte_idx    <= rx_byte_idx + 1'b1;
                                    rx_bit_in_byte <= 3'd0;
                                end else begin
                                    rx_bit_in_byte <= rx_bit_in_byte + 1'b1;
                                end
                            end
                        end else begin
                            // ---- Trailing (falling) edge: set up next bit ----
                            SCLK    <= 1'b0;
                            bit_cnt <= bit_cnt + 1'b1;
                            if ((bit_cnt + 1'b1) < tx_bits) begin
                                tx_sh <= {tx_sh[30:0], 1'b0};
                                MOSI  <= tx_sh[30];
                            end else begin
                                MOSI  <= 1'b0;     // RX phase: MOSI idle
                            end
                            if ((bit_cnt + 1'b1) >= (tx_bits + rx_bits)) begin
                                state <= DONE;
                            end
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DONE: begin
                    CS_N  <= 1'b1;
                    SCLK  <= 1'b0;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
