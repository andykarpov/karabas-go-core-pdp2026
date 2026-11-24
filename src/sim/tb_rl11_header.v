`timescale 1ns / 1ps
// tb_rl11_header: rl11 register reads with the bus timing of the pdp2011 mmu: the strobe stays up
// until the clock after the ack is seen, the CPU latches the data one clock after the ack (mmu
// io_ack -> cpu_ack -> datain). A SEEK to cylinder 5 head 1, then READ HEADER and the 3 reads of
// the MPR: the first must give { cyl 5, head 1, sector }, the next two 0. Then GET STATUS.
// Run from src:
// iverilog -g2005 -I rtl/inc -o tb sim/tb_rl11_header.v rtl/pdp/rl11.v rtl/pdp/sdspi_img.v
//   rtl/ip/ip_mem.v ../modules/rtl/mem/kg_tdpram.v ../modules/rtl/mem/kg_sprom.v && vvp tb
module tb;
reg clk = 0;
always #10 clk = ~clk;
reg init = 1;

reg [21:0] adr = 0;
reg [15:0] dat = 0;
reg we = 0;
reg stb = 0;
wire [15:0] dout;
wire ack;

rl11 dut (
	.clk_p(clk), .sys_init(init),
	.wb_adr_i(adr), .wb_dat_i(dat), .wb_dat_o(dout), .bus_stb(stb), .wb_we_i(we),
	.wb_sel_i(2'b11), .rl11_ack(ack),
	.irq(), .iack(1'b0),
	.dma_req(), .dma_gnt(1'b0), .dma_adr_o(), .dma_dat_i(16'd0), .dma_dat_o(), .dma_stb_o(),
	.dma_we_o(), .dma_ack_i(1'b0),
	.sdcard_cs(), .sdcard_mosi(), .sdcard_sclk(), .sdcard_miso(1'b1), .sdreq(), .sdack(1'b0),
	.sdclock(1'b0), .start_offset(27'd0), .master_sdhc(), .slave_sdhc(1'b0),
	.img_in(20'd0), .img_out()
);

// one bus cycle as the mmu + cpu do it
reg [15:0] datain;
task bus(input w, input [15:0] a, input [15:0] d);
	begin
		@(posedge clk); adr <= {6'd0, a}; dat <= d; we <= w; stb <= 1;   // mmu io_idle
		@(posedge clk); while (!ack) @(posedge clk);                    // mmu io_ack sees the ack
		@(posedge clk); datain <= dout; stb <= 0;                       // io_reply, cpu latches
		@(posedge clk); @(posedge clk);
	end
endtask

localparam CS = 16'o174400, BA = 16'o174402, DA = 16'o174404, MP = 16'o174406;

task wait_rdy;   // poll CSR until CRDY and DRDY
	begin
		bus(0, CS, 0);
		while (!(datain[7] && datain[0])) bus(0, CS, 0);
	end
endtask

integer fails = 0;
task expect(input [15:0] got, input [15:0] want, input [8*40-1:0] what);
	if (got !== want) begin
		$display("FAIL %0s: %06o, want %06o", what, got, want); fails = fails + 1;
	end else
		$display("ok   %0s: %06o", what, got);
endtask

initial begin
	repeat (4) @(posedge clk);
	init <= 0;
	repeat (4) @(posedge clk);
	// SEEK unit 1: 5 cylinders forward, head 1 (DA: diff<<7 | hs<<4 | dir<<2 | 1)
	bus(1, DA, (16'd5 << 7) | (16'd1 << 4) | 16'd4 | 16'd1);
	bus(1, CS, 16'o000406 | 16'o400);  // unit 1, function SEEK (3<<1), CRDY = 0
	wait_rdy;
	// READ HEADER
	bus(1, CS, 16'o000410 | 16'o400);  // unit 1, function READ HEADER (4<<1)
	wait_rdy;
	bus(0, MP, 0); expect(datain >> 6, (16'd5 << 1) | 16'd1, "header cyl / head");
	bus(0, MP, 0); expect(datain, 16'd0, "header word 2");
	bus(0, MP, 0); expect(datain, 16'd0, "header word 3 (CRC)");
	// GET STATUS, after the delay of the seek / header (the drive is in seek state until then)
	repeat (1000) @(posedge clk);
	bus(1, DA, 16'o3);
	bus(1, CS, 16'o000404 | 16'o400);
	wait_rdy;
	bus(0, MP, 0); expect(datain & 16'o377, 16'o335, "status: RL02 head 1 lock on");
	if (fails) $display("FAILED %0d", fails); else $display("PASS");
	$finish;
end
initial begin #2000000 $display("TIMEOUT"); $finish; end
endmodule
