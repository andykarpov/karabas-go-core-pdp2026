`timescale 1ns / 1ps
// tb_pdp_img: sdspi_img (as a disk controller drives it) + pdp_img against a model of the SDC side
// of kg_l2_img (OUT_LATENCY 3, 512 byte strobes for a read). A write of a sector, a read back, a
// slot without an image and a block past the end (both: an error at once, no request).
// iverilog -g2005 -o tb tb_pdp_img.v ../rtl/pdp/sdspi_img.v ../rtl/karabas/pdp_img.v
//   ../rtl/ip/ip_mem.v ../../modules/rtl/mem/kg_tdpram.v ../../modules/rtl/mem/kg_sprom.v
module tb;
reg clk = 0;
always #10 clk = ~clk;
reg reset = 1;

// the controller side of sdspi_img
reg [26:0] addr = 0;
reg start = 0, wmode = 0;
wire done, err, idle;
reg [7:0] ba = 0;
wire [15:0] bq;
reg bwe = 0;
reg [15:0] bd = 0;
wire [19:0] ans;
wire [36:0] out;
sdspi_img dut (
	.sdcard_cs(), .sdcard_mosi(), .sdcard_sclk(), .sdcard_miso(1'b1), .sdcard_debug(),
	.sdcard_addr(addr), .sdcard_idle(idle), .sdspi_start(start), .sdspi_io_done(done),
	.sdspi_write_mode(wmode), .sdcard_error(err), .master_sdhc(), .slave_sdhc(1'b0),
	.sdbuf_addr(ba), .sdbuf_dataout(bq), .sdbuf_we(bwe), .sdbuf_datain(bd),
	.controller_clk(clk), .mode(1'b1), .sdclk(1'b0), .reset(reset), .img_in(ans), .img_out(out)
);

// the slot of this controller
reg [2:0] slot = 3'd0;

// the SDC model
reg [7:0] mounted = 0;
reg [63:0] size = 0;
wire [7:0] rd, wr;
wire [31:0] sector;
reg busy = 0, sdone = 0, serr = 0, strobe = 0;
reg [8:0] baddr = 0;
reg [7:0] bin = 0;
wire [7:0] bout;
wire act;
pdp_img eng (
	.clk(clk), .reset(reset), .img_req({ slot, out }), .img_ans(ans),
	.sdc_img_mounted(mounted), .sdc_img_size(size), .sdc_rd(rd), .sdc_wr(wr), .sdc_sector(sector),
	.sdc_busy(busy), .sdc_done(sdone), .sdc_error(serr), .sdc_byte_in_strobe(strobe),
	.sdc_byte_addr(baddr), .sdc_byte_in_data(bin), .sdc_byte_out_data(bout), .active(act)
);

reg [7:0] disk [0:4095];   // 8 blocks of the image
integer n_req = 0, i, k, errors = 0;
reg [31:0] lba;
always @(posedge clk) begin
	if (!busy && (rd != 0 || wr != 0)) begin
		n_req = n_req + 1;
		lba = sector;
		busy <= 1'b1;
		if (wr != 0) begin
			for (i = 0; i < 512; i = i + 1) begin
				@(posedge clk) baddr <= i;
				@(posedge clk); @(posedge clk); @(posedge clk);  // OUT_LATENCY 3
				disk[lba * 512 + i] = bout;
			end
		end
		else begin
			for (i = 0; i < 512; i = i + 1) begin
				@(posedge clk) begin strobe <= 1'b1; baddr <= i; bin <= disk[lba * 512 + i]; end
				@(posedge clk) strobe <= 1'b0;
			end
		end
		@(posedge clk) begin busy <= 1'b0; sdone <= 1'b1; serr <= 1'b0; end
		@(posedge clk) sdone <= 1'b0;
	end
end

task io(input w, input [26:0] a);
begin
	@(posedge clk) begin addr <= a; wmode <= w; start <= 1'b1; end
	while (!done) @(posedge clk);
	@(posedge clk) start <= 1'b0;
	while (done) @(posedge clk);
end
endtask

initial begin
	repeat (4) @(posedge clk); reset <= 0;
	// mount slot 0: 4 blocks
	@(posedge clk) begin mounted <= 8'h01; size <= 64'd2048; end
	@(posedge clk) mounted <= 0;
	// fill the buffer and write block 2
	for (k = 0; k < 256; k = k + 1) begin
		@(posedge clk) begin ba <= k; bd <= { k[7:0] ^ 8'h5A, k[7:0] }; bwe <= 1'b1; end
	end
	@(posedge clk) bwe <= 1'b0;
	io(1, 27'd2);
	if (err) begin $display("FAIL: write error"); errors = errors + 1; end
	for (k = 0; k < 256; k = k + 1)
		if (disk[2 * 512 + 2 * k] !== k[7:0] || disk[2 * 512 + 2 * k + 1] !== (k[7:0] ^ 8'h5A)) begin
			if (errors < 5) $display("FAIL: write byte order word %0d: %h %h", k, disk[1024 + 2 * k], disk[1024 + 2 * k + 1]);
			errors = errors + 1;
		end
	// clear the buffer, read block 2 back
	for (k = 0; k < 256; k = k + 1) begin
		@(posedge clk) begin ba <= k; bd <= 16'hDEAD; bwe <= 1'b1; end
	end
	@(posedge clk) bwe <= 1'b0;
	io(0, 27'd2);
	if (err) begin $display("FAIL: read error"); errors = errors + 1; end
	for (k = 0; k < 256; k = k + 1) begin
		@(posedge clk) ba <= k;
		@(posedge clk); @(posedge clk);
		if (bq !== { k[7:0] ^ 8'h5A, k[7:0] }) begin
			if (errors < 10) $display("FAIL: read word %0d = %h", k, bq);
			errors = errors + 1;
		end
	end
	// past the end (block 4 of 4): error, no request
	k = n_req;
	io(0, 27'd4);
	if (!err || n_req != k) begin $display("FAIL: past the end err=%b req %0d", err, n_req - k); errors = errors + 1; end
	// slot 1, no image: error, no request
	slot = 3'd1;
	io(0, 27'd0);
	if (!err || n_req != k) begin $display("FAIL: no image err=%b", err); errors = errors + 1; end
	// slot 0 again works after the errors
	slot = 3'd0;
	io(0, 27'd2);
	if (err || n_req != k + 1) begin $display("FAIL: after errors err=%b", err); errors = errors + 1; end
	$display("%s: %0d requests, %0d errors", errors ? "FAIL" : "PASS", n_req, errors);
	$finish;
end
initial begin #20000000; $display("FAIL: timeout"); $finish; end
endmodule
