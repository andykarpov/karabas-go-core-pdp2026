`timescale 1ns / 1ps
`default_nettype wire
/*
 pdp_img.v (karabas)

 The disks of the PDP-11 from image files on the SD card of the MCU (kg_mcu2 IMG = kg_l2_img)
 instead of the SD2 card: one slot per controller, its units back to back in the file at
 unit * unit size, as they were on SD2 (the controllers compute the block themselves; their start
 offsets are 0): slot 0 RK11 (RK05, 4872 blocks a unit), 1 RL11 (RL02, 40960: a 256 byte sector a
 block, as sd-store wrote them), 2 RH70 (RP06, 340670), 3 the paper tape (PC11 reader and punch,
 200 blocks: a byte a word { 0377, byte }).

 img_req = { slot[2:0], req, write, lba[26:0], byte_out[7:0] } of the controller that holds the
 card (topboard22, sdspi_img); img_ans = { done, error, strobe, byte_addr[8:0], byte_in[7:0] } to
 all of them. A request of a slot without an image, or past the end of its image, is answered at
 once with an error (no event to the MCU).
*/
module pdp_img (
	input  wire clk,
	input  wire reset,

	input  wire [39:0] img_req,
	output wire [19:0] img_ans,

	// kg_mcu2 SDC_*
	input  wire [7:0]  sdc_img_mounted,
	input  wire [63:0] sdc_img_size,
	output reg  [7:0]  sdc_rd = 8'd0,
	output reg  [7:0]  sdc_wr = 8'd0,
	output reg  [31:0] sdc_sector = 32'd0,
	input  wire        sdc_busy,
	input  wire        sdc_done,
	input  wire        sdc_error,
	input  wire        sdc_byte_in_strobe,
	input  wire [8:0]  sdc_byte_addr,
	input  wire [7:0]  sdc_byte_in_data,
	output wire [7:0]  sdc_byte_out_data,

	output wire        active   // a request is being served (the disk light)
);

wire [2:0]  r_slot = img_req[39:37];
wire        r_req  = img_req[36];
wire        r_wr   = img_req[35];
wire [26:0] r_lba  = img_req[34:8];
assign sdc_byte_out_data = img_req[7:0];

// the size of each image in blocks (0 = no image)
reg [27:0] blocks [0:3];
integer i;
initial for (i = 0; i < 4; i = i + 1) blocks[i] = 28'd0;
always @(posedge clk)
	for (i = 0; i < 4; i = i + 1)
		if (sdc_img_mounted[i])
			blocks[i] <= sdc_img_size[36:9];

localparam S_IDLE = 2'd0, S_TAKE = 2'd1, S_WAIT = 2'd2, S_LOW = 2'd3;
reg [1:0] state = S_IDLE;
reg done = 1'b0, error = 1'b0;
wire in_range = r_slot[2] == 1'b0 && { 1'b0, r_lba } < blocks[r_slot[1:0]];

always @(posedge clk) begin
	done <= 1'b0;
	if (reset) begin
		state <= S_IDLE;
		sdc_rd <= 8'd0;
		sdc_wr <= 8'd0;
	end
	else case (state)
		S_IDLE:
			if (r_req) begin
				if (!in_range) begin
					done <= 1'b1;
					error <= 1'b1;
					state <= S_LOW;
				end
				else begin
					sdc_sector <= { 5'd0, r_lba };
					sdc_rd <= r_wr ? 8'd0 : (8'd1 << r_slot);
					sdc_wr <= r_wr ? (8'd1 << r_slot) : 8'd0;
					state <= S_TAKE;
				end
			end
		S_TAKE:
			if (sdc_busy) begin
				sdc_rd <= 8'd0;
				sdc_wr <= 8'd0;
				state <= S_WAIT;
			end
		S_WAIT:
			if (sdc_done) begin
				done <= 1'b1;
				error <= sdc_error;
				state <= S_LOW;
			end
		S_LOW:   // the controller drops req a clock after done
			if (!r_req && !done)
				state <= S_IDLE;
	endcase
end

assign img_ans = { done, error, sdc_byte_in_strobe, sdc_byte_addr, sdc_byte_in_data };
assign active = state != S_IDLE;

endmodule
