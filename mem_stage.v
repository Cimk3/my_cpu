`include "mycpu_head.v"

module MEM_stage(
    input  wire        clk,
    input  wire        reset,
    input wire flush,
    output wire occupied, serial,
    input  wire        ws_allowin,
    output wire        ms_allowin,
    input  wire        es_to_ms_valid,
    input  wire [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus,
    output wire        ms_to_ws_valid,
    output wire [`MS_TO_WS_BUS_WD-1:0] ms_to_ws_bus,
    // output wire        data_sram_en,
    // output wire [3:0]  data_sram_we,
    // output wire [31:0] data_sram_addr,
    // output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata
);

reg         ms_valid;
wire        ms_ready_go;

reg [`ES_TO_MS_BUS_WD-1:0] es_to_ms_bus_r;

// wire        es_gr_we;
// wire        es_mem_we;
// wire        es_res_from_mem;
// wire [4:0]  es_dest;
// wire [31:0] es_alu_result;
// wire [31:0] es_rkd_value;
// wire [31:0] es_pc;

wire        ms_gr_we;
// wire        ms_mem_we;
wire        ms_res_from_mem;
wire [1:0]  ms_mem_size;
wire        ms_load_unsigned;
wire [4:0]  ms_dest;
wire [31:0] ms_alu_result;
// wire [31:0] ms_rkd_value;
wire [31:0] ms_pc;
wire [31:0] mem_result;
wire [31:0] ms_final_result;
wire [7:0]  load_byte;
wire [15:0] load_half;

// assign {
//     es_gr_we,
//     es_mem_we,
//     es_res_from_mem,
//     es_dest,
//     es_alu_result,
//     es_rkd_value,
//     es_pc
// } = es_to_ms_bus;

assign {
    ms_mem_size,
    ms_load_unsigned,
    ms_res_from_mem,
    ms_gr_we,
    ms_dest,
    ms_alu_result,
    ms_pc
} = es_to_ms_bus_r[73:0];

// assign data_sram_en    = es_to_ms_valid && ms_allowin &&
//                          (es_mem_we || es_res_from_mem);
// assign data_sram_we    = (data_sram_en && es_mem_we) ? 4'b1111 : 4'b0000;
// assign data_sram_addr  = es_alu_result;
// assign data_sram_wdata = es_rkd_value;


wire [`CTRL_WD-1:0] ctrl = es_to_ms_bus_r[`ES_TO_MS_BUS_WD-1:74];
assign occupied = ms_valid;
assign serial = ms_valid && (ctrl[`CTRL_RE] || ctrl[`CTRL_WE] || ctrl[`CTRL_EX] || ctrl[`CTRL_ERTN]);
assign ms_to_ws_bus = {
    ctrl,
    ms_gr_we,
    ms_dest,
    ms_final_result,
    ms_pc
};

assign ms_ready_go    = 1'b1;
assign ms_allowin     = !ms_valid || (ms_ready_go && ws_allowin);
assign ms_to_ws_valid = ms_valid && ms_ready_go && !flush;

always @(posedge clk) begin
    if (reset || flush) begin
        ms_valid        <= 1'b0;
        // es_to_ms_bus_r  <= {`ES_TO_MS_BUS_WD{1'b0}};
    end
    else begin
        if (ms_allowin) begin
            ms_valid <= es_to_ms_valid;
        end
        if (es_to_ms_valid && ms_allowin) begin
            es_to_ms_bus_r <= es_to_ms_bus;
        end
    end
end

// The address and access type are latched with the load, independently of EXE.
assign load_byte = data_sram_rdata[ms_alu_result[1:0] * 8 +: 8];
assign load_half = ms_alu_result[1] ? data_sram_rdata[31:16] : data_sram_rdata[15:0];
assign mem_result = ms_mem_size == `MEM_SIZE_BYTE ?
                    {{24{!ms_load_unsigned && load_byte[7]}}, load_byte} :
                   ms_mem_size == `MEM_SIZE_HALF ?
                    {{16{!ms_load_unsigned && load_half[15]}}, load_half} :
                    data_sram_rdata;
assign ms_final_result = ms_res_from_mem ? mem_result : ms_alu_result;

endmodule
