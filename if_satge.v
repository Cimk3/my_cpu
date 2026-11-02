`include "mycpu_head.v"

module IF_stage #(parameter ENABLE_BP=1)(
    input  wire        clk,
    input  wire        reset,
    input wire bp_update, bp_branch, bp_taken,
    input wire [31:0] bp_pc, bp_target,
    input wire flush,
    input wire [31:0] redirect_pc,
    input  wire        ds_allowin,
    input  wire [`BR_BUS_WD-1:0] br_bus,
    output wire        fs_to_ds_valid,
    output wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus,
    //inst sram interface
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata
);

reg         fs_valid;
wire        fs_ready_go;
wire        fs_allowin;
wire        to_fs_valid;

wire [31:0] seq_pc;
wire [31:0] next_pc;

wire        br_taken;
wire [31:0] br_target;

assign {br_taken, br_target} = br_bus;

wire [31:0] fs_inst;
reg  [31:0] fs_pc;

wire [31:0] predicted_next;
wire [31:0] bp_next;
branch_predictor u_predictor(.clk(clk),.reset(reset),.query_pc(fs_pc),
    .predicted_next(bp_next),.update(bp_update && ENABLE_BP),.is_branch(bp_branch),
    .taken(bp_taken),.update_pc(bp_pc),.target(bp_target));
assign predicted_next=ENABLE_BP ? bp_next : seq_pc;
assign fs_to_ds_bus = {predicted_next, fs_inst, fs_pc};

assign to_fs_valid = ~reset;
assign seq_pc      = fs_pc + 32'h4;
assign next_pc     = flush ? redirect_pc : br_taken ? br_target : predicted_next;
//握手
assign fs_ready_go    = 1'b1;
assign fs_allowin     = flush || !fs_valid || (fs_ready_go && ds_allowin);
assign fs_to_ds_valid = fs_valid && fs_ready_go && !flush;

always @(posedge clk) begin
    if (reset) begin
        fs_valid <= 1'b0;
    end
    else if (fs_allowin) begin
        fs_valid <= to_fs_valid;
    end
end

always @(posedge clk) begin
    if (reset) begin
        fs_pc <= 32'h1bfffffc;
    end
    else if (to_fs_valid && fs_allowin) begin
        fs_pc <= next_pc;
    end
end

assign inst_sram_en    = to_fs_valid && fs_allowin && next_pc[1:0] == 0;
assign inst_sram_we    = 4'h0;
assign inst_sram_addr  = next_pc;
assign inst_sram_wdata = 32'b0;
assign fs_inst         = inst_sram_rdata;

endmodule
