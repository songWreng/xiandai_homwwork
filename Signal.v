`timescale 1ns / 1ps

module Signal(clk, en_write, rw_addr, cs_addr, input_data,
				an_data, en_out);

output 		clk;
output 		en_write;
output[7:0] rw_addr;
output[7:0] cs_addr;
output[7:0] input_data;
output		an_data;
output		en_out;

reg 			clk;
reg 			en_write;
reg[7:0]	 	rw_addr;
reg[7:0] 	cs_addr;
reg[7:0] 	input_data;
reg			an_data;
reg			en_out;

/************************* 产生时钟信号 *************************/
always #50 clk = ~clk;

/*************************  仿真信号 	 *************************/
initial begin
	en_write = 0;
	clk = 0;
	en_out = 0;
	an_data = 0;
	
	/* 测试1：在地址0x48写入数据0x55 */
	rw_addr = 8'h48;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'h55;
	#100; 
	en_write = 1;
	#100;
	en_write = 0;
	#100000; // 100us
	
	/* 测试2：在地址0x49写入数据0xAA */
	rw_addr = 8'h49;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'hAA;
	en_write = 1;
	#100;
	en_write = 0;
	#100000;
	
	/* 测试3：在地址0x4A写入数据0xCC */
	rw_addr = 8'h4A;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'hCC;
	en_write = 1;
	#100;
	en_write = 0;
	#100000;
	
	/* 测试4：放大数据*/
	an_data = 1;
	#100;		
	en_out = 1;
	#100;
	en_out = 0;
	
	
end
endmodule
