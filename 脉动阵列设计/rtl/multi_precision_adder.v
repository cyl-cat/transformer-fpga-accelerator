module multi_precision_adder(
	input                      clk,
    input      [31:0]          num1,//int4_32或int8_32中的int4/int8
    input      [31:0]          num2,//int4_32或int8_32中的int32
    input      [3:0]           precision_mode,
    input      [1:0]           location,//0在tree_adder，1在c_adder,2在累加器
	output reg [31:0] 		   sum
);

    localparam DATAWIDTH_FP16  = 16;
    localparam EXPOWIDTH_FP16  = 5 ;
    localparam MANTWIDTH_FP16  = 10;
    localparam DATAWIDTH_BF16  = 16;
    localparam EXPOWIDTH_BF16  = 8 ;
    localparam MANTWIDTH_BF16  = 7 ;
    localparam DATAWIDTH_FP32  = 32;
    localparam EXPOWIDTH_FP32  = 8 ;
    localparam MANTWIDTH_FP32  = 23;

    localparam INT4     = 4'd0;
    localparam INT8     = 4'd1;
    localparam INT4_32  = 4'd2;
    localparam INT8_32  = 4'd3;
    localparam FP16     = 4'd4;
    localparam BF16     = 4'd5;
    localparam FP32     = 4'd6;
    localparam FP16_MIX = 4'd7;
    localparam BF16_MIX = 4'd8;

    //reduce fanout
    reg  [3:0]              precision_mode_reg,precision_mode_reg1;

    always @(posedge clk) begin
        precision_mode_reg <= precision_mode;
        precision_mode_reg1 <= precision_mode_reg;
    end

// reg 1
    reg  [32-1:0]           num1_reg       ;
    reg  [32-1:0]           num2_reg       ;
    reg  [EXPOWIDTH_FP32-1:0] exponentA      ;
    reg  [EXPOWIDTH_FP32-1:0] exponentB      ;
    reg  [23:0]             fractionA      ;
    reg  [23:0]             fractionB      ;
    reg                     signA, signB   ;
    wire [31:0]             sum_32         ;  

    reg  [31:0]             addend1,addend2;

    //variable in 1st stage
    reg                      flag_big       ;
    reg                      flag_small     ;
    reg [EXPOWIDTH_FP32-1:0] expo_diff      ;  
    reg [EXPOWIDTH_FP32-1:0] exponent       ;
    reg [23:0]               big_num        ;
    reg [23:0]               small_num      ;
    reg                      big_A          ; //check if A is the bigger one

    //variable in 2nd stage
    reg [EXPOWIDTH_FP32-1:0] exponent_stage5,exponent_reg5;
    wire                     cin_fp32,cin_fp16,cin_bf16,cin;
    reg                      cin_reg4;
    reg                      flag_stage5         ;
    reg [23:0  ]             sum_stage5,sum_reg5     ;

    // 3rd stage
    reg [23:0]               fraction_shifted;
    reg [EXPOWIDTH_FP32-1:0] exponent_result ;
    reg                      flag_reslut     ;
    reg [5:0]                shift_num_fp32  ;//0-10
    wire [3:0]               shift_num_fp16  ;
    wire [2:0]               shift_num_bf16  ;
    reg                      non_std         ;
    reg [EXPOWIDTH_FP32-1:0] shift_num_actual;//1-30

    //case variable
    reg [1:0]                decode_case;  
    reg                      compare_case;
    reg [2:0]                addend_case;
    reg [3:0]                sum_case;

    //reg 3
    reg                      flag_same_reg3;

// reg 4
    reg [31:0]               sum_32_reg;
    reg [EXPOWIDTH_FP32-1:0] exponent_reg4;
    reg                      flag_same_reg4;
    reg                      flag_big_reg4;

/*--------------------------precision_mode--------------------------------*/

//precision mode signal
    wire                     int_wire,int4,int8,int16,int4_32,int8_32;
    wire					 fp16,bf16,fp32;
    wire					 fp16_1,bf16_1,fp32_1;

    wire [9:0] mode_onehot = 1<<precision_mode_reg;
    assign int_wire     = |{mode_onehot[INT4],mode_onehot[INT8],mode_onehot[INT4_32],mode_onehot[INT8_32]};
    assign fp16    = mode_onehot[FP16];
    assign bf16    = mode_onehot[BF16];
    assign fp32    = |{mode_onehot[BF16_MIX],mode_onehot[FP16_MIX],mode_onehot[FP32]}; // BF16_MIX or FP16_MIX or FP32
    assign int4    = mode_onehot[INT4];
    assign int8    = mode_onehot[INT8];
    assign int4_32 = mode_onehot[INT4_32];
    assign int8_32 = mode_onehot[INT8_32];

    wire [9:0] mode_onehot1 = 1<<precision_mode_reg1;
    assign fp16_1  = mode_onehot1[FP16];
    assign bf16_1  = mode_onehot1[BF16];
    assign fp32_1  = |{mode_onehot1[BF16_MIX],mode_onehot1[FP16_MIX],mode_onehot1[FP32]}; 


    wire 					  num1_is_nan, num1_is_inf_pos, num1_is_inf_neg;
    wire 					  num2_is_nan, num2_is_inf_pos, num2_is_inf_neg;
    wire 					  nan, inf_pos, inf_neg;
    reg 					  nan_reg2, inf_pos_reg2, inf_neg_reg2,zero_reg2;
    reg 					  nan_reg3, inf_pos_reg3, inf_neg_reg3,zero_reg3;
    reg 					  nan_reg4, inf_pos_reg4, inf_neg_reg4,zero_reg4;
////////////////////////////////
// detect inf/nan input
////////////////////////////////
//    wire [7:0] exp_num1 = 

    assign num1_is_nan     = ((fp16)&&(num1_reg[14:10]==5'b11111)&&(num1_reg[9:0] != 0))
    || ((fp32)&&(num1_reg[30:23]==8'hff)&&(num1_reg[22:0]!=0)) 
    || ((bf16)&&(num1_reg[14:7]==8'hff)&&(num1_reg[6:0]!=0));          // 判断+inf

    assign num1_is_inf_pos = ((fp16)&&(num1_reg[14:10]==5'b11111)&&(num1_reg[9:0] == 0)&&!num1_reg[15]) 
    || ((fp32)&&(num1_reg[30:23]==8'hff)&&(num1_reg[22:0]==0)&&!num1_reg[31]) 
    || ((bf16)&&(num1_reg[14:7]==8'hff)&&(num1_reg[6:0]==0)&&!num1_reg[15]); // 判断-inf

    assign num1_is_inf_neg = ((fp16)&&(num1_reg[14:10]==5'b11111)&&(num1_reg[9:0] == 0)&& num1_reg[15]) 
    || ((fp32)&&(num1_reg[30:23]==8'hff)&&(num1_reg[22:0]==0)&& num1_reg[31])
    || ((bf16)&&(num1_reg[14:7]==8'hff)&&(num1_reg[6:0]==0)&&num1_reg[15]);

    assign num2_is_nan     = ((fp16)&&(num2_reg[14:10]==5'b11111)&&(num2_reg[9:0] != 0)) 
    || ((fp32)&&(num2_reg[30:23]==8'hff)&&(num2_reg[22:0]!=0))
    || ((bf16)&&(num2_reg[14:7]==8'hff)&&(num2_reg[6:0]!=0));          // 判断+inf

    assign num2_is_inf_pos = ((fp16)&&(num2_reg[14:10]==5'b11111)&&(num2_reg[9:0] == 0)&&!num2_reg[15]) 
    || ((fp32)&&(num2_reg[30:23]==8'hff)&&(num2_reg[22:0]==0)&&!num2_reg[31]) 
    || ((bf16)&&(num2_reg[14:7]==8'hff)&&(num2_reg[6:0]==0)&&!num2_reg[15]); // 判断-inf

    assign num2_is_inf_neg = ((fp16)&&(num2_reg[14:10]==5'b11111)&&(num2_reg[9:0] == 0)&& num2_reg[15]) 
    || ((fp32)&&(num2_reg[30:23]==8'hff)&&(num2_reg[22:0]==0)&& num2_reg[31])
    || ((bf16)&&(num2_reg[14:7]==8'hff)&&(num2_reg[6:0]==0)&&num2_reg[15]);

    assign nan = num2_is_nan || num1_is_nan || (num1_is_inf_pos && num2_is_inf_neg) || (num2_is_inf_pos && num1_is_inf_neg);
    assign inf_pos = !nan && (num1_is_inf_pos || num2_is_inf_pos);
    assign inf_neg = !nan && (num1_is_inf_neg || num2_is_inf_neg);

// reg 2
    always @(posedge clk) begin
        nan_reg2 <= nan;                             
        inf_pos_reg2 <= inf_pos;
        inf_neg_reg2 <= inf_neg;
    end
// 处理数�?�相同，符号相反的数相加
    always @(posedge clk) begin
        if (((fp16||bf16) && num1_reg[14:0]==num2_reg[14:0] && num1_reg[15]!=num2_reg[15]) 
        || (fp32 && num1_reg[30:0]==num2_reg[30:0] && num1_reg[31]!=num2_reg[31]))
        zero_reg2 <= 1;
        else
        zero_reg2 <= 0;
    end
// reg 3
    always @(posedge clk) begin
        nan_reg3 <= nan_reg2;
        inf_pos_reg3 <= inf_pos_reg2;
        inf_neg_reg3 <= inf_neg_reg2;
        zero_reg3 <= zero_reg2;
    end
// reg 4
    always @(posedge clk) begin
        nan_reg4 <= nan_reg3;
        inf_pos_reg4 <= inf_pos_reg3;
        inf_neg_reg4 <= inf_neg_reg3;
        zero_reg4 <= zero_reg3;
    end

  // reg 1
    always @(posedge clk) begin
        num1_reg <= num1;
        num2_reg <= num2;
    end
////////////////////////////////
// decode
////////////////////////////////
    always @(*) begin
        if(fp16) begin
            decode_case = 2'd0;
        end else if (bf16) begin
            decode_case = 2'd1;
        end else begin
            decode_case = 2'd2;
        end
    end


    always @* begin
        case(decode_case)
        2'd0: begin
            fractionA = (num1_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16] != 0 ) ? {13'd0,1'b1,num1_reg[MANTWIDTH_FP16-1:0]} : {13'd0,1'b0,num1_reg[MANTWIDTH_FP16-1:0]};//9:0
            fractionB = (num2_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16] != 0 ) ? {13'd0,1'b1,num2_reg[MANTWIDTH_FP16-1:0]} : {13'd0,1'b0,num2_reg[MANTWIDTH_FP16-1:0]};
        end 
        2'd1: begin
            fractionA = (num1_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16] != 0 ) ? {16'd0,1'b1,num1_reg[MANTWIDTH_BF16-1:0]} : {16'd0,1'b0,num1_reg[MANTWIDTH_BF16-1:0]};//9:0
            fractionB = (num2_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16] != 0 ) ? {16'd0,1'b1,num2_reg[MANTWIDTH_BF16-1:0]} : {16'd0,1'b0,num2_reg[MANTWIDTH_BF16-1:0]};
        end 
        default: begin
            fractionA = (num1_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32] != 0 ) ? {1'b1,num1_reg[MANTWIDTH_FP32-1:0]} : {1'b0,num1_reg[MANTWIDTH_FP32-1:0]};//9:0
            fractionB = (num2_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32] != 0 ) ? {1'b1,num2_reg[MANTWIDTH_FP32-1:0]} : {1'b0,num2_reg[MANTWIDTH_FP32-1:0]};
        end 
        endcase
    end

    always @(*) begin
        case(decode_case)
        2'd0:begin//exponent位宽9，相加后的stage2位宽10
            exponentA = (num1_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16] != 0 ) ? {3'b0,num1_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16]} : 8'd1;
            exponentB = (num2_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16] != 0 ) ? {3'b0,num2_reg[DATAWIDTH_FP16-2:DATAWIDTH_FP16-1-EXPOWIDTH_FP16]} : 8'd1;
        end 
        2'd1: begin
            exponentA = (num1_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16] != 0 ) ? {num1_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16]} : 8'd1;
            exponentB = (num2_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16] != 0 ) ? {num2_reg[DATAWIDTH_BF16-2:DATAWIDTH_BF16-1-EXPOWIDTH_BF16]} : 8'd1;
        end
        default: begin
            exponentA = (num1_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32] != 0 ) ? {num1_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32]} : 8'd1;
            exponentB = (num2_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32] != 0 ) ? {num2_reg[DATAWIDTH_FP32-2:DATAWIDTH_FP32-1-EXPOWIDTH_FP32]} : 8'd1;
        end
        endcase
    end

    always @(*) begin
        case(decode_case)
        2'd0:begin//exponent位宽9，相加后的stage2位宽10
            signA = num1_reg[DATAWIDTH_FP16-1];
            signB = num2_reg[DATAWIDTH_FP16-1];
        end 
        2'd1: begin
            signA = num1_reg[DATAWIDTH_BF16-1];
            signB = num2_reg[DATAWIDTH_BF16-1];
        end
        default: begin
            signA = num1_reg[DATAWIDTH_FP32-1];
            signB = num2_reg[DATAWIDTH_FP32-1];
        end
        endcase
    end
////////////////////////////////
// compare two fp input 
////////////////////////////////
    wire [EXPOWIDTH_FP32:0] exp_diff = exponentA - exponentB;

    always @* begin // get the biegger num 
        if (exp_diff[EXPOWIDTH_FP32]==1) begin
            compare_case = 1'b1;
        end else if (exp_diff != 0)begin
            compare_case = 1'b0;
        end else if (fractionA > fractionB) begin
            compare_case = 1'b0;
        end else begin
            compare_case = 1'b1;
        end
    end

    always @* begin // get the biegger num 
        case(compare_case)
            0:begin
                expo_diff = exponentA - exponentB;
                big_A = 1;
            end
            1:begin
                expo_diff = exponentB - exponentA;
                big_A = 0;
            end
        endcase
    end
// reg 2
    always @(posedge clk)begin
        if (big_A)begin
            small_num  <= fractionB >> (expo_diff);
            big_num    <= fractionA;
            exponent   <= exponentA;
            flag_big   <= signA;
            flag_small <= signB;
        end else begin 
            small_num  <= fractionA >> (expo_diff);
            big_num    <= fractionB;
            exponent   <= exponentB;
            flag_big   <= signB;
            flag_small <= signA;
        end   
    end

////////////////////////////////
// process two addends
////////////////////////////////
    always @(*) begin
        if ((int_wire && (location==0 || location==2) || int4_32 || int8_32)) begin
            addend_case = 3'd0;
        end else if (int16)begin
            addend_case = 3'd1;
        end else if (int4) begin
            addend_case = 3'd2;
        end else if (int8) begin
            addend_case = 3'd3;
        end else if (flag_big == flag_small) begin
            addend_case = 3'd4;
        end else begin
            addend_case = 3'd5;
        end
    end

    always @* begin
        case(addend_case)
            3'd0:begin
                addend1 = num1_reg;
                addend2 = num2_reg;
            end
            3'd1:begin
                addend1 = {{16{num1_reg[15]}},num1_reg[15:0]};
                addend2 = num2_reg;
            end
            3'd2:begin
                addend1 = {{28{num1_reg[3]}},num1_reg[3:0]};
                addend2 = num2_reg;
            end
            3'd3:begin
                addend1 = {{24{num1_reg[7]}},num1_reg[7:0]};
                addend2 = num2_reg;
            end
            3'd4:begin
                addend1 = big_num;
                addend2 = small_num;
            end
            default:begin
                addend1 = big_num;
                addend2 = (~small_num)+1;
            end
        endcase
    end

//////////////////////////////////////////////////
// Because of the timing insertion register
//////////////////////////////////////////////////
// reg 3
    always @(*) begin //compute sum_32bit of mantissa
        if (flag_big == flag_small)begin
            flag_same_reg3 <= 1;
        end else begin
            flag_same_reg3 <= 0;
        end 
    end

    assign sum_32 = addend1 + addend2; // 32bit adder
//////////////////////////////////////////////////
// Because of the timing insertion register
//////////////////////////////////////////////////
// reg 3
    always @(posedge clk) begin
        sum_32_reg <= sum_32;
        exponent_reg4 <= exponent;
        flag_same_reg4 <= flag_same_reg3;
        flag_big_reg4 <= flag_big;
        cin_reg4 <= sum_32[MANTWIDTH_FP32+1]; // carry in for the next stage
    end

/////////////////////////////////////////////////////
// Handling the carry-over resulting from fp addition
/////////////////////////////////////////////////////
    // assign flag_stage5 = flag_big_reg4;
    assign cin_bf16 = sum_32_reg[MANTWIDTH_BF16+1];
    assign cin_fp16 = sum_32_reg[MANTWIDTH_FP16+1];
    assign cin_fp32 = cin_reg4;

    always @(*)begin
        //Add if the signs are the same; subtract if the signs are different.
        if (flag_same_reg4 && (fp32_1 && cin_fp32) || (fp16_1 && cin_fp16) || (bf16_1 && cin_bf16))begin
            exponent_stage5  = exponent_reg4 +1   ;
            sum_stage5 = {cin_fp32,sum_32_reg} >> 1;
        end else begin
            exponent_stage5  = exponent_reg4 ;
            sum_stage5 = sum_32_reg;
        end
    end
//reg4
    always @(posedge clk)begin
        flag_stage5 <= flag_big_reg4;
        exponent_reg5 <= exponent_stage5;
        sum_reg5 <= sum_stage5;
    end
///////////////////////////////////////////////////
// Detect the first 1 in the sequence for fp32
///////////////////////////////////////////////////
    always @(*) begin
        casez (sum_stage5[23:0])
            24'b1???????????????????????: shift_num_fp32 = 0;
            24'b01??????????????????????: shift_num_fp32 = 1;
            24'b001?????????????????????: shift_num_fp32 = 2;
            24'b0001????????????????????: shift_num_fp32 = 3;
            24'b00001???????????????????: shift_num_fp32 = 4;
            24'b000001??????????????????: shift_num_fp32 = 5;
            24'b0000001?????????????????: shift_num_fp32 = 6;
            24'b00000001????????????????: shift_num_fp32 = 7;
            24'b000000001???????????????: shift_num_fp32 = 8;
            24'b0000000001??????????????: shift_num_fp32 = 9;
            24'b00000000001?????????????: shift_num_fp32 = 10;
            24'b000000000001????????????: shift_num_fp32 = 11;
            24'b0000000000001???????????: shift_num_fp32 = 12;
            24'b00000000000001??????????: shift_num_fp32 = 13;
            24'b000000000000001?????????: shift_num_fp32 = 14;
            24'b0000000000000001????????: shift_num_fp32 = 15;
            24'b00000000000000001???????: shift_num_fp32 = 16;
            24'b000000000000000001??????: shift_num_fp32 = 17;
            24'b0000000000000000001?????: shift_num_fp32 = 18;
            24'b00000000000000000001????: shift_num_fp32 = 19;
            24'b000000000000000000001???: shift_num_fp32 = 20;
            24'b0000000000000000000001??: shift_num_fp32 = 21;
            24'b00000000000000000000001?: shift_num_fp32 = 22;
            24'b000000000000000000000001: shift_num_fp32 = 23;
            default: shift_num_fp32 = 0;
        endcase
    end
///////////////////////////////////////////////////
// Detect the first 1 in the sequence for bf16
///////////////////////////////////////////////////
    assign shift_num_bf16 = shift_num_fp32 - 16;

///////////////////////////////////////////////////
// Detect the first 1 in the sequence for fp16
///////////////////////////////////////////////////
    assign shift_num_fp16 = shift_num_fp32 - 13;

///////////////////////////////////////////
// calculate the parameter of normalization
///////////////////////////////////////////
//reg 4
    always @(posedge clk) begin
        if ((exponent_stage5 > shift_num_fp32)&&(fp32_1)) begin
            shift_num_actual <= shift_num_fp32;
            non_std <= 0;
        end else if ((exponent_stage5 > shift_num_fp16)&&(fp16_1)) begin
            shift_num_actual <= shift_num_fp16;
            non_std <= 0;
        end else if ((exponent_stage5 > shift_num_bf16)&&(bf16_1))begin
            shift_num_actual <= shift_num_bf16;
            non_std <= 0;
        end else begin
            shift_num_actual <= exponent_stage5-1;
            non_std <= 1;
        end
    end


///////////////////////////////////////////
// normalization
///////////////////////////////////////////
    always @(*)begin
        if (nan_reg4) begin
            flag_reslut <= 0;
            fraction_shifted <= {32{1'b1}};
            exponent_result <= {8{1'b1}};
        end else if (inf_pos_reg4) begin
            flag_reslut <= 0;
            fraction_shifted <= 0;
            exponent_result <= {8{1'b1}};
        end else if (inf_neg_reg4) begin
            flag_reslut <= 1;
            fraction_shifted <= 0;
            exponent_result <= {8{1'b1}};
        end else if (zero_reg4) begin
            flag_reslut <= 0;
            fraction_shifted <= 0;
            exponent_result <= 0;
        end else if (non_std == 1) begin
            flag_reslut <= flag_stage5 ;
            fraction_shifted <= sum_reg5 << shift_num_actual;
            exponent_result <= 0;
        end else begin
            flag_reslut <= flag_stage5 ;
            fraction_shifted <= sum_reg5 << shift_num_actual;
            exponent_result <= exponent_reg5 - shift_num_actual; 
        end
    end


///////////////////////////////////
// overflow detect and ouput select
//////////////////////////////////
    // reg 5 for fp  reg 2 for int_wire
    always @ (*) begin
        if (fp32_1 & exponent_result>254 & !nan_reg4)begin
		    sum_case = 4'd0;
	    end else if (fp16_1 & exponent_result>30 & !nan_reg4) begin
		    sum_case = 4'd1;
	    end else if (bf16_1 & exponent_result>254 & !nan_reg4) begin
		    sum_case = 4'd2;
        end else if (fp32_1)begin
            sum_case = 4'd3;
        end else if (fp16_1) begin
            sum_case = 4'd4;
        end else if (bf16_1) begin
            sum_case = 4'd5;
        end else if (addend1[31]==1'b0 && addend2[31]==1'b0 && sum_32[31]==1'b1) begin
            sum_case = 4'd6;
        end else if (addend1[31]==1'b1 && addend2[31]==1'b1 && sum_32[31]==1'b0)begin
            sum_case = 4'd7;
        end else if ((int4||int4_32) && location==0)begin//对双加法因为补码计算产生的进位进行处理
            sum_case = 4'd8;
        end else begin
            sum_case = 4'd9;
        end
    end

    always @ (posedge clk) begin
        case(sum_case)
            4'd0:sum <= {flag_reslut,{8{1'b1}},23'd0};
            4'd1:sum <= {16'd0,flag_reslut,{5{1'b1}},10'd0};
            4'd2:sum <= {16'd0,flag_reslut,{8{1'b1}},7'd0};
            4'd3:sum <= {flag_reslut, exponent_result[EXPOWIDTH_FP32-1:0], fraction_shifted[MANTWIDTH_FP32-1:0]};
            4'd4:sum <= {16'd0,flag_reslut, exponent_result[EXPOWIDTH_FP16-1:0], fraction_shifted[MANTWIDTH_FP16-1:0]};
            4'd5:sum <= {16'd0,flag_reslut, exponent_result[EXPOWIDTH_BF16-1:0], fraction_shifted[MANTWIDTH_BF16-1:0]};
            4'd6:sum <= 32'h7fffffff;
            4'd7:sum <= 32'h80000000;
            4'd8:sum <= {3'd0,sum_32[28:16],3'd0,sum_32[12:0]};
            default:sum <= sum_32;
        endcase
    end
endmodule