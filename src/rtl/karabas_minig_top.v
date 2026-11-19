`timescale 1ns / 1ps
`default_nettype wire

/*
 PDP-11/70 core for Karabas Mini rev.G (HDMI, PCM5102): the PDP-11/70 of Pavel Tsybulin's
 pdp2026 (pdp_top: the pdp2011 CPU of Sytse van Slooten in the DVK-FPGA board of upstream, RK / RL /
 RP disks on the second SD card, TOY clock, M9312 boot ROM, bootmon in the SRAM), its VT100 console
 terminal, and the board glue of karabas-go-modules (MCU link v2, kg_mcu2). Upstream:
 tsybulin/karabas-go-core-pdp2026; the karabas changes are marked karabas: in its sources.

 Clocks (pdp_clocks): clk_50 (the PDP-11 = clk_p of upstream, the SRAM, the MCU link, the serial
 lines, the DAC), clk_25 (640 x 480, the OSD, HDMI), clk_125 / clk_125_n (the serialiser), clk_10
 (the PDP-11 of the terminal), clk_sd (12.5 MHz, sdclock), clk_8 (FT_CLK_OUT, a DCM).

 Disks: image files on the SD card of the MCU (SD1), one per controller (pdp_img on kg_l2_img;
   slot 0 RK11, 1 RL11, 2 RH70 / RP06, 3 the paper tape of PC11), the units back to back at
   unit * unit size as they were on SD2; the sdspi of each controller is sdspi_img. SD2 is not used.
 SRAM: the memory of the PDP-11; bootmon.rom (core.json roms, LD kind 0) is written into it while
 the PDP-11 is held in reset (sram.v loader port, a 16 bit word per two bytes).
 RTC: the TOY of the PDP-11 reads the DS1307 registers of kg_mcu2 (rtc_mode 1).

 Console (OSD item Console, switch 11): the console line of the PDP-11 (irps, 115200 8N1) to the
   built-in VT100 terminal (0) or to the core serial port of the board (1: kg_mcu2 port 0 = CDC 1,
   Linux /dev/serial/by-id/usb-Karabas_Go_*-if02).
   Terminal: XON / XOFF of the terminal are done in the line (the vt10x firmware drops characters
   while it scrolls): XOFF / rts of the terminal hold the transmitter of the PDP-11 (wbc_uart
   tx_hold), both are taken out of the stream to the PDP-11.
   USB: transparent both ways; a full in fifo of the port holds the PDP-11 transmitter (one byte
   latched meanwhile), the bytes of the PC wait in the out fifo of the port and the USB fifo.
 Front panel LEDs (icons.v of upstream, OSD item Front panel).

 Soft switches (the "index" of the items in core.json, the numbers of soft_switches.v of upstream):
   0 Reset   1 Continue (CONT)   2 Slow CPU   3..7 not used (the SD2 offset and
   banks of upstream)   8 Colour   9 Front panel   10 Sound (On / Off)
   11 Console (Terminal / USB serial)
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);


// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP32_SPI_CS_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;
assign MIDI_TX = 1'b1;
assign TAPE_OUT = 1'b0;

// SDRAM: not used (NOP: RAS / CAS / WE high)
assign SDR_BA = 2'b00;
assign SDR_A = 13'd0;
assign SDR_CLK = 1'b0;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

// FLASH_CS_N (T3) is the SDRAM /CS of Mini G2 (rev G: tied low on the board): always selected
assign FLASH_CS_N = 1'b0;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

// ------------------------------------------------------------------ clocks

wire clk_50, clk_125, clk_125_n, clk_25, clk_10, clk_sd, clk_8, pll_locked;
pdp_clocks clocks (
	.clk_in(CLK_50MHZ),
	.clk_50(clk_50),
	.clk_125(clk_125),
	.clk_125_n(clk_125_n),
	.clk_25(clk_25),
	.clk_10(clk_10),
	.clk_sd(clk_sd),
	.clk_8(clk_8),
	.locked(pll_locked)
);
(* KEEP = "TRUE" *) wire areset_async = ~pll_locked;
wire areset, areset_25;
kg_sync #(.W(1), .STAGES(2), .INIT(1'b1)) sync_areset (.clk(clk_50), .d(areset_async), .q(areset));
kg_sync #(.W(1), .STAGES(2), .INIT(1'b1)) sync_areset_25 (.clk(clk_25), .d(areset_async), .q(areset_25));

// the clock of the FT812 (every core must drive it on Mini / Mini G)
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

// MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire [8*12-1:0] sw;
wire [5:0] btns;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on;
wire [15:0] dbg_addr;
reg [15:0] dbg_data = 16'd0;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;

wire [1:0] ld_kind;
wire [31:0] ld_addr;
wire [7:0] ld_data;
wire ld_active, ld_wr;

// the RTC registers of kg_mcu2 (rtc_mode 1: DS1307, BCD) for the TOY of the PDP-11
wire [7:0] rtc_a, rtc_do;

// the core serial port (port 0) <-> the console line (USB serial mode)
wire [31:0] port_out_data;
wire [3:0] port_out_wr, port_in_full;
wire ser_out_ready;
reg ser_in_wr = 1'b0;
reg [7:0] ser_in_data = 8'd0;

// the disks (pdp_img): kg_l2_img of kg_mcu2
wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sdc_byte_out_data;

kg_mcu2 #(
	.SW_N(12),
	.CS_FILTER(3),
	.CAPS(16'h0000),     // (RTC bit 5 comes from ENABLE_RTC)
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the disks: image files on SD1 (pdp_img), slot 0 RK, 1 RL, 2 RP, 3 tape
	.IMG_OUT_LATENCY(3), // sdspi_img: the buffer (1) and the byte register (1), then the sample
	.ENABLE_RTC(1),
	.ENABLE_AUX(1),      // DEBUG_*: the state of the console line (AT+KARABAS=debug:1)
	.ENABLE_FT(1),
	.ENABLE_SD2(0),      // SD2 is not used (the disks are image files)
	.ENABLE_PORTS(4'b0001) // port 0: the core serial port (Console = USB serial)
) mcu (
	.CLK(clk_50),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(1'b1),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(), .BTNS(btns), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(), .KBD_WR(),
	.PS2_CODE(ps2_code), .PS2_KIND(ps2_kind), .PS2_WR(ps2_wr),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(), .JOY_R(), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(), .LD_SIZE(), .LD_EXT(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size), .SDC_RD(sdc_rd),
	.SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector), .SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done),
	.SDC_ERROR(sdc_error), .SDC_SLOT(), .SDC_BYTE_IN_STROBE(sdc_byte_in_strobe),
	.SDC_BYTE_ADDR(sdc_byte_addr), .SDC_BYTE_IN_DATA(sdc_byte_in_data),
	.SDC_BYTE_OUT_DATA(sdc_byte_out_data), .IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0),
	.BK_MOUNT(1'b0), .BK_FLUSHED(1'b0), .BK_SLOT(3'd0), .BK_SIZE(32'd0), .BK_KIND(8'd0), .BK_RESULT(8'd0), .IMG_ACTIVE(),
	.PORT_OUT_DATA(port_out_data), .PORT_OUT_WR(port_out_wr), .PORT_OUT_READY({ 3'b111, ser_out_ready }),
	.PORT_IN_DATA({ 24'd0, ser_in_data }), .PORT_IN_WR({ 3'b000, ser_in_wr }),
	.PORT_CFG(128'd0), .PORT_IN_FULL(port_in_full), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(rtc_a), .RTC_DI(8'd0), .RTC_CS(1'b1), .RTC_WR_N(1'b1), .MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(dbg_addr), .DEBUG_DATA(dbg_data), .RTC_DO(rtc_do),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b1), .SD2_CS_N()
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;

// ------------------------------------------------------------------ soft switches

wire sw_reset = sw[0*8];
wire sw_cont = sw[1*8];
wire sw_slow = sw[2*8];
wire [2:0] sw_bank_offset = 3'd0;   // the banks of SD2: not used with image files
wire [7:0] sw_bank = 8'd0;
wire [1:0] sw_color = sw[8*8 +: 2];
wire sw_leds = sw[9*8];
wire [1:0] sw_sound = sw[10*8 +: 2];
wire sw_console = sw[11*8];

// ------------------------------------------------------------------ the ROM loader (bootmon.rom)

// LD kind 0 (the ROMs of the .kg): bytes, the even one held, the odd one makes the word, as the
// romloader of the old mcu.vhd (ROMLOAD_ADDR = byte address 21..1, ROMLOAD_DATA = { odd, even })
reg [7:0] ld_lo = 8'd0;
reg loader_wr = 1'b0;
reg [21:1] loader_addr = 21'd0;
reg [15:0] loader_data = 16'd0;
always @(posedge clk_50) begin
	loader_wr <= 1'b0;
	if (ld_wr && ld_kind == 2'd0) begin
		if (!ld_addr[0])
			ld_lo <= ld_data;
		else begin
			loader_addr <= ld_addr[21:1];
			loader_data <= { ld_data, ld_lo };
			loader_wr <= 1'b1;
		end
	end
end

// the PDP-11 is held in reset from power on until the first ROM load has ended (upstream mcu_load)
reg mcu_load = 1'b1;
reg ld_active_q = 1'b0;
always @(posedge clk_50) begin
	ld_active_q <= ld_active;
	if (ld_active_q && !ld_active)
		mcu_load <= 1'b0;
end

// the buttons of upstream: [1] CONT. (HALT / program), [0] RESET; active low
reg [1:0] buttons = 2'b11;
always @(posedge clk_50) begin
	buttons[1] <= ~(sw_cont | btns[0]);
	buttons[0] <= ~(sw_reset | btns[1] | mcu_load);
end

// ------------------------------------------------------------------ the console line

wire pdp_txd;              // the console of the PDP-11
reg pdp_rxd = 1'b1;
wire pdp_hold;

// terminal mode: the PDP-11 to the terminal straight; the terminal to the PDP-11 through a
// receiver and a transmitter that take XON / XOFF out
wire term_tx, term_rts;
wire term_rx = sw_console ? 1'b1 : pdp_txd;
reg term_xoff = 1'b0;
wire term_done;
wire [7:0] term_byte;
vt_uart_rx term_rcv (.clk(clk_50), .reset(areset), .rx(term_tx), .done(term_done), .data(term_byte));
reg [7:0] n_xoff = 8'd0;
always @(posedge clk_50) begin
	if (areset)
		term_xoff <= 1'b0;
	else if (term_done && term_byte == 8'h13) begin
		term_xoff <= 1'b1;
		n_xoff <= n_xoff + 8'd1;
	end
	else if (term_done && term_byte == 8'h11)
		term_xoff <= 1'b0;
end
wire term_pass = term_done && term_byte != 8'h13 && term_byte != 8'h11;

// usb mode: the bytes of the PC from the out fifo of port 0
wire usb_out_ready;
assign ser_out_ready = sw_console && usb_out_ready;

// one transmitter to the rxd of the PDP-11: the terminal bytes (a 4-byte queue, the terminal sends
// at the line rate) or the bytes of the PC
reg [7:0] tq [0:3];
reg [1:0] tq_w = 2'd0, tq_r = 2'd0;
reg [2:0] tq_n = 3'd0;
wire tq_take = !sw_console && tq_n != 3'd0 && usb_out_ready;   // the transmitter is free
always @(posedge clk_50) begin
	if (areset || sw_console) begin
		tq_w <= 2'd0; tq_r <= 2'd0; tq_n <= 3'd0;
	end
	else begin
		if (term_pass && tq_n != 3'd4) begin
			tq[tq_w] <= term_byte;
			tq_w <= tq_w + 2'd1;
		end
		if (tq_take)
			tq_r <= tq_r + 2'd1;
		tq_n <= tq_n + ((term_pass && tq_n != 3'd4) ? 3'd1 : 3'd0) - (tq_take ? 3'd1 : 3'd0);
	end
end
reg tq_load = 1'b0;
reg [7:0] tq_byte = 8'd0;
always @(posedge clk_50) begin
	tq_load <= tq_take;
	if (tq_take) tq_byte <= tq[tq_r];
end
wire tx_load = sw_console ? port_out_wr[0] : tq_load;
wire [7:0] tx_byte = sw_console ? port_out_data[7:0] : tq_byte;
wire tx_line;
vt_uart_tx to_pdp (
	.clk(clk_50), .reset(areset), .hold(1'b0), .load(tx_load), .data(tx_byte), .ready(usb_out_ready), .tx(tx_line)
);
always @(posedge clk_50)
	pdp_rxd <= tx_line;

// the PDP-11 to the PC (usb mode): a receiver into the in fifo of port 0; a byte that finds the fifo
// full waits in a latch, and the PDP-11 transmitter is held while the latch is taken
wire usb_done;
wire [7:0] usb_byte;
vt_uart_rx from_pdp (.clk(clk_50), .reset(areset), .rx(sw_console ? pdp_txd : 1'b1), .done(usb_done), .data(usb_byte));
reg usb_latch = 1'b0;
reg [7:0] usb_latch_byte = 8'd0;
reg [7:0] n_drop = 8'd0;
always @(posedge clk_50) begin
	ser_in_wr <= 1'b0;
	if (areset || !sw_console)
		usb_latch <= 1'b0;
	else if (usb_latch) begin
		if (!port_in_full[0]) begin
			ser_in_data <= usb_latch_byte;
			ser_in_wr <= 1'b1;
			usb_latch <= usb_done;          // a byte at this very clock takes the latch again
			usb_latch_byte <= usb_byte;
		end
		else if (usb_done)
			n_drop <= n_drop + 8'd1;        // a second byte while held: lost (the hold came late)
	end
	else if (usb_done) begin
		if (port_in_full[0]) begin
			usb_latch <= 1'b1;
			usb_latch_byte <= usb_byte;
		end
		else begin
			ser_in_data <= usb_byte;
			ser_in_wr <= 1'b1;
		end
	end
end

assign pdp_hold = sw_console ? (usb_latch || port_in_full[0]) : (term_rts || term_xoff);

// ------------------------------------------------------------------ the PDP-11

wire [7:0] leds;
// the disks of the PDP-11: one image file per controller (slots 0..3 of kg_l2_img)
wire [39:0] img_req;
wire [19:0] img_ans;
wire img_active;
pdp_img disks (
	.clk(clk_50), .reset(areset), .img_req(img_req), .img_ans(img_ans),
	.sdc_img_mounted(sdc_img_mounted), .sdc_img_size(sdc_img_size), .sdc_rd(sdc_rd), .sdc_wr(sdc_wr),
	.sdc_sector(sdc_sector), .sdc_busy(sdc_busy), .sdc_done(sdc_done), .sdc_error(sdc_error),
	.sdc_byte_in_strobe(sdc_byte_in_strobe), .sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data), .sdc_byte_out_data(sdc_byte_out_data), .active(img_active)
);

// SD2 is not used
assign SD_CS_N = 1'b1;
assign SD_CLK = 1'b0;
assign SD_DI = 1'b1;

pdp_top mainboard (
	.clk50(clk_50),
	.clk_p(clk_50),
	.clk_n(1'b0),
	.sdclock(clk_sd),
	.clkrdy(pll_locked),
	.rst_n(1'b1),
	.button(buttons),
	.sw_slow(sw_slow),
	.sw_bank_offset(sw_bank_offset),
	.sw_bank(sw_bank),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N),
	.sdcard_cs(),
	.sdcard_mosi(),
	.sdcard_sclk(),
	.sdcard_miso(1'b1),
	.irps_txd(pdp_txd),
	.irps_rxd(pdp_rxd),
	.irps_hold(pdp_hold),
	.img_req(img_req),
	.img_ans(img_ans),
	.rtc_a(rtc_a),
	.rtc_di(rtc_do),
	.leds(leds),
	.loader_wr(loader_wr),
	.loader_addr(loader_addr),
	.loader_data(loader_data)
);

// ------------------------------------------------------------------ the terminal

wire vt_o, vt_hs, vt_vs, vt_blank, vt_bell;
vt100_top terminal (
	.clkin(clk_50),
	.c0(clk_10),
	.resetbtn(~areset),
	.tx(term_tx),
	.rx(term_rx),
	.rts(term_rts),
	.vgao(vt_o),
	.vgai(),
	.vgah(vt_hs),
	.vgav(vt_vs),
	.vgaclk(),
	.vga_blank(vt_blank),
	.ps2k_upd(ps2_wr && !ps2_kind),
	.ps2k_dat(ps2_code),
	.audio(vt_bell)
);

// the picture: clk_50 -> clk_25 (both registered; the terminal holds a pixel for two clk_50)
reg [3:0] vt_q = 4'b1100;
always @(posedge clk_50)
	vt_q <= { vt_hs, vt_vs, vt_blank, vt_o };
reg [3:0] vt_p = 4'b1100;
always @(posedge clk_25)
	vt_p <= vt_q;

//                    Amber            Green            White
wire [23:0] fg = sw_color == 2'd0 ? 24'hFFB700 : sw_color == 2'd1 ? 24'h33FF33 : 24'hFFFFFF;
reg [23:0] vt_rgb = 24'd0;
reg vt_hs_p = 1'b0, vt_vs_p = 1'b0, vt_de_p = 1'b0;
always @(posedge clk_25) begin
	vt_rgb <= (vt_p[0] && !vt_p[1]) ? fg : 24'd0;
	vt_hs_p <= vt_p[3];     // the syncs of the terminal: low active
	vt_vs_p <= vt_p[2];
	vt_de_p <= !vt_p[1];
end

// the front panel LEDs of upstream (icons.v): counted from the starts of the sync pulses as the
// old overlay.vhd did, shown with the Front panel item
reg [10:0] hcnt = 11'd0, vcnt = 11'd0;
reg hs_q = 1'b1, vs_q = 1'b1;
always @(posedge clk_25) begin
	hs_q <= vt_hs_p;
	if (!vt_hs_p && hs_q) begin
		hcnt <= 11'd0;
		vcnt <= vcnt + 11'd1;
		vs_q <= vt_vs_p;
		if (!vt_vs_p && vs_q)
			vcnt <= 11'd0;
	end
	else
		hcnt <= hcnt + 11'd1;
end
wire [23:0] led_rgb;
wire led_visible;
icons led_icons (.clk(clk_25), .hcnt(hcnt), .vcnt(vcnt), .leds(leds), .rgb_o(led_rgb), .visible(led_visible));
reg leds_on = 1'b0;
always @(posedge clk_25)
	leds_on <= sw_leds;

// icons has one clock of latency: the video is delayed by one clock with it
reg [23:0] vid_rgb = 24'd0;
reg vid_hs = 1'b0, vid_vs = 1'b0, vid_de = 1'b0;
reg [23:0] vt_rgb_d = 24'd0;
reg vt_hs_d = 1'b1, vt_vs_d = 1'b1, vt_de_d = 1'b0;
always @(posedge clk_25) begin
	vt_rgb_d <= vt_rgb; vt_hs_d <= vt_hs_p; vt_vs_d <= vt_vs_p; vt_de_d <= vt_de_p;
	vid_rgb <= (leds_on && led_visible) ? led_rgb : vt_rgb_d;
	vid_hs <= !vt_hs_d;     // positive inside, negative to HDMI
	vid_vs <= !vt_vs_d;
	vid_de <= vt_de_d;
end

// the bitmap OSD of link v2 (kg_l2_osd_overlay): centred in de, 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(clk_50),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_25),
	.rgb_i(vid_rgb), .hs_i(vid_hs), .vs_i(vid_vs), .de_i(vid_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the bell of the terminal: a square wave, an eighth of full scale; Sound = Off mutes it
reg [15:0] audio = 16'd0;
always @(posedge clk_50)
	audio <= sw_sound == 2'd1 ? 16'd0 : vt_bell ? 16'h0800 : 16'hF800;

kg_pcm5102 #(.DIV_BITS(3)) dac (  // bck 3.1 MHz, 97.7 kHz
	.clk(clk_50),
	.reset(areset),
	.left(audio),
	.right(audio),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// 48 kHz for HDMI: a phase accumulator on clk_50 (48000 / 50e6 * 2^20 = 1006.6), the sample held
// and taken in clk_25 on the toggle (clk_25 is synchronous to clk_50, stable for ~1000 clocks)
reg [20:0] aud_acc = 21'd0;
reg aud_tgl = 1'b0;
reg [15:0] aud_s = 16'd0;
always @(posedge clk_50) begin
	aud_acc <= { 1'b0, aud_acc[19:0] } + 21'd1007;
	if (aud_acc[20]) begin
		aud_s <= audio;
		aud_tgl <= ~aud_tgl;
	end
end

reg [1:0] aud_tgl_s = 2'b00;
reg aud_stb = 1'b0;
reg [23:0] hdmi_a = 24'd0;
always @(posedge clk_25) begin
	aud_tgl_s <= { aud_tgl_s[0], aud_tgl };
	aud_stb <= aud_tgl_s[1] ^ aud_tgl_s[0];
	if (aud_tgl_s[1] ^ aud_tgl_s[0])
		hdmi_a <= { aud_s, 8'd0 };
end

// ------------------------------------------------------------------ HDMI

reg dvi_only_p = 1'b0;
always @(posedge clk_25)
	dvi_only_p <= dvi_only;

// negative syncs
reg hdmi_hs = 1'b1, hdmi_vs = 1'b1, hdmi_de = 1'b0;
reg [23:0] hdmi_rgb = 24'd0;
always @(posedge clk_25) begin
	hdmi_hs <= ~osd_hs;
	hdmi_vs <= ~osd_vs;
	hdmi_de <= osd_de;
	hdmi_rgb <= osd_rgb;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_25),
	.sclk(clk_125),
	.sclk_n(clk_125_n),
	.reset(areset_25),
	.rgb(hdmi_rgb),
	.vsync(hdmi_vs),
	.hsync(hdmi_hs),
	.de(hdmi_de),
	.audio_en(~dvi_only_p),
	.audio_l(hdmi_a),
	.audio_r(hdmi_a),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

// ------------------------------------------------------------------ debug

// DEBUG_ADDR: { console, hold, rts, xoff, usb latch, 3'b0, XOFF count }; DEBUG_DATA: { LEDs, USB bytes lost }
assign dbg_addr = { sw_console, pdp_hold, term_rts, term_xoff, usb_latch, 3'd0, n_xoff };
always @(posedge clk_50)
	dbg_data <= { leds, n_drop };

endmodule
