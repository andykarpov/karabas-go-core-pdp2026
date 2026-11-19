`timescale 1ns / 1ps
`default_nettype wire
/*
 sdspi_img.v (karabas)

 The sdspi of a disk controller (same ports, same 256 x 16 sector buffer on port A for the
 controller) without the SD card: the sector goes to / comes from an image file on the SD card of
 the MCU through pdp_img (kg_l2_img of kg_mcu2). The controllers keep their sdreq / sdack
 arbitration of topboard22; while one holds sdack its img_out is the request of the bus.

 img_out = { req, write, lba[26:0], byte_out[7:0] }: req is up from sdspi_start until the answer;
   byte_out is the byte at img_in byte_addr of the buffer, two clocks later (a write).
 img_in = { done, error, strobe, byte_addr[8:0], byte_in[7:0] }: strobe writes a byte of a read
   into the buffer (little-endian words: byte 2i is bits 7:0 of word i, as sdspi); done (one
   clock) ends the request, error with it.
 The handshake to the controller is that of sdspi: start = 1 -> io_done = 1 -> start = 0 ->
 io_done = 0; idle is always 1, error stays from done until the next start. All on
 controller_clk (the clock of the bus = the clock of pdp_img).
*/
module sdspi_img (
	output wire       sdcard_cs,
	output wire       sdcard_mosi,
	output wire       sdcard_sclk,
	input  wire       sdcard_miso,
	output wire [7:0] sdcard_debug,

	input  wire [26:0] sdcard_addr,
	output wire       sdcard_idle,
	input  wire       sdspi_start,
	output reg        sdspi_io_done = 1'b0,
	input  wire       sdspi_write_mode,
	output reg        sdcard_error = 1'b0,
	output wire       master_sdhc,
	input  wire       slave_sdhc,

	input  wire [7:0]  sdbuf_addr,
	output wire [15:0] sdbuf_dataout,
	input  wire        sdbuf_we,
	input  wire [15:0] sdbuf_datain,

	input  wire       controller_clk,
	input  wire       mode,
	input  wire       sdclk,
	input  wire       reset,

	input  wire [19:0] img_in,
	output wire [36:0] img_out
);

assign sdcard_cs = 1'b1;
assign sdcard_mosi = 1'b1;
assign sdcard_sclk = 1'b0;
assign sdcard_debug = 8'd0;
assign master_sdhc = 1'b0;
assign sdcard_idle = 1'b1;

wire       i_done   = img_in[19];
wire       i_error  = img_in[18];
wire       i_strobe = img_in[17];
wire [8:0] i_addr   = img_in[16:8];
wire [7:0] i_data   = img_in[7:0];

wire clk = controller_clk;

// the request: from start until the answer of this request
reg busy = 1'b0;
reg wr = 1'b0;
always @(posedge clk)
	if (reset) begin
		busy <= 1'b0;
		sdspi_io_done <= 1'b0;
		sdcard_error <= 1'b0;
	end
	else if (!sdspi_start)
		sdspi_io_done <= 1'b0;
	else if (!busy && !sdspi_io_done) begin
		busy <= 1'b1;
		wr <= sdspi_write_mode;
		sdcard_error <= 1'b0;
	end
	else if (busy && i_done) begin
		busy <= 1'b0;
		sdspi_io_done <= 1'b1;
		sdcard_error <= i_error;
	end

// port B: the bytes of a read in, the bytes of a write out
reg [7:0] lo = 8'd0;
wire b_we = busy && !wr && i_strobe && i_addr[0];
always @(posedge clk)
	if (busy && !wr && i_strobe && !i_addr[0])
		lo <= i_data;

wire [15:0] b_q;
sectorbuf sbuf (
	.clka(clk), .wea(sdbuf_we), .addra(sdbuf_addr), .dina(sdbuf_datain), .douta(sdbuf_dataout),
	.clkb(clk), .web(b_we), .addrb(i_addr[8:1]), .dinb({ i_data, lo }), .doutb(b_q)
);

reg hi_sel = 1'b0;
reg [7:0] b_out = 8'd0;
always @(posedge clk) begin
	hi_sel <= i_addr[0];
	b_out <= hi_sel ? b_q[15:8] : b_q[7:0];
end

assign img_out = { busy, wr, sdcard_addr, b_out };

endmodule
