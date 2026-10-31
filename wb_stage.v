`include "mycpu_head.v"

module WB_stage(
    input  wire        clk,
    input  wire        reset,
    input wire [7:0] hw_int,
    output wire flush,
    output wire [31:0] redirect_pc,
    output wire has_int,
    output wire [63:0] counter,
    output wire occupied, serial,
    output wire        ws_allowin,
    input  wire        ms_to_ws_valid,
    input  wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,
    output wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus,
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg         ws_valid;
wire        ws_ready_go;

reg [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus_r;

wire        ws_gr_we;
wire [4:0]  ws_dest;
wire [31:0] ws_final_result;
wire [31:0] ws_pc;

wire        rf_we;
wire [4:0]  rf_waddr;
wire [31:0]  rf_wdata;

assign {
    ws_gr_we,
    ws_dest,
    ws_final_result,
    ws_pc
} = ms_to_ws_bus_r[69:0];

wire [`CTRL_WD-1:0] ctrl = ms_to_ws_bus_r[`MS_TO_WS_BUS_WD-1:70];
wire wb_ex = ws_valid && ctrl[`CTRL_EX];
wire ertn_flush = ws_valid && ctrl[`CTRL_ERTN] && !wb_ex;
wire [31:0] csr_value, ex_entry, era_value;
assign flush = wb_ex || ertn_flush;
assign redirect_pc = wb_ex ? ex_entry : era_value;
assign occupied = ws_valid;
assign serial = ws_valid && (ctrl[`CTRL_RE] || ctrl[`CTRL_WE] || ctrl[`CTRL_EX] || ctrl[`CTRL_ERTN]);
csr u_csr(.clk(clk),.reset(reset),.hw_int(hw_int),
    .num(ctrl[`CTRL_NUM]),.we(ws_valid && ctrl[`CTRL_WE] && !flush),
    .wmask(ctrl[`CTRL_MASK]),.wvalue(ctrl[`CTRL_VALUE]),.rvalue(csr_value),
    .wb_ex(wb_ex),.ertn_flush(ertn_flush),.ecode(ctrl[`CTRL_ECODE]),
    .esubcode(ctrl[`CTRL_ESUB]),.pc(ws_pc),.badv(ctrl[`CTRL_BADV]),
    .ex_entry(ex_entry),.era_value(era_value),.has_int(has_int),.counter(counter));

assign ws_to_rf_bus = {
    rf_we,
    rf_waddr,
    rf_wdata
};

assign ws_ready_go = 1'b1;
assign ws_allowin  = !ws_valid||ws_ready_go;

always @(posedge clk) begin
    if (reset || flush) begin
        ws_valid       <= 1'b0;
        // ms_to_ws_bus_r <= {`MS_TO_WS_BUS_WD{1'b0}};
    end
    else begin
        if (ws_allowin) begin
            ws_valid <= ms_to_ws_valid;
        end
        if (ms_to_ws_valid && ws_allowin) begin
            ms_to_ws_bus_r <= ms_to_ws_bus;
        end
    end
end

assign rf_we = ws_valid && ws_gr_we && !flush;
assign rf_waddr = ws_dest;
assign rf_wdata = ctrl[`CTRL_RE] ? csr_value : ws_final_result;

assign debug_wb_pc       = ws_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = ws_dest;
assign debug_wb_rf_wdata = rf_wdata;

endmodule
