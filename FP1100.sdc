# Restricciones propias del core (las generales estan en sys/sys_top.sdc).

# Salidas de rtl/pll.v (PLL "General"). En get_pins el patron va con
# -compatibility_mode; en get_clocks, con los corchetes escapados.
set clk_sys_pin {*|pll|pll_inst|altera_pll_i|*[0].*|divclk}
set clk_sys {emu|pll|pll_inst|altera_pll_i|general\[0\].gpll~PLL_OUTPUT_COUNTER|divclk}
set clk_pix {emu|pll|pll_inst|altera_pll_i|general\[1\].gpll~PLL_OUTPUT_COUNTER|divclk}
set clk_vid {emu|pll|pll_inst|altera_pll_i|general\[2\].gpll~PLL_OUTPUT_COUNTER|divclk}

# ----------------------------------------------------------------------------
# SDRAM (rtl/fp1100/rtl/fp1100_sdram.v)
# ----------------------------------------------------------------------------
# SDRAM_CLK sale por un registro DDR con datain_h = 0 y datain_l = 1, es decir,
# clk_sys (32 MHz) invertido.
create_generated_clock -name SDRAM_CLK -source [get_pins -compatibility_mode $clk_sys_pin] -invert [get_ports {SDRAM_CLK}]

# Tiempos del chip a CL2 (modulos SDRAM de MiSTer):
#   entrada: tAC 6 ns + pista (max), tOH 2,5 ns + pista (min)
#   salida:  tIS 1,5 ns (setup), tIH 0,8 ns (hold)
set_input_delay  -clock SDRAM_CLK -max 6.4  [get_ports {SDRAM_DQ[*]}]
set_input_delay  -clock SDRAM_CLK -min 3.2  [get_ports {SDRAM_DQ[*]}]
set_output_delay -clock SDRAM_CLK -max 1.5  [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]
set_output_delay -clock SDRAM_CLK -min -0.8 [get_ports {SDRAM_DQ[*] SDRAM_A[*] SDRAM_BA[*] SDRAM_DQML SDRAM_DQMH SDRAM_n* SDRAM_CKE}]

# ----------------------------------------------------------------------------
# clk_sys <-> video
# ----------------------------------------------------------------------------
# El CRTC (clk_sys) le pasa cada linea a fp1100_display (clk_pix) con un
# conmutador sincronizado, y los buffers de linea son de doble reloj: como en
# las otras placas, los dos dominios se tratan como asincronos. clk_pix y
# clk_vid si se analizan juntos (clk_vid es el doble exacto de clk_pix).
set_clock_groups -asynchronous \
	-group [get_clocks [list $clk_sys SDRAM_CLK]] \
	-group [get_clocks [list $clk_pix $clk_vid]]
