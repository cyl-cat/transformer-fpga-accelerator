module precision_convert #(
    parameter PREC_WIDTH = 4
)(
    input                        clk,
    input      [31:0]            data,
    input      [PREC_WIDTH-1:0]  precision_mode,//0，1，2，3，4，5，7打拍/6转精度
    output reg [31:0]            data_output
);

wire             sign_fp16    ;       
wire [4:0]       exponent_fp16;
wire [9:0]       mantissa_fp16;

wire             sign_bf16    ;       
wire [7:0]       exponent_bf16;
wire [6:0]       mantissa_bf16;

reg              sign_fp32    ;       
reg  [7:0]       exponent_fp32;
reg  [22:0]      mantissa_fp32;

reg  [31:0]      data_1     ;//用于打拍，除了混合精度，其余部分都是打一拍后输出

reg  [3:0]       shift_num_fp16  ;

wire             zero       ;
wire             NaN,INF    ;
reg              mixed_precision ;

localparam FP16_MIX = 4'd7;
localparam BF16_MIX = 4'd8;

//nan/inf of fp16
assign zero = (exponent_fp16 == 0)  && (mantissa_fp16 == 0);
assign NaN  = (exponent_fp16 == 31) && (mantissa_fp16 != 0);
assign INF  = (exponent_fp16 == 31) && (mantissa_fp16 == 0);

/*---------------stage 1-----------------*/
//decode
assign sign_fp16     = data[15];
assign exponent_fp16 = data[14:10];
assign mantissa_fp16 = data[9:0]; 

assign sign_bf16     = data[15];
assign exponent_bf16 = data[14:7];
assign mantissa_bf16 = data[6:0]; 

always @(*) begin
    casez(mantissa_fp16)
        10'b1????????? : shift_num_fp16 = 1;
        10'b01???????? : shift_num_fp16 = 2;
        10'b001??????? : shift_num_fp16 = 3;
        10'b0001?????? : shift_num_fp16 = 4;
        10'b00001????? : shift_num_fp16 = 5;
        10'b000001???? : shift_num_fp16 = 6;
        10'b0000001??? : shift_num_fp16 = 7;
        10'b00000001?? : shift_num_fp16 = 8;
        10'b000000001? : shift_num_fp16 = 9;
        10'b0000000001 : shift_num_fp16 = 10;
        default : shift_num_fp16 = 0;
    endcase
end


always @(posedge clk) begin
    case (precision_mode)
        FP16_MIX: begin
            mixed_precision <= 1;
            if (NaN || INF)begin
                exponent_fp32 <= 8'hFF;
                mantissa_fp32 <= {mantissa_fp16,13'd0};
            end else if (zero)begin
                exponent_fp32 <= 8'd0;
                mantissa_fp32 <= 23'd0;
            end else if (exponent_fp16==0) begin
                exponent_fp32 <= 113 - shift_num_fp16;
                mantissa_fp32 <= mantissa_fp16 << (shift_num_fp16 + 13);
            end else begin
                exponent_fp32 <= 112 + exponent_fp16;//exp-15+127
                mantissa_fp32 <= {mantissa_fp16,13'd0};
            end
        end
        BF16_MIX: begin
            mixed_precision <= 1;
            exponent_fp32 <= exponent_bf16;
            mantissa_fp32 <= {mantissa_bf16,16'd0};
        end
        default: mixed_precision <= 0;
    endcase
end

always @(posedge clk) begin
    sign_fp32 <= sign_fp16;
end

//不转换的数据
always @(posedge clk) begin
    data_1 <= data;
end

/*---------------stage 2-----------------*/

always @(posedge clk) begin
    if (mixed_precision) begin
        data_output <= {sign_fp32,exponent_fp32,mantissa_fp32};
    end else begin
        data_output <= data_1;
    end
end
endmodule