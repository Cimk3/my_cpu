`include "mycpu_head.v"

module mycpu_top(
    input  wire        clk,
    input  wire        resetn,
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

IF_stage u_if_stage(
    .flush(flush),.redirect_pc(redirect_pc),
    .clk              (clk              ),
    .reset            (reset            ),
    .ds_allowin       (ds_allowin       ),
    .br_bus           (br_bus           ),
    .fs_to_ds_valid   (fs_to_ds_valid   ),
    .fs_to_ds_bus     (fs_to_ds_bus     ),
    .inst_sram_en     (inst_sram_en     ),
    .inst_sram_we     (inst_sram_we     ),
    .inst_sram_addr   (inst_sram_addr   ),
    .inst_sram_wdata  (inst_sram_wdata  ),
    .inst_sram_rdata  (inst_sram_rdata  )
);

ID_stage u_id_stage(
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
    .data_sram_en     (data_sram_en     ),
    .data_sram_we     (data_sram_we     ),
    .data_sram_addr   (data_sram_addr   ),
    .data_sram_wdata  (data_sram_wdata  )
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
    .data_sram_rdata  (data_sram_rdata  )
);

WB_stage u_wb_stage(
    .hw_int(ext_int),.flush(flush),.redirect_pc(redirect_pc),.has_int(has_int),
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
