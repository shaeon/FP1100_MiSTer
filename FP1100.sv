//-------------------------------------------------------------------------------------------------
// Casio FP-1100 / FP-1000 para MiSTer
//
// Core: Shaeon (Carlos Palmero), https://github.com/shaeon/fp1100 (submodulo rtl/fp1100, el mismo
//       que usan la Poseidon, la SiDi y la Calypso). Este fichero hace con el marco de MiSTer lo
//       que fp1100_top.sv hace con el de MiST: relojes, hps_io, video, audio, cinta y LEDs. La
//       maquina (rtl/fp1100/rtl/fp1100.v) va sin tocar.
//
// Relojes (rtl/pll.v, todos de un VCO de 800 MHz, asi que van en fase):
//   clk_sys  32 MHz   la maquina y la SDRAM (SDRAM_CLK = clk_sys invertido)
//   clk_pix  25 MHz   fp1100_display: puntos de 12,5 MHz, 800 por linea. La relacion 25/32 con
//                     clk_sys tiene que ser exacta (ver la cabecera de fp1100_display.v)
//   clk_vid  50 MHz   CLK_VIDEO. El scandoubler de MiSTer necesita CLK_VIDEO >= 4 x ce_pix (lo
//                     usa para el HQ2x y para repartir los puntos), y a 25 MHz con puntos de 12,5
//                     no llega: la salida de fp1100_display se pasa a 50 MHz, donde cada punto
//                     dura 4 ciclos (2 en el modo de 31 kHz, que no pasa por el scandoubler).
//
// ROM (games/FP1100/boot.rom, indice 0): el FP1100.ROM de 48K del core de MiST (ver
// rtl/fp1100/roms/README.md). La maquina se queda en reset mientras se carga.
//
// Cinta: WAV (indice 2) a la SDRAM desde 010000h, o el ADC de la placa I/O.
// Discos: imagenes EDSK en las unidades A y B (FDC pack).
//
// This program is free software; you can redistribute it and/or modify it under the terms of the
// GNU General Public License as published by the Free Software Foundation; either version 3 of
// the License, or (at your option) any later version.
//-------------------------------------------------------------------------------------------------
`default_nettype none

module emu
(
	`include "sys/emu_ports.vh"
);
//--- defaults ------------------------------------------------------------------------------------

	assign USER_OUT = '1;
	assign {UART_RTS, UART_TXD, UART_DTR} = 0;
	assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

	assign VGA_F1 = 0;
	assign VGA_SCALER = 0;
	assign VGA_DISABLE = 0;
	assign HDMI_FREEZE = 0;
	assign HDMI_BLACKOUT = 0;
	assign HDMI_BOB_DEINT = 0;

	assign BUTTONS = 0;
	assign LED_POWER = 0;

	assign {DDRAM_CLK, DDRAM_BURSTCNT, DDRAM_ADDR, DDRAM_RD, DDRAM_DIN, DDRAM_BE, DDRAM_WE} = '0;

//--- config string -------------------------------------------------------------------------------
//
//  bits usados: 0-27
//  0         1         2         3
//  01234567890123456789012345678901
//  XXXXXXXXXXXXXXXXXXXXXXXXXXXX
//

	`include "build_id.v"
	localparam CONF_STR =
	{
		"FP1100;;",
		"-;",
		"S0,DSK,Drive A:;",
		"S1,DSK,Drive B:;",
		"F2,WAV,Load tape;",
		"-;",
		"P1,Video;",
		"P1-;",
		"P1O[3:2],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
		"P1O[6:4],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
		"P1O[8:7],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
		"P1-;",
		"P1O[11],Screen 1 display,400 lines,Fields;",
		"P1O[14],Green mode colour,Green,White;",
		"P1O[22:20],H centre,0,+4,+8,+12,-16,-12,-8,-4;",
		"P1O[25:23],V centre,0,+2,+4,+6,-8,-6,-4,-2;",
		"P2,Machine;",
		"P2-;",
		"P2O[12],Model,FP-1100,FP-1000;",
		"P2O[9],Text width,80,40;",
		"P2O[10],Screen,0,1;",
		"P2O[13],CMT baud,1200,300;",
		"P2O[15],FDC pack,On,Off;",
		"P2-;",
		"P2O[27],SDRAM read,Early,Normal;",
		"P2-;",
		"P2F0,ROM,Load ROM;",
		"P3,Tape;",
		"P3-;",
		"P3O[16],Tape input,WAV file,ADC;",
		"P3O[26],Invert ADC,Off,On;",
		"P3O[17],Tape,Play,Pause;",
		"P3O[19:18],Tape monitor,Motor on,Always,Off;",
		"P3T[1],Rewind tape;",
		"-;",
		"R[0],Reset;",
		"V,v",`BUILD_DATE
	};

//--- relojes -------------------------------------------------------------------------------------

	wire clk_sys, clk_pix, clk_vid;
	wire pll_locked;

	pll pll
	(
		.refclk  (CLK_50M   ),
		.rst     (1'b0      ),
		.outclk_0(clk_sys   ),     // 32 MHz
		.outclk_1(clk_pix   ),     // 25 MHz
		.outclk_2(clk_vid   ),     // 50 MHz
		.locked  (pll_locked)
	);

	localparam CLK_HZ = 32_000_000;

//--- hps io --------------------------------------------------------------------------------------

	wire [127:0] status;
	wire [  1:0] buttons;
	wire         forced_scandoubler;
	wire [ 21:0] gamma_bus;

	wire         ps2_kbd_clk, ps2_kbd_data;

	wire         ioctl_download;
	wire [ 15:0] ioctl_index;
	wire         ioctl_wr;
	wire [ 26:0] ioctl_addr;
	wire [  7:0] ioctl_dout;
	wire         ioctl_wait;

	wire [  1:0] img_mounted;
	wire         img_readonly;
	wire [ 63:0] img_size;

	wire [ 31:0] sd_lba[2];
	wire [  1:0] sd_rd;
	wire [  1:0] sd_wr;
	wire [  1:0] sd_ack;
	wire [ 13:0] sd_buff_addr;
	wire [  7:0] sd_buff_dout;
	wire [  7:0] sd_buff_din[2];
	wire         sd_buff_wr;

	// Teclado por la linea PS/2 serie, como en MiST: fp1100_ps2 la recibe y guarda el estado de
	// E0/F0 entre bytes (y filtra la tecla Pausa). PS2DIV 1000: ~16 kHz a 32 MHz, el reloj de un
	// teclado PS/2 de verdad (PS2_16KHZ en las otras placas).
	hps_io #(.CONF_STR(CONF_STR), .PS2DIV(1000), .VDNUM(2)) hps_io
	(
		.clk_sys           (clk_sys           ),
		.HPS_BUS           (HPS_BUS           ),
		.EXT_BUS           (                  ),
		.gamma_bus         (gamma_bus         ),

		.forced_scandoubler(forced_scandoubler),
		.buttons           (buttons           ),
		.status            (status            ),
		.status_menumask   (16'd0             ),

		.ps2_kbd_clk_out   (ps2_kbd_clk       ),
		.ps2_kbd_data_out  (ps2_kbd_data      ),

		.ioctl_download    (ioctl_download    ),
		.ioctl_index       (ioctl_index       ),
		.ioctl_wr          (ioctl_wr          ),
		.ioctl_addr        (ioctl_addr        ),
		.ioctl_dout        (ioctl_dout        ),
		.ioctl_wait        (ioctl_wait        ),

		.img_mounted       (img_mounted       ),
		.img_readonly      (img_readonly      ),
		.img_size          (img_size          ),

		.sd_lba            (sd_lba            ),
		.sd_blk_cnt        ('{6'd0, 6'd0}     ),
		.sd_rd             (sd_rd             ),
		.sd_wr             (sd_wr             ),
		.sd_ack            (sd_ack            ),
		.sd_buff_addr      (sd_buff_addr      ),
		.sd_buff_dout      (sd_buff_dout      ),
		.sd_buff_din       (sd_buff_din       ),
		.sd_buff_wr        (sd_buff_wr        )
	);

//--- carga de ficheros ---------------------------------------------------------------------------

	// Reparto de boot.rom (FP1100.ROM, 48K):
	//   0000-8FFF   36K  basic.rom  ROM del Z80       -> SDRAM 000000
	//   9000-9FFF    4K  sub1.rom   ROM interna 7801  -> block RAM (fp1100_upd7801)
	//   A000-AFFF    4K  sub2.rom   ROM sub 1000      -> block RAM (fp1100_sub)
	//   B000-BFFF    4K  sub3.rom   chargen F000      -> block RAM (fp1100_sub)
	wire sdram_free;
	wire rom_dl  = ioctl_download & (ioctl_index[5:0] == 6'd0);
	wire in_z80  = ioctl_addr < 27'h9000;
	wire in_sub1 = (ioctl_addr[26:12] == 15'h9);
	wire in_sub2 = (ioctl_addr[26:12] == 15'hA);
	wire in_sub3 = (ioctl_addr[26:12] == 15'hB);

	// Indice 2: el WAV de la cinta, a la SDRAM desde 010000h (hasta 3EFFFFh)
	wire tape_dl = ioctl_download & (ioctl_index[5:0] == 6'd2);
	wire dl_wr   = (rom_dl & ioctl_wr & in_z80) | (tape_dl & ioctl_wr & (ioctl_addr < 27'h3F0000));
	wire [23:0] dl_sdram_addr = tape_dl ? (24'h010000 + ioctl_addr[23:0]) : {3'd0, ioctl_addr[20:0]};

	// fp1100.v guarda UNA escritura pendiente para la SDRAM: hps_io espera hasta que la ha pasado
	// al controlador (en MiST hacia lo mismo clkref_n de data_io)
	assign ioctl_wait = (rom_dl | tape_dl) & ~sdram_free;

	reg        tape_dl_d = 1'b0, tape_cargada = 1'b0;
	reg [23:0] tape_tamano = 24'd0;
	always @(posedge clk_sys) begin
		tape_dl_d    <= tape_dl;
		tape_cargada <= tape_dl_d & ~tape_dl;
		if (tape_dl & ioctl_wr) tape_tamano <= ioctl_addr[23:0] + 24'd1;
	end

	reg st1_d = 1'b0, tape_rebobinar = 1'b0;
	always @(posedge clk_sys) begin
		st1_d          <= status[1];
		tape_rebobinar <= status[1] & ~st1_d;
	end

	// La maquina se reinicia al cargar la ROM (no al cargar una cinta); la SDRAM solo cuando el
	// PLL pierde el enganche (si estuviera en reset mientras se carga, la ROM no llegaria nunca)
	wire reset     = RESET | status[0] | buttons[1] | ~pll_locked | rom_dl;
	wire mem_reset = ~pll_locked;

//--- entrada de cinta por el ADC ----------------------------------------------------------------

	wire tape_adc, tape_adc_act;

	ltc2308_tape ltc2308_tape
	(
		.reset   (1'b0        ),
		.clk     (CLK_50M     ),
		.ADC_BUS (ADC_BUS     ),
		.dout    (tape_adc    ),
		.active  (tape_adc_act),
		.adc_sync(            ),
		.adc_data(            )
	);

	reg [1:0] adc_s = 2'b00;
	always @(posedge clk_sys) adc_s <= {adc_s[0], tape_adc};

	// La maquina mide el periodo de flanco de subida a flanco de subida: con la senal invertida la
	// carga falla (ver fp1100_top.sv). En las placas MiST el comparador la da la vuelta; aqui el ADC
	// no, y por si acaso queda la opcion "Invert ADC".
	wire ear_in = adc_s[1] ^ status[26];

//--- maquina -------------------------------------------------------------------------------------

	wire        ce_pix;
	wire        vid_31k;
	wire [ 7:0] R, G, B;
	wire        hs, vs, hblank, vblank;
	wire        beeper, cmt_motor, cmt_mic, fdc_motor, tape_lista, tape_play, cmt_rec, ear_mon;
	wire        led_shift, led_caps, kbd_alguna;
	wire [10:0] ps2_key;
	wire [ 7:0] sd_din;
	wire [31:0] lba;

	assign sd_lba[0] = lba;
	assign sd_lba[1] = lba;
	assign sd_buff_din[0] = sd_din;
	assign sd_buff_din[1] = sd_din;

	// DIP switches: b0 80 col, b1 Screen 1, b2 FP-1100, b3 300 baud, b4 impresora FP-1012PR,
	// b5 siempre a uno
	wire [7:0] dip = {2'b11, 1'b1, 1'b1, status[13], ~status[12], status[10], ~status[9]};

	// Scandoubler: el de MiSTer (forzado por el ini o por un efecto del OSD). Con el, fp1100_display
	// saca los sincronismos de VGA; sin el, los de la television (15 kHz).
	wire [2:0] scale = status[6:4];
	wire       sd_req = forced_scandoubler | (scale != 3'd0);

	// Centrado (como en fp1100_top.sv): a 15 kHz la imagen empieza 20 puntos antes
	wire signed [5:0] h_off_menu = {status[22], status[22:20], 2'b00};
	wire signed [6:0] h_off_15k  = {h_off_menu[5], h_off_menu} - 7'sd20;
	wire signed [5:0] h_off = sd_req ? h_off_menu :
	                          (h_off_15k < -7'sd32) ? 6'b100000 : h_off_15k[5:0];
	wire signed [5:0] v_off_menu = {status[25], status[25:23], 1'b0};
	wire signed [4:0] v_off = v_off_menu[4:0];

	// Al abrir y cerrar el OSD se sueltan todas las teclas (lo que estuviera pulsado al abrirlo no
	// recibiria nunca su "soltar")
	reg [2:0] osd_s = 3'b000;
	always @(posedge clk_sys) osd_s <= {osd_s[1:0], OSD_STATUS};
	wire kbd_soltar = osd_s[2] ^ osd_s[1];

	// Mascara de bytes tambien en A12:A11. En algunos modulos SDRAM de MiSTer las patas DQML/DQMH
	// van unidas a A11/A12, asi que la mascara de una escritura tiene que ir en esas dos lineas
	// de direccion en el ciclo del WRITE (en la columna no se usan: el controlador las deja a 0).
	// Sin esto cada escritura de un byte pisaba los dos de la palabra: el Z80 leia en cada
	// direccion par el byte de la impar (01 01 FF FF en vez de AF 01 80 FF) y no arrancaba.
	// En el READ el controlador pone DQM = 00, asi que A12:A11 siguen a 0. Las patas DQML/DQMH
	// se siguen moviendo igual, para los modulos que si las tienen.
	wire [12:0] sdram_a;
	wire        sdram_dqml, sdram_dqmh;
	wire        sdram_col = SDRAM_nRAS & ~SDRAM_nCAS;           // READ o WRITE
	assign SDRAM_A    = sdram_col ? {sdram_dqmh, sdram_dqml, sdram_a[10:0]} : sdram_a;
	assign SDRAM_DQML = sdram_dqml;
	assign SDRAM_DQMH = sdram_dqmh;

	fp1100 #(.CLK_HZ(CLK_HZ)) fp1100
	(
		.clk_sys        (clk_sys        ),
		.clk_pix        (clk_pix        ),
		.clk_vga        (clk_pix        ),
		.vga525         (1'b0           ),
		.vga_scanlines  (2'b00          ),
		.h_off          (h_off          ),
		.v_off          (v_off          ),
		.vid_15k        (~sd_req        ),
		.reset          (reset          ),
		// Momento de recoger el dato de la SDRAM: "Early" es SDRAM_ANTES, lo que llevan la
		// Poseidon, la SiDi y la Calypso (doc §23-24)
		.sdram_antes    (~status[27]    ),
		// Screen 1 (640x400 entrelazado): "400 lines" = las dos tramas juntas a 31 kHz, sacadas
		// por el propio core; "Fields" = cada trama por separado a 15 kHz
		.vga400         (~status[11]    ),
		.vid_31k        (vid_31k        ),
		.mem_reset      (mem_reset      ),
		.dip            (dip            ),
		.vid_libre      (1'b0           ),
		.dl_addr        (dl_sdram_addr  ),
		.dl_data        (ioctl_dout     ),
		.dl_wr          (dl_wr          ),
		.sdram_free     (sdram_free     ),
		.rom1_wr        (rom_dl & ioctl_wr & in_sub1),
		.rom2_wr        (rom_dl & ioctl_wr & in_sub2),
		.cg_wr          (rom_dl & ioctl_wr & in_sub3),
		.rom_wr_addr    (ioctl_addr[11:0]),
		.SDRAM_A        (sdram_a        ),
		.SDRAM_DQ       (SDRAM_DQ       ),
		.SDRAM_DQML     (sdram_dqml     ),
		.SDRAM_DQMH     (sdram_dqmh     ),
		.SDRAM_nWE      (SDRAM_nWE      ),
		.SDRAM_nCAS     (SDRAM_nCAS     ),
		.SDRAM_nRAS     (SDRAM_nRAS     ),
		.SDRAM_nCS      (SDRAM_nCS      ),
		.SDRAM_BA       (SDRAM_BA       ),
		.SDRAM_CKE      (SDRAM_CKE      ),
		.ce_pix         (ce_pix         ),
		.vid_r          (R              ),
		.vid_g          (G              ),
		.vid_b          (B              ),
		.vid_hs         (hs             ),
		.vid_hs_cs      (               ),
		.vid_vs         (vs             ),
		.vid_hb         (hblank         ),
		.vid_vb         (vblank         ),
		.vga_r          (               ),
		.vga_g          (               ),
		.vga_b          (               ),
		.vga_hs         (               ),
		.vga_vs         (               ),
		.vga_hb         (               ),
		.vga_vb         (               ),
		.ps2_key        (ps2_key        ),
		.kbd_soltar     (kbd_soltar     ),
		.kbd_alguna     (kbd_alguna     ),
		.led_shift      (led_shift      ),
		.led_caps       (led_caps       ),
		.beeper         (beeper         ),
		.cmt_motor      (cmt_motor      ),
		.cmt_mic        (cmt_mic        ),
		.ear_in         (ear_in         ),
		.tape_externa   (status[16]     ),
		.tape_cargada   (tape_cargada   ),
		.tape_tamano    (tape_tamano    ),
		.tape_rebobinar (tape_rebobinar ),
		.tape_pausa     (status[17]     ),
		.tape_lista     (tape_lista     ),
		.tape_play      (tape_play      ),
		.cmt_rec        (cmt_rec        ),
		.ear_mon        (ear_mon        ),
		.fdc_enable     (~status[15]    ),
		.img_mounted    (img_mounted    ),
		.img_size       (img_size[31:0] ),
		.sd_lba         (lba            ),
		.sd_rd          (sd_rd          ),
		.sd_wr          (sd_wr          ),
		.sd_ack         (|sd_ack        ),
		.sd_buff_addr   (sd_buff_addr[8:0]),
		.sd_buff_dout   (sd_buff_dout   ),
		.sd_buff_din    (sd_din         ),
		.sd_buff_wr     (sd_buff_wr     ),
		.fdc_motor      (fdc_motor      ),
		.dbg_pc         (               ),
		.dbg_sub_a      (               ),
		.dbg_sdram_ready(               ),
		.dbg_int_req    (               ),
		.dbg_int_ack    (               )
	);

	fp1100_ps2 teclado_ps2
	(
		.clk     (clk_sys     ),
		.reset   (reset       ),
		.ps2_clk (ps2_kbd_clk ),
		.ps2_data(ps2_kbd_data),
		.ps2_key (ps2_key     ),
		.rx_byte (            ),
		.rx_error(            )
	);

	// SDRAM_CLK = clk_sys invertido por un registro DDR del pin, como en las otras placas
	altddio_out
	#(
		.extend_oe_disable     ("OFF"         ),
		.intended_device_family("Cyclone V"   ),
		.invert_output         ("OFF"         ),
		.lpm_hint              ("UNUSED"      ),
		.lpm_type              ("altddio_out" ),
		.oe_reg                ("UNREGISTERED"),
		.power_up_high         ("OFF"         ),
		.width                 (1             )
	)
	sdramclk_ddr
	(
		.datain_h  (1'b0     ),
		.datain_l  (1'b1     ),
		.outclock  (clk_sys  ),
		.dataout   (SDRAM_CLK),
		.aclr      (1'b0     ),
		.aset      (1'b0     ),
		.oe        (1'b1     ),
		.outclocken(1'b1     ),
		.sclr      (1'b0     ),
		.sset      (1'b0     )
	);

//--- video ---------------------------------------------------------------------------------------

	// Modo verde (PA4): el generador saca solo verde; con la opcion del OSD se vuelve blanco
	wire [7:0] R_mix = status[14] ? G : R;
	wire [7:0] B_mix = status[14] ? G : B;

	// De clk_pix (25 MHz) a clk_vid (50 MHz): los dos salen del mismo VCO y clk_vid es el doble
	// exacto, asi que basta con tomar cada punto en clk_pix y pasarlo con un conmutador. El punto
	// queda quieto al menos dos ciclos de clk_vid, y ce_vid sale un ciclo por punto.
	reg       tgl_pix = 1'b0;
	reg [7:0] r_p, g_p, b_p;
	reg       hs_p, vs_p, hb_p, vb_p;
	always @(posedge clk_pix) if (ce_pix) begin
		tgl_pix <= ~tgl_pix;
		r_p  <= R_mix;  g_p  <= G;  b_p  <= B_mix;
		hs_p <= hs;     vs_p <= vs; hb_p <= hblank; vb_p <= vblank;
	end

	reg       tgl_vid = 1'b0, ce_vid = 1'b0;
	reg [7:0] r_v, g_v, b_v;
	reg       hs_v, vs_v, hb_v, vb_v;
	always @(posedge clk_vid) begin
		tgl_vid <= tgl_pix;
		ce_vid  <= tgl_vid ^ tgl_pix;
		if (tgl_vid ^ tgl_pix) begin
			r_v  <= r_p;  g_v  <= g_p;  b_v  <= b_p;
			hs_v <= hs_p; vs_v <= vs_p; hb_v <= hb_p; vb_v <= vb_p;
		end
	end

	// En el modo de 400 lineas el core ya saca 31 kHz: sin scandoubler
	reg [1:0] v31_s = 2'b00;
	always @(posedge clk_vid) v31_s <= {v31_s[0], vid_31k};
	wire scandoubler = sd_req & ~v31_s[1];

	wire [1:0] ar = status[3:2];
	wire       vga_de;

	assign CLK_VIDEO = clk_vid;
	assign VGA_SL = (scale >= 3'd2 && scandoubler) ? scale[1:0] - 2'd1 : 2'd0;

	video_freak video_freak
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.VGA_VS     (VGA_VS     ),
		.HDMI_WIDTH (HDMI_WIDTH ),
		.HDMI_HEIGHT(HDMI_HEIGHT),
		.VGA_DE     (VGA_DE     ),
		.VIDEO_ARX  (VIDEO_ARX  ),
		.VIDEO_ARY  (VIDEO_ARY  ),
		.VGA_DE_IN  (vga_de     ),
		.ARX        ((!ar) ? 12'd4 : (ar - 1'd1)),
		.ARY        ((!ar) ? 12'd3 : 12'd0),
		.CROP_SIZE  (12'd0      ),
		.CROP_OFF   (5'd0       ),
		.SCALE      ({1'b0, status[8:7]})
	);

	video_mixer #(.LINE_LENGTH(800), .GAMMA(1)) video_mixer
	(
		.CLK_VIDEO  (CLK_VIDEO  ),
		.CE_PIXEL   (CE_PIXEL   ),
		.ce_pix     (ce_vid     ),
		.scandoubler(scandoubler),
		.hq2x       (scale == 3'd1),
		.gamma_bus  (gamma_bus  ),
		.R          (r_v        ),
		.G          (g_v        ),
		.B          (b_v        ),
		.HSync      (hs_v       ),
		.VSync      (vs_v       ),
		.HBlank     (hb_v       ),
		.VBlank     (vb_v       ),
		.HDMI_FREEZE(1'b0       ),
		.freeze_sync(           ),
		.VGA_R      (VGA_R      ),
		.VGA_G      (VGA_G      ),
		.VGA_B      (VGA_B      ),
		.VGA_VS     (VGA_VS     ),
		.VGA_HS     (VGA_HS     ),
		.VGA_DE     (vga_de     )
	);

//--- audio ---------------------------------------------------------------------------------------

	// El beeper del teclado: onda cuadrada de ~950 Hz mientras esta activo
	reg [14:0] beep_cnt = 15'd0;
	reg        beep_osc = 1'b0;
	always @(posedge clk_sys) begin
		if (beep_cnt == 15'd16841) begin
			beep_cnt <= 15'd0;
			beep_osc <= ~beep_osc;
		end else beep_cnt <= beep_cnt + 1'b1;
	end

	// La cinta se oye bajito, como el altavoz de un casete (opcion "Tape monitor"):
	//   0 Motor on   solo con el motor en marcha
	//   1 Always     EAR siempre (para ajustar el volumen del reproductor antes de LOAD)
	//   2 Off        sin sonido de cinta
	localparam signed [15:0] NIVEL       = 16'sd6144;
	localparam signed [15:0] NIVEL_CINTA = 16'sd1536;
	wire [1:0] tape_monitor = status[19:18];
	wire       oye_mic = cmt_motor & cmt_rec & (tape_monitor != 2'd2);
	wire       oye_ear = ~(cmt_motor & cmt_rec) &
	                     ((tape_monitor == 2'd1) | ((tape_monitor == 2'd0) & cmt_motor));
	wire signed [15:0] audio_beep  = beeper ? (beep_osc ? NIVEL : -NIVEL) : 16'sd0;
	wire signed [15:0] audio_cinta = oye_mic ? (cmt_mic ? NIVEL_CINTA : -NIVEL_CINTA) :
	                                 oye_ear ? (ear_mon ? NIVEL_CINTA : -NIVEL_CINTA) :
	                                           16'sd0;

	reg [15:0] audio = 16'd0;
	always @(posedge clk_sys) audio <= audio_beep + audio_cinta;

	assign AUDIO_S   = 1'b1;
	assign AUDIO_L   = audio;
	assign AUDIO_R   = audio;
	assign AUDIO_MIX = 2'd0;

//--- leds ----------------------------------------------------------------------------------------

	assign LED_USER = ioctl_download | tape_play;
	assign LED_DISK = {1'b0, fdc_motor | (|sd_rd) | (|sd_wr)};

//-------------------------------------------------------------------------------------------------
endmodule

`default_nettype wire
