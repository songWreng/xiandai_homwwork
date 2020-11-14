`timescale 1ns / 1ps
`define PERIOD_QUARTER 625

module EEPROM_WR(clk, en_write, input_data, cs_addr, rw_addr, SCL, SDA,
					  dclk, tran_data, amp_data);

input 		clk;
input 		en_write;
input[7:0] 	input_data;	// �����ֽ�
input[7:0]	cs_addr;		// Ƭѡ��ַ
input[7:0]	rw_addr;		// �������Ƭ�ڵ�ַ
output 		SCL;
inout 		SDA;
output 		dclk;			// ʱ�ӷ�Ƶ1
input[7:0]	tran_data;	// ����ADоƬת��������
output[11:0] amp_data;	// �Ŵ�12�������ݣ�8λ���Ŵ�12����Ҫ12λ���洢

reg 			SCL;
reg 			out_flag;	// SDA��������Ŀ����ź�
reg 			sda_out;		// SDA����Ĵ���
reg[7:0] 	sda_outbuf;	// SDA���������
reg[7:0] 	sda_inbuf;	// SDA�����뻺��

reg			dclk;
reg[11:0]	amp_data;

reg[3:0] 	state;		// IIC״̬
reg[7:0] 	psc_cnt;		// SCL��Ƶ������
reg[3:0]		psc_clk_cnt;// dclk��Ƶϵ��	
reg[3:0]		i;				// ѭ������

parameter IIC_IDLE  		= 4'd0,
			 IIC_START 		= 4'd1,	
			 IIC_TX_CS 		= 4'd2,  // ����Ƭѡ��ַ
			 IIC_ACK1  		= 4'd3,	
		    IIC_TX_ADDR	= 4'd4,	// ����Ƭ�ڵ�ַ
			 IIC_ACK2  		= 4'd5,
			 IIC_TX_DATA	= 4'd6,	// ��������
			 IIC_ACK3		= 4'd7,
			 IIC_STOP  		= 4'd8;

assign SDA = (out_flag ? sda_out : 1'bz);

/*************************** ��ʼ�� ***************************/
initial begin
	SCL 			<= 0;
	sda_out 		<= 1;
	out_flag 	<= 1'd1; // ����Ϊ���ģʽ
	sda_outbuf	<= 8'd0;
	sda_inbuf  	<= 8'd0;
	psc_cnt 		<= 8'd0;
	state			<= IIC_IDLE;
	i				<= 4'd0;
	dclk			<= 0;
	amp_data 	<= 8'd0;
	psc_clk_cnt	<= 4'd0;
end


/************************* ��Ƶ�õ�SCL *************************/
// clkƵ��Ϊ10MHz, SCLҪ��Ƶ��400kHz, ��Ƶϵ��10M/400k=25, ��25��clk��������1��SCL����;
// SCL����Ϊ2.5us=2500ns, 1/4����Ϊ625ns;
always @(posedge clk) begin
	psc_cnt = psc_cnt + 1;
	if (psc_cnt == 25) begin
		SCL = ~SCL;
		psc_cnt = 0;
	end
	if (psc_cnt == 12) begin
		// 25��ż���������м��clk����(��13��)���½���ͻ��
		@(negedge clk) SCL = ~SCL;
	end
end

// ��Ƶ��EEPROM�ṩ����ʱ�ӣ������źŵ����Ƶ��Ϊ1MHz�����Բ���Ƶ�ʲ�С��2MHz��
// ʵ�ʲ���Ƶ��ȡ���Ƶ��2.5������, ����ȡ dclk = 2.5MHz
always @(posedge clk) begin
	psc_clk_cnt = psc_clk_cnt + 1;
	if (psc_clk_cnt == 4) begin
		dclk = ~dclk;
		psc_clk_cnt = 0;
	end
end

/************************* ����Ŵ����� *************************/
always @(tran_data) begin
	if (state == IIC_IDLE)
		amp_data <= ({4'b0000, tran_data} << 2) + ({4'b0000, tran_data} << 3);
	else
		amp_data <= 12'd0;
end

/************************* �ȴ�дʹ���ź� *************************/
always @(posedge en_write) begin
	$display("EEPROM_WR said: en_write now");
	if (state == IIC_IDLE)
		state <= IIC_START;
end

/************************* IICͨ�Ź��� *************************/
// ʵ�⣺state ����ʹ�÷�������ֵ�����ܴ��� @(state)
always @(state) begin
	$display("EEPROM_WR said: Time=%d, state=%d", $time, state);
	case(state)
		/*��EEPROM���Ϳ�ʼ�ź�*/
		IIC_START: begin
			@(negedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 1;
			@(posedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 0;
			state <= IIC_TX_CS;
		end
		
		/*��EEPROM����Ƭѡ��ַ*/
		IIC_TX_CS: begin
			sda_outbuf = cs_addr; // Ƭѡ��ַ�����������
			SDA_TX_Byte; // task: ��ӻ��������������ֽ�
			state <= IIC_ACK1; 
		end
		
		/*�ȴ�EEPROM��Ӧ*/
		IIC_ACK1: begin
			SDA_Wait_ACK; // task: �ȴ��ӻ���Ӧ
			state <= IIC_TX_ADDR; 
		end
		
		/*��EEPROM����Ƭ�ڵ�ַ*/
		IIC_TX_ADDR: begin
			sda_outbuf = rw_addr; // Ƭ�ڵ�ַ�����������
			SDA_TX_Byte; // task: ��ӻ��������������ֽ�
			state <= IIC_ACK2;
		end
		
		/*�ȴ�EEPROM��Ӧ*/
		IIC_ACK2: begin
			SDA_Wait_ACK; // task: �ȴ��ӻ���Ӧ
			state <= IIC_TX_DATA;
		end
		
		/*��EEPROM��������*/
		IIC_TX_DATA: begin
			sda_outbuf = input_data; // ��д���ݷ����������
			SDA_TX_Byte; // task: ��ӻ��������������ֽ�
			state <= IIC_ACK3;
		end
		
		/*�ȴ�EEPROM��Ӧ*/
		IIC_ACK3: begin
			SDA_Wait_ACK; // task: �ȴ��ӻ���Ӧ
			sda_out = 0; // ��������SDA���0, ����ֹͣ�źŲ���һ��������
			state <= IIC_STOP;
		end
		
		/*��EEPROM����ֹͣ�ź�*/
		IIC_STOP: begin
			@(negedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 0;
			out_flag = 1; // SDA��������Ϊ���ģʽ
			@(posedge SCL);
			#`PERIOD_QUARTER;
			sda_out = 1; // ��������SDA���1, ���ڿ�ʼ�źŲ���һ���½���
			state <= IIC_IDLE;
		end
		
		default:
			state <= IIC_IDLE;
	endcase
	
end

/************************* task���� ***************************/

//----------- ������ӻ�����һ���ֽ� --------------//
task SDA_TX_Byte;
begin
$display("EEPROM_WR said: time=%d, processing SDA_TX_Byte", $time);
for(i = 8; i >= 1; i = i - 1) begin // @note: for(i=7;i>=0;i=i-1) ����ѭ��
	@(negedge SCL);
	#`PERIOD_QUARTER;
	if (out_flag == 1'b0) out_flag = 1'b1; // ���SDAΪ����ģʽ��������ΪSDAΪ���ģʽ
	sda_out = sda_outbuf[i - 1];
end
$display("EEPROM_WR said: time=%d, finish SDA_TX_Byte", $time);
end
endtask

//------------- �����ȴ��ӻ���Ӧ ----------------//
// ע�⣺ÿ�ε��ô������, SDA������Ϊ����ģʽ!
task SDA_Wait_ACK;
begin
	$display("EEPROM_WR said: time=%d, processing SDA_Wait_ACK.", $time);
	@(negedge SCL);
	#`PERIOD_QUARTER;
	out_flag = 0; // SDA����Ϊ����ģʽ
	
	// �жϴӻ��Ƿ�����Ӧ
	@(posedge SCL) sda_inbuf[7] = SDA;
	if (sda_inbuf[7] == 1'b0)
		$display("EEPROM_WR said: Get ACK!");
	else 
		$display("EEPROM_WR said: No ACK!");
	
	$display("EEPROM_WR said: time=%d, finish SDA_Wait_ACK.", $time);
end
endtask

endmodule
