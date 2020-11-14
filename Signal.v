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

/************************* ����ʱ���ź� *************************/
always #50 clk = ~clk;

/*************************  �����ź� 	 *************************/
initial begin
	en_write = 0;
	clk = 0;
	en_out = 0;
	an_data = 0;
	
	/* ����1���ڵ�ַ0x48д������0x55 */
	rw_addr = 8'h48;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'h55;
	#100; 
	en_write = 1;
	#100;
	en_write = 0;
	#100000; // 100us
	
	/* ����2���ڵ�ַ0x49д������0xAA */
	rw_addr = 8'h49;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'hAA;
	en_write = 1;
	#100;
	en_write = 0;
	#100000;
	
	/* ����3���ڵ�ַ0x4Aд������0xCC */
	rw_addr = 8'h4A;
	cs_addr = {7'b000_0111, 1'b0};
	input_data = 8'hCC;
	en_write = 1;
	#100;
	en_write = 0;
	#100000;
	
	/* ����4���Ŵ�����*/
	an_data = 1;
	#100;		
	en_out = 1;
	#100;
	en_out = 0;
	
	
end
endmodule
