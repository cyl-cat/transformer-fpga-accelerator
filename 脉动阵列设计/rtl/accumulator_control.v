module accumulator_control#(
    parameter PE_SIZE    = 8,
    parameter PREC_WIDTH = 4
)(
    input                       clk,
    input                       rst_n,
    input      [PREC_WIDTH-1:0] precision_mode,
    input                       data_valid,//数据有效，同周期数据输入累计加器
    input                       empty_fifo1,
    input                       empty_fifo2,
    output reg [1:0]            mode,//mode[1]控制int4，优先级最高，mode[0]表示fifo1和fifo2的选择
    output reg                  wr_en_to_demux,
    output reg                  wr_en_to_fifo,
    output                      rd_en
);
//实现功能
//1. 通过计时产生写使能，将累加结果存入fifo
//2. 适时产生mode信号，使其选通fifo
//3. 通过两个fifo的empty反馈，给出读使能，并在读出数据后计时，适时将读出的数据存入最终的fifo内
localparam IDLE   = 3'd0;
localparam WAIT   = 3'd1;
localparam DELAY  = 3'd2;
localparam STORE  = 3'd3;
localparam FINISH = 3'd4;

localparam DELAY_FP  = 5;//寄存器级数
localparam DELAY_INT = 2;

localparam INT4     = 4'd0;
localparam INT8     = 4'd1;
localparam INT4_32  = 4'd2;
localparam INT8_32  = 4'd3;
localparam FP16     = 4'd4;
localparam BF16     = 4'd5;
localparam FP32     = 4'd6;
localparam FP16_MIX = 4'd7;
localparam BF16_MIX = 4'd8;

reg  [2:0]            curr_state;
reg  [2:0]            next_state;
wire                  start     ;
wire                  match_fp  ;
wire                  match_int ;//fp和int的计算延迟节点
reg                   first_to_store;//第一次进入存储状态

wire                  int_wire;

reg  [6:0]            cnt       ;
reg  [2:0]            cnt_sel   ;//计数存入数据数量，用于切换select
reg  [6:0]            cnt_tree_output;
reg  [6:0]            cnt_valid_input;
reg  [PREC_WIDTH-1:0] precision_mode_reg;
wire [8:0] mode_onehot = 1 << precision_mode_reg;
wire fp32 = mode_onehot[FP32];
wire int4 = mode_onehot[INT4]|| mode_onehot[INT4_32];
assign int_wire = |{mode_onehot[INT4],mode_onehot[INT8],mode_onehot[INT4_32],mode_onehot[INT8_32]};
assign match_fp  = (cnt == ((DELAY_FP<<2)-DELAY_FP-1));//MUX为时序则用如此，组合则-1
assign match_int = (cnt == ((DELAY_INT<<2)-DELAY_INT-1));
assign start  = ((match_fp && !int_wire)||(match_int && int_wire))? 1 : 0;

always @(posedge clk) begin
    precision_mode_reg <= precision_mode;
end

/*-----------------------------实现功能1,2-----------------------------------*/
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        curr_state <= 0;
    end else begin
        curr_state <= next_state;
    end
end

always @* begin
    case (curr_state)
        IDLE: begin
            if (data_valid!=0) begin
                next_state = DELAY;
            end else begin
                next_state = IDLE;
            end
        end
        WAIT:begin//等待下一组有效数据输入
            if (data_valid)begin
                next_state = DELAY;
            end else begin
                next_state = WAIT;
            end
        end
        DELAY: begin//数据输入后等待计算延时
            if (start)begin
                next_state = STORE;
            end else begin
                next_state = DELAY;
            end
        end
        STORE: begin//存储计算结果，给出写使能
            if ((cnt_tree_output==64 && !int4)||(cnt_tree_output==32 && int4))begin//写出固定的64个数据结束
                next_state = FINISH;
            end else if (cnt_tree_output == cnt_valid_input)begin
                next_state = WAIT;
            end else begin
                next_state = STORE;
            end
        end
        FINISH: next_state = IDLE;
    endcase
end

always @(posedge clk) begin
    if (mode_onehot[INT4]||mode_onehot[INT4_32]) begin
        mode[1] <= 1;
    end else begin
        mode[1] <= 0;
    end
    case (next_state)
        IDLE: begin//清零数据
            cnt <= 0;
            first_to_store <= 1;
            cnt_sel <= 0;
            cnt_tree_output <= 0;
            mode <= 0;
            cnt_valid_input <= 0;
            wr_en_to_demux <= 0; 
        end
        WAIT:begin
            cnt <= 0;
            wr_en_to_demux <= 0;
            first_to_store <= 1;
        end
        DELAY:begin
            cnt <= cnt + 1;

            if (data_valid) begin//计数输入的有效数据个数
                cnt_valid_input <= cnt_valid_input + 1;
            end
        end
        STORE: begin
            wr_en_to_demux <= 1;
            cnt_tree_output <= cnt_tree_output + 1;
            
            if (first_to_store) begin
                cnt_sel <= 0;
                
                first_to_store <= 0;
            end else begin
                cnt_sel <= cnt_sel + 1;
                
            end

            if (data_valid) begin
                cnt_valid_input <= cnt_valid_input + 1;
            end

            if (cnt_sel==7)begin
                mode[0] <= ~mode[0];
            end else begin
                mode[0] <= mode[0];
            end
        end
        FINISH: begin
            cnt_valid_input <= 0;
            wr_en_to_demux <= 0; 
        end    
    endcase
end

/*-----------------------------实现功能3-----------------------------------*/
reg [2:0] cnt_delay;
reg [6:0] cnt_rd_num;//读出的数据数
reg [6:0] cnt_wr_num;//写出的数据数
reg       write_state;//写入状态

assign rd_en = (!empty_fifo1 && !empty_fifo2);//非空则开始读数据

always @(posedge clk or negedge rst_n) begin
    if (!rst_n )begin// 当写出数据数量和读出数据数量相同，清零预备下一次连续读出写出
        cnt_rd_num <= 0;
    end else if (rd_en) begin
        cnt_rd_num <= cnt_rd_num + 1;
    end else if (cnt_rd_num==cnt_wr_num)begin
        cnt_rd_num <= 0;
    end
end

always @(posedge clk) begin//计数最后一级加法器的延时
    if (write_state)begin
        cnt_delay <= 0;
    end else if (rd_en) begin//读出数据后计时
        cnt_delay <= cnt_delay + 1;
    end else begin
        cnt_delay <= 0;
    end
end

always @(posedge clk or negedge rst_n) begin//写状态下写使能持续拉高，直到写入8个数据
    if (!rst_n || cnt_wr_num==cnt_rd_num-1) begin
        wr_en_to_fifo <= 0;
    end else if (write_state)begin
        wr_en_to_fifo <= 1;
    end else begin
        wr_en_to_fifo <= wr_en_to_fifo;
    end
end

always @(posedge clk ) begin//写入数据计数，计数到一定数量，write_state拉低则清零
    if (wr_en_to_fifo) begin
        cnt_wr_num <= cnt_wr_num + 1;
    end else begin
        cnt_wr_num <= 0;
    end
end

always @(posedge clk or negedge rst_n) begin//计算延时到达提前一拍进入写状态
    if (!rst_n) begin
        write_state <= 0;
    end else if ((cnt_delay==DELAY_INT-1&int_wire) | (cnt_delay==DELAY_FP-1&!int_wire)) begin
        write_state <= 1;
    end else if (cnt_wr_num==cnt_rd_num-1)begin
        write_state <= 0;
    end
end

endmodule