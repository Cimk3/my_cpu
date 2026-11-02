`include "mycpu_head.v"

module mycpu_top #(
    parameter ENABLE_BP=1, ENABLE_CACHE=1, CPU_CLOCK_HZ=50000000
)(
    input  wire        clk,
    input  wire        resetn,
    input tri1 uart_rx,
    output wire uart_tx,
    input tri0 [7:0] ext_int, // optional hardware interrupt pins; omitted ports tie low
    // instruction sram interface
    output wire        inst_sram_en,
    output wire [3:0]  inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,
    // data sram interface
    output wire        data_sram_en,
    output wire [3:0]  data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    // trace debug interface
    output wire [31:0] debug_wb_pc,
    output wire [3:0]  debug_wb_rf_we,
    output wire [4:0]  debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

reg reset;

always @(posedge clk) begin
    reset <= ~resetn;
end

wire flush, has_int;
wire [31:0] redirect_pc;
wire [63:0] counter;
wire es_occupied, ms_occupied, ws_occupied, es_serial, ms_serial, ws_serial;
wire        ds_allowin;
wire        es_allowin;
wire        ms_allowin;
wire        ws_allowin;

wire        fs_to_ds_valid;
wire        ds_to_es_valid;
wire        es_to_ms_valid;
wire        ms_to_ws_valid;

wire [`BR_BUS_WD-1:0]       br_bus;
wire [`FS_TO_DS_BUS_WD-1:0] fs_to_ds_bus;
wire [`DS_TO_ES_BUS_WD-1:0] ds_to_es_bus;
wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus;
wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus;
wire [`WS_TO_RF_BUS_WD-1:0] ws_to_rf_bus;

wire core_inst_en, core_data_en;
wire [3:0] core_inst_we, core_data_we;
wire [31:0] core_inst_addr,core_inst_wdata,core_inst_rdata;
wire [31:0] core_data_addr,core_data_wdata,core_data_rdata;
wire bp_update,bp_branch,bp_taken;
wire [31:0] bp_pc,bp_target;
wire uart_sel=core_data_addr[28:5]==24'hfd7f88; // 1faf_f100..1faf_f11f, including bfaf alias
wire uart_access=core_data_en && uart_sel;
wire inv_write=uart_access && |core_data_we && core_data_addr[4:2]==5;
wire ic_invalidate=inv_write && core_data_wdata[0];
wire dc_invalidate=inv_write && core_data_wdata[1];
wire [31:0] uart_rdata,dc_rdata;
wire uart_irq;
reg uart_response;
always @(posedge clk) begin
    if(reset)uart_response<=0;
    else if(core_data_en)uart_response<=uart_sel;
end
assign core_data_rdata=uart_response ? uart_rdata : dc_rdata;
uart_mmio #(.CLOCK_HZ(CPU_CLOCK_HZ)) u_uart(.clk(clk),.reset(reset),
    .en(uart_access),.we(core_data_we),.addr(core_data_addr[4:0]),
    .wdata(core_data_wdata),.rdata(uart_rdata),.rx(uart_rx),.tx(uart_tx),.irq(uart_irq));
// The local SoC mirrors instruction RAM at 1 MiB, data RAM at 256 KiB.
// Tags use the backend's address bits so physical aliases stay coherent.
word_cache #(.ADDRESS_BITS(20)) u_icache(.clk(clk),.reset(reset),.invalidate(ic_invalidate),
    .req(core_inst_en),.cacheable(ENABLE_CACHE!=0),.we(core_inst_we),
    .addr(core_inst_addr),.wdata(core_inst_wdata),.rdata(core_inst_rdata),
    .mem_en(inst_sram_en),.mem_we(inst_sram_we),.mem_addr(inst_sram_addr),
    .mem_wdata(inst_sram_wdata),.mem_rdata(inst_sram_rdata),.hit_count(),.miss_count());
word_cache #(.ADDRESS_BITS(18)) u_dcache(.clk(clk),.reset(reset),.invalidate(dc_invalidate),
    .req(core_data_en && !uart_sel),
    .cacheable(ENABLE_CACHE!=0 && core_data_addr[28:16]!=13'h1faf),
    .we(core_data_we),.addr(core_data_addr),.wdata(core_data_wdata),.rdata(dc_rdata),
    .mem_en(data_sram_en),.mem_we(data_sram_we),.mem_addr(data_sram_addr),
    .mem_wdata(data_sram_wdata),.mem_rdata(data_sram_rdata),.hit_count(),.miss_count());

IF_stage #(.ENABLE_BP(ENABLE_BP)) u_if_stage(
    .bp_update(bp_update),.bp_branch(bp_branch),.bp_taken(bp_taken),.bp_pc(bp_pc),.bp_target(bp_target),
    .flush(flush),.redirect_pc(redirect_pc),
    .clk              (clk              ),
    .reset            (reset            ),
    .ds_allowin       (ds_allowin       ),
    .br_bus           (br_bus           ),
    .fs_to_ds_valid   (fs_to_ds_valid   ),
    .fs_to_ds_bus     (fs_to_ds_bus     ),
    .inst_sram_en(core_inst_en),
    .inst_sram_we(core_inst_we),
    .inst_sram_addr(core_inst_addr),
    .inst_sram_wdata(core_inst_wdata),
    .inst_sram_rdata(core_inst_rdata)
);

ID_stage u_id_stage(
    .bp_update(bp_update),.bp_branch(bp_branch),.bp_taken(bp_taken),.bp_pc(bp_pc),.bp_target(bp_target),
    .flush(flush),.has_int(has_int),
    .es_occupied(es_occupied),.ms_occupied(ms_occupied),.ws_occupied(ws_occupied),
    .es_serial(es_serial),.ms_serial(ms_serial),.ws_serial(ws_serial),
    .clk              (clk              ),
    .reset            (reset            ),
    .es_allowin       (es_allowin       ),
    .ds_allowin       (ds_allowin       ),
    .fs_to_ds_valid   (fs_to_ds_valid   ),
    .fs_to_ds_bus     (fs_to_ds_bus     ),
    .ds_to_es_valid   (ds_to_es_valid   ),
    .ds_to_es_bus     (ds_to_es_bus     ),
    .br_bus           (br_bus           ),
    .es_to_ms_valid   (es_to_ms_valid   ),
    .es_to_ms_bus     (es_to_ms_bus     ),
    .ms_to_ws_valid   (ms_to_ws_valid   ),
    .ms_to_ws_bus     (ms_to_ws_bus     ),
    .ws_to_rf_bus     (ws_to_rf_bus     )
);

EXE_stage u_exe_stage(
    .flush(flush),.older_serial(ms_serial || ws_serial),.counter(counter),
    .occupied(es_occupied),.serial(es_serial),
    .clk              (clk              ),
    .reset            (reset            ),
    .ms_allowin       (ms_allowin       ),
    .es_allowin       (es_allowin       ),
    .ds_to_es_valid   (ds_to_es_valid   ),
    .ds_to_es_bus     (ds_to_es_bus     ),
    .es_to_ms_valid   (es_to_ms_valid   ),
    .es_to_ms_bus     (es_to_ms_bus     ),
    .data_sram_en(core_data_en),
    .data_sram_we(core_data_we),
    .data_sram_addr(core_data_addr),
    .data_sram_wdata(core_data_wdata)
);

MEM_stage u_mem_stage(
    .flush(flush),.occupied(ms_occupied),.serial(ms_serial),
    .clk              (clk              ),
    .reset            (reset            ),
    .ws_allowin       (ws_allowin       ),
    .ms_allowin       (ms_allowin       ),
    .es_to_ms_valid   (es_to_ms_valid   ),
    .es_to_ms_bus     (es_to_ms_bus     ),
    .ms_to_ws_valid   (ms_to_ws_valid   ),
    .ms_to_ws_bus     (ms_to_ws_bus     ),
    .data_sram_rdata(core_data_rdata)
);

WB_stage u_wb_stage(
    .hw_int(ext_int | {7'b0,uart_irq}),.flush(flush),.redirect_pc(redirect_pc),.has_int(has_int),
    .counter(counter),.occupied(ws_occupied),.serial(ws_serial),
    .clk              (clk              ),
    .reset            (reset            ),
    .ws_allowin       (ws_allowin       ),
    .ms_to_ws_valid   (ms_to_ws_valid   ),
    .ms_to_ws_bus     (ms_to_ws_bus     ),
    .ws_to_rf_bus     (ws_to_rf_bus     ),
    .debug_wb_pc      (debug_wb_pc      ),
    .debug_wb_rf_we   (debug_wb_rf_we   ),
    .debug_wb_rf_wnum (debug_wb_rf_wnum ),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

endmodule
