module tpu_top #(
    parameter AXI_ID_WIDTH         = 4             ,
    parameter AXI_ADDR_WIDTH       = 32            ,
    parameter AXI_DATA_WIDTH       = 64            ,
    parameter AXI_AWUSER_WIDTH     = 1             ,
    parameter AXI_WUSER_WIDTH      = 1             ,
    parameter AXI_BUSER_WIDTH      = 1             ,

    parameter CSR_DATA_WIDTH       = 32            ,
    parameter CSR_ADDR_WIDTH       = 8             ,

    parameter PE_SIZE              = 8             ,    // PE数量/阵列大小
    parameter MATRIX_DIM_WIDTH     = 8             ,    // 矩阵维度宽度
    parameter PRECISION_MODE_WIDTH = 4             ,    // 精度模式宽度
    parameter RAM_ADDR_WIDTH       = 5             ,    // RAM地址宽度
    parameter RAM_C_ADDR_WIDTH     = 4             ,    // RAM地址宽度
    parameter RAM_D_ADDR_WIDTH     = 4             ,    // RAM地址宽度
    parameter RAM_DATA_WIDTH       = 64            ,    // RAM数据宽度
    parameter FIFO_DATA_WIDTH      = 32            ,    // FIFO数据宽度
    parameter FIFO_DEPTH           = 32            ,    // FIFO深度
    parameter MATRIX_A_BASE_ADDR   = 32'h0000_0000 ,    // 矩阵A的基地址
    parameter MATRIX_B_BASE_ADDR   = 32'h0000_4000 ,    // 矩阵B的基地址
    parameter MATRIX_C_BASE_ADDR   = 32'h0000_8000 ,    // 矩阵C的基地址
    parameter MATRIX_D_BASE_ADDR   = 32'h0000_C000 ,

    parameter DATA_WIDTH           = 32             

) (
    /******************** AXI-Slave 接口 ********************/
    // Global signals
    input wire                               clk              ,
    input wire                               rst_n            ,

    // Write address channel
    input  wire [        AXI_ID_WIDTH-1:0]   s_axi_awid       ,
    input  wire [      AXI_ADDR_WIDTH-1:0]   s_axi_awaddr     ,
    input  wire [                     7:0]   s_axi_awlen      ,
    input  wire [                     2:0]   s_axi_awsize     ,
    input  wire [                     1:0]   s_axi_awburst    ,
    input  wire                              s_axi_awlock     ,
    input  wire [                     3:0]   s_axi_awcache    ,
    input  wire [                     2:0]   s_axi_awprot     ,
    input  wire [                     3:0]   s_axi_awqos      ,
    input  wire [                     3:0]   s_axi_awregion   ,
    input  wire [    AXI_AWUSER_WIDTH-1:0]   s_axi_awuser     ,
    input  wire                              s_axi_awvalid    ,
    output wire                              s_axi_awready    ,

    // Write data channel
    input  wire [        AXI_DATA_WIDTH-1:0] s_axi_wdata      ,
    input  wire [(    AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb      ,
    input  wire                              s_axi_wlast      ,
    input  wire [       AXI_WUSER_WIDTH-1:0] s_axi_wuser      ,
    input  wire                              s_axi_wvalid     ,
    output wire                              s_axi_wready     ,

    // Write response channel
    output wire [       AXI_ID_WIDTH-1:0]    s_axi_bid        ,
    output wire [                    1:0]    s_axi_bresp      ,
    output wire [    AXI_BUSER_WIDTH-1:0]    s_axi_buser      ,
    output wire                              s_axi_bvalid     ,
    input  wire                              s_axi_bready     ,

    /******************** AXI-Lite-Slave 接口 ********************/
    // 写地址通道
    input  wire [                 8-1:0]     s_axil_awaddr    ,
    input  wire                              s_axil_awvalid   ,
    output wire                              s_axil_awready   ,
    
    // 写数据通道
    input  wire [    CSR_DATA_WIDTH-1:0]     s_axil_wdata     ,
    input  wire [    CSR_DATA_WIDTH/8-1:0]   s_axil_wstrb     ,
    input  wire                              s_axil_wvalid    ,
    output wire                              s_axil_wready    ,
    
    // 写响应通道
    output wire [1:0]                        s_axil_bresp     ,
    output wire                              s_axil_bvalid    ,
    input  wire                              s_axil_bready    ,
    
    // 读地址通道
    input  wire [                 8-1:0]     s_axil_araddr    ,
    input  wire                              s_axil_arvalid   ,
    output wire                              s_axil_arready   ,
    
    // 读数据通道
    output wire [    CSR_DATA_WIDTH-1:0]     s_axil_rdata     ,
    output wire [1:0]                        s_axil_rresp     ,
    output wire                              s_axil_rvalid    ,
    input  wire                              s_axil_rready    ,

    /******************** AXI-Master接口 ********************/
    output wire [          AXI_ID_WIDTH-1:0] m_axi_awid       ,
    output wire [        AXI_ADDR_WIDTH-1:0] m_axi_awaddr     ,
    output wire [                       7:0] m_axi_awlen      ,
    output wire [                       2:0] m_axi_awsize     ,
    output wire [                       1:0] m_axi_awburst    ,
    output wire                              m_axi_awlock     ,
    output wire [                       3:0] m_axi_awcache    ,
    output wire [                       2:0] m_axi_awprot     ,
    output wire [                       3:0] m_axi_awqos      ,
    output wire [                       3:0] m_axi_awregion   ,
    output wire [      AXI_AWUSER_WIDTH-1:0] m_axi_awuser     ,
    output wire                              m_axi_awvalid    ,
    input  wire                              m_axi_awready    ,

    // AXI写数据通道
    output wire [        AXI_DATA_WIDTH-1:0] m_axi_wdata      ,
    output wire [    (AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb      ,
    output wire                              m_axi_wlast      ,
    output wire [       AXI_WUSER_WIDTH-1:0] m_axi_wuser      ,
    output wire                              m_axi_wvalid     ,
    input  wire                              m_axi_wready     ,

    // AXI写响应通道
    input  wire [          AXI_ID_WIDTH-1:0] m_axi_bid        ,
    input  wire [                       1:0] m_axi_bresp      ,
    input  wire [       AXI_BUSER_WIDTH-1:0] m_axi_buser      ,
    input  wire                              m_axi_bvalid     ,
    output wire                              m_axi_bready      

);

    // AXI RAM 写接口
    wire                                  ram_wr_en          ;
    wire [            AXI_ADDR_WIDTH-1:0] ram_wr_addr        ;
    wire [            AXI_DATA_WIDTH-1:0] ram_wr_data        ;
    wire [        (AXI_DATA_WIDTH/8)-1:0] ram_wr_strb        ;
    
    // RAM阵列A写入接口
    wire [                   PE_SIZE-1:0] ram_a_wr_en        ;
    wire [    RAM_ADDR_WIDTH*PE_SIZE-1:0] ram_a_wr_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_a_wr_data      ;
    wire [(RAM_DATA_WIDTH/8)*PE_SIZE-1:0] ram_a_wr_strb      ; // 写选通

    wire                                  a_index_wr_en      ;
    wire [            RAM_ADDR_WIDTH-1:0] a_index_wr_addr    ;
    wire [            RAM_DATA_WIDTH-1:0] a_index_wr_data    ;
    
    // RAM阵列B写入接口
    wire [                   PE_SIZE-1:0] ram_b_wr_en        ;
    wire [    RAM_ADDR_WIDTH*PE_SIZE-1:0] ram_b_wr_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_b_wr_data      ;
    wire [(RAM_DATA_WIDTH/8)*PE_SIZE-1:0] ram_b_wr_strb      ;  // 写选通

    // RAM阵列C写入接口
    wire [                   PE_SIZE-1:0] ram_c_wr_en        ;
    wire [  RAM_C_ADDR_WIDTH*PE_SIZE-1:0] ram_c_wr_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_c_wr_data      ;
    wire [(RAM_DATA_WIDTH/8)*PE_SIZE-1:0] ram_c_wr_strb      ;  // 写选通
    
    // A矩阵RAM阵列读接口
    wire [                   PE_SIZE-1:0] ram_a_rd_en        ;
    wire [    RAM_ADDR_WIDTH*PE_SIZE-1:0] ram_a_rd_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_a_rd_data      ;
    
    // A矩阵阵列写接口
    wire [                   PE_SIZE-1:0] systolic_a_wr_en   ;
    wire [        DATA_WIDTH*PE_SIZE-1:0] systolic_a_wr_data ;

    // B矩阵RAM阵列读接口
    wire [                   PE_SIZE-1:0] ram_b_rd_en        ;
    wire [    RAM_ADDR_WIDTH*PE_SIZE-1:0] ram_b_rd_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_b_rd_data      ;
    
    // B矩阵阵列写接口
    wire [                   PE_SIZE-1:0] systolic_b_wr_en   ;
    wire [        DATA_WIDTH*PE_SIZE-1:0] systolic_b_wr_data ;

    // C矩阵RAM阵列读接口
    wire [                   PE_SIZE-1:0] ram_c_rd_en        ;
    wire [  RAM_C_ADDR_WIDTH*PE_SIZE-1:0] ram_c_rd_addr      ;
    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_c_rd_data      ;
    
    // C矩阵FIFO阵列写接口
    wire [                   PE_SIZE-1:0] fifo_c_wr_en       ;
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] fifo_c_wr_data     ;
    wire [                   PE_SIZE-1:0] fifo_c_full        ; // FIFO满信号
    wire [                   PE_SIZE-1:0] fifo_c_almost_full ; // FIFO接近满信号

    wire                                  axi_wr_ready       ;

    // CSR访问
    wire                                  csr_wr_en          ;
    wire [            CSR_ADDR_WIDTH-1:0] csr_wr_addr        ;
    wire [            CSR_DATA_WIDTH-1:0] csr_wr_data        ;
    wire [          CSR_DATA_WIDTH/8-1:0] csr_wr_strb        ;
    wire                                  csr_rd_en          ;
    wire [            CSR_ADDR_WIDTH-1:0] csr_rd_addr        ;
    wire [            CSR_DATA_WIDTH-1:0] csr_rd_data        ;

    wire [          MATRIX_DIM_WIDTH-1:0] matrix_m1          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_n1          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_k1          ;
    wire [      PRECISION_MODE_WIDTH-1:0] precision_mode1    ;
    wire                                  sparse_en1         ;

    wire [          MATRIX_DIM_WIDTH-1:0] matrix_m2          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_n2          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_k2          ;
    wire [      PRECISION_MODE_WIDTH-1:0] precision_mode2    ;
    wire                                  sparse_en2         ;

    wire [          MATRIX_DIM_WIDTH-1:0] matrix_m3          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_n3          ;
    wire [          MATRIX_DIM_WIDTH-1:0] matrix_k3          ;
    wire [      PRECISION_MODE_WIDTH-1:0] precision_mode3    ;

    wire                                  ram_a_wr_done      ; // A矩阵写入完成信号
    wire                                  ram_b_wr_done      ; // B矩阵写入完成信号
    wire                                  ram_c_wr_done      ; // C矩阵写入完成信号

    wire                                  ram_a_read_ready   ; // A矩阵读取准备就绪信号
    wire                                  ram_b_read_ready   ; // B矩阵读取准备就绪信号
    wire                                  ram_c_read_ready   ; // C矩阵读取准备就绪信号
    wire                                  ram_d_read_ready   ; // D矩阵读取准备就绪信号

    wire                                  ram_a_write_ready  ; // A矩阵写入准备就绪信号
    wire                                  ram_b_write_ready  ; // B矩阵写入准备就绪信号
    wire                                  ram_c_write_ready  ; // C矩阵写入准备就绪信号
    wire                                  ram_d_write_ready  ; // D矩阵写入准备就绪信号

    wire                                  load_busy          ; // 忙状态指示
    wire                                  load_done          ; // 传输完成指示

    wire                                  rctf_done          ;
    wire                                  rctf_busy          ;

    // A矩阵FIFO阵列读接口
    wire [                   PE_SIZE-1:0] fifo_a_rd_en       ;
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] fifo_a_rd_data     ;
    wire [                   PE_SIZE-1:0] fifo_a_empty       ;
    wire [                   PE_SIZE-1:0] fifo_a_almost_empty;

    // B矩阵FIFO阵列读接口
    wire [                   PE_SIZE-1:0] fifo_b_rd_en       ;
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] fifo_b_rd_data     ;
    wire [                   PE_SIZE-1:0] fifo_b_empty       ;
    wire [                   PE_SIZE-1:0] fifo_b_almost_empty;

    // C矩阵FIFO阵列读接口
    wire [                   PE_SIZE-1:0] fifo_c_rd_en       ;
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] fifo_c_rd_data     ;
    wire [                   PE_SIZE-1:0] fifo_c_empty       ;
    wire [                   PE_SIZE-1:0] fifo_c_almost_empty;

    // 脉动阵列数据接口
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] systolic_a_data    ;
    wire [   FIFO_DATA_WIDTH*PE_SIZE-1:0] systolic_b_data    ;
    
    // 第一个数据和最后一个数据脉冲
    wire                                  first_data         ;
    wire                                  last_data          ;

    wire [     DATA_WIDTH*PE_SIZE*8-1:0]  systolic_to_accu_data ;
    wire [     PE_SIZE-1:0]               systolic_to_accu_sel  ;

    wire [     DATA_WIDTH*PE_SIZE-1:0]    accu_to_fifo_data     ;
    wire [     PE_SIZE-1:0]               accu_to_fifo_wr_en    ;

    wire                                  accu_done             ;
    wire [     DATA_WIDTH*PE_SIZE-1:0]    accu_data             ;

    wire                                  fifo_c_rd_en_single   ;

    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_d_wr_data         ;
    wire [          RAM_DATA_WIDTH/8-1:0] ram_d_wr_strb         ;
    wire                                  ram_d_wr_en           ;
    wire [          RAM_D_ADDR_WIDTH-1:0] ram_d_wr_addr         ;

    wire                                  compute_done          ;

    wire [    RAM_DATA_WIDTH*PE_SIZE-1:0] ram_d_rd_data         ;
    wire [                   PE_SIZE-1:0] ram_d_rd_en           ;
    wire [  RAM_D_ADDR_WIDTH*PE_SIZE-1:0] ram_d_rd_addr         ;

    wire [        DATA_WIDTH*PE_SIZE-1:0] up_all                ;      //8columns input,8bit num
    wire [        DATA_WIDTH*PE_SIZE-1:0] left_all              ;      //8rows input ,8bit num
    wire [        1:0]                    control               ;

    wire                                  transfer_start        ; // 传输开始脉冲
    wire [            AXI_ADDR_WIDTH-1:0] axi_target_addr       ; // AXI目标地址
    wire [                          15:0] transfer_count        ; // 传输数据量
    wire [            AXI_ADDR_WIDTH-1:0] ram_base_addr         ; // RAM基地址
    wire                                  transfer_done         ; // 传输完成信号
    wire [                           1:0] transfer_status       ; // 传输状态

    wire                                  axi_rd_en             ;
    wire [            AXI_ADDR_WIDTH-1:0] axi_rd_addr           ;
    wire [            AXI_DATA_WIDTH-1:0] axi_rd_data           ;
    wire                                  axi_rd_data_vld       ;


    assign control                = {last_data, first_data} ;
    assign left_all               = systolic_a_data         ;
    assign up_all                 = systolic_b_data         ;
    assign fifo_c_rd_en           = {PE_SIZE{fifo_c_rd_en_single}};




    axi4_full_slave #(
        .AXI_ID_WIDTH     (AXI_ID_WIDTH    ) ,
        .AXI_ADDR_WIDTH   (AXI_ADDR_WIDTH  ) ,
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH  ) ,
        .AXI_AWUSER_WIDTH (AXI_AWUSER_WIDTH) ,
        .AXI_WUSER_WIDTH  (AXI_WUSER_WIDTH ) ,
        .AXI_BUSER_WIDTH  (AXI_BUSER_WIDTH )
    ) axi4_full_slave_inst (
        // Global signals
        .s_axi_aclk       (clk),
        .s_axi_aresetn    (rst_n),

        // Write address channel
        .s_axi_awid       (s_axi_awid),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awlen      (s_axi_awlen),
        .s_axi_awsize     (s_axi_awsize),
        .s_axi_awburst    (s_axi_awburst),
        .s_axi_awlock     (s_axi_awlock),
        .s_axi_awcache    (s_axi_awcache),
        .s_axi_awprot     (s_axi_awprot),
        .s_axi_awqos      (s_axi_awqos),
        .s_axi_awregion   (s_axi_awregion),
        .s_axi_awuser     (s_axi_awuser),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),

        // Write data channel
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wlast      (s_axi_wlast),
        .s_axi_wuser      (s_axi_wuser),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),

        // Write response channel
        .s_axi_bid        (s_axi_bid),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_buser      (s_axi_buser),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),

        // RAM interface outputs
        .ram_wr_en        (ram_wr_en),
        .ram_wr_addr      (ram_wr_addr),
        .ram_wr_data      (ram_wr_data),
        .ram_wr_strb      (ram_wr_strb),

        .ram_wr_ready     (axi_wr_ready)
    );

    axi4_lite_slave #(
        .AXI_DATA_WIDTH(CSR_DATA_WIDTH),  // 数据位宽
        .AXI_ADDR_WIDTH(CSR_ADDR_WIDTH)   // 地址位宽，8bit=256字节空间
    ) axi4_lite_slave_inst (
        .s_axil_aclk     (clk),
        .s_axil_aresetn  (rst_n),
        
        // 写地址通道
        .s_axil_awaddr   (s_axil_awaddr),
        .s_axil_awvalid  (s_axil_awvalid),
        .s_axil_awready  (s_axil_awready),
        
        // 写数据通道
        .s_axil_wdata    (s_axil_wdata),
        .s_axil_wstrb    (s_axil_wstrb),
        .s_axil_wvalid   (s_axil_wvalid),
        .s_axil_wready   (s_axil_wready),
        
        // 写响应通道
        .s_axil_bresp    (s_axil_bresp),
        .s_axil_bvalid   (s_axil_bvalid),
        .s_axil_bready   (s_axil_bready),
        
        // 读地址通道
        .s_axil_araddr   (s_axil_araddr),
        .s_axil_arvalid  (s_axil_arvalid),
        .s_axil_arready  (s_axil_arready),
        
        // 读数据通道
        .s_axil_rdata    (s_axil_rdata),
        .s_axil_rresp    (s_axil_rresp),
        .s_axil_rvalid   (s_axil_rvalid),
        .s_axil_rready   (s_axil_rready),
        
        // CSR接口信号
        .csr_wr_en       (csr_wr_en),
        .csr_wr_addr     (csr_wr_addr),
        .csr_wr_data     (csr_wr_data),
        .csr_wr_strb     (csr_wr_strb),
        .csr_rd_en       (csr_rd_en),
        .csr_rd_addr     (csr_rd_addr),
        .csr_rd_data     (csr_rd_data)
    );

    csr_bank #(
        .CSR_DATA_WIDTH (CSR_DATA_WIDTH) ,
        .CSR_ADDR_WIDTH (CSR_ADDR_WIDTH) ,
        .MATRIX_DIM_WIDTH (MATRIX_DIM_WIDTH) ,
        .PRECISION_MODE_WIDTH (PRECISION_MODE_WIDTH)
    ) csr_bank_inst(
        // 时钟和复位
        .clk                 (clk),
        .rst_n               (rst_n),
        
        // CSR访问接口
        .csr_wr_en           (csr_wr_en),
        .csr_wr_addr         (csr_wr_addr),
        .csr_wr_data         (csr_wr_data),
        .csr_wr_strb         (csr_wr_strb),
        .csr_rd_en           (csr_rd_en),
        .csr_rd_addr         (csr_rd_addr),
        .csr_rd_data         (csr_rd_data),
        
        // AXI数据传输控制
        .axi_wr_ready        (axi_wr_ready), // AXI写就绪信号

        .ram_c_write_ready   (ram_c_write_ready), // RAM 写就绪信号
        .ram_c_wr_done       (ram_c_wr_done), // RAM C写完成信号

        .ram_b_read_ready    (ram_b_read_ready), // RAM B读就绪信号
        .ram_d_write_ready   (ram_d_write_ready), // RAM D写就绪信号
        .compute_done        (compute_done), // 计算完成信号

        .ram_d_read_ready    (ram_d_read_ready),
        .transfer_done       (transfer_done),

        // 配置输出
        .matrix_m1           (matrix_m1),
        .matrix_n1           (matrix_n1),
        .matrix_k1           (matrix_k1),
        .precision_mode1     (precision_mode1),
        .sparse_en1          (sparse_en1),

        .matrix_m2           (matrix_m2),
        .matrix_n2           (matrix_n2),
        .matrix_k2           (matrix_k2),
        .precision_mode2     (precision_mode2),
        .sparse_en2          (sparse_en2),

        .matrix_m3           (matrix_m3),
        .matrix_n3           (matrix_n3),
        .matrix_k3           (matrix_k3),
        .precision_mode3     (precision_mode3)
    );

    matrix_mem_mapper #(
        .PE_SIZE              (PE_SIZE),
        .MATRIX_DIM_WIDTH     (MATRIX_DIM_WIDTH),
        .PRECISION_MODE_WIDTH (PRECISION_MODE_WIDTH),
        .AXI_DATA_WIDTH       (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH       (AXI_ADDR_WIDTH),
        .RAM_ADDR_WIDTH       (RAM_ADDR_WIDTH),
        .RAM_C_ADDR_WIDTH     (RAM_C_ADDR_WIDTH),
        .RAM_DATA_WIDTH       (RAM_DATA_WIDTH),
        .MATRIX_A_BASE_ADDR   (MATRIX_A_BASE_ADDR),
        .MATRIX_B_BASE_ADDR   (MATRIX_B_BASE_ADDR),
        .MATRIX_C_BASE_ADDR   (MATRIX_C_BASE_ADDR),
        .MATRIX_D_BASE_ADDR   (MATRIX_D_BASE_ADDR)
    ) matrix_mem_mapper_inst (
        // 时钟和复位
        .clk              (clk),
        .rst_n            (rst_n),
        
        // AXI RAM 写接口
        .ram_wr_en        (ram_wr_en),
        .ram_wr_addr      (ram_wr_addr),
        .ram_wr_data      (ram_wr_data),
        .ram_wr_strb      (ram_wr_strb),
        
        // CSR 寄存器配置
        .matrix_m         (matrix_m1),  
        .matrix_n         (matrix_n1),  
        .matrix_k         (matrix_k1),  
        .precision_mode   (precision_mode1),  // 数据精度模式
        .sparse_en        (sparse_en1),
        
        // RAM阵列A写入接口
        .ram_a_wr_en      (ram_a_wr_en),
        .ram_a_wr_addr    (ram_a_wr_addr),
        .ram_a_wr_data    (ram_a_wr_data),
        .ram_a_wr_strb    (ram_a_wr_strb), // 写选通

        .a_index_wr_en    (a_index_wr_en),
        .a_index_wr_addr  (a_index_wr_addr),
        .a_index_wr_data  (a_index_wr_data),

        // RAM阵列B写入接口
        .ram_b_wr_en      (ram_b_wr_en),
        .ram_b_wr_addr    (ram_b_wr_addr),
        .ram_b_wr_data    (ram_b_wr_data),
        .ram_b_wr_strb    (ram_b_wr_strb),  // 写选通

        // RAM阵列C写入接口
        .ram_c_wr_en      (ram_c_wr_en),
        .ram_c_wr_addr    (ram_c_wr_addr),
        .ram_c_wr_data    (ram_c_wr_data),
        .ram_c_wr_strb    (ram_c_wr_strb),  // 写选通

        // 矩阵写入完成信号
        .ram_a_wr_done    (ram_a_wr_done),  // A矩阵写入完成信号
        .ram_b_wr_done    (ram_b_wr_done),  // B矩阵写入完成信号  
        .ram_c_wr_done    (ram_c_wr_done)   // C矩阵写入完成信号
    );

    ram_array_pingpong #(
        .PE_SIZE        (PE_SIZE),   // PE数量/阵列大小
        .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH (RAM_DATA_WIDTH)    // RAM数据宽度
    ) a_ram_array_pingpong_inst (
        // 全局时钟
        .clk            (clk),
        .rst_n          (rst_n),

        // 缓冲区控制信号
        .write_complete (ram_a_wr_done), 
        .read_complete  (load_done),
        .buffer_select  (),
        .read_ready     (ram_a_read_ready), 
        .write_ready    (),

        // 写接口
        .ram_wr_en      (ram_a_wr_en),
        .ram_wr_addr    (ram_a_wr_addr),
        .ram_wr_data    (ram_a_wr_data),
        .ram_wr_strb    (ram_a_wr_strb),

        // 读接口
        .ram_rd_en      (ram_a_rd_en),
        .ram_rd_addr    (ram_a_rd_addr),
        .ram_rd_data    (ram_a_rd_data)
    );

    ram_array_pingpong #(
        .PE_SIZE        (PE_SIZE),   // PE数量/阵列大小
        .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH (RAM_DATA_WIDTH)    // RAM数据宽度
    ) b_ram_array_pingpong_inst (
        // 全局时钟
        .clk            (clk),
        .rst_n          (rst_n),

        // 缓冲区控制信号
        .write_complete (ram_b_wr_done), 
        .read_complete  (load_done),
        .buffer_select  (),
        .read_ready     (ram_b_read_ready), 
        .write_ready    (),

        // 写接口
        .ram_wr_en      (ram_b_wr_en),
        .ram_wr_addr    (ram_b_wr_addr),
        .ram_wr_data    (ram_b_wr_data),
        .ram_wr_strb    (ram_b_wr_strb),

        // 读接口
        .ram_rd_en      (ram_b_rd_en),
        .ram_rd_addr    (ram_b_rd_addr),
        .ram_rd_data    (ram_b_rd_data)
    );

    ram_array_pingpong #(
        .PE_SIZE        (PE_SIZE),   // PE数量/阵列大小
        .RAM_ADDR_WIDTH (RAM_C_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH (RAM_DATA_WIDTH)    // RAM数据宽度
    ) c_ram_array_pingpong_inst (
        // 全局时钟
        .clk            (clk),
        .rst_n          (rst_n),

        // 缓冲区控制信号
        .write_complete (ram_c_wr_done), 
        .read_complete  (load_done),
        .buffer_select  (),
        .read_ready     (ram_c_read_ready), 
        .write_ready    (ram_c_write_ready),

        // 写接口
        .ram_wr_en      (ram_c_wr_en),
        .ram_wr_addr    (ram_c_wr_addr),
        .ram_wr_data    (ram_c_wr_data),
        .ram_wr_strb    (ram_c_wr_strb),

        // 读接口
        .ram_rd_en      (ram_c_rd_en),
        .ram_rd_addr    (ram_c_rd_addr),
        .ram_rd_data    (ram_c_rd_data)
    );

    data_flow_load #(
        .PE_SIZE              (PE_SIZE),   // PE数量/阵列大小
        .MATRIX_DIM_WIDTH     (MATRIX_DIM_WIDTH),   // 矩阵维度宽度
        .PRECISION_MODE_WIDTH (PRECISION_MODE_WIDTH),   // 精度模式宽度
        .RAM_ADDR_WIDTH       (RAM_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH       (RAM_DATA_WIDTH),   // RAM数据宽度
        .SYS_DATA_WIDTH       (DATA_WIDTH)    
    ) data_flow_load_inst(
        // 时钟和复位
        .clk                (clk) ,
        .rst_n              (rst_n) ,

        // CSR 寄存器配置
        .matrix_m           (matrix_m2) ,
        .matrix_n           (matrix_n2) ,
        .matrix_k           (matrix_k2) ,
        .precision_mode     (precision_mode2) ,
        .sparse_en          (sparse_en2) ,
        
        // 控制信号
        .ram_a_read_ready   (ram_a_read_ready) , // A矩阵RAM准备好信号
        .ram_b_read_ready   (ram_b_read_ready) , // B矩阵RAM准备好信号
        .ram_d_write_ready  (ram_d_write_ready) ,
        .load_busy          (load_busy) , // 忙状态指示
        .load_done          (load_done) , // 传输完成指示

        .compute_done       (compute_done) ,

        .a_index_wr_en      (a_index_wr_en) ,
        .a_index_wr_addr    (a_index_wr_addr) ,
        .a_index_wr_data    (a_index_wr_data) ,

        // A矩阵RAM阵列读接口
        .ram_a_rd_en        (ram_a_rd_en) ,
        .ram_a_rd_addr      (ram_a_rd_addr) ,
        .ram_a_rd_data      (ram_a_rd_data) ,
        
        // A矩阵阵列写接口
        .systolic_a_wr_en   (systolic_a_wr_en) ,
        .systolic_a_wr_data (systolic_a_wr_data) ,

        // B矩阵RAM阵列读接口
        .ram_b_rd_en        (ram_b_rd_en) ,
        .ram_b_rd_addr      (ram_b_rd_addr) ,
        .ram_b_rd_data      (ram_b_rd_data) ,

        // B矩阵阵列写接口
        .systolic_b_wr_en   (systolic_b_wr_en) ,
        .systolic_b_wr_data (systolic_b_wr_data),

        .first_data         (first_data), // 第一个数据脉冲
        .last_data          (last_data)  // 最后一个数据脉冲
    );

    data_flow_load_c #(
        .PE_SIZE              (PE_SIZE),   // PE数量/阵列大小
        .MATRIX_DIM_WIDTH     (MATRIX_DIM_WIDTH),   // 矩阵维度宽度
        .PRECISION_MODE_WIDTH (PRECISION_MODE_WIDTH),   // 精度模式宽度
        .RAM_ADDR_WIDTH       (RAM_C_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH       (RAM_DATA_WIDTH),   // RAM数据宽度
        .FIFO_DATA_WIDTH      (FIFO_DATA_WIDTH)    // FIFO数据宽度，通常与RAM_DATA_WIDTH相同
    ) data_flow_load_c_inst (
        // 时钟和复位
        .clk               (clk),
        .rst_n             (rst_n),
        
        // CSR 寄存器配置
        .matrix_m          (matrix_m2), // 矩阵C的行数
        .matrix_n          (matrix_n2), // 矩阵C的列数
        .precision_mode    (precision_mode2), // 精度模式
        
        // 控制信号
        .ram_c_read_ready  (ram_c_read_ready), // C矩阵写入RAM完成信号
        .ram_d_write_ready (ram_d_write_ready), // D矩阵写入RAM完成信号
        .rctf_busy         (rctf_busy), // 忙状态指示
        .rctf_done         (rctf_done), // 传输完成指示

        .compute_done      (compute_done), // 计算完成信号
        
        // C矩阵RAM读接口
        .ram_c_rd_en       (ram_c_rd_en),
        .ram_c_rd_addr     (ram_c_rd_addr),
        .ram_c_rd_data     (ram_c_rd_data),
        
        // C矩阵FIFO写接口
        .fifo_c_wr_en      (fifo_c_wr_en),
        .fifo_c_wr_data    (fifo_c_wr_data),
        .fifo_c_full       (fifo_c_full), // FIFO满信号
        .fifo_c_almost_full(fifo_c_almost_full)  // FIFO接近满信号
    );

    delay_array #(
        .PE_SIZE         (PE_SIZE),
        .DATA_WIDTH      (DATA_WIDTH)
    ) a_delay_array_inst (
        // 时钟和复位
        .clk           (clk),
        .rst_n         (rst_n),

        .wr_en         (systolic_a_wr_en),
        .data_in       (systolic_a_wr_data),

        .data_out      (systolic_a_data)
    );

    delay_array #(
        .PE_SIZE         (PE_SIZE),
        .DATA_WIDTH      (DATA_WIDTH)
    ) b_delay_array_inst (
        // 时钟和复位
        .clk           (clk),
        .rst_n         (rst_n),

        .wr_en         (systolic_b_wr_en),
        .data_in       (systolic_b_wr_data),

        .data_out      (systolic_b_data)
    );

    fifo_array #(
        .PE_SIZE        (PE_SIZE),   // FIFO数量/阵列大小
        .DATA_WIDTH     (FIFO_DATA_WIDTH),   // 每个FIFO的数据宽度
        .FIFO_DEPTH     (FIFO_DEPTH),   // 每个FIFO的深度
        .ALMOST_FULL_TH (4),   // 接近满阈值
        .ALMOST_EMPTY_TH(4)    // 接近空阈值
    ) c_fifo_array_inst (
        // 时钟和复位
        .clk           (clk),
        .rst_n         (rst_n),

        // 写接口
        .wr_en         (fifo_c_wr_en),
        .data_in       (fifo_c_wr_data),

        // 读接口
        .rd_en         (fifo_c_rd_en),
        .data_out      (fifo_c_rd_data),

        // 状态信号
        .full          (fifo_c_full),
        .empty         (fifo_c_empty),
        .almost_full   (fifo_c_almost_full),
        .almost_empty  (fifo_c_almost_empty)
    );


    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .PE_SIZE(PE_SIZE) 
    )systolic_array_inst(
        .clk            (clk),
        .rst_n          (rst_n),
        .control        (control),
        .up_all         (up_all),      //8columns input,8bit num
        .left_all       (left_all),    //8rows input ,8bit num
        .precision_mode (precision_mode2),
        .data_selected  (systolic_to_accu_data),
        .done_systolic  (accu_done),
        .data_valid     (systolic_to_accu_sel)//sel信号，接累加器control
    );

    accumulator_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .PE_SIZE(PE_SIZE)
    )accumulator_array_inst(
        .clk            (clk),
        .rst_n          (rst_n),
        .precision_mode (precision_mode2),
        .num            (systolic_to_accu_data),
        .data_valid     (systolic_to_accu_sel),
        .out            (accu_to_fifo_data),//累加输出，接fifo阵列
        .wr_en_to_fifo  (accu_to_fifo_wr_en)
    );


    fifo_array #(
        .PE_SIZE        (PE_SIZE),   // FIFO数量/阵列大小
        .DATA_WIDTH     (FIFO_DATA_WIDTH),   // 每个FIFO的数据宽度
        .FIFO_DEPTH     (32),   // 每个FIFO的深度
        .ALMOST_FULL_TH (4),   // 接近满阈值
        .ALMOST_EMPTY_TH(4)    // 接近空阈值
    ) a_dot_b_fifo_array_inst (
        // 时钟和复位
        .clk           (clk),
        .rst_n         (rst_n),

        // 写接口
        .wr_en         (accu_to_fifo_wr_en),
        .data_in       (accu_to_fifo_data),

        // 读接口
        .rd_en         (fifo_c_rd_en),
        .data_out      (accu_data),

        // 状态信号
        .full          (),
        .empty         (),
        .almost_full   (),
        .almost_empty  ()
    );

    c_matrix_adder #(
        .DATA_WIDTH(DATA_WIDTH),
        .PE_SIZE(PE_SIZE),
        .ADDR_WIDTH(RAM_D_ADDR_WIDTH)
    ) c_matrix_adder_inst(
        .clk            (clk),
        .rst_n          (rst_n),
        .PE_data        (accu_data),
        .RAM_C_data     (fifo_c_rd_data),
        .done_systolic  (accu_done),
        .done_fifoC     (!fifo_c_empty),
        .done_transfer  (ram_d_write_ready),
        .precision_mode (precision_mode2),
        .rd_en          (fifo_c_rd_en_single),
        .wr_data        (ram_d_wr_data),
        .wr_strb        (ram_d_wr_strb),
        .wr_en          (ram_d_wr_en),
        .wr_addr        (ram_d_wr_addr),
        .done           (compute_done)
    );

    ram_array_pingpong #(
        .PE_SIZE        (PE_SIZE),   // PE数量/阵列大小
        .RAM_ADDR_WIDTH (RAM_C_ADDR_WIDTH),   // RAM地址宽度
        .RAM_DATA_WIDTH (RAM_DATA_WIDTH)    // RAM数据宽度
    ) d_ram_array_pingpong_inst (
        // 全局时钟
        .clk            (clk),
        .rst_n          (rst_n),

        // 缓冲区控制信号
        .write_complete (compute_done), 
        .read_complete  (transfer_done),
        .buffer_select  (),
        .read_ready     (ram_d_read_ready), 
        .write_ready    (ram_d_write_ready),

        // 写接口
        .ram_wr_en      ({PE_SIZE{ram_d_wr_en}}),
        .ram_wr_addr    ({PE_SIZE{ram_d_wr_addr}}),
        .ram_wr_data    (ram_d_wr_data),
        .ram_wr_strb    ({PE_SIZE{ram_d_wr_strb}}),

        // 读接口
        .ram_rd_en      (ram_d_rd_en),
        .ram_rd_addr    (ram_d_rd_addr),
        .ram_rd_data    (ram_d_rd_data)
    );

    transfer_d_to_axi_ctrl #(
        .PE_SIZE            (PE_SIZE),
        .AXI_DATA_WIDTH     (AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH     (AXI_ADDR_WIDTH),
        .RAM_ADDR_WIDTH     (RAM_D_ADDR_WIDTH),
        .RAM_DATA_WIDTH     (RAM_DATA_WIDTH),
        .MATRIX_D_BASE_ADDR (MATRIX_D_BASE_ADDR)
    ) transfer_d_to_axi_ctrl_inst (
        // 时钟和复位
        .clk               (clk),
        .rst_n             (rst_n),

        // AXI读请求接口
        .axi_rd_en         (axi_rd_en), // 读使能信号
        .axi_rd_addr       (axi_rd_addr), // 请求读地址
        .axi_rd_data       (axi_rd_data), // 读出的数据
        .axi_rd_data_vld   (axi_rd_data_vld), // 读数据有效

        // CSR寄存器配置
        .matrix_m          (matrix_m3),
        .matrix_n          (matrix_n3),
        .precision_mode    (precision_mode3),

        // RAM阵列D读取接口
        .ram_d_rd_en       (ram_d_rd_en),
        .ram_d_rd_addr     (ram_d_rd_addr),
        .ram_d_rd_data     (ram_d_rd_data),

        // 传输控制信号
        .a_dot_b_add_c_done(ram_d_read_ready), // 矩阵计算完成
        .transfer_start    (transfer_start), // 开始传输脉冲
        .transfer_count    (transfer_count), // 传输数据量
        .ram_base_addr     (ram_base_addr), // RAM基地址
        .axi_target_addr   (axi_target_addr), // AXI目标地址

        // 状态信号
        .transfer_done     (transfer_done), // 传输完成
        .transfer_status   (transfer_status)  // 传输状态
    );

    axi4_full_master #(
        .AXI_ID_WIDTH     (AXI_ID_WIDTH) ,
        .AXI_ADDR_WIDTH   (AXI_ADDR_WIDTH) ,
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH) ,
        .AXI_AWUSER_WIDTH (AXI_AWUSER_WIDTH) ,
        .AXI_WUSER_WIDTH  (AXI_WUSER_WIDTH) ,
        .AXI_BUSER_WIDTH  (AXI_BUSER_WIDTH) ,
        .MAX_BURST_LEN    (255) ,
        .FIFO_DEPTH       (16)
    ) axi4_full_master_inst(
        .m_axi_aclk       (clk),
        .m_axi_aresetn    (rst_n),

        // AXI写地址通道
        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awlock     (m_axi_awlock),
        .m_axi_awcache    (m_axi_awcache),
        .m_axi_awprot     (m_axi_awprot),
        .m_axi_awqos      (m_axi_awqos),
        .m_axi_awregion   (m_axi_awregion),
        .m_axi_awuser     (m_axi_awuser),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),

        // AXI写数据通道
        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wuser      (m_axi_wuser),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),

        // AXI写响应通道
        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_buser      (m_axi_buser),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready),

        // RAM接口
        .axi_rd_en        (axi_rd_en),
        .axi_rd_addr      (axi_rd_addr),
        .axi_rd_data      (axi_rd_data),
        .axi_rd_data_vld  (axi_rd_data_vld),

        // 控制信号
        .transfer_start   (transfer_start),
        .transfer_count   (transfer_count),
        .ram_base_addr    (ram_base_addr), // RAM基地址
        .axi_target_addr  (axi_target_addr),

        // 状态信号
        .transfer_done    (transfer_done),
        .transfer_status  (transfer_status)
    );

    
endmodule