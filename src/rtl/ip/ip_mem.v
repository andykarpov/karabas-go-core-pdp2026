`timescale 1ns / 1ps
`default_nettype wire
/*
 ip_mem.v (karabas)

 The coregen blk_mem_gen cores of the upstream ISE project (ipcore_dir: bootrom, ledfont,
 sectorbuf) as inferred block RAM of karabas-go-modules, with the same names, ports and one clock of
 read latency (no output registers, WRITE_FIRST), so the sources that use them stay as they are and
 the Makefile flow needs no coregen netlists. The ROM contents: the .hex files of rtl/ip, made from the .coe
 files of rom by karabas-go-modules tools/coe2hex.py (equal to the .mif files of ipcore_dir).
*/

// the M9312 boot ROM: 512 x 16 (rom/m9312/bootrom.coe)
module bootrom (
	input wire clka,
	input wire [8:0] addra,
	output wire [15:0] douta
);
kg_sprom #(.DW(16), .AW(9), .INIT_FILE("rtl/ip/bootrom.hex")) rom (
	.clk(clka), .en(1'b1), .addr(addra), .dout(douta)
);
endmodule

// the font of the LED icons: 16 x 16 (rom/led/led.coe)
module ledfont (
	input wire clka,
	input wire [3:0] addra,
	output wire [15:0] douta
);
kg_sprom #(.DW(16), .AW(4), .INIT_FILE("rtl/ip/ledfont.hex")) rom (
	.clk(clka), .en(1'b1), .addr(addra), .dout(douta)
);
endmodule

// the sector buffer of sdspi: 256 x 16, true dual port
module sectorbuf (
	input wire clka,
	input wire [0:0] wea,
	input wire [7:0] addra,
	input wire [15:0] dina,
	output wire [15:0] douta,
	input wire clkb,
	input wire [0:0] web,
	input wire [7:0] addrb,
	input wire [15:0] dinb,
	output wire [15:0] doutb
);
kg_tdpram #(.DW(16), .AW(8), .WRITE_FIRST(1)) ram (
	.clka(clka), .ena(1'b1), .wea(wea), .addra(addra), .dina(dina), .douta(douta),
	.clkb(clkb), .enb(1'b1), .web(web), .addrb(addrb), .dinb(dinb), .doutb(doutb)
);
endmodule
