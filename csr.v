// LoongArch32 reduced privileged state. All software accesses commit in WB.
module csr(
    input wire clk, reset,
    input wire [7:0] hw_int,
    input wire [13:0] num,
    input wire we,
    input wire [31:0] wmask, wvalue,
    output reg [31:0] rvalue,
    input wire wb_ex, ertn_flush,
    input wire [5:0] ecode,
    input wire [8:0] esubcode,
    input wire [31:0] pc, badv,
    output wire [31:0] ex_entry, era_value,
    output wire has_int,
    output reg [63:0] counter
);
reg [31:0] crmd, prmd, ecfg, era, badv_reg, eentry;
reg [31:0] save0, save1, save2, save3, tid, tcfg, timer_cnt;
reg [1:0] soft_int;
reg [7:0] hard_int;
reg timer_int;
reg [5:0] estat_ecode;
reg [8:0] estat_esubcode;
wire [12:0] pending = {1'b0, timer_int, 1'b0, hard_int, soft_int};
wire [31:0] next_value = (rvalue & ~wmask) | (wvalue & wmask);
wire [31:0] next_tcfg = (tcfg & ~wmask) | (wvalue & wmask);
assign ex_entry = eentry;
assign era_value = era;
assign has_int = crmd[2] && |(pending & ecfg[12:0]);

always @* begin
    case (num)
    14'h000: rvalue = crmd;
    14'h001: rvalue = prmd;
    14'h004: rvalue = ecfg;
    14'h005: rvalue = {1'b0,estat_esubcode,estat_ecode,3'b0,pending};
    14'h006: rvalue = era;
    14'h007: rvalue = badv_reg;
    14'h00c: rvalue = eentry;
    14'h030: rvalue = save0;
    14'h031: rvalue = save1;
    14'h032: rvalue = save2;
    14'h033: rvalue = save3;
    14'h040: rvalue = tid;
    14'h041: rvalue = tcfg;
    14'h042: rvalue = timer_cnt;
    default: rvalue = 32'b0; // TICLR is write-one-to-clear, reads zero.
    endcase
end

always @(posedge clk) begin
    if (reset) begin
        crmd <= 32'h8; // PLV=0, IE=0, DA=1, PG=0.
        prmd <= 0; ecfg <= 0; era <= 0; badv_reg <= 0; eentry <= 0;
        save0 <= 0; save1 <= 0; save2 <= 0; save3 <= 0; tid <= 0;
        soft_int <= 0; hard_int <= 0; timer_int <= 0;
        estat_ecode <= 0; estat_esubcode <= 0;
        tcfg <= 0; timer_cnt <= 32'hffffffff; counter <= 0;
    end else begin
        counter <= counter + 1'b1;
        hard_int <= hw_int;
        if (wb_ex) begin
            prmd[2:0] <= crmd[2:0];
            crmd[2:0] <= 3'b0;
            era <= pc;
            estat_ecode <= ecode;
            estat_esubcode <= esubcode;
            if (ecode == 6'h08 || ecode == 6'h09) badv_reg <= badv;
        end else if (ertn_flush) begin
            crmd[2:0] <= prmd[2:0];
        end else if (we) begin
            case (num)
            14'h000: crmd <= next_value & 32'h1ff;
            14'h001: prmd <= next_value & 32'h7;
            14'h004: ecfg <= next_value & 32'h1bff;
            14'h005: soft_int <= next_value[1:0];
            14'h006: era <= next_value;
            14'h00c: eentry <= {next_value[31:6],6'b0};
            14'h030: save0 <= next_value;
            14'h031: save1 <= next_value;
            14'h032: save2 <= next_value;
            14'h033: save3 <= next_value;
            14'h040: tid <= next_value;
            default: begin end
            endcase
        end
        if (we && num == 14'h041) begin
            tcfg <= next_tcfg;
            if (next_tcfg[0]) timer_cnt <= {next_tcfg[31:2],2'b0};
        end else if (tcfg[0] && timer_cnt != 32'hffffffff) begin
            if (timer_cnt == 0 && tcfg[1]) timer_cnt <= {tcfg[31:2],2'b0};
            else timer_cnt <= timer_cnt - 1'b1;
        end
        // Expiration wins over a simultaneous clear, as in the guide.
        if (tcfg[0] && timer_cnt == 0) timer_int <= 1'b1;
        else if (we && num == 14'h044 && wmask[0] && wvalue[0]) timer_int <= 1'b0;
    end
end
endmodule
