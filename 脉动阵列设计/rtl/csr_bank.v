module csr_bank #(
    parameter CSR_DATA_WIDTH       = 32 ,
    parameter CSR_ADDR_WIDTH       = 8  ,
    parameter MATRIX_DIM_WIDTH     = 8  ,   // 矩阵维度宽度
    parameter PRECISION_MODE_WIDTH = 4      // 精度模式宽度
)(
    // 时钟和复位
    input  wire                            clk                 ,
    input  wire                            rst_n               ,
    
    // CSR访问接口
    input  wire                            csr_wr_en           ,
    input  wire [      CSR_ADDR_WIDTH-1:0] csr_wr_addr         ,
    input  wire [      CSR_DATA_WIDTH-1:0] csr_wr_data         ,
    input  wire [    CSR_DATA_WIDTH/8-1:0] csr_wr_strb         ,
    input  wire                            csr_rd_en           ,
    input  wire [      CSR_ADDR_WIDTH-1:0] csr_rd_addr         ,
    output reg  [      CSR_DATA_WIDTH-1:0] csr_rd_data         ,

    // AXI数据传输控制
    output wire                            axi_wr_ready        , // AXI写就绪信号

    input  wire                            ram_c_write_ready   , // RAM C写就绪信号
    input  wire                            ram_c_wr_done       , // RAM C写完成信号

    input  wire                            ram_b_read_ready    , // RAM B读就绪信号
    input  wire                            ram_d_write_ready   , // RAM D写就绪信号
    input  wire                            compute_done        , // 计算完成信号

    input  wire                            ram_d_read_ready    ,
    input  wire                            transfer_done       ,
    
    // 配置输出
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_m1           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_n1           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_k1           ,
    output wire [PRECISION_MODE_WIDTH-1:0] precision_mode1     ,
    output wire                            sparse_en1          ,

    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_m2           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_n2           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_k2           ,
    output wire [PRECISION_MODE_WIDTH-1:0] precision_mode2     ,
    output wire                            sparse_en2          ,

    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_m3           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_n3           ,
    output wire [    MATRIX_DIM_WIDTH-1:0] matrix_k3           ,
    output wire [PRECISION_MODE_WIDTH-1:0] precision_mode3      
);
    
    // CSR地址定义
    localparam CSR_ADDR_CTRL           = 8'h00;    // 控制寄存器
    localparam CSR_ADDR_STATUS         = 8'h04;    // 状态寄存器
    localparam CSR_ADDR_CONFIG         = 8'h08;    // 配置寄存器 (合并矩阵维度和精度模式)

    // 控制寄存器位定义
    localparam TPU_ENABLE_BIT          = 0;        // TPU使能位
    localparam TPU_SPARSE_ENABLE_BIT   = 1;        // TPU稀疏使能位

    // 状态寄存器位定义
    localparam TPU_READY_BIT           = 0;        // TPU就绪标志
    localparam TPU_LOAD_BUSY_BIT       = 1;        // TPU加载忙碌标志
    localparam TPU_COMPUTE_BUSY_BIT    = 2;        // TPU计算忙碌标志
    localparam TPU_STORE_BUSY_BIT      = 3;        // TPU存储忙碌标志
    localparam TPU_DONE_BIT            = 4;        // TPU计算完成标志

    // 精度模式定义
    localparam PM_INT4_ALL    = 4'd0; // ABC 矩阵均为 INT4
    localparam PM_INT8_ALL    = 4'd1; // ABC 矩阵均为 INT8
    localparam PM_INT4_INT32  = 4'd2; // AB 为 INT4，C 为 INT32
    localparam PM_INT8_INT32  = 4'd3; // AB 为 INT8，C 为 INT32
    localparam PM_FP16_ALL    = 4'd4; // ABC 矩阵均为 FP16
    localparam PM_BF16_ALL    = 4'd5; // ABC 矩阵均为 BF16
    localparam PM_FP32_ALL    = 4'd6; // ABC 矩阵均为 FP32
    localparam PM_FP16_MIX    = 4'd7; // AB 为 FP16，C 为 FP32
    localparam PM_BF16_MIX    = 4'd8; // AB 为 BF16，C 为 FP32

    // 配置寄存器位定义
    localparam CONFIG_K_POS          = 0;                     // K维度位置
    localparam CONFIG_N_POS          = MATRIX_DIM_WIDTH;      // N维度位置
    localparam CONFIG_M_POS          = MATRIX_DIM_WIDTH * 2;  // M维度位置
    localparam CONFIG_PRECISION_POS  = 24;                    // 精度模式位置

    // 状态机定义
    localparam IDLE            = 3'd0;
    localparam BUSY            = 3'd1;
    localparam DONE            = 3'd2;


    reg [2:0] load_state; // 数据加载状态机
    reg [2:0] compute_state; // 数据传输状态机
    reg [2:0] store_state; // 数据存储状态机

    // CSR寄存器定义
    reg [CSR_DATA_WIDTH-1:0] ctrl_reg;            // 控制寄存器
    reg [CSR_DATA_WIDTH-1:0] status_reg;          // 状态寄存器
    reg [CSR_DATA_WIDTH-1:0] config_reg;          // 配置寄存器

    // 配置寄存器
    reg [MATRIX_DIM_WIDTH-1:0] matrix_m1_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_n1_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_k1_r;
    reg [PRECISION_MODE_WIDTH-1:0] precision_mode1_r;
    reg                        sparse_en1_r;

    reg [MATRIX_DIM_WIDTH-1:0] matrix_m2_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_n2_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_k2_r;
    reg [PRECISION_MODE_WIDTH-1:0] precision_mode2_r;
    reg                        sparse_en2_r;

    reg [MATRIX_DIM_WIDTH-1:0] matrix_m3_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_n3_r;
    reg [MATRIX_DIM_WIDTH-1:0] matrix_k3_r;
    reg [PRECISION_MODE_WIDTH-1:0] precision_mode3_r;

    // 配置锁定标志
    reg config_locked;

    // load状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            config_locked     <= 1'b0;
            matrix_m1_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_n1_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_k1_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            precision_mode1_r <= {PRECISION_MODE_WIDTH{1'b0}};
            sparse_en1_r      <= 1'b0;
            load_state        <= IDLE;
        end else begin
            case (load_state)
                IDLE: begin
                    if (ctrl_reg[TPU_ENABLE_BIT] && !config_locked) begin
                        config_locked     <= 1'b1;
                        matrix_m1_r       <= config_reg[CONFIG_M_POS +: MATRIX_DIM_WIDTH];
                        matrix_n1_r       <= config_reg[CONFIG_N_POS +: MATRIX_DIM_WIDTH];
                        matrix_k1_r       <= config_reg[CONFIG_K_POS +: MATRIX_DIM_WIDTH];
                        precision_mode1_r <= config_reg[CONFIG_PRECISION_POS +: PRECISION_MODE_WIDTH];
                        sparse_en1_r      <= ctrl_reg[TPU_SPARSE_ENABLE_BIT];
                        load_state        <= BUSY;
                    end
                end

                BUSY: begin
                    if (ram_c_wr_done) begin
                        config_locked <= 1'b0;
                        load_state <= IDLE;
                    end
                end

                default: begin
                    load_state <= IDLE;
                end
            endcase
        end
    end

    // compute状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_m2_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_n2_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_k2_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            precision_mode2_r <= {PRECISION_MODE_WIDTH{1'b0}};
            sparse_en2_r      <= 1'b0;
            compute_state     <= IDLE;
        end else begin
            case (compute_state)
                IDLE: begin
                    if (ram_b_read_ready && ram_d_write_ready) begin
                        matrix_m2_r       <= matrix_m1_r;
                        matrix_n2_r       <= matrix_n1_r;
                        matrix_k2_r       <= matrix_k1_r;
                        precision_mode2_r <= precision_mode1_r;
                        sparse_en2_r      <= sparse_en1_r;
                        compute_state     <= BUSY;
                    end
                end

                BUSY: begin
                    if (compute_done) begin
                        compute_state <= IDLE;
                    end
                end

                default: begin
                    compute_state <= IDLE;
                end
            endcase
        end
    end

    // store状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            matrix_m3_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_n3_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            matrix_k3_r       <= {MATRIX_DIM_WIDTH{1'b0}};
            precision_mode3_r <= {PRECISION_MODE_WIDTH{1'b0}};
            store_state       <= IDLE;
        end else begin
            case (store_state)
                IDLE: begin
                    if (ram_d_read_ready) begin
                        matrix_m3_r       <= matrix_m2_r;
                        matrix_n3_r       <= matrix_n2_r;
                        matrix_k3_r       <= matrix_k2_r;
                        precision_mode3_r <= precision_mode2_r;
                        store_state       <= BUSY;
                    end
                end

                BUSY: begin
                    if (transfer_done) begin
                        store_state <= IDLE;
                    end
                end

                default: begin
                    store_state <= IDLE;
                end
            endcase
        end
    end

    // CSR写入
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg   <= 32'h00000000;
            // 默认配置: 精度模式=INT8_ALL(1), M=16, N=16, K=16
            config_reg <= {PM_INT8_ALL, 8'h0, 8'h10, 8'h10, 8'h10};
        end else begin
            // 处理CSR写入 - 随时可写
            if (csr_wr_en) begin
                case (csr_wr_addr)
                    CSR_ADDR_CTRL: begin
                        if (csr_wr_strb[0]) ctrl_reg[7:0]   <= csr_wr_data[7:0];
                        if (csr_wr_strb[1]) ctrl_reg[15:8]  <= csr_wr_data[15:8];
                        if (csr_wr_strb[2]) ctrl_reg[23:16] <= csr_wr_data[23:16];
                        if (csr_wr_strb[3]) ctrl_reg[31:24] <= csr_wr_data[31:24];
                    end
                    
                    CSR_ADDR_CONFIG: begin
                        if (csr_wr_strb[0]) config_reg[7:0]   <= csr_wr_data[7:0];
                        if (csr_wr_strb[1]) config_reg[15:8]  <= csr_wr_data[15:8];
                        if (csr_wr_strb[2]) config_reg[23:16] <= csr_wr_data[23:16];
                        if (csr_wr_strb[3]) config_reg[31:24] <= csr_wr_data[31:24];
                    end
                    
                    default: begin
                        // 不操作
                    end
                endcase
            end
            
            // 自动清除使能位
            if (load_state == IDLE && ctrl_reg[TPU_ENABLE_BIT] && !config_locked) begin
                ctrl_reg[TPU_ENABLE_BIT] <= 1'b0;
            end
        end
    end
    
    // 状态寄存器更新
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_reg <= 32'h00000001; // 默认空闲状态
        end else begin

            // 更新就绪标志
            if (ram_c_write_ready && ram_d_write_ready && !config_locked) begin
                status_reg[TPU_READY_BIT] <= 1'b1;
            end else begin
                status_reg[TPU_READY_BIT] <= 1'b0;
            end

            // 更新忙碌标志
            status_reg[TPU_LOAD_BUSY_BIT] <= (load_state == BUSY);
            status_reg[TPU_STORE_BUSY_BIT] <= (store_state == BUSY);
            status_reg[TPU_COMPUTE_BUSY_BIT] <= (compute_state == BUSY);

            // 更新计算完成标志
            if (compute_done) begin
                status_reg[TPU_DONE_BIT] <= 1'b1;
            end else if (csr_rd_en && csr_rd_addr == CSR_ADDR_STATUS) begin
                status_reg[TPU_DONE_BIT] <= 1'b0; // 读取后清除
            end
        end
    end
    
    // CSR读取
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            csr_rd_data     <= 32'h0;
        end else begin
            
            if (csr_rd_en) begin
                
                case (csr_rd_addr)
                    
                    CSR_ADDR_CTRL: begin
                        csr_rd_data <= ctrl_reg;
                    end

                    CSR_ADDR_STATUS: begin
                        csr_rd_data <= status_reg;
                    end

                    CSR_ADDR_CONFIG: begin
                        csr_rd_data <= config_reg;
                    end

                    default: begin
                        csr_rd_data <= 32'h0;
                    end
                endcase
            end
        end
    end


    assign axi_wr_ready = (load_state == BUSY) && ram_c_write_ready && ram_d_write_ready;

    assign matrix_m1 = matrix_m1_r;
    assign matrix_n1 = matrix_n1_r;
    assign matrix_k1 = matrix_k1_r;
    assign precision_mode1 = precision_mode1_r;
    assign sparse_en1 = sparse_en1_r;

    assign matrix_m2 = matrix_m2_r;
    assign matrix_n2 = matrix_n2_r;
    assign matrix_k2 = matrix_k2_r;
    assign precision_mode2 = precision_mode2_r;
    assign sparse_en2 = sparse_en2_r;

    assign matrix_m3 = matrix_m3_r;
    assign matrix_n3 = matrix_n3_r;
    assign matrix_k3 = matrix_k3_r;
    assign precision_mode3 = precision_mode3_r;

endmodule