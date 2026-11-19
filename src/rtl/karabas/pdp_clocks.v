`timescale 1ns / 1ps
`default_nettype wire
/*
 pdp_clocks.v (karabas)

 The clocks of the PDP-11/70 core, one PLL from CLK_50MHZ (/1 x10, VCO 500 MHz), as the coregen pll
 of upstream (10 / 50 / 12.5 MHz) plus the clocks of the karabas-go-modules video:
   clk_50     /10  50 MHz: the PDP-11 (clk_p, wishbone), the SRAM, the MCU link, the serial lines,
                   the DAC, the video timing of the terminal (vt10x clk50mhz)
   clk_125    /4   125 MHz and clk_125_n (180 degrees): the TMDS serialiser
   clk_25     /20  25 MHz: the pixel clock (640 x 480), the OSD, HDMI
   clk_10     /50  10 MHz: the PDP-11 of the terminal (vt10x cpuclk)
   clk_sd     /40  12.5 MHz: the SD card (sdclock of upstream)
 FT_CLK_OUT (8.33 MHz, every core must drive it on Mini / Mini G): a DCM on clk_50 (x1 / 6).
 upstream also had clk_50 at 180 degrees (clk_n): only its old DAC used it.
*/
module pdp_clocks (
	input wire clk_in,
	output wire clk_50,
	output wire clk_125,
	output wire clk_125_n,
	output wire clk_25,
	output wire clk_10,
	output wire clk_sd,
	output wire clk_8,
	output wire locked
);

wire [5:0] clk;
wire pll_locked;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(10),
	.CLKOUT0_DIVIDE(10),
	.CLKOUT1_DIVIDE(4),
	.CLKOUT2_DIVIDE(4),
	.CLKOUT2_PHASE(180.0),
	.CLKOUT3_DIVIDE(20),
	.CLKOUT4_DIVIDE(50),
	.CLKOUT5_DIVIDE(40),
	.IBUFG(1),
	.BUFG_MASK(6'b111111)
) pll (
	.clk_in(clk_in),
	.rst(1'b0),
	.clk_out(clk),
	.locked(pll_locked)
);

assign clk_50 = clk[0];
assign clk_125 = clk[1];
assign clk_125_n = clk[2];
assign clk_25 = clk[3];
assign clk_10 = clk[4];
assign clk_sd = clk[5];

wire dcm_locked;
kg_dcm #(
	.CLKIN_PERIOD(20.0),
	.CLKFX_MULTIPLY(2),
	.CLKFX_DIVIDE(12),
	.IBUFG(0)
) dcm_ft (
	.clk_in(clk_50),
	.rst(!pll_locked),
	.clk_fx(clk_8),
	.clk_fx180(),
	.clk_0(),
	.locked(dcm_locked)
);

assign locked = pll_locked;

endmodule
