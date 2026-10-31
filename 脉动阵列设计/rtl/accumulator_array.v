module accumulator_array #(
    parameter DATA_WIDTH = 32,
    parameter PE_SIZE    = 8,
    parameter PREC_WIDTH = 4
)(
    input                              clk,
    input                              rst_n,
    input  [PREC_WIDTH-1:0]            precision_mode,
    input  [DATA_WIDTH*PE_SIZE*8-1:0]  num,
    input  [PE_SIZE-1:0]               data_valid,
    output [DATA_WIDTH*PE_SIZE-1:0]    out,
    output [PE_SIZE-1:0]               wr_en_to_fifo
);
reg  [PREC_WIDTH-1:0]                     precision_mode_reg;

// 寄存减少信号扇出
always @(posedge clk) begin
    precision_mode_reg <= precision_mode;
end

genvar i;
generate
    for (i = 0; i < PE_SIZE; i = i + 1) begin : gen_accumulator_array
        accumulator #(
            .DATA_WIDTH      (32),
            .PE_SIZE         (8),
            .PREC_WIDTH      (PREC_WIDTH)
        )accumulator_inst(
            .clk             (clk),
            .rst_n           (rst_n),
            .num             (num[i*DATA_WIDTH*8 +: DATA_WIDTH*8]),
            .data_valid      (data_valid[i]),
            .precision_mode  (precision_mode_reg),
            .sum             (out[i*DATA_WIDTH +: DATA_WIDTH]),
            .wr_en_to_fifo   (wr_en_to_fifo[i])
        );
    end

endgenerate


endmodule