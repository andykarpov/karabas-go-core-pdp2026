`timescale 1ns / 1ps
// tb_wbc_uart_reset: the console transmitter (wbc_uart, 115200, 8N2 as uart1 of topboard22) and a
// bus RESET (sys_init) in the middle of a frame, as bootmon does after S: the echo of CR LF is on the
// line, RESET, then the banner back to back. The line goes to a receiver that does not check the stop
// bit (as kl11 of the terminal): it prints what it decodes. iverilog -g2005 -I ../rtl/inc
module tb;
reg clk = 0;
always #10 clk = ~clk;   // 50 MHz
reg rst = 1;
reg [2:0] adr = 3'b110;
reg [15:0] dat = 0;
reg cyc = 0, stb = 0, we = 0;
wire ack, txd;
wire [15:0] q;
wbc_uart #(.REFCLK(50000000)) u (
	.wb_clk_i(clk), .wb_rst_i(rst), .wb_adr_i(adr), .wb_dat_i(dat), .wb_dat_o(q), .wb_cyc_i(cyc),
	.wb_we_i(we), .wb_stb_i(stb), .wb_ack_o(ack), .txd(txd), .rxd(1'b1), .tx_hold(1'b0),
	.tx_irq_o(), .tx_iack_i(1'b0), .rx_irq_o(), .rx_iack_i(1'b0),
	.cfg_bdiv(16'd7), .cfg_nbit(2'b11), .cfg_nstp(1'b1), .cfg_pena(1'b0), .cfg_podd(1'b0)
);

task bus(input [2:0] a, input w, input [15:0] d);
begin
	@(posedge clk); adr <= a; we <= w; dat <= d; cyc <= 1; stb <= 1;
	@(posedge clk); while (!ack) @(posedge clk);
	cyc <= 0; stb <= 0; we <= 0;
end
endtask
// wait for TX ready (xcsr bit 7), then write the byte
task putc(input [7:0] c);
begin
	bus(3'b100, 0, 0);
	@(posedge clk);
	while (!q[7]) begin bus(3'b100, 0, 0); @(posedge clk); end
	bus(3'b110, 1, {8'd0, c});
end
endtask

// the receiver: 434 clocks a bit (kl11 at 115200), sampled in the middle, no stop bit check
localparam BIT = 434;
integer i; reg [7:0] b;
initial begin
	@(negedge rst);
	forever begin
		@(negedge txd);
		repeat (BIT / 2) @(posedge clk);
		if (txd == 0) begin
			for (i = 0; i < 8; i = i + 1) begin
				repeat (BIT) @(posedge clk);
				b[i] = txd;
			end
			repeat (BIT) @(posedge clk);   // the stop bit (not checked)
			if (b >= 8'h20 && b < 8'h7f) $write("%c", b); else $write("<%02h>", b);
		end
	end
end

reg [8*24-1:0] s; integer k;
initial begin
	repeat (5) @(posedge clk); rst <= 0;
	putc("S"); putc(8'h0d); putc(8'h0a);
	// RESET while the CR / LF frames are on the line
	`ifdef RESET_AT
	repeat (`RESET_AT) @(posedge clk);
	`else
	repeat (3000) @(posedge clk);
	`endif
	rst <= 1; repeat (40) @(posedge clk); rst <= 0;
	s = "PDP-11 MONITOR V1.0";
	for (k = 18; k >= 0; k = k - 1) putc(s[k*8 +: 8]);
	putc(8'h0a); putc(8'h0d); putc(8'h0a); putc(8'h0d);
	putc("B"); putc("O"); putc("O"); putc("T"); putc(">"); putc(" ");
	repeat (BIT * 40) @(posedge clk);
	$display("");
	$finish;
end
endmodule
