module accumulator #(
    parameter DATA_WIDTH = 32,
    parameter PE_SIZE    = 8,
    parameter PREC_WIDTH = 4
)(
    input                              clk,
    input                              rst_n,
    input  [PREC_WIDTH-1:0]            precision_mode,
    input                              data_valid,
    input  [DATA_WIDTH*PE_SIZE-1:0]    num,
    output [DATA_WIDTH-1:0]            sum,
    output                             wr_en_to_fifo
);
    reg [PREC_WIDTH-1:0]   precision_mode_reg;

    wire                   empty_fifo1,empty_fifo2,rd_en;
    wire [1:0]             mode;
    wire                   wr_en_to_demux,wr_en_to_fifo1,wr_en_to_fifo2;
    wire [DATA_WIDTH-1:0]  out,data_to_fifo1,data_to_fifo2,data_out_fifo1,data_out_fifo2;


    // 寄存减少信号扇出
    always @(posedge clk) begin
        precision_mode_reg <= precision_mode;
    end

    tree_adder #(
        .DATA_WIDTH(32),
        .PREC_WIDTH(PREC_WIDTH)
    )tree_adder_inst(
        .clk             (clk),
        .num             (num),
        .precision_mode  (precision_mode_reg),
        .out             (out)
    );

    accumulator_control #(
        .PE_SIZE(PE_SIZE),
        .PREC_WIDTH(PREC_WIDTH)
    )accumulator_control_inst(
        .clk             (clk),
        .rst_n           (rst_n),
        .precision_mode  (precision_mode_reg),
        .data_valid      (data_valid),
        .empty_fifo1     (empty_fifo1),
        .empty_fifo2     (empty_fifo2),
        .mode            (mode),
        .wr_en_to_demux  (wr_en_to_demux),
        .wr_en_to_fifo   (wr_en_to_fifo),
        .rd_en           (rd_en)
    );

    demux demux_inst(
        .data            (out),
        .wr_en           (wr_en_to_demux),
        .mode            (mode),
        .data_to_fifo1   (data_to_fifo1),
        .data_to_fifo2   (data_to_fifo2),
        .wr_en_to_fifo1  (wr_en_to_fifo1),
        .wr_en_to_fifo2  (wr_en_to_fifo2)
    );

    sync_fifo #(
        .DATA_WIDTH     (DATA_WIDTH),
        .FIFO_DEPTH     (9),
        .ALMOST_FULL_TH (8),
        .ALMOST_EMPTY_TH(1)
    ) fifo_1_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .wr_en         (wr_en_to_fifo1),
        .rd_en         (rd_en),
        .data_in       (data_to_fifo1),
        .full          (),
        .empty         (empty_fifo1),
        .almost_full   (),
        .almost_empty  (),
        .data_out      (data_out_fifo1)
    );

    sync_fifo #(
        .DATA_WIDTH     (DATA_WIDTH),
        .FIFO_DEPTH     (9),
        .ALMOST_FULL_TH (8),
        .ALMOST_EMPTY_TH(1)
    ) fifo_2_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .wr_en         (wr_en_to_fifo2),
        .rd_en         (rd_en),
        .data_in       (data_to_fifo2),
        .full          (),
        .empty         (empty_fifo2),
        .almost_full   (),
        .almost_empty  (),
        .data_out      (data_out_fifo2)
    );

    // multi_precision_adder #(
    //     .DATA_WIDTH(DATA_WIDTH)
    // )u_mixed_precision_adder(
    //     .clk             (clk)               ,
    //     .num1            (data_out_fifo1)    ,
    //     .num2            (data_out_fifo2)    ,
    //     .precision_mode  (precision_mode_reg),
    //     .location        (1'b0)              ,
    //     .sum             (sum)    
    // );

    multi_precision_adder u_mixed_precision_adder(
        .clk             (clk)               ,
        .num1            (data_out_fifo1)    ,
        .num2            (data_out_fifo2)    ,
        .precision_mode  (precision_mode_reg),
        .location        (2'd2)              ,
        .sum             (sum)    
    );
endmodule