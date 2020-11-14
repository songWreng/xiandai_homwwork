`include ".\Signal.v"
`include ".\AD_Chip.v"
`include ".\EEPROM_WR.v"
`timescale 1ns / 1ps

// ISE 仿真时间只有1us(太短了), 需要在控制台上输入 run 1ms, 才可以看见实验结果
module Top;

wire clk;
wire en_write;
wire[7:0] input_data;
wire[7:0] cs_addr;
wire[7:0] rw_addr;
wire an_data;
wire en_out;

wire dclk;
wire[7:0] tran_data;
wire[11:0] amp_data;

wire SCL;
wire SDA;
wire[23:0] memory;

Signal signal(.clk(clk), 
				  .en_write(en_write),
				  .rw_addr(rw_addr), 
				  .cs_addr(cs_addr), 
				  .input_data(input_data),
				  .an_data(an_data),
				  .en_out(en_out));

EEPROM_WR eeprom_wr(.clk(clk),
						  .en_write(en_write),
						  .input_data(input_data),
						  .cs_addr(cs_addr),
						  .rw_addr(rw_addr),
						  .SCL(SCL), 
						  .SDA(SDA),
						  .dclk(dclk),
						  .tran_data(tran_data),
						  .amp_data(amp_data));
						  
EEPROM eeprom(.SCL(SCL), 
				  .SDA(SDA), 
				  .memory(memory),
				  .sa_input(an_data), 
				  .en_sample(en_out), 
				  .tran_data(tran_data),
				  .clk(dclk));

endmodule
