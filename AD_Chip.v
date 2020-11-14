`timescale 1ns / 1ps
`define PERIOD_QUARTER 625

module EEPROM(SCL, SDA, memory, 
		sa_input, en_sample, tran_data, clk);

input SCL;
inout SDA;
input sa_input;
input en_sample;
input clk;					// 采样时钟，由EEPROM提供
output[23:0] memory;
output[7:0] tran_data;			

reg[23:0] memory;
reg[ 7:0] tran_data;		// 转化的数据
//reg en_sample;				// AD芯片采样使能

reg sda_out;            // sda 输出寄存器  
reg out_flag;           // sda 输出标志
reg[7:0] sda_outbuf;    // sda 输出缓存
reg[7:0] sda_inbuf;     // sda 输入缓存

reg[3:0] state;         // IIC 状态

reg[6:0] cs_addr;       // 接收到的片选地址
reg[7:0] rw_addr;       // 接收到的待读写的片内地址
reg isread;             // 是否读取AD数据

reg[8:0] i;             // 循环变量 

parameter CS_ADDR = 7'b000_0111; // AD芯片的片选地址

parameter IIC_IDLE    = 4'd0,
          IIC_START   = 4'd1,	
          IIC_RX_CS   = 4'd2, // 接收片选地址
          IIC_ACK1    = 4'd3,	
          IIC_RX_ADDR = 4'd4,	// 接收片内地址
          IIC_ACK2    = 4'd5,
          IIC_RX_DATA = 4'd6,	// 接收数据
          IIC_ACK3    = 4'd7,
          IIC_TX_DATA = 4'd8; // 发送数据
          
assign SDA = (out_flag == 1'b1) ? sda_out : 1'bz;

/*************************** 初始化 ***************************/
initial begin
	cs_addr <= 7'b0;
	rw_addr <= 8'b0;
	memory <= 24'b0;
	state <= IIC_IDLE;
	tran_data <= 8'b0000_0000;

	out_flag <= 1'b0; // SDA默认为输入模式
	sda_out <= 1'b0;
	sda_outbuf <= 8'b0;
	sda_inbuf <= 8'b0;
end

/******************** 捕获到在空闲状态使能采样 *********************/
always @(posedge en_sample) begin
	if (state == IIC_IDLE)
		tran_data <= 8'b1010_1010; //这里不考虑AD芯片如何实现数据转化，直接设置的
	else
		tran_data <= 8'b0000_0000; 
end


/******************** 捕获主机的开始/停止信号 *********************/
/*检测到开始信号*/
always @(negedge SDA) begin
    if (SCL) begin
        $display("   EEPROM said: Time=%d, get iic-start.", $time);
        state <= IIC_START;
    end
end

/*检测到停止信号*/
always @(posedge SDA) begin
    if (SCL) begin
        $display("   EEPROM said: Time=%d, get iic-stop.", $time);
        state <= IIC_IDLE;
    end
end

/************************* IIC通信过程 *************************/
always @(state) begin
	$display("   EEPROM said: Time=%d, state=%d", $time, state);
	case(state)

		/*EEPROM接收开始信号*/
		IIC_START: begin
			state <= IIC_RX_CS;        
		end
		
		/*EEPROM接收片选地址*/
		IIC_RX_CS: begin
			shift_in(sda_inbuf); // task: 将SDA接收的字节保存在指定的寄存器中
			{cs_addr, isread} = sda_inbuf;
			if (cs_addr != CS_ADDR) begin //判断片选地址是否匹配
				$display("   EEPROM said: Time=%d, cs_addr(%h) didn't match.", $time, cs_addr);
				state <= IIC_IDLE;
			end
			else
				state <= IIC_ACK1;
		end
		
		/*EEPROM发送应答*/
		IIC_ACK1: begin
			ack_respond; // task: 发送应答
			state <= IIC_RX_ADDR;
		end
		
		/*EEPROM接收片内地址*/
		IIC_RX_ADDR: begin
			shift_in(rw_addr); // task: 将SDA接收的字节保存在指定的寄存器中
			state <= IIC_ACK2;
		end
		
		/*EEPROM发送应答*/
		IIC_ACK2: begin
			ack_respond; // task: 发送应答
			if(isread) begin // 判断读写
				 state <= IIC_TX_DATA;
			end
			else begin
				 state <= IIC_RX_DATA;
			end
		end
		
		/*EEPROM接收数据*/
		IIC_RX_DATA: begin
			shift_in(sda_inbuf); // task: 将SDA接收的字节保存在指定的寄存器中
			write_to_memory(rw_addr, sda_inbuf); // task: 向memory指定地址写入数据
			state <= IIC_ACK3;
		end
		
		/*EEPROM发送数据*/
		IIC_TX_DATA: begin
			read_from_memory(rw_addr, sda_outbuf); // task: 读取memory指定地址的数据
			shift_out; // task: SDA发送输出缓存的字节
			state <= IIC_ACK3;
		end
		
		/*EEPROM等待/发送应答*/
		IIC_ACK3: begin
			if (isread) begin
				ack_wait; // task: 等待主机响应
			end
			else begin
				ack_respond; // task: 发送应答
				
				@(negedge SCL); // 这里得设置为输入模式，才可以捕获停止信号
				# `PERIOD_QUARTER;
				out_flag = 1'b0;
			end
			state <= IIC_IDLE;
		end
		
		default:
			state <= IIC_IDLE;
		
	endcase
end

/************************* task定义 ***************************/

//----------- EEPROM接收字节，保存在指定寄存器 --------------//
task shift_in;
output[7:0] inbuf;
begin
	 $display("   EEPROM said: Time=%d, processing shift_in.", $time);
    // 设置SDA输入模式
    @(negedge SCL) begin
        # `PERIOD_QUARTER
        out_flag = 1'b0;
    end

    for(i = 4'd8; i >= 4'd1; i = i - 1) begin
        @(posedge SCL); // 每次SCL上升沿读取
        inbuf[i-1] = SDA;
    end
	 $display("   EEPROM said: Time=%d, finishing shift_in.", $time);
end
endtask

//----------- EEPROM发送输出缓存的字节 --------------//
task shift_out;
begin
	 $display("   EEPROM said: Time=%d, processing shift_out.", $time);
    for(i = 4'd8; i >= 1; i = i - 1) begin
        @(negedge SCL);
        # `PERIOD_QUARTER;
        if(out_flag == 1'b0) out_flag = 1'b1; // 设置为输出模式
        sda_out = sda_outbuf[i-1];
    end
	 $display("   EEPROM said: Time=%d, finishing shift_out.", $time);
end
endtask

//----------- 		EEPROM发送应答 	--------------//
// 注意: 使用此任务后SDA被设置为输出模式, 需要手动设置才能接受数据
task ack_respond;
begin
	 $display("   EEPROM said: Time=%d, processing ack_respond.", $time);
    @(negedge SCL);
	 # `PERIOD_QUARTER;
	 sda_out = 1'b0; // 应答
    out_flag = 1'b1; // 设置SDA输出模式
	 $display("   EEPROM said: Time=%d, finishing ack_respond.", $time);
end
endtask

//----------- 	EEPROM等待主机应答 	--------------//
task ack_wait;
begin
	 $display("   EEPROM said: Time=%d, processing ack_wait.", $time);
    @(negedge SCL);
    # `PERIOD_QUARTER
    out_flag = 1'b0; // 设置SDA输入模式

    @(posedge SCL) sda_inbuf[7] = SDA; // 判断主机是否应答
    if (SDA == 1'b0)
        $display("   EEPROM said: Get respond.");
    else
        $display("   EEPROM said: No respond.");
	 $display("   EEPROM said: Time=%d, finishing ack_wait.", $time); 
end
endtask

//----------- 在memory指定的地址上写数据 --------------//
task write_to_memory;
input[7:0] addr;
input[7:0] data;
case(addr)
    8'h48: memory[7:0] = data;
    8'h49: memory[15:8] = data;
    8'h4A: memory[23:16] = data;
    default: memory[7:0] = data;
endcase
endtask

//----------- 读取memory指定的地址上的数据 --------------//
task read_from_memory;
input[7:0] addr;
output[7:0] data;
case(addr)
    8'h48: data = memory[7:0];
    8'h49: data = memory[15:8];
    8'h4A: data = memory[23:16];
    default: data = memory[7:0];
endcase
endtask

endmodule
