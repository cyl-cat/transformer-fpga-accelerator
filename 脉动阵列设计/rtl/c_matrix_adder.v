module c_matrix_adder #(
    parameter PE_SIZE    = 8,
    parameter RAM_DATA_WIDTH = 64,
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 5,
    parameter PREC_WIDTH = 4
)(
    input                               clk,
    input                               rst_n,
    input      [DATA_WIDTH*PE_SIZE-1:0] PE_data,
    input      [DATA_WIDTH*PE_SIZE-1:0] RAM_C_data,
    input                               done_systolic,
    input                               done_fifoC,
    input                               done_transfer,
    input      [PREC_WIDTH-1:0]         precision_mode,
    output reg [RAM_DATA_WIDTH*PE_SIZE-1:0]wr_data,
    output reg                          rd_en,
    output reg                          wr_en,
    output reg [ADDR_WIDTH-1:0]         wr_addr,
    output reg [7:0]                    wr_strb, 
    output reg                          done//计算结束信号，用于通知AXI_MASTER模块
);

    localparam IDLE    = 0;
    localparam CAL     = 1;
    localparam DONE    = 2;
    localparam PENDING = 3;

    localparam DELAY_INT = 2;//寄存器级数
    localparam DELAY_FP  = 5;

    localparam INT4     = 4'd0;
    localparam INT8     = 4'd1;
    localparam INT4_32  = 4'd2;
    localparam INT8_32  = 4'd3;
    localparam FP16     = 4'd4;
    localparam BF16     = 4'd5;

    reg  [1:0]                      curr_state;
    reg  [1:0]                      next_state;

    reg  [5:0]                      cnt;//计数输入的数据
    reg                             first_to_CAL;
    reg  [DATA_WIDTH*PE_SIZE*2-1:0] i_data;
    wire [  DATA_WIDTH*PE_SIZE-1:0] o_data;

    reg                             done_systolic_reg;
    reg                             done_fifoC_reg;
    reg                             done_transfer_reg;
    wire                            finish;

    reg [PREC_WIDTH-1:0]            precision_mode_reg;
    reg [1:0] byte_select_cnt;

    always @(posedge clk) begin
        precision_mode_reg <= precision_mode;
    end

    wire [8:0] mode_onehot = 1 << precision_mode_reg;

    assign int_wire = |{mode_onehot[INT4],mode_onehot[INT8],mode_onehot[INT4_32],mode_onehot[INT8_32]};//计算类型为int
    assign finish = ((cnt==32+DELAY_INT+1 && int_wire)||(cnt==32+DELAY_FP+1 && !int_wire))?1:0;
    //32为PE每行最终算出的结果数量,结束时刻为数据输入延时加上计算延时

    integer i;
    always @(*) begin
        for (i=0;i<PE_SIZE;i=i+1) begin
            i_data[i*DATA_WIDTH*2 +: DATA_WIDTH*2] = {PE_data[i*DATA_WIDTH +: DATA_WIDTH],RAM_C_data[i*DATA_WIDTH +: DATA_WIDTH]};
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n||curr_state==CAL)begin
            done_systolic_reg <= 0;
        end else if(done_systolic==1)begin
            done_systolic_reg <= 1;
        end else begin
            done_systolic_reg <= done_systolic_reg;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n||curr_state==CAL)begin
            done_fifoC_reg <= 0;
        end else if(done_fifoC==1)begin
            done_fifoC_reg <= 1;
        end else begin
            done_fifoC_reg <= done_fifoC_reg;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            curr_state <= IDLE;
        end else begin
            curr_state <= next_state;
        end
    end

    always @(*) begin
        case(curr_state)
            IDLE:begin
                if (done_systolic_reg && done_fifoC_reg) begin
                    next_state = CAL;
                end else begin
                    next_state = IDLE;
                end
            end
            CAL: begin
                if (finish)begin
                    next_state = DONE;
                end else begin
                    next_state = CAL;
                end
            end
            DONE: next_state = PENDING; // DONE状态不再使用，直接跳转到PENDING
            PENDING :begin
                if (done_transfer) begin
                    next_state = IDLE;
                end else begin
                    next_state = PENDING;
                end
            end
            default : next_state = IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin
            cnt <= 0;
            byte_select_cnt <= 0;
            rd_en <= 0;
            wr_en <= 0;
            wr_addr <= 0;
            // wr_strb <= 8'h00;  // 初始化字节使能为全0
            done <= 0;
            first_to_CAL <= 1;
        end else begin
            case(next_state)
                IDLE: begin
                    byte_select_cnt <= 0;
                    first_to_CAL <= 1;
                    done <= 0;
                end
                CAL: begin
                    cnt <= cnt + 1;

                    // 控制读使能
                    if (cnt>31) begin
                        rd_en <= 0;
                    end else begin
                        rd_en <= 1;
                    end

                    // 控制写使能和地址生成
                    if ((int_wire && cnt>DELAY_INT) || (!int_wire && cnt>DELAY_FP)) begin
                        wr_en <= 1;
                        
                        // 精度模式判断
                        case(precision_mode_reg)
                            FP16, BF16, INT4: begin  // 16位模式
                                // 每4个周期增加一次地址
                                if (first_to_CAL)begin
                                    byte_select_cnt <= 0;
                                    first_to_CAL <= 0;
                                end
                                else if (byte_select_cnt == 2'b11) begin
                                    wr_addr <= wr_addr + 1;
                                    byte_select_cnt <= 0;
                                end else begin
                                    byte_select_cnt <= byte_select_cnt + 1;
                                end
                            end
                            default: begin  // 32位及其他模式
                                // 每2个周期增加一次地址
                                if (first_to_CAL)begin
                                    byte_select_cnt <= 0;
                                    first_to_CAL <= 0;
                                end
                                else if (byte_select_cnt[0]) begin
                                    wr_addr <= wr_addr + 1;
                                    byte_select_cnt <= 0;
                                end else begin
                                    byte_select_cnt <= byte_select_cnt + 1;
                                end
                                
                                // // 设置32位模式的字节使能
                                // if (byte_select_cnt[0] == 0)
                                //     wr_strb <= 8'h0F;  // 使能[31:0]
                                // else
                                //     wr_strb <= 8'hF0;  // 使能[63:32]
                            end
                        endcase
                        
                    end else begin
                        wr_en <= 0;
                    end
                end
                DONE:begin
                    done <= 1;
                end
                PENDING: begin
                    cnt <= 0;
                    byte_select_cnt <= 0;
                    rd_en <= 0;
                    wr_en <= 0;
                    wr_addr <= 0;
                    done <= 0;
                end
                default: begin
                    cnt <= 0;
                    byte_select_cnt <= 0;
                    rd_en <= 0;
                    wr_en <= 0;
                    wr_addr <= 0;
                    done <= 0;
                end
            endcase 
        end
    end

    always @(*) begin
        case (precision_mode_reg)
            FP16, BF16, INT4: begin
                // 设置16位模式的字节使能
                case(byte_select_cnt)
                    2'b00: wr_strb = 8'h03;  // 使能[15:0]
                    2'b01: wr_strb = 8'h0C;  // 使能[31:16]
                    2'b10: wr_strb = 8'h30;  // 使能[47:32]
                    2'b11: wr_strb = 8'hC0;  // 使能[63:48]
                endcase
            end
            default: begin
                // 设置32位模式的字节使能
                case(byte_select_cnt[0])
                    1'b0: wr_strb = 8'h0F;  // 使能[31:0]
                    1'b1: wr_strb = 8'hF0;  // 使能[63:32]
                endcase
            end
        endcase
    end

    always @(*) begin
        case(wr_strb)
            8'h03,8'h0F:begin
                for(i=0;i<PE_SIZE;i=i+1) begin
                    wr_data[i*RAM_DATA_WIDTH +: RAM_DATA_WIDTH] = {32'b0,o_data[i*DATA_WIDTH +: DATA_WIDTH]};
                end
            end
            8'h0C:begin
                for(i=0;i<PE_SIZE;i=i+1) begin
                    wr_data[i*RAM_DATA_WIDTH +: RAM_DATA_WIDTH] = {32'b0,o_data[i*DATA_WIDTH +: DATA_WIDTH]}<<16;
                end
            end
            8'h30,8'hF0:begin
                for(i=0;i<PE_SIZE;i=i+1) begin
                    wr_data[i*RAM_DATA_WIDTH +: RAM_DATA_WIDTH] = {32'b0,o_data[i*DATA_WIDTH +: DATA_WIDTH]}<<32;
                end
            end
            8'hC0:begin
                for(i=0;i<PE_SIZE;i=i+1) begin
                    wr_data[i*RAM_DATA_WIDTH +: RAM_DATA_WIDTH] = {32'b0,o_data[i*DATA_WIDTH +: DATA_WIDTH]}<<48;
                end
            end
        endcase
    end

    adder_array_8 #(
        .DATA_WIDTH(DATA_WIDTH),
        .PREC_WIDTH(PREC_WIDTH)
    ) adder_array_8_inst (
        .clk            (clk),              
        .precision_mode (precision_mode_reg),
        .num_16         (i_data),//左侧开始，每两个数据相加，结果从输出的最左侧开始排列
        .num_8          (o_data)
    );
endmodule