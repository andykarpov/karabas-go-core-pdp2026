/*
	128	words per sector (256 bytes)
	 40	sectors per surface
	  2	surfaces per cylinder
	512	cylinders per drive (RL02)
	
	===   10_485_760 bytes per drive, 40960 sectors per drive
*/

module rl11(
	input							clk_p,
	input							sys_init,

	// BUS
	input				[21:0]	wb_adr_i,
	input				[15:0]	wb_dat_i,
	output	reg	[15:0]	wb_dat_o,
	input							bus_stb,
	input							wb_we_i,
	input				[1:0]		wb_sel_i,
	output	reg				rl11_ack,

	// IRQ
	output	reg           irq,         // запрос
   input                  iack,        // подтверждение

// DMA
   output	reg           dma_req,    // запрос DMA
   input                  dma_gnt,    // подтверждение DMA
   output 	reg	[17:0]  dma_adr_o,  // выходной адрес при DMA-обмене
   input				[15:0]  dma_dat_i,  // входная шина данных DMA
   output	reg	[15:0]  dma_dat_o,  // выходная шина данных DMA
   output	reg           dma_stb_o,  // строб цикла шины DMA
   output	reg           dma_we_o,   // направление передачи DMA (0 - память->диск, 1 - диск->память) 
   input                  dma_ack_i,  // Ответ от устройства, с которым идет DMA-обмен
	
// интерфейс SD-карты
   output                 sdcard_cs, 
   output                 sdcard_mosi, 
   output                 sdcard_sclk, 
   input                  sdcard_miso, 
   output	reg           sdreq,      // запрос доступа к карте
   input                  sdack,      // подтверждение доступа к карте
   
// тактирование SD-карты
   input                  sdclock,   

// Адрес начала банка на карте
   input				[26:0]  start_offset,
	output 			 		  master_sdhc,
	input				 		  slave_sdhc,
	input  [19:0]           img_in,    // karabas: the image bus of sdspi_img (pdp_img)
	output [36:0]           img_out
) ;

	wire	[26:0] 	sdaddr ;						// адрес сектора карты
	reg 	[26:0] 	sdcard_addr ;				// адрес сектора карты
	wire				sdcard_idle ;           // признак готовности контроллера
	wire				sdcard_error ;          // флаг ошибки
	reg				sdspi_start = 1'b0 ;		// строб запуска sdspi
	wire				sdspi_io_done ;			// флаг заверщение операции обмена с картой
	reg	[7:0]		sdbuf_addr ;				// адрес в буфере чтния/записи
	wire	[15:0] 	sdbuf_dataout ;			// слово; читаемое из буфера чтения
	reg	[15:0] 	sdbuf_datain = 16'b0 ;
	reg				sdbuf_we = 1'b0 ;
	reg				sdspi_we = 1'b0 ;

	sdspi_img sdcard (   // karabas: an image file of the MCU instead of the SD card
		.img_in(img_in), .img_out(img_out),
		// интерфейс к карте
		.sdcard_cs(sdcard_cs), 
		.sdcard_mosi(sdcard_mosi), 
		.sdcard_miso(sdcard_miso),
		.sdcard_sclk(sdcard_sclk),

		.sdcard_addr(sdcard_addr),               // адрес блока на карте
		.sdcard_idle(sdcard_idle),               // сигнал готовности модуля к обмену
		.sdcard_error(sdcard_error),             // флаг ошибки
		.master_sdhc(master_sdhc),
		.slave_sdhc(slave_sdhc),

		// сигналы управления чтением - записью
		.sdspi_start(sdspi_start),                // строб запуска ввода вывода
		.sdspi_io_done(sdspi_io_done),            // флаг окончания обмена данными
		.sdspi_write_mode(sdspi_we),    				// режим: 0 - чтение, 1 - запись

		// интерфейс к буферной памяти контроллера
		.sdbuf_addr(sdbuf_addr),                 // текущий адрес в буферах чтения и записи
		.sdbuf_dataout(sdbuf_dataout),           // слово, читаемое из буфера чтения
		.sdbuf_datain(sdbuf_datain),       		  // слово, записываемое в буфер записи
		.sdbuf_we(sdbuf_we),                  	  // строб записи буфера

		.mode(1'b0),                             // режим ведущего-ведомого контроллера
		.controller_clk(clk_p),                  // синхросигнал общей шины
		.reset(sys_init),                        // сброс
		.sdclk(sdclock)                          // синхросигнал SD-карты
	) ; 

	localparam CSR_ADR = 15'o76200 ;
	localparam BAR_ADR = 15'o76201 ;
	localparam DAR_ADR = 15'o76202 ;
	localparam MPR_ADR = 15'o76203 ;

	reg [15:0]	bar, // 174402 Bus Address (BA)
					// 174404 Disk Address (DA)
					mpr ; // 174406 Multipurpose (MP)

	wire [14:0] adr_i = wb_adr_i[15:1] ;
	wire rl11_stb = bus_stb & ((adr_i == CSR_ADR) || (adr_i == BAR_ADR) || (adr_i == DAR_ADR) || (adr_i == MPR_ADR)) ;
	
	
	// CSR 174400 Control Status (CS)
	wire			csr_err ;			// [15]		composite error if one or more of bits [14:10] is set
	reg			csr_de	= 1'b0 ; // [14]		drive has errors
	reg			csr_nxm	= 1'b0 ; // [13]		non-existent memory
	reg	[2:0]	csr_e		= 3'b0 ; // [12:10]	error bits: OPI, CRC | WCE, DLT | HNF
	reg	[1:0]	csr_ds	= 2'b0 ; // [9:8]		drive select (unit number 0..3)
	reg			csr_crdy = 1'b1 ; // [7]		controller ready
	reg			csr_ie	= 1'b0 ; // [6]		interrupt enable
	reg	[1:0]	csr_ba	= 2'b0 ; // [5:4]		bus address extension bits BA17, BA16
	reg	[2:0]	csr_fc	= 2'b0 ; // [3:1]		function code
	reg			csr_drdy = 1'b1 ; // [1]		drive ready
	
	assign csr_err = | csr_e | csr_nxm | csr_de ;
	
	// DAR 174404 Disk Address (DA)
	reg  [15:0]	dar = 16'b0 ;
	reg			dn_head[0:3]	;   // karabas: [0:3] (Verilog-2001 for XST) // drive head
	reg	[8:0]	dn_cyl[0:3]	;   // karabas: [0:3] // drive cylinder

	initial begin
		dn_head[0]	<= 1'b0 ;
		dn_head[1]	<= 1'b0 ;
		dn_head[2]	<= 1'b0 ;
		dn_head[3]	<= 1'b0 ;
		dn_cyl[0]	<= 9'b0 ;
		dn_cyl[1] <= 9'b0 ;
		dn_cyl[2] <= 9'b0 ;
		dn_cyl[3] <= 9'b0 ;
	end

	localparam IS_IDLE = 2'd0 ;	// ожидание прерывания
	localparam IS_REQ  = 2'd1 ;   // запрос векторного прерывания
	localparam IS_WAIT = 2'd2 ;	// ожидание обработки прерывания со стороны процессора
	
	localparam DELAY_SEEK = 16'd500 ;
	localparam DELAY_READ_HEADER = 16'd100 ;

	reg	[1:0]	interrupt_state	= IS_IDLE ;
	reg			interrupt_trigger	= 1'b0 ;

	reg [15:0] RLWC = 16'b0 ;
	reg update_mpr = 1'b0 ;
	
	wire  [5:0] sector = dar[5:0] ;

	localparam RL_FUNC_NOP				= 3'b000 ;
	localparam RL_FUNC_WRITE_CHECK	= 3'b001 ;
	localparam RL_FUNC_GET_STATUS		= 3'b010 ;
	localparam RL_FUNC_SEEK				= 3'b011 ;
	localparam RL_FUNC_READ_HEADER	= 3'b100 ;
	localparam RL_FUNC_WRITE_DATA		= 3'b101 ;
	localparam RL_FUNC_READ_DATA		= 3'b110 ;
	localparam RL_FUNC_READ_DATA_WH	= 3'b111 ;
	
	localparam RS_IDLE	= 4'd0 ;
	localparam RS_R01		= 4'd1 ;
	localparam RS_R02		= 4'd2 ;
	localparam RS_R03		= 4'd3 ;
	localparam RS_R04		= 4'd4 ;
	localparam RS_R05		= 4'd5 ;
	localparam RS_R06		= 4'd6 ;
	localparam RS_R07		= 4'd7 ;
	localparam RS_W01		= 4'd8 ;
	localparam RS_W02		= 4'd9 ;
	localparam RS_W03		= 4'd10 ;
	localparam RS_W04		= 4'd11 ;
	localparam RS_W05		= 4'd12 ;
	localparam RS_W06		= 4'd13 ;
	localparam RS_DELAY	= 4'd14 ;

	reg [3:0] rl_state = RS_IDLE ;
	
	reg [15:0] rl_delay = 16'b0 ;
	reg [15:0] header_reg0 = 16'b0 ;
	reg [15:0] header_reg1 = 16'b0 ;
	reg [15:0] header_reg2 = 16'b0 ;
	reg heads_on = 1'b1 ;

	always @(posedge clk_p) begin
		if (sys_init) begin
			csr_de <= 1'b0 ;
			csr_nxm <= 1'b0 ;
			csr_e <= 3'b0 ;
			csr_ds <= 2'b0 ;
			csr_crdy <= 1'b1 ;
			csr_ie <= 1'b0 ;
			csr_ba <= 2'b0 ;
			csr_fc <= 2'b0 ;
			csr_drdy <= 1'b1 ;

			dar <= 16'b0 ;
			mpr <= 16'b0 ;
			bar <= 16'b0 ;
			RLWC <= 16'b0 ;
			update_mpr <= 1'b0 ;
			rl_delay <= 16'b0 ;
			heads_on <= 1'b1 ;

			irq <= 1'b0 ;
			rl11_ack	<= 1'b0 ;
			rl_state <= RS_IDLE ;
			dma_req <= 1'b0 ;
			dma_we_o <= 1'b0 ;
			sdreq <= 1'b0 ;
			interrupt_trigger <= 1'b0 ;
			interrupt_state <= IS_IDLE ;
			sdspi_start <= 1'b0 ;
		end else begin
			case (interrupt_state)
				IS_IDLE : begin
					if (csr_ie & interrupt_trigger) begin
						irq <= 1'b1 ;
						interrupt_state <= IS_REQ ;
					end else
						irq <= 1'b0 ;
				end
				
				IS_REQ : begin
					if (~csr_ie) begin
						interrupt_trigger <= 1'b0 ;
						interrupt_state <= IS_IDLE ;
					end else if (iack) begin
						irq <= 1'b0 ;
						interrupt_trigger <= 1'b0 ;
						interrupt_state <= IS_WAIT ;
					end
				end
				
				IS_WAIT :
					if (~iack)
						interrupt_state <= IS_IDLE ;
			endcase
			
			if (rl11_stb) begin
				// karabas: the access once, on the first clock of the strobe: the strobe stays up until the
				// clock after the ack and the CPU latches the data then, so a repeated MPR read shifted the
				// header out before it was taken (READ HEADER gave 0, the boot seeked to a wrong cylinder)
				if (rl11_ack) begin
				end else if (wb_we_i) begin
					case (adr_i)
						CSR_ADR : begin
							if (wb_sel_i[0]) begin
								csr_fc	<= wb_dat_i[3:1] ;
								csr_ba	<= wb_dat_i[5:4] ;
								csr_ie	<= wb_dat_i[6] ;
								csr_crdy	<= wb_dat_i[7] ;
							end
							if (wb_sel_i[1]) begin
								csr_e		<= 3'b0 ;
								csr_nxm	<= 1'b0 ;
								csr_ds	<= wb_dat_i[9:8] ;
							end
						end
						
						BAR_ADR : begin
							if (wb_sel_i[0])
								bar[7:0] <= {wb_dat_i[7:1], 1'b0} ;
							if (wb_sel_i[1])
								bar[15:8] <= wb_dat_i[15:8] ;
						end
						
						DAR_ADR : begin
							if (wb_sel_i[0])
								dar[7:0] <= wb_dat_i[7:0] ;
							if (wb_sel_i[1])
								dar[15:8] <= wb_dat_i[15:8] ;
						end
						
						MPR_ADR : begin
							if (wb_sel_i[0]) begin
								mpr[7:0] <= wb_dat_i[7:0] ;
								update_mpr <= 1'b1 ;
							end
							if (wb_sel_i[1]) begin
								mpr[15:8] <= wb_dat_i[15:8] ;
								update_mpr <= 1'b1 ;
							end
						end
					endcase
				end else begin
					case (adr_i)
						CSR_ADR : begin
								wb_dat_o <= {csr_err, csr_de, csr_nxm, csr_e, csr_ds, csr_crdy, csr_ie, csr_ba, csr_fc, csr_drdy} ;
								csr_drdy <= 1'b1 ;
							end
						BAR_ADR : wb_dat_o <= bar ;
						DAR_ADR : wb_dat_o <= dar ;
						MPR_ADR :
							case (csr_fc)
								RL_FUNC_GET_STATUS : begin
									wb_dat_o <= {9'b000000001, dn_head[csr_ds], 5'b01110, heads_on} ; // DriveType RL02, head number, LockOn, BrushHome, HeadsOn
									heads_on <= 1'b1 ;
								end
								
								RL_FUNC_READ_HEADER : begin
									wb_dat_o <= header_reg0 ;
									header_reg0 <= header_reg1 ;
									header_reg1 <= header_reg2 ;
								end
								default : wb_dat_o <= 16'b0 ;
							endcase
					endcase
				end

				rl11_ack <= 1'b1 ;
			end
			
			if (update_mpr) begin
				RLWC <= mpr ;
				update_mpr <= 1'b0 ;
			end
			
			if (~rl11_stb) begin
				rl11_ack <= 1'b0 ;
				
				if (~csr_crdy) begin
					case (csr_fc)
						RL_FUNC_NOP : begin
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
						end
						
						RL_FUNC_GET_STATUS : begin
							if (dar[1] == 1'b0)	// check go bit set
								csr_e <= 3'b001 ;
								
							if (dar[3] == 1'b1) // clear errors
								{csr_de, csr_nxm, csr_e} <= 5'b0 ;
								
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
						end
						
						RL_FUNC_SEEK : begin
							csr_drdy <= 1'b0 ;
							heads_on <= 1'b0 ;
							if (dar[2]) begin // forward
								if ({1'b0, dn_cyl[csr_ds]} + {1'b0, dar[15:7]} <= 10'o777) begin
									dn_cyl[csr_ds] <= dn_cyl[csr_ds] + dar[15:7] ;
								end else begin
									dn_cyl[csr_ds] <= 9'o777 ;
								end
							end else begin    // backward
								if (dn_cyl[csr_ds] >= dar[15:7]) begin
									dn_cyl[csr_ds] <= dn_cyl[csr_ds] - dar[15:7] ;
								end else begin
									dn_cyl[csr_ds] <= 9'b0 ;
								end
							end
							dn_head[csr_ds] <= dar[4] ;
							rl_delay <= DELAY_SEEK ;
							rl_state <= RS_DELAY ;
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
						end
						
						RL_FUNC_READ_HEADER : begin
							if ({1'b0, dar[5:0]} < 7'b0100111) begin	// don't increment beyond o47
								dar[5:0] <= dar[5:0] + 1'b1 ;
								header_reg0 <= {dn_cyl[csr_ds], dn_head[csr_ds], dar[5:0] + 1'b1} ;
							end else begin
								dar[5:0] <= 6'b0 ;	// acc. manual, should be set to 050 on track overrun
								header_reg0 <= {dn_cyl[csr_ds], dn_head[csr_ds], 6'b0} ;
							end
							header_reg1 <= 16'b0 ; //zeroes
							header_reg2 <= 16'b0 ; // CRC
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
							csr_drdy <= 1'b0 ;
							rl_delay <= DELAY_READ_HEADER ;
							rl_state <= RS_DELAY ;
						end
					endcase
				end
				
				case (rl_state)
					RS_IDLE : begin
						if (~csr_crdy && (csr_fc == RL_FUNC_READ_DATA || csr_fc == RL_FUNC_READ_DATA_WH || csr_fc == RL_FUNC_WRITE_CHECK)) begin
							{csr_de, csr_nxm, csr_e} <= 5'b0 ;
							rl_state <= RS_R01 ;
						end else if (~csr_crdy && csr_fc == RL_FUNC_WRITE_DATA) begin
							{csr_de, csr_nxm, csr_e} <= 5'b0 ;
							rl_state <= RS_W01 ;
						end
					end
					
					RS_DELAY : begin
						rl_delay <= rl_delay - 1'b1 ;
						if (rl_delay == 16'd0) begin
							csr_drdy <= 1'b1 ;
							heads_on <= 1'b1 ;
							rl_state <= RS_IDLE ;
						end
					end
					
					// ----------------------- READ ---------------------------------
					
					RS_R01 : begin
						if (sector > 6'd39) begin
							{csr_e, csr_crdy} <= 4'b0011 ; // OPI, Ready
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
							rl_state <= RS_IDLE ;
						end else begin
							sdreq <= 1'b1 ;
							rl_state <= RS_R02 ;
						end
					end
					
					RS_R02 : if (sdack & sdcard_idle) begin
						sdcard_addr <= sdaddr ;
						sdbuf_addr <= 8'b0 ;
						sdspi_we <= 1'b0 ;
						sdspi_start <= 1'b1 ;
						rl_state <= RS_R03 ;
					end
					
					RS_R03 : if (sdspi_io_done) begin
						sdspi_start <= 1'b0 ;
						sdreq <= 1'b0 ;
						dar[5:0] <= dar[5:0] + 1'b1 ;
						sdbuf_we <= 1'b0 ;
						dma_req <= 1'b1 ;
						rl_state <= RS_R04 ;
					end
					
					RS_R04 : if (dma_gnt & ~dma_ack_i) begin
						rl_state <= RS_R05 ;
					end
					
					RS_R05 : begin
						if (RLWC == 16'b0) begin
							dma_req <= 1'b0 ;
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
							rl_state <= RS_IDLE ;
						end else begin
							dma_adr_o <= {csr_ba, bar} ;
							dma_dat_o <= sdbuf_dataout ;
							dma_we_o <= 1'b1 ;
							dma_stb_o <= 1'b1 ;
							rl_state <= RS_R06 ;
						end
					end
					
					RS_R06 : if (dma_ack_i) begin
						dma_stb_o <= 1'b0 ;
						rl_state <= RS_R07 ;
					end
					
					RS_R07 : if (~dma_ack_i) begin
						dma_we_o <= 1'b0 ;
						RLWC <= RLWC + 1'b1 ;
						bar <= bar + 2'd2 ;
						sdbuf_addr <= sdbuf_addr + 1'b1 ;
						rl_state <= RS_R04 ;
						
						if (sdbuf_addr == 8'd127 && RLWC != 16'o177777) begin
							dma_req <= 1'b0 ;
							rl_state <= RS_R01 ;
						end
					end
					
					// ----------------------- WRITE ---------------------------------
					
					RS_W01 : begin
						if (sector > 6'd39) begin
							{csr_e, csr_crdy} <= 4'b0011 ; // Err, OPI, Ready
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
							rl_state <= RS_IDLE ;
						end else begin
							dma_req <= 1'b1 ;
							sdbuf_addr <= 8'b0 ;
							rl_state <= RS_W02 ;
						end
					end
					
					RS_W02 : if (dma_gnt & ~dma_ack_i) begin
						if (sdbuf_addr < 8'd128) begin
							dma_adr_o <= {csr_ba, bar} ;
							dma_we_o <= 1'b0 ;
							dma_stb_o <= 1'b1 ;
						end
						rl_state <= RS_W03 ;
					end
					
					RS_W03 : if (dma_ack_i | sdbuf_addr > 8'd127) begin
						sdbuf_datain <= sdbuf_addr < 8'd128 ? dma_dat_i : 16'b0 ;
						sdbuf_we <= 1'b1 ;
						dma_stb_o <= 1'b0 ;
						rl_state <= RS_W04 ;
					end
					
					RS_W04 : if (~dma_ack_i) begin
						sdbuf_we <= 1'b0 ;
						if (sdbuf_addr < 8'd128 && RLWC != 16'b0) begin
							RLWC <= RLWC + 1'b1 ;
							bar <= bar + 2'd2 ;
						end
						sdbuf_addr <= sdbuf_addr + 1'b1 ;
						
						rl_state <= RS_W02 ;
						
						if (sdbuf_addr == 8'd255) begin
							dma_req <= 1'b0 ;
							sdreq <= 1'b1 ;
							rl_state <= RS_W05 ;
						end
						
					end
					
					RS_W05 : if (sdack & sdcard_idle) begin
						sdcard_addr <= sdaddr ;
						sdspi_we <= 1'b1 ;
						sdspi_start <= 1'b1 ;
						rl_state <= RS_W06 ;
					end
					
					RS_W06 : if (sdspi_io_done) begin
						dar[5:0] <= dar[5:0] + 1'b1 ;
						sdspi_start <= 1'b0 ;
						sdreq <= 1'b0 ;
						
						if (RLWC == 16'b0) begin
							csr_crdy <= 1'b1 ;
							if (csr_ie)
								interrupt_trigger <= 1'b1 ;
							rl_state <= RS_IDLE ;
						end else begin
							rl_state <= RS_W01 ;
						end
					end
				endcase
			end
			
			csr_de <= sdcard_error ;
		end
	end
	
/*
	 40	sectors per surface
	  2	surfaces per cylinder
	512	cylinders per drive (RL02)
	
	===   40960 sectors per drive,
	      4 drives per controller
	
*/
	
   wire [16:0]	dn_offset = {csr_ds, 15'd0} + {csr_ds, 13'b0} ; // dn * 40960 = dn << 15 + dn << 13 ;
	wire [17:0]	cyl_offset = {dn_cyl[csr_ds], 6'b0} + {dn_cyl[csr_ds], 4'b0}; // cyl * 80 = cyl << 6 + cyl << 4
	wire  [5:0]	head_offset = {dn_head[csr_ds], 5'b0} + {dn_head[csr_ds], 3'b0} ; // head * 40 = head << 5 + head << 3

	assign sdaddr = start_offset + dn_offset + cyl_offset + head_offset + sector ;
	
endmodule
