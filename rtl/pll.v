// PLL del FP-1100 para MiSTer: 50 MHz -> VCO 800 MHz
//   outclk_0  32 MHz  clk_sys  (/25)
//   outclk_1  25 MHz  clk_pix  (/32): la relacion 25/32 con clk_sys tiene que ser exacta
//   outclk_2  50 MHz  clk_vid  (/16): CLK_VIDEO, el doble exacto de clk_pix
`timescale 1 ps / 1 ps
module pll (
		input  wire  refclk,
		input  wire  rst,
		output wire  outclk_0,
		output wire  outclk_1,
		output wire  outclk_2,
		output wire  locked
	);

	pll_0002 pll_inst (
		.refclk   (refclk),
		.rst      (rst),
		.outclk_0 (outclk_0),
		.outclk_1 (outclk_1),
		.outclk_2 (outclk_2),
		.locked   (locked)
	);

endmodule
