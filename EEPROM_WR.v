`timescale 1ns / 1ps
`define PERIOD_QUARTER 625

module EEPROM_WR(clk, en_write, input_data, cs_addr, rw_addr, SCL, SDA,
					  dclk, tran_data, amp_data);

input 		clk;
input 		en_write;
input[7:0] 	input_data;	// 输入字节
input[7:0]	cs_addr;		// 片选地址
input[7:0]	rw_addr;		// 待处理的片内地址
output 		SCL;
inout 		SDA;
output 		dclk;			// 时钟分频1
input[7:0]	tran_data;	// 接受AD芯片转化的数据
output[11:0] amp_data;	// 放大12倍的数据，8位数放大12倍需要12位来存储

reg 			SCL;
reg 			out_flag;	// SDA数据输出的控制信号
reg 			sda_out;		// SDA输出寄存器
reg[7:0] 	sda_outbuf;	// SDA的输出缓存
reg[7:0] 	sda_inbuf;	// SDA的输入缓存

reg			dclk;
reg[11:0]	amp_data;

reg[3:0] 	state;		// IIC状态
reg[7:0] 	psc_cnt;		// SCL分频计数器
reg[3:0]		psc_clk_cnt;// dclk分频系数	
reg[3:0]		i;				// 循环变量

parameter IIC_IDLE  		= 4'd0,
			 IIC_START 		= 4'd1,	
			 IIC_TX_CS 		= 4'd2,  // 传输片选地址
			 IIC_ACK1  		= 4'd3,	
		    IIC_TX_ADDR	= 4'd4,	// 传输片内地址
			 IIC_ACK2  		= 4'd5,
			 IIC_TX_DATA	= 4'd6,	// 传输数据
			 IIC_ACK3		= 4'd7,
			 IIC_STOP  		= 4'd8;

assign SDA = (out_flag ? sda_out : 1'bz);

/*************************** 初始化 ***************************/
initial begin
	SCL 			<= 0;
	sda_out 		<= 1;
	out_flag 	<= 1'd1; // 设置为输出模式
	sda_outbuf	<= 8'd0;
	sda_inbuf  	<= 8'd0;
	psc_cnt 		<= 8'd0;
	state			<= IIC_IDLE;
	i				<= 4'd0;
	dclk			<= 0;
	amp_data 	<= 8'd0;
	psc_clk_cnt	<= 4'd0;
end


/************************* 分频得到SCL *************************/
// clk频率为10MHz, SCL要求频率400kHz, 分频系数10M/400k=25, 即25个clk周期算作1个SCL周期;
// SCL周期为2.5us=2500ns, 1/4周期为625ns;
always @(posedge clk) begin
	psc_cnt = psc_cnt + 1;
	if (psc_cnt == 25) begin
		SCL = ~SCL;
		psc_cnt = 0;
	end
	if (psc_cnt == 12) begin
		// 25非偶数，得再中间的clk周期(第13个)的下降沿突变
		@(negedge clk) SCL = ~SCL;
	end
end

// 分频给EEPROM提供采样时钟，输入信号的最高频率为1MHz，所以采样频率不小于2MHz，
// 实际采样频率取最高频率2.5倍以上, 这里取 dclk = 2.5MHz
always @(posedge clk) begin
	psc_clk_cnt = psc_clk_cnt + 1;
	if (psc_clk_cnt == 4) begin
		dclk = ~dclk;
		psc_clk_cnt = 0;
	end
end

/************************* 输出放大数据 *************************/
always @(tran_data) begin
	if (state == IIC_IDLE)
		amp_data <= ({4'b0000, tran_data} << 2) + ({4'b0000, tran_data} << 3);
	else
		amp_data <= 12'd0;
end

/************************* 等待写使能信号 *************************/
always @(posedge en_write) begin
	$display("EEPROM_WR said: en_write now");
	if (state == IIC_IDLE)
		state <= IIC_START;
end

/************************* IIC通信过程 *************************/
// 实测：state 必须使用非阻塞赋值，才能触发 @(state)
always @(state) begin
	$display("EEPROM_WR said: Time=%d, state=%d", $time, state);
	case(state)
		/*向EEPROM发送开始信号*/
		IIC_START: begin
			@(negedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 1;
			@(posedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 0;
			state <= IIC_TX_CS;
		end
		
		/*向EEPROM发送片选地址*/
		IIC_TX_CS: begin
			sda_outbuf = cs_addr; // 片选地址放入输出缓存
			SDA_TX_Byte; // task: 向从机发送输出缓存的字节
			state <= IIC_ACK1; 
		end
		
		/*等待EEPROM响应*/
		IIC_ACK1: begin
			SDA_Wait_ACK; // task: 等待从机响应
			state <= IIC_TX_ADDR; 
		end
		
		/*向EEPROM发送片内地址*/
		IIC_TX_ADDR: begin
			sda_outbuf = rw_addr; // 片内地址放入输出缓存
			SDA_TX_Byte; // task: 向从机发送输出缓存的字节
			state <= IIC_ACK2;
		end
		
		/*等待EEPROM响应*/
		IIC_ACK2: begin
			SDA_Wait_ACK; // task: 等待从机响应
			state <= IIC_TX_DATA;
		end
		
		/*向EEPROM发送数据*/
		IIC_TX_DATA: begin
			sda_outbuf = input_data; // 待写数据放入输出缓存
			SDA_TX_Byte; // task: 向从机发送输出缓存的字节
			state <= IIC_ACK3;
		end
		
		/*等待EEPROM响应*/
		IIC_ACK3: begin
			SDA_Wait_ACK; // task: 等待从机响应
			sda_out = 0; // 这里设置SDA输出0, 便于停止信号产生一个上升沿
			state <= IIC_STOP;
		end
		
		/*向EEPROM发送停止信号*/
		IIC_STOP: begin
			@(negedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 0;
			out_flag = 1; // SDA重新设置为输出模式
			@(posedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 1; // 这里设置SDA输出1, 便于开始信号产生一个下降沿
			state <= IIC_IDLE;
		end
		
		default:
			state <= IIC_IDLE;
	endcase
	
end

/************************* task定义 ***************************/

//----------- 主机向从机发送一个字节 --------------//
task SDA_TX_Byte;
begin
$display("EEPROM_WR said: time=%d, processing SDA_TX_Byte", $time);
for(i = 8; i >= 1; i = i - 1) begin // @note: for(i=7;i>=0;i=i-1) 是死循环
	@(negedge SCL);
	#`PERIOD_QUARTER;
	if (out_flag == 1'b0) out_flag = 1'b1; // 如果SDA为输入模式，则设置为SDA为输出模式
	sda_out = sda_outbuf[i - 1];
end
$display("EEPROM_WR said: time=%d, finish SDA_TX_Byte", $time);
end
endtask

//------------- 主机等待从机响应 ----------------//
// 注意：每次调用次任务后, SDA被设置为输入模式!
task SDA_Wait_ACK;
begin
	$display("EEPROM_WR said: time=%d, processing SDA_Wait_ACK.", $time);
	@(negedge SCL);
	#`PERIOD_QUARTER;
	out_flag = 0; // SDA设置为输入模式
	
	// 判断从机是否有响应
	@(posedge SCL) sda_inbuf[7] = SDA;
	if (sda_inbuf[7] == 1'b0)
		$display("EEPROM_WR said: Get ACK!");
	else 
		$display("EEPROM_WR said: No ACK!");
	
	$display("EEPROM_WR said: time=%d, finish SDA_Wait_ACK.", $time);
end
endtask

endmodule
