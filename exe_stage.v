`include "mycpu_head.v"

module EXE_stage(
    input  wire        clk,
    input  wire        reset,
    input wire flush, older_serial,
    input wire [63:0] counter,
    output wire occupied, serial,
    input  wire        ms_allowin,
    output wire        es_allowin,
    input  wire        ds_to_es_valid,
    input  wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus,
    output wire        es_to_ms_valid,
    output wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,
    //data sram interface(write)
    output data_sram_en,
    output [3:0] data_sram_we,
    output [31:0] data_sram_addr,
    output [31:0] data_sram_wdata
);

reg         es_valid;
wire        es_ready_go;

reg [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus_r;

wire [11:0] alu_op;
wire [6:0]  muldiv_op;//乘除法操作码
wire        src1_is_pc;
wire        src2_is_imm;
wire        src2_is_4;
wire        res_from_mem;
wire [1:0]  mem_size;
wire        load_unsigned;
wire        dst_is_r1;
wire        gr_we;
wire        mem_we;
wire [4:0]  dest;
wire [31:0] imm;
wire [31:0] rj_value;
wire [31:0] rkd_value;
wire [31:0] es_pc;

wire [31:0] alu_src1;
wire [31:0] alu_src2;
wire [31:0] alu_result;
wire [31:0] es_result;//exe阶段结果

wire [`CTRL_WD-1:0] ctrl_in = ds_to_es_bus_r[`DS_TO_ES_BUS_WD-1:161];
wire ale = (res_from_mem || mem_we) &&
           ((mem_size == `MEM_SIZE_WORD && |alu_result[1:0]) ||
            (mem_size == `MEM_SIZE_HALF && alu_result[0]));
wire [`CTRL_WD-1:0] ctrl_out = ctrl_in[`CTRL_EX] || !ale ? ctrl_in :
    {ctrl_in[130:49],1'b0,1'b1,6'h09,9'b0,alu_result};
assign occupied = es_valid;
assign serial = es_valid && (ctrl_out[`CTRL_RE] || ctrl_out[`CTRL_WE] ||
                            ctrl_out[`CTRL_ERTN] || ctrl_out[`CTRL_EX]);
assign {
    muldiv_op,
    mem_size,
    load_unsigned,
    alu_op,
    src1_is_pc,
    src2_is_imm,
    src2_is_4,
    gr_we,
    mem_we,
    dest,
    imm,
    rj_value,
    rkd_value,
    es_pc,
    res_from_mem
} = ds_to_es_bus_r[160:0];

assign alu_src1 = src1_is_pc  ? es_pc : rj_value;
assign alu_src2 = src2_is_imm ? imm   : rkd_value;

alu u_alu(
    .alu_op     (alu_op    ),
    .alu_src1   (alu_src1  ),
    .alu_src2   (alu_src2  ),
    .alu_result (alu_result)
);

assign es_to_ms_bus = {
    ctrl_out,
    mem_size,
    load_unsigned,
    res_from_mem,
    gr_we,
    dest,
    es_result,
    es_pc
};

wire        is_mul;
wire        is_div;
wire        div_start;//除法开始
wire        div_complete;//除法完成
reg         div_started;
wire [31:0] div_quotient;//商
wire [31:0] div_remainder;//余数
wire signed [32:0] mul_src1;
wire signed [32:0] mul_src2;
wire signed [65:0] mul_product;
wire [31:0] mul_result;

assign is_mul = |muldiv_op[2:0];
assign is_div = |muldiv_op[6:3];
assign mul_src1 = {(!muldiv_op[2]) && rj_value[31], rj_value};
assign mul_src2 = {(!muldiv_op[2]) && rkd_value[31], rkd_value};
assign mul_product = mul_src1 * mul_src2;
assign mul_result = muldiv_op[0] ? mul_product[31:0] : mul_product[63:32];
assign es_result = ctrl_in[130] ? counter[63:32] : ctrl_in[129] ? counter[31:0] : is_mul ? mul_result :
                   is_div ? ((muldiv_op[4] || muldiv_op[6]) ? div_remainder : div_quotient) :
                            alu_result;

// Issue once and keep EX occupied until the registered quotient/remainder is ready.
assign div_start = es_valid && is_div && !div_started && !flush && !ctrl_out[`CTRL_EX];
divider32 u_divider(
    .clk         (clk),
    .reset       (reset || flush),
    .start       (div_start),
    .div_signed  (muldiv_op[3] || muldiv_op[4]),
    .dividend    (rj_value),
    .divisor     (rkd_value),
    .busy        (),
    .complete    (div_complete),
    .quotient    (div_quotient),
    .remainder   (div_remainder)
);



always @(posedge clk) begin
    if (reset || flush || es_allowin)
        div_started <= 1'b0;
    else if (div_start)
        div_started <= 1'b1;
end

assign es_ready_go    = ctrl_out[`CTRL_EX] || !is_div || (div_started && div_complete);
assign es_allowin     = !es_valid || (es_ready_go && ms_allowin);
assign es_to_ms_valid = es_valid && es_ready_go && !flush;

always @(posedge clk) begin
    if (reset || flush) begin
        es_valid       <= 1'b0;
        //ds_to_es_bus_r <= {`DS_TO_ES_BUS_WD{1'b0}};
    end
    else begin
        if (es_allowin) begin
            es_valid <= ds_to_es_valid;
        end
        if (ds_to_es_valid && es_allowin) begin
            ds_to_es_bus_r <= ds_to_es_bus;
        end
    end
end

wire [3:0] store_byte_en;

// SRAM lanes are selected by the byte offset in the effective address.
assign store_byte_en = mem_size == `MEM_SIZE_BYTE ? (4'b0001 << alu_result[1:0]) :
                       mem_size == `MEM_SIZE_HALF ? (4'b0011 << {alu_result[1], 1'b0}) :
                                                   4'b1111;

assign data_sram_en    = es_to_ms_valid && ms_allowin && (res_from_mem || mem_we) && !ctrl_out[`CTRL_EX] && !older_serial && !flush;
assign data_sram_we    = data_sram_en && mem_we ? store_byte_en : 4'b0000;
assign data_sram_addr  = alu_result;
assign data_sram_wdata = mem_size == `MEM_SIZE_BYTE ? {4{rkd_value[7:0]}} :
                        mem_size == `MEM_SIZE_HALF ? {2{rkd_value[15:0]}} :
                                                    rkd_value;

endmodule
