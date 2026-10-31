module multi_precision_multiplier#(
    parameter DATA_WIDTH = 32,
    parameter PREC_WIDTH = 4
)(
	input                        clk,
    input                        rst_n,
    input                        input_valid,
    input      [DATA_WIDTH-1:0]  num1,
    input      [DATA_WIDTH-1:0]  num2,
    input      [PREC_WIDTH-1:0]  precision_mode,
	output     [DATA_WIDTH-1:0]  product,
    output                       output_valid
);
localparam INT4     = 4'd0;
localparam INT8     = 4'd1;
localparam INT4_32  = 4'd2;
localparam INT8_32  = 4'd3;
localparam FP16     = 4'd4;
localparam BF16     = 4'd5;
localparam FP32     = 4'd6;
localparam FP16_MIX = 4'd7;
localparam BF16_MIX = 4'd8;

reg  [DATA_WIDTH-1:0] num1_reg, num2_reg;
wire [DATA_WIDTH-1:0] product_int;
wire [10:0]           multi_num1_fp16, multi_num2_fp16;
wire [ 7:0]           multi_num1_bf16, multi_num2_bf16;
wire [11:0]           multi_num1_fp32, multi_num2_fp32;
wire [12:0]           multi_num1_int, multi_num2_int;
reg  [12:0]           multiplicand1, multiplicand2;
wire [25:0]           product_mantissa;
wire [16-1:0]         product_fp16, product_bf16;
wire [DATA_WIDTH-1:0] product_fp32;
                 
wire [8:0] mode_onehot = 1 << precision_mode;
wire       fp16_en = |{mode_onehot[FP16], mode_onehot[FP16_MIX]};//通道使能信号，推导门控时钟
wire       bf16_en = |{mode_onehot[BF16], mode_onehot[BF16_MIX]};
wire       fp32_en = mode_onehot[FP32];
wire       int_en  = |{mode_onehot[INT4], mode_onehot[INT8], mode_onehot[INT4_32], mode_onehot[INT8_32]};

always @(posedge clk ) begin
    num1_reg <= num1;
    num2_reg <= num2;
end

//整数位扩展
int_channel #(
    .DATA_WIDTH(32),
    .PREC_WIDTH(PREC_WIDTH)
)int_channel_inst(
    .clk            (clk),
    .int_en         (int_en),
    .num1           (num1_reg),
    .num2           (num2_reg),
    .precision_mode (precision_mode),
    .num1_extended  (multi_num1_int),
    .num2_extended  (multi_num2_int),
    .product_mantissa (product_mantissa),
    .product        (product_int)
);
//fp16、bf16、fp32通道
fp16_channel #(
    .DATA_WIDTH(16),
    .EXPO_WIDTH(5),
    .MANT_WIDTH(10)
)fp16_channel_inst(
    .clk              (clk),
    .en               (fp16_en), // 添加使能端口
    .num1             (num1_reg[15:0]),
    .num2             (num2_reg[15:0]),
    .product_mantissa (product_mantissa[21:0]),
    .multi_num1       (multi_num1_fp16),
    .multi_num2       (multi_num2_fp16),
    .product          (product_fp16)
);

bf16_channel #(
    .DATA_WIDTH(16),
    .EXPO_WIDTH(8),
    .MANT_WIDTH(7)
)bf16_channel_inst(
    .clk              (clk),
    .en               (bf16_en), // 添加使能端口
    .num1             (num1_reg[15:0]),
    .num2             (num2_reg[15:0]),
    .product_mantissa (product_mantissa[15:0]),
    .multi_num1       (multi_num1_bf16),
    .multi_num2       (multi_num2_bf16),
    .product          (product_bf16)
);

fp32_channel #(
    .DATA_WIDTH(32),
    .EXPO_WIDTH(8),
    .MANT_WIDTH(23)
)fp32_channel_inst(
    .clk              (clk),
    .rst_n            (rst_n),
    .en               (fp32_en), // 添加使能端口
    .num1_wire        (num1),
    .num2_wire        (num2),
    .input_valid      (input_valid), 
    .product_mantissa (product_mantissa[23:0]),
    .multi_num1       (multi_num1_fp32),
    .multi_num2       (multi_num2_fp32),
    .product          (product_fp32),
    .output_valid     (output_valid)
);

//根据精度模式选择乘数
always @(*)begin
    case(precision_mode)
        INT4,INT8,INT4_32,INT8_32:begin
            multiplicand1 = multi_num1_int;
            multiplicand2 = multi_num2_int;
        end
        FP16,FP16_MIX: begin
            multiplicand1 = {2'd0,multi_num1_fp16};
            multiplicand2 = {2'd0,multi_num2_fp16};
        end
        BF16,BF16_MIX: begin
            multiplicand1 = {5'd0,multi_num1_bf16};
            multiplicand2 = {5'd0,multi_num2_bf16};
        end   
        default: begin
            multiplicand1 = {1'd0,multi_num1_fp32};
            multiplicand2 = {1'd0,multi_num2_fp32};
        end                  
    endcase
end

assign product_mantissa = multiplicand1 * multiplicand2;

//选择输出
mux4to1_mul #(
    .DATA_WIDTH(32),
    .PREC_WIDTH(PREC_WIDTH)
)mux4to1_mul_product_inst(
    .fp16           ({16'd0,product_fp16}),
    .bf16           ({16'd0,product_bf16}),
    .fp32           (product_fp32),
    .int_wire       (product_int),
    .precision_mode (precision_mode),
    .result         (product)
);
endmodule