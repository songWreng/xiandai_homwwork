`timescale 1ns / 1ps
`define PERIOD_QUARTER 625

module EEPROM(SCL, SDA, memory, 
		sa_input, en_sample, tran_data, clk);

input SCL;
inout SDA;
input sa_input;
input en_sample;
input clk;					// ����ʱ�ӣ���EEPROM�ṩ
output[23:0] memory;
output[7:0] tran_data;			

reg[23:0] memory;
reg[ 7:0] tran_data;		// ת��������
//reg en_sample;				// ADоƬ����ʹ��

reg sda_out;            // sda ����Ĵ���  
reg out_flag;           // sda �����־
reg[7:0] sda_outbuf;    // sda �������
reg[7:0] sda_inbuf;     // sda ���뻺��

reg[3:0] state;         // IIC ״̬

reg[6:0] cs_addr;       // ���յ���Ƭѡ��ַ
reg[7:0] rw_addr;       // ���յ��Ĵ���д��Ƭ�ڵ�ַ
reg isread;             // �Ƿ��ȡAD����

reg[8:0] i;             // ѭ������ 

parameter CS_ADDR = 7'b000_0111; // ADоƬ��Ƭѡ��ַ

parameter IIC_IDLE    = 4'd0,
          IIC_START   = 4'd1,	
          IIC_RX_CS   = 4'd2, // ����Ƭѡ��ַ
          IIC_ACK1    = 4'd3,	
          IIC_RX_ADDR = 4'd4,	// ����Ƭ�ڵ�ַ
          IIC_ACK2    = 4'd5,
          IIC_RX_DATA = 4'd6,	// ��������
          IIC_ACK3    = 4'd7,
          IIC_TX_DATA = 4'd8; // ��������
          
assign SDA = (out_flag == 1'b1) ? sda_out : 1'bz;

/*************************** ��ʼ�� ***************************/
initial begin
	cs_addr <= 7'b0;
	rw_addr <= 8'b0;
	memory <= 24'b0;
	state <= IIC_IDLE;
	tran_data <= 8'b0000_0000;

	out_flag <= 1'b0; // SDAĬ��Ϊ����ģʽ
	sda_out <= 1'b0;
	sda_outbuf <= 8'b0;
	sda_inbuf <= 8'b0;
end

/******************** �����ڿ���״̬ʹ�ܲ��� *********************/
always @(posedge en_sample) begin
	if (state == IIC_IDLE)
		tran_data <= 8'b1010_1010; //���ﲻ����ADоƬ���ʵ������ת����ֱ�����õ�
	else
		tran_data <= 8'b0000_0000; 
end


/******************** ���������Ŀ�ʼ/ֹͣ�ź� *********************/
/*��⵽��ʼ�ź�*/
always @(negedge SDA) begin
    if (SCL) begin
        $display("   EEPROM said: Time=%d, get iic-start.", $time);
        state <= IIC_START;
    end
end

/*��⵽ֹͣ�ź�*/
always @(posedge SDA) begin
    if (SCL) begin
        $display("   EEPROM said: Time=%d, get iic-stop.", $time);
        state <= IIC_IDLE;
    end
end

/************************* IICͨ�Ź��� *************************/
always @(state) begin
	$display("   EEPROM said: Time=%d, state=%d", $time, state);
	case(state)

		/*EEPROM���տ�ʼ�ź�*/
		IIC_START: begin
			state <= IIC_RX_CS;        
		end
		
		/*EEPROM����Ƭѡ��ַ*/
		IIC_RX_CS: begin
			shift_in(sda_inbuf); // task: ��SDA���յ��ֽڱ�����ָ���ļĴ�����
			{cs_addr, isread} = sda_inbuf;
			if (cs_addr != CS_ADDR) begin //�ж�Ƭѡ��ַ�Ƿ�ƥ��
				$display("   EEPROM said: Time=%d, cs_addr(%h) didn't match.", $time, cs_addr);
				state <= IIC_IDLE;
			end
			else
				state <= IIC_ACK1;
		end
		
		/*EEPROM����Ӧ��*/
		IIC_ACK1: begin
			ack_respond; // task: ����Ӧ��
			state <= IIC_RX_ADDR;
		end
		
		/*EEPROM����Ƭ�ڵ�ַ*/
		IIC_RX_ADDR: begin
			shift_in(rw_addr); // task: ��SDA���յ��ֽڱ�����ָ���ļĴ�����
			state <= IIC_ACK2;
		end
		
		/*EEPROM����Ӧ��*/
		IIC_ACK2: begin
			ack_respond; // task: ����Ӧ��
			if(isread) begin // �ж϶�д
				 state <= IIC_TX_DATA;
			end
			else begin
				 state <= IIC_RX_DATA;
			end
		end
		
		/*EEPROM��������*/
		IIC_RX_DATA: begin
			shift_in(sda_inbuf); // task: ��SDA���յ��ֽڱ�����ָ���ļĴ�����
			write_to_memory(rw_addr, sda_inbuf); // task: ��memoryָ����ַд������
			state <= IIC_ACK3;
		end
		
		/*EEPROM��������*/
		IIC_TX_DATA: begin
			read_from_memory(rw_addr, sda_outbuf); // task: ��ȡmemoryָ����ַ������
			shift_out; // task: SDA�������������ֽ�
			state <= IIC_ACK3;
		end
		
		/*EEPROM�ȴ�/����Ӧ��*/
		IIC_ACK3: begin
			if (isread) begin
				ack_wait; // task: �ȴ�������Ӧ
			end
			else begin
				ack_respond; // task: ����Ӧ��
				
				@(negedge SCL); // ���������Ϊ����ģʽ���ſ��Բ���ֹͣ�ź�
				# `PERIOD_QUARTER;
				out_flag = 1'b0;
			end
			state <= IIC_IDLE;
		end
		
		default:
			state <= IIC_IDLE;
		
	endcase
end

/************************* task���� ***************************/

//----------- EEPROM�����ֽڣ�������ָ���Ĵ��� --------------//
task shift_in;
output[7:0] inbuf;
begin
	 $display("   EEPROM said: Time=%d, processing shift_in.", $time);
    // ����SDA����ģʽ
    @(negedge SCL) begin
        # `PERIOD_QUARTER
        out_flag = 1'b0;
    end

    for(i = 4'd8; i >= 4'd1; i = i - 1) begin
        @(posedge SCL); // ÿ��SCL�����ض�ȡ
        inbuf[i-1] = SDA;
    end
	 $display("   EEPROM said: Time=%d, finishing shift_in.", $time);
end
endtask

//----------- EEPROM�������������ֽ� --------------//
task shift_out;
begin
	 $display("   EEPROM said: Time=%d, processing shift_out.", $time);
    for(i = 4'd8; i >= 1; i = i - 1) begin
        @(negedge SCL);
        # `PERIOD_QUARTER;
        if(out_flag == 1'b0) out_flag = 1'b1; // ����Ϊ���ģʽ
        sda_out = sda_outbuf[i-1];
    end
	 $display("   EEPROM said: Time=%d, finishing shift_out.", $time);
end
endtask

//----------- 		EEPROM����Ӧ�� 	--------------//
// ע��: ʹ�ô������SDA������Ϊ���ģʽ, ��Ҫ�ֶ����ò��ܽ�������
task ack_respond;
begin
	 $display("   EEPROM said: Time=%d, processing ack_respond.", $time);
    @(negedge SCL);
	 # `PERIOD_QUARTER;
	 sda_out = 1'b0; // Ӧ��
    out_flag = 1'b1; // ����SDA���ģʽ
	 $display("   EEPROM said: Time=%d, finishing ack_respond.", $time);
end
endtask

//----------- 	EEPROM�ȴ�����Ӧ�� 	--------------//
task ack_wait;
begin
	 $display("   EEPROM said: Time=%d, processing ack_wait.", $time);
    @(negedge SCL);
    # `PERIOD_QUARTER
    out_flag = 1'b0; // ����SDA����ģʽ

    @(posedge SCL) sda_inbuf[7] = SDA; // �ж������Ƿ�Ӧ��
    if (SDA == 1'b0)
        $display("   EEPROM said: Get respond.");
    else
        $display("   EEPROM said: No respond.");
	 $display("   EEPROM said: Time=%d, finishing ack_wait.", $time); 
end
endtask

//----------- ��memoryָ���ĵ�ַ��д���� --------------//
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

//----------- ��ȡmemoryָ���ĵ�ַ�ϵ����� --------------//
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
