// Board-level top module for the Nexys A7-100T.
//
// The single-cycle core needs about 17 ns for its longest path, so it cannot
// run at the board's 100 MHz clock. An MMCM derives a 50 MHz system clock
// (100 MHz x 8 / 16) and everything below runs from it, which keeps a single
// clock domain and leaves about 2-3 ns of timing slack.
module Nexys_A7(
    //////////// GCLK //////////
    input  wire        CLK100MHZ,
    //////////// BTN //////////
    input  wire        BTNU,
                       BTNL, BTNC, BTNR,
                       BTND,
    //////////// SW //////////
    input  wire [15:0] SW,
    //////////// LED //////////
    output wire [15:0] LED,
    //////////// 7 SEG //////////
    output wire [7:0]  AN,
    output wire        CA, CB, CC, CD, CE, CF, CG, DP,
    //////////// ADXL362 SPI //////////
    output wire        ACL_MOSI,
    input  wire        ACL_MISO,
    output wire        ACL_SCLK,
    output wire        ACL_CSN
);
    localparam CLK_HZ = 50_000_000;   // system clock produced by the MMCM below

    // ---------------- Clock generation ----------------
    wire clk_fb, clk_mmcm, clk_sys, mmcm_locked;

    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKIN1_PERIOD    (10.0),     // 100 MHz input
        .DIVCLK_DIVIDE    (1),
        .CLKFBOUT_MULT_F  (8.0),      // VCO = 800 MHz
        .CLKOUT0_DIVIDE_F (16.0),     // 800 / 16 = 50 MHz
        .STARTUP_WAIT     ("FALSE")
    ) sys_mmcm (
        .CLKIN1   (CLK100MHZ),
        .CLKFBIN  (clk_fb),
        .CLKFBOUT (clk_fb),
        .CLKOUT0  (clk_mmcm),
        .LOCKED   (mmcm_locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG sys_clk_buf (.I(clk_mmcm), .O(clk_sys));

    // Release reset only after the MMCM has locked (two-flop synchroniser).
    reg [1:0] lock_sync = 2'b00;
    always @(posedge clk_sys) lock_sync <= {lock_sync[0], mmcm_locked};

    // ---------------- Board logic ----------------
    wire [31:0] reg_out, PC;
    wire [4:0]  buttons;       // debounced: [4]=BTNU [3]=BTNL [2]=BTNC [1]=BTNR [0]=BTND
    wire        step_pulse;
    wire        cpu_reset = buttons[0] | ~lock_sync[1];

    assign LED = SW;

    debouncer #(.HOLD_CYCLES(CLK_HZ / 10)) debouncer_0(     // 100 ms hold-off
        .clk        (clk_sys),
        .buttons    ({BTNU, BTNL, BTNC, BTNR, BTND}),
        .out        (buttons)
    );

    // BTNU press -> one system-clock cycle enable -> the CPU advances exactly
    // one instruction. The processor and SPI run on the full system clock, so
    // an SPI transaction completes at 1 Mbps right after the X_Start store.
    OnePulse step_gen(
        .clk    (clk_sys),
        .signal (buttons[4]),   // debounced BTNU
        .pulse  (step_pulse)
    );

    MSSD #(.TICKS(CLK_HZ / 1000 - 1)) mssd_0(               // ~1 ms per digit
        .clk        (clk_sys),
        .value      ({PC[7:0], reg_out[23:0]}),
        .dpValue    (8'b01000000),
        .display    ({CG, CF, CE, CD, CC, CB, CA}),
        .DP         (DP),
        .AN         (AN)
    );

    RISCV_Top #(.CLK_HZ(CLK_HZ)) my_computer(
        .clk              (clk_sys),
        .reset            (cpu_reset),  // BTND held, or MMCM not yet locked
        .en               (step_pulse), // BTNU press = single instruction step
        .debug_reg_select (SW[4:0]),
        .debug_reg_out    (reg_out),
        .PC               (PC),
        .ACL_MOSI         (ACL_MOSI),
        .ACL_MISO         (ACL_MISO),
        .ACL_SCLK         (ACL_SCLK),
        .ACL_CSN          (ACL_CSN)
    );

endmodule
